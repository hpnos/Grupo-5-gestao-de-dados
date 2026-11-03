"""Carga do data warehouse e relatório da diretoria."""
import os

import psycopg

from conftest import DW, su_sql, url


def test_etl_carrega_e_e_idempotente():
    from etl.carregar_dw import carregar
    args = (os.environ["SVP_ETL_DATABASE_URL"], os.environ["SVP_DW_ETL_DATABASE_URL"],
            os.environ["SVP_ETL_CHAVE_PSEUDONIMO"].encode(), None)
    primeira = carregar(*args)
    segunda = carregar(*args)
    assert primeira == segunda
    assert primeira["fato_atendimento"] == su_sql("SELECT count(*) FROM atendimento")[0][0]
    with psycopg.connect(url("svp_bi", DW)) as c:
        assert c.execute("SELECT count(*) FROM dw.fato_atendimento").fetchone()[0] == primeira["fato_atendimento"]


def test_dw_nao_tem_dados_identificaveis():
    with psycopg.connect(url("svp_bi", DW)) as c:
        colunas = {r[0] for r in c.execute(
            "SELECT column_name FROM information_schema.columns WHERE table_schema = 'dw'").fetchall()}
        assert not colunas & {"cpf", "nome_tutor", "telefone", "email", "anamnese", "id_tutor", "id_animal"}
        pseudo = c.execute("SELECT animal_pseudo FROM dw.fato_atendimento LIMIT 1").fetchone()[0]
        assert len(pseudo) == 64


def test_bi_so_le_o_dw():
    with psycopg.connect(url("svp_bi", DW), autocommit=True) as c:
        try:
            c.execute("DELETE FROM dw.fato_atendimento")
            assert False, "svp_bi não deveria apagar"
        except psycopg.errors.InsufficientPrivilege:
            pass


def test_diretoria_ve_kpis_e_espera_cai(cliente, token):
    assert cliente.get("/relatorios/kpis", headers=token("vet.ana")).status_code == 403
    r = cliente.get("/relatorios/kpis", headers=token("dir.joao"))
    assert r.status_code == 200
    centro = [l for l in r.json()["linhas"] if l["unidade"] == "Vida Plena Centro" and l["mes"] < "2026-11"]
    assert len(centro) == 6
    assert float(centro[0]["espera_media_min"]) > float(centro[-1]["espera_media_min"])      # mai > out
    assert float(centro[-1]["teleconsulta_pct"]) > float(centro[0]["teleconsulta_pct"])      # telemedicina cresce
