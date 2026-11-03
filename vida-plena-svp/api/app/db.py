"""Acesso ao banco com pool de conexões e contexto de auditoria."""
from contextlib import contextmanager

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import config

_pools: dict[str, ConnectionPool] = {}


def _pool(url: str) -> ConnectionPool:
    if url not in _pools:
        _pools[url] = ConnectionPool(url, min_size=1, max_size=10, open=True,
                                     kwargs={"row_factory": dict_row})
    return _pools[url]


def fechar_pools() -> None:
    for p in _pools.values():
        p.close()
    _pools.clear()


@contextmanager
def transacao(id_usuario: int | None = None):
    """Abre uma transação no banco operacional.

    Informa ao banco quem é o usuário logado (SET LOCAL svp.id_usuario),
    para que os gatilhos de auditoria gravem o autor de cada alteração.
    """
    with _pool(config().database_url).connection() as conn:
        with conn.transaction():
            if id_usuario is not None:
                conn.execute("SELECT set_config('svp.id_usuario', %s, true)", (str(id_usuario),))
            yield conn


@contextmanager
def leitura_dw():
    """Conexão somente leitura ao data warehouse (relatórios)."""
    with _pool(config().dw_database_url).connection() as conn:
        conn.read_only = True
        yield conn
