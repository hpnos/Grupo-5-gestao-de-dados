"""Fluxo SVP ↔ laboratório: outbox, worker, webhook, idempotência e erros.

Os testes rodam em sequência e contam uma história com o pedido 1
(tutor com consentimento) e o pedido 2 (tutor sem consentimento).
"""
import json

import httpx

from conftest import TOKEN_LAB, resultado, su_sql, webhook

estado: dict = {}


def lab_falso(respostas: list):
    """Transporte HTTP falso: devolve as respostas em ordem e guarda as chamadas."""
    chamadas = []

    def tratar(req: httpx.Request) -> httpx.Response:
        chamadas.append(req)
        r = respostas.pop(0)
        if isinstance(r, Exception):
            raise r
        return r
    return httpx.Client(transport=httpx.MockTransport(tratar)), chamadas


def test_sem_consentimento_nao_envia(cliente, token):
    r = cliente.post("/exames/2/enviar", headers=token("vet.ana"))
    assert r.status_code == 409 and "consentimento" in r.json()["detail"]
    assert su_sql("SELECT count(*) FROM integracao_evento WHERE id_agregado = 2")[0][0] == 0


def test_recepcao_nao_envia_exame(cliente, token):
    assert cliente.post("/exames/1/enviar", headers=token("rec.gabriela")).status_code == 403


def test_envio_vira_evento_no_outbox_sem_dados_do_tutor(cliente, token):
    r = cliente.post("/exames/1/enviar", headers=token("vet.ana"))
    assert r.status_code == 202 and r.json()["situacao"] == "enfileirado"
    payload = su_sql("SELECT payload FROM integracao_evento WHERE id_agregado = 1")[0][0]
    texto = json.dumps(payload, ensure_ascii=False)
    nome, cpf = su_sql("SELECT t.nome, t.cpf FROM tutor t WHERE id_tutor = 1")[0]
    assert cpf not in texto and nome not in texto                      # minimização
    assert payload["paciente"]["codigo"].startswith("VP-A-")
    # clicar de novo não duplica
    assert cliente.post("/exames/1/enviar", headers=token("vet.ana")).json()["situacao"] == "ja_enfileirado"
    assert su_sql("SELECT count(*) FROM integracao_evento WHERE id_agregado = 1")[0][0] == 1


def test_laboratorio_fora_do_ar_agenda_nova_tentativa():
    from app.worker import processar_lote
    http, chamadas = lab_falso([httpx.Response(503, text="manutenção")])
    assert processar_lote(http) == {"ERRO": 1}
    status, tent, atraso = su_sql("""SELECT status, tentativas, proxima_tentativa_em > now() + INTERVAL '25 seconds'
                                     FROM integracao_evento WHERE id_agregado = 1""")[0]
    assert (status, tent, atraso) == ("ERRO", 1, True)
    assert chamadas[0].headers["Authorization"] == f"Bearer {TOKEN_LAB}"
    estado["chave"] = chamadas[0].headers["Idempotency-Key"]


def test_timeout_tambem_agenda_nova_tentativa():
    from app.worker import processar_lote
    su_sql("UPDATE integracao_evento SET proxima_tentativa_em = now() WHERE id_agregado = 1")
    http, chamadas = lab_falso([httpx.ReadTimeout("sem resposta")])
    assert processar_lote(http) == {"ERRO": 1}
    assert chamadas[0].headers["Idempotency-Key"] == estado["chave"]   # mesma chave em todo reenvio


def test_envio_com_sucesso_grava_protocolo():
    from app.worker import processar_lote
    su_sql("UPDATE integracao_evento SET proxima_tentativa_em = now() WHERE id_agregado = 1")
    http, _ = lab_falso([httpx.Response(201, json={"protocolo": "LV-TESTE01"})])
    assert processar_lote(http) == {"ENVIADO": 1}
    assert su_sql("SELECT status, protocolo_laboratorio FROM solicitacao_exame WHERE id_solicitacao = 1")[0] \
        == ("ENVIADO", "LV-TESTE01")
    assert su_sql("SELECT status FROM integracao_evento WHERE id_agregado = 1")[0][0] == "ENVIADO"


def test_dado_recusado_pelo_laboratorio_e_falha_definitiva():
    from app.worker import processar_lote
    su_sql("""INSERT INTO integracao_evento (tipo, destino, id_agregado, chave_idempotencia, payload)
              VALUES ('EXAME_SOLICITADO', 'laboratorio:1', 999, 'teste-invalido', '{}')""")
    http, _ = lab_falso([httpx.Response(422, json={"detail": "campo obrigatório ausente"})])
    assert processar_lote(http) == {"FALHA_DEFINITIVA": 1}
    assert su_sql("""SELECT count(*) FROM vw_integracao_pendencias
                     WHERE status = 'FALHA_DEFINITIVA'""")[0][0] == 1


def test_webhook_com_assinatura_errada_e_recusado(cliente):
    corpo, cab = webhook(resultado("LV-TESTE01", 1), "LV-TESTE01-v1", segredo="outro")
    assert cliente.post("/integracoes/laboratorio/1/resultados", content=corpo, headers=cab).status_code == 401
    corpo, cab = webhook(resultado("LV-TESTE01", 1), "LV-TESTE01-v1", ts=1_700_000_000)   # replay antigo
    assert cliente.post("/integracoes/laboratorio/1/resultados", content=corpo, headers=cab).status_code == 401


def test_webhook_com_hash_errado_e_rejeitado(cliente):
    corpo, cab = webhook(resultado("LV-TESTE01", 1, sha="0" * 64), "LV-TESTE01-hash")
    r = cliente.post("/integracoes/laboratorio/1/resultados", content=corpo, headers=cab)
    assert r.status_code == 422
    assert su_sql("""SELECT status FROM integracao_recebida
                     WHERE chave_idempotencia = 'LV-TESTE01-hash'""")[0][0] == "REJEITADA"


def test_webhook_com_payload_invalido_e_rejeitado(cliente):
    ruim = resultado("LV-TESTE01", 1)
    del ruim["laudo"]
    corpo, cab = webhook(ruim, "LV-TESTE01-ruim")
    assert cliente.post("/integracoes/laboratorio/1/resultados", content=corpo, headers=cab).status_code == 422


def test_webhook_valido_conclui_exame_e_guarda_laudo(cliente):
    corpo, cab = webhook(resultado("LV-TESTE01", 1), "LV-TESTE01-v1")
    r = cliente.post("/integracoes/laboratorio/1/resultados", content=corpo, headers=cab)
    assert r.status_code == 200 and r.json()["situacao"] == "processado"
    status, versao, hash_doc, origem = su_sql(
        """SELECT s.status, s.versao_resultado, d.hash_sha256, d.origem
           FROM solicitacao_exame s JOIN documento d USING (id_documento) WHERE s.id_solicitacao = 1""")[0]
    assert (status, versao, origem) == ("CONCLUIDO", 1, "laboratorio:1")
    from app import armazenamento
    caminho = su_sql("SELECT caminho FROM documento WHERE hash_sha256 = %s", hash_doc)[0][0]
    assert armazenamento.ler(caminho, hash_doc).startswith(b"%PDF")


def test_webhook_repetido_nao_duplica(cliente):
    corpo, cab = webhook(resultado("LV-TESTE01", 1), "LV-TESTE01-v1")
    r = cliente.post("/integracoes/laboratorio/1/resultados", content=corpo, headers=cab)
    assert r.json()["situacao"] == "duplicado"
    assert su_sql("SELECT count(*) FROM documento WHERE origem = 'laboratorio:1'")[0][0] == 1


def test_laudo_retificado_atualiza_e_versao_antiga_e_ignorada(cliente):
    corpo, cab = webhook(resultado("LV-TESTE01", 1, versao=2, pdf=b"%PDF-1.4 laudo v2"), "LV-TESTE01-v2")
    assert cliente.post("/integracoes/laboratorio/1/resultados", content=corpo, headers=cab).json()["versao"] == 2
    corpo, cab = webhook(resultado("LV-TESTE01", 1, versao=1, pdf=b"%PDF-1.4 laudo v1b"), "LV-TESTE01-v1b")
    r = cliente.post("/integracoes/laboratorio/1/resultados", content=corpo, headers=cab)
    assert r.json()["situacao"] == "versao_antiga"
    assert su_sql("SELECT versao_resultado FROM solicitacao_exame WHERE id_solicitacao = 1")[0][0] == 2
    # o laudo v1 continua guardado (documento é imutável); o pedido aponta para o v2
    assert su_sql("SELECT count(*) FROM documento WHERE origem = 'laboratorio:1'")[0][0] == 2


def test_protocolo_de_outro_pedido_e_rejeitado(cliente):
    corpo, cab = webhook(resultado("LV-OUTRO", 1, versao=3), "LV-OUTRO-v3")
    assert cliente.post("/integracoes/laboratorio/1/resultados", content=corpo, headers=cab).status_code == 422
