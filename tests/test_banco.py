"""Regras garantidas pelo próprio banco (Storage e Security)."""
import psycopg
import pytest

from conftest import DB, DW, url, su_sql


def como(papel: str, banco: str = DB):
    return psycopg.connect(url(papel, banco), autocommit=True)


def test_seed_carregou_modelo_completo():
    tabelas = su_sql("""SELECT count(*) FROM information_schema.tables
                        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
                          AND table_name !~ '^log_auditoria_'""")[0][0]
    # 42 da modelagem + politica_retencao + sessao + integracao_evento + integracao_recebida
    assert tabelas == 46
    assert su_sql("SELECT count(*) FROM atendimento")[0][0] > 4000


def test_veterinario_nao_tem_dois_horarios_iguais():
    ag = su_sql("""SELECT id_animal, id_veterinario, id_especialidade, id_unidade, data_hora
                   FROM agendamento WHERE status <> 'CANCELADO' LIMIT 1""")[0]
    with como("svp_api") as c, pytest.raises(psycopg.errors.UniqueViolation):
        c.execute("""INSERT INTO agendamento (id_animal, id_veterinario, id_especialidade, id_unidade,
                                              data_hora, modalidade, criado_por)
                     VALUES (%s, %s, %s, %s, %s, 'PRESENCIAL', 7)""", ag)


def test_aplicacao_nao_apaga_prontuario_nem_altera_log():
    with como("svp_api") as c:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            c.execute("DELETE FROM atendimento WHERE id_atendimento = 1")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            c.execute("UPDATE log_auditoria SET acao = 'LOGIN' WHERE id_log = 1")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            c.execute("DELETE FROM tutor WHERE id_tutor = 1")


def test_log_e_imutavel_ate_para_o_dono():
    with pytest.raises(psycopg.errors.RaiseException):
        su_sql("DELETE FROM log_auditoria WHERE id_log = (SELECT min(id_log) FROM log_auditoria)")


def test_alteracao_clinica_gera_log_com_autor():
    with como("svp_api") as c:
        with c.transaction():
            c.execute("SELECT set_config('svp.id_usuario', '1', true)")
            c.execute("UPDATE atendimento SET conduta = 'Retorno em 15 dias' WHERE id_atendimento = 10")
    log = su_sql("""SELECT id_usuario, acao, dados_antes->>'conduta', dados_depois->>'conduta'
                    FROM log_auditoria WHERE tabela = 'atendimento' AND id_registro = 10
                    ORDER BY id_log DESC LIMIT 1""")[0]
    assert log[0] == 1 and log[1] == "ALTERACAO" and log[3] == "Retorno em 15 dias"


def test_etl_nao_le_dados_identificaveis():
    with como("svp_etl") as c:
        c.execute("SELECT id_tutor, cidade FROM tutor LIMIT 1")          # permitido
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            c.execute("SELECT cpf FROM tutor LIMIT 1")
    with como("svp_etl") as c, pytest.raises(psycopg.errors.InsufficientPrivilege):
        c.execute("SELECT anamnese FROM atendimento LIMIT 1")


def test_anonimizacao_respeita_prazo_legal():
    with pytest.raises(psycopg.errors.RaiseException):
        su_sql("SELECT fn_anonimizar_tutor(3)")                        # atendido em 2026
    su_sql("SELECT fn_anonimizar_tutor(299, TRUE)")                     # pedido do tutor, forçado
    nome, cpf, cidade = su_sql("SELECT nome, cpf, cidade FROM tutor WHERE id_tutor = 299")[0]
    assert cpf is None and nome.startswith("TUTOR ANONIMIZADO") and cidade is not None
    # o histórico clínico continua
    assert su_sql("""SELECT count(*) FROM animal WHERE id_tutor = 299""")[0][0] >= 1


def test_desligamento_desativa_usuario():
    su_sql("UPDATE funcionario SET data_desligamento = current_date WHERE id_funcionario = 13")
    assert su_sql("SELECT ativo FROM usuario WHERE id_funcionario = 13")[0][0] is False


def test_rotinas_de_manutencao_rodam():
    itens = dict((i, n) for i, n in su_sql("SELECT * FROM fn_expurgar_temporarios()"))
    assert "sessoes expiradas" in itens
    particoes = su_sql("SELECT * FROM fn_manter_particoes_log()")
    assert len([p for p in particoes if p[1] == "ativa"]) == 4
