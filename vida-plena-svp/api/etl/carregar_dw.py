"""ETL noturno: banco operacional (réplica de leitura) → data warehouse.

- Lê com o papel svp_etl, que só enxerga colunas não identificáveis.
- Pseudonimiza ids de animal e tutor com HMAC-SHA256 (chave no cofre).
- Recarrega uma janela móvel (padrão: 90 dias) de forma idempotente:
  apaga os fatos da janela e insere de novo, numa única transação.
  Rodar duas vezes dá o mesmo resultado; status que mudam depois
  (falta, fatura paga) são corrigidos na carga seguinte.

Uso: python -m etl.carregar_dw [--dias 90 | --completo]
"""
import argparse
import hashlib
import hmac
import json
import os
import sys
from datetime import date, timedelta

import psycopg
from psycopg.rows import dict_row

DIMENSOES = {
    "dim_unidade": ("SELECT id_unidade, nome, cidade, uf FROM unidade", "id_unidade"),
    "dim_especie": ("SELECT id_especie, nome FROM especie", "id_especie"),
    "dim_veterinario": ("""SELECT v.id_veterinario, f.nome, f.id_unidade
                           FROM veterinario v JOIN funcionario f ON f.id_funcionario = v.id_veterinario""",
                        "id_veterinario"),
    "dim_diagnostico": ("SELECT id_diagnostico, codigo, descricao, cronico FROM diagnostico", "id_diagnostico"),
    "dim_servico": ("SELECT id_servico, descricao, tipo FROM servico", "id_servico"),
}

SQL_AGENDAMENTO = """
SELECT id_agendamento, (data_hora AT TIME ZONE 'America/Bahia')::DATE AS data, id_unidade, id_veterinario,
       modalidade, status, (extract(epoch FROM data_hora - criado_em) / 86400)::INT AS antecedencia_dias
FROM agendamento
WHERE data_hora >= %(ini)s AND data_hora < %(fim)s"""

SQL_ATENDIMENTO = """
SELECT atd.id_atendimento, (atd.inicio_em AT TIME ZONE 'America/Bahia')::DATE AS data,
       ag.id_unidade, atd.id_veterinario, a.id_especie, ag.modalidade, a.porte,
       a.data_nascimento, a.id_animal, a.id_tutor, t.cidade, t.uf, tr.prioridade,
       round((extract(epoch FROM atd.inicio_em - ag.chegada_em) / 60)::NUMERIC, 1) AS espera_min,
       round((extract(epoch FROM atd.fim_em - atd.inicio_em) / 60)::NUMERIC, 1)    AS duracao_min,
       (SELECT ad.id_diagnostico FROM atendimento_diagnostico ad
         WHERE ad.id_atendimento = atd.id_atendimento AND ad.tipo = 'PRINCIPAL') AS id_diagnostico
FROM atendimento atd
JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento
JOIN animal a       ON a.id_animal = ag.id_animal
JOIN tutor t        ON t.id_tutor = a.id_tutor
LEFT JOIN triagem tr ON tr.id_agendamento = ag.id_agendamento
WHERE atd.inicio_em >= %(ini)s AND atd.inicio_em < %(fim)s"""

SQL_FATURAMENTO = """
SELECT f.id_fatura, (f.emitida_em AT TIME ZONE 'America/Bahia')::DATE AS data, f.id_unidade, f.desconto, f.status,
       coalesce((SELECT sum(i.quantidade * i.valor_unitario) FROM item_fatura i WHERE i.id_fatura = f.id_fatura), 0) AS bruto,
       coalesce((SELECT sum(p.valor) FROM pagamento p WHERE p.id_fatura = f.id_fatura), 0) AS pago,
       (SELECT p.forma FROM pagamento p WHERE p.id_fatura = f.id_fatura ORDER BY p.valor DESC LIMIT 1) AS forma,
       EXISTS (SELECT 1 FROM item_fatura i JOIN servico s ON s.id_servico = i.id_servico
               WHERE i.id_fatura = f.id_fatura AND s.tipo = 'TELECONSULTA') AS teleconsulta
FROM fatura f
WHERE f.emitida_em >= %(ini)s AND f.emitida_em < %(fim)s"""


def pseudonimo(chave: bytes, tipo: str, valor: int) -> str:
    return hmac.new(chave, f"{tipo}:{valor}".encode(), hashlib.sha256).hexdigest()


def faixa_etaria(nascimento: date | None, referencia: date) -> str:
    if nascimento is None:
        return "sem data"
    anos = (referencia - nascimento).days / 365.25
    return "filhote" if anos < 1 else "adulto" if anos < 8 else "idoso"


def carregar(origem_url: str, destino_url: str, chave: bytes, dias: int | None) -> dict:
    fim = date.today() + timedelta(days=1)
    ini = date(2000, 1, 1) if dias is None else fim - timedelta(days=dias)
    janela = {"ini": ini, "fim": fim}
    contagem: dict[str, int] = {}

    with psycopg.connect(origem_url, row_factory=dict_row) as src, \
         psycopg.connect(destino_url, row_factory=dict_row) as dst:
        src.read_only = True
        exec_id = dst.execute("INSERT INTO dw.etl_execucao (janela_inicio, janela_fim) VALUES (%s, %s) "
                              "RETURNING id_execucao", (ini, fim)).fetchone()["id_execucao"]
        dst.commit()
        try:
            with dst.transaction():
                # dimensões: upsert completo (são pequenas)
                for tabela, (sql, pk) in DIMENSOES.items():
                    linhas = src.execute(sql).fetchall()
                    if not linhas:
                        continue
                    cols = list(linhas[0].keys())
                    upd = ", ".join(f"{c} = EXCLUDED.{c}" for c in cols if c != pk)
                    dst.cursor().executemany(
                        f"INSERT INTO dw.{tabela} ({', '.join(cols)}) VALUES ({', '.join(['%s'] * len(cols))}) "
                        f"ON CONFLICT ({pk}) DO UPDATE SET {upd}",
                        [tuple(l.values()) for l in linhas])
                    contagem[tabela] = len(linhas)

                # fatos: apaga a janela e recarrega (idempotente)
                ag = src.execute(SQL_AGENDAMENTO, janela).fetchall()
                dst.execute("DELETE FROM dw.fato_agendamento WHERE data >= %s AND data < %s", (ini, fim))
                dst.cursor().executemany(
                    "INSERT INTO dw.fato_agendamento VALUES (%s, %s, %s, %s, %s, %s, %s)",
                    [(r["id_agendamento"], r["data"], r["id_unidade"], r["id_veterinario"], r["modalidade"],
                      r["status"], r["antecedencia_dias"]) for r in ag])
                contagem["fato_agendamento"] = len(ag)

                at = src.execute(SQL_ATENDIMENTO, janela).fetchall()
                dst.execute("DELETE FROM dw.fato_atendimento WHERE data >= %s AND data < %s", (ini, fim))
                dst.cursor().executemany(
                    """INSERT INTO dw.fato_atendimento (id_atendimento, data, id_unidade, id_veterinario, id_especie,
                           id_diagnostico, modalidade, porte, faixa_etaria, prioridade, espera_min, duracao_min,
                           animal_pseudo, tutor_pseudo, cidade_tutor, uf_tutor)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                    [(r["id_atendimento"], r["data"], r["id_unidade"], r["id_veterinario"], r["id_especie"],
                      r["id_diagnostico"], r["modalidade"], r["porte"], faixa_etaria(r["data_nascimento"], r["data"]),
                      r["prioridade"], r["espera_min"], r["duracao_min"],
                      pseudonimo(chave, "animal", r["id_animal"]), pseudonimo(chave, "tutor", r["id_tutor"]),
                      r["cidade"], r["uf"]) for r in at])
                contagem["fato_atendimento"] = len(at)

                fa = src.execute(SQL_FATURAMENTO, janela).fetchall()
                dst.execute("DELETE FROM dw.fato_faturamento WHERE data >= %s AND data < %s", (ini, fim))
                dst.cursor().executemany(
                    "INSERT INTO dw.fato_faturamento VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                    [(r["id_fatura"], r["data"], r["id_unidade"], r["bruto"], r["desconto"],
                      r["bruto"] - r["desconto"], r["pago"], r["forma"], r["status"], r["teleconsulta"]) for r in fa])
                contagem["fato_faturamento"] = len(fa)

                dst.execute("""UPDATE dw.etl_execucao SET terminada_em = now(), status = 'OK', linhas = %s
                               WHERE id_execucao = %s""", (json.dumps(contagem), exec_id))
        except Exception as e:
            dst.execute("UPDATE dw.etl_execucao SET terminada_em = now(), status = 'ERRO', erro = %s "
                        "WHERE id_execucao = %s", (str(e)[:2000], exec_id))
            dst.commit()
            raise
    return contagem


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dias", type=int, default=90)
    ap.add_argument("--completo", action="store_true")
    a = ap.parse_args()
    try:
        chave = os.environ["SVP_ETL_CHAVE_PSEUDONIMO"].encode()
        r = carregar(os.environ["SVP_ETL_DATABASE_URL"], os.environ["SVP_DW_ETL_DATABASE_URL"],
                     chave, None if a.completo else a.dias)
    except KeyError as e:
        sys.exit(f"Variável de ambiente ausente: {e}")
    print(json.dumps(r, ensure_ascii=False))


if __name__ == "__main__":
    main()
