"""Autenticação, autorização por perfil e auditoria de acesso pela API."""
import pyotp

from conftest import su_sql


def test_login_ok_e_registrado(cliente):
    r = cliente.post("/auth/login", json={"login": "vet.ana", "senha": "VidaPlena@2026"})
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["token_type"] == "bearer" and corpo["refresh_token"]
    assert su_sql("""SELECT count(*) FROM log_auditoria l JOIN usuario u USING (id_usuario)
                     WHERE u.login = 'vet.ana' AND l.acao = 'LOGIN'""")[0][0] >= 1
    # o banco guarda só o hash do refresh token
    assert su_sql("SELECT count(*) FROM sessao WHERE refresh_hash = %s", corpo["refresh_token"])[0][0] == 0


def test_bloqueio_apos_cinco_tentativas(cliente):
    for _ in range(5):
        assert cliente.post("/auth/login", json={"login": "enf.fabio", "senha": "errada"}).status_code == 401
    r = cliente.post("/auth/login", json={"login": "enf.fabio", "senha": "VidaPlena@2026"})
    assert r.status_code == 423                      # bloqueado mesmo com a senha certa
    falhas = su_sql("""SELECT count(*) FROM log_auditoria l JOIN usuario u USING (id_usuario)
                       WHERE u.login = 'enf.fabio' AND l.acao = 'LOGIN_FALHA'""")[0][0]
    assert falhas == 6


def test_login_inexistente_nao_revela_usuario(cliente):
    r = cliente.post("/auth/login", json={"login": "nao.existe", "senha": "x"})
    assert r.status_code == 401 and r.json()["detail"] == "Login ou senha inválidos"


def test_refresh_gira_o_token(cliente):
    t = cliente.post("/auth/login", json={"login": "rec.hugo", "senha": "VidaPlena@2026"}).json()
    novo = cliente.post("/auth/refresh", json={"refresh_token": t["refresh_token"]})
    assert novo.status_code == 200
    reuso = cliente.post("/auth/refresh", json={"refresh_token": t["refresh_token"]})
    assert reuso.status_code == 401                  # o antigo não vale mais


def test_mfa_exige_codigo(cliente):
    from app.seguranca import cifrar
    segredo = pyotp.random_base32()
    import psycopg
    from conftest import DB, url
    with psycopg.connect(url("svp_api", DB), autocommit=True) as c:
        c.execute("UPDATE usuario SET mfa_ativo = TRUE, mfa_segredo_cif = %s WHERE login = 'dir.joao'",
                  (cifrar(segredo),))
    sem = cliente.post("/auth/login", json={"login": "dir.joao", "senha": "VidaPlena@2026"})
    assert sem.status_code == 401
    com = cliente.post("/auth/login", json={"login": "dir.joao", "senha": "VidaPlena@2026",
                                            "codigo_mfa": pyotp.TOTP(segredo).now()})
    assert com.status_code == 200
    # o segredo não fica legível no banco
    assert segredo.encode() not in bytes(su_sql("SELECT mfa_segredo_cif FROM usuario WHERE login = 'dir.joao'")[0][0])


def test_sem_token_401(cliente):
    assert cliente.get("/animais/1/prontuario").status_code == 401


def test_recepcao_nao_le_prontuario_e_tentativa_fica_no_log(cliente, token):
    r = cliente.get("/animais/1/prontuario", headers=token("rec.gabriela"))
    assert r.status_code == 403
    assert su_sql("""SELECT count(*) FROM log_auditoria l JOIN usuario u USING (id_usuario)
                     WHERE u.login = 'rec.gabriela' AND l.acao = 'ACESSO_NEGADO'
                       AND l.tabela = 'prontuario'""")[0][0] == 1


def test_veterinario_le_prontuario_e_leitura_fica_no_log(cliente, token):
    r = cliente.get("/animais/1/prontuario", headers=token("vet.ana"))
    assert r.status_code == 200
    assert r.json()["animal"]["id_animal"] == 1
    assert su_sql("""SELECT count(*) FROM log_auditoria l JOIN usuario u USING (id_usuario)
                     WHERE u.login = 'vet.ana' AND l.acao = 'LEITURA' AND l.tabela = 'atendimento'
                       AND l.id_registro = 1""")[0][0] == 1
    assert r.headers["cache-control"] == "no-store"


def test_cpf_mascarado_para_quem_so_le_cadastro(cliente, token):
    vet = cliente.get("/tutores/1", headers=token("vet.ana")).json()
    rec = cliente.get("/tutores/1", headers=token("rec.gabriela")).json()
    assert vet["cpf"].startswith("***.") and vet["cpf"].endswith("-**")
    assert rec["cpf"].isdigit() and len(rec["cpf"]) == 11


def test_admin_ti_nao_ve_dados_de_negocio(cliente, token):
    assert cliente.get("/tutores/1", headers=token("ti.karina")).status_code == 403
    assert cliente.get("/auditoria/logs?acao=ACESSO_NEGADO", headers=token("ti.karina")).status_code == 200


def test_auditoria_consulta_o_log(cliente, token):
    r = cliente.get("/auditoria/logs?tabela=atendimento&id_registro=1", headers=token("aud.lucas"))
    assert r.status_code == 200 and any(l["acao"] == "LEITURA" for l in r.json())
