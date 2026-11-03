"""Relatórios da diretoria (lidos do data warehouse) e consulta ao log."""
from fastapi import APIRouter, Depends, Query

from ..db import leitura_dw, transacao
from ..seguranca import Usuario, exige

router = APIRouter(tags=["relatórios e auditoria"])


@router.get("/relatorios/kpis")
def kpis(usuario: Usuario = Depends(exige("relatorios", "LER"))):
    """Indicadores dos objetivos estratégicos, sem identificar tutor ou animal."""
    with leitura_dw() as conn:
        linhas = conn.execute(
            "SELECT * FROM dw.vw_kpi_mensal ORDER BY mes, unidade").fetchall()
    return {"fonte": "data warehouse (carga noturna)", "linhas": linhas}


@router.get("/auditoria/logs")
def logs(tabela: str | None = None, id_registro: int | None = None, acao: str | None = None,
         limite: int = Query(100, le=500), usuario: Usuario = Depends(exige("log", "LER"))):
    filtros, args = [], []
    for coluna, valor in (("tabela", tabela), ("id_registro", id_registro), ("acao", acao)):
        if valor is not None:
            filtros.append(f"{coluna} = %s")
            args.append(valor)
    where = ("WHERE " + " AND ".join(filtros)) if filtros else ""
    with transacao(usuario.id_usuario) as conn:
        return conn.execute(
            f"""SELECT l.id_log, l.ocorrido_em, u.login, l.acao, l.tabela, l.id_registro,
                       host(l.ip_origem) AS ip, l.justificativa
                FROM log_auditoria l LEFT JOIN usuario u USING (id_usuario)
                {where} ORDER BY l.ocorrido_em DESC, l.id_log DESC LIMIT %s""",
            (*args, limite)).fetchall()
