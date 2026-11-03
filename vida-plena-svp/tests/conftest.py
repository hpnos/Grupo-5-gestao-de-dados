"""Prepara bancos novos para os testes e a API apontando para eles.

Precisa de um PostgreSQL 16 acessível como superusuário. Variáveis:
  TEST_PGHOST (localhost), TEST_PGPORT (5432), TEST_PGUSER (postgres), TEST_PGPASSWORD
Rodar da raiz do repositório:  pytest -q
"""
import base64
import hashlib
import hmac
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest
from cryptography.fernet import Fernet

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ / "api"))

H = os.environ.get("TEST_PGHOST", "localhost")
PORTA = os.environ.get("TEST_PGPORT", "5432")
SU = os.environ.get("TEST_PGUSER", "postgres")
SENHA_SU = os.environ.get("TEST_PGPASSWORD", "")
DB, DW = "svp_teste", "svp_dw_teste"
SENHA_PAPEIS = "senha-de-teste"


def psql(banco: str, *args: str) -> None:
    env = {**os.environ, "PGPASSWORD": SENHA_SU}
    subprocess.run(["psql", "-h", H, "-p", PORTA, "-U", SU, "-d", banco, "-v", "ON_ERROR_STOP=1", "-q", *args],
                   check=True, env=env, stdout=subprocess.DEVNULL)


def url(papel: str, banco: str) -> str:
    return f"postgresql://{papel}:{SENHA_PAPEIS}@{H}:{PORTA}/{banco}"


def preparar_bancos() -> None:
    psql("postgres", "-c", f"DROP DATABASE IF EXISTS {DB} WITH (FORCE)",
         "-c", f"DROP DATABASE IF EXISTS {DW} WITH (FORCE)",
         "-c", f"CREATE DATABASE {DB}", "-c", f"CREATE DATABASE {DW}")
    for f in sorted((RAIZ / "database/scripts").glob("0*.sql")):
        psql(DB, "-f", str(f))
    psql(DB, "-f", str(RAIZ / "database/data/seed.sql"))
    psql(DW, "-f", str(RAIZ / "database/dw/01_dw.sql"))
    for papel in ("svp_api", "svp_etl", "svp_bi"):
        psql("postgres", "-c", f"ALTER ROLE {papel} PASSWORD '{SENHA_PAPEIS}'")


SEGREDO_WEBHOOK = "segredo-webhook-de-teste"
TOKEN_LAB = "token-lab-de-teste"


@pytest.fixture(scope="session", autouse=True)
def ambiente(tmp_path_factory):
    preparar_bancos()
    os.environ.update({
        "SVP_DATABASE_URL": url("svp_api", DB),
        "SVP_DW_DATABASE_URL": url("svp_api", DW),
        "SVP_JWT_SECRET": "jwt-de-teste-" + "x" * 32,
        "SVP_CHAVE_CIFRA": Fernet.generate_key().decode(),
        "SVP_URL_PUBLICA": "http://testserver",
        "SVP_PASTA_DOCUMENTOS": str(tmp_path_factory.mktemp("documentos")),
        "SVP_SECRET__LABORATORIO_1_WEBHOOK": SEGREDO_WEBHOOK,
        "SVP_SECRET__LABORATORIO_1_API_TOKEN": TOKEN_LAB,
        "SVP_ETL_DATABASE_URL": url("svp_etl", DB),
        "SVP_DW_ETL_DATABASE_URL": url("svp_etl", DW),
        "SVP_ETL_CHAVE_PSEUDONIMO": "chave-pseudonimo-de-teste",
    })
    yield


@pytest.fixture(scope="session")
def cliente(ambiente):
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="session")
def token(cliente):
    cache: dict[str, str] = {}

    def obter(login: str) -> dict:
        if login not in cache:
            r = cliente.post("/auth/login", json={"login": login, "senha": "VidaPlena@2026"})
            assert r.status_code == 200, r.text
            cache[login] = r.json()["access_token"]
        return {"Authorization": f"Bearer {cache[login]}"}
    return obter


def su_sql(sql: str, *args):
    """Consulta direta como superusuário (para conferir o efeito no banco)."""
    import psycopg
    with psycopg.connect(host=H, port=PORTA, user=SU, password=SENHA_SU or None, dbname=DB) as c:
        cur = c.execute(sql, args or None)
        return cur.fetchall() if cur.description else []


def webhook(corpo: dict, chave: str, segredo: str = SEGREDO_WEBHOOK, ts: int | None = None) -> tuple[bytes, dict]:
    bruto = json.dumps(corpo).encode()
    ts = str(ts or int(time.time()))
    assinatura = "sha256=" + hmac.new(segredo.encode(), ts.encode() + b"." + bruto, hashlib.sha256).hexdigest()
    return bruto, {"Content-Type": "application/json", "X-SVP-Timestamp": ts,
                   "X-SVP-Assinatura": assinatura, "Idempotency-Key": chave}


def resultado(protocolo: str, ref: int, versao: int = 1, pdf: bytes = b"%PDF-1.4 laudo v1",
              sha: str | None = None) -> dict:
    return {"protocolo": protocolo, "referencia_svp": ref, "versao": versao, "status": "CONCLUIDO",
            "concluido_em": "2026-11-02T15:00:00-03:00", "resumo": "Sem alterações.",
            "laudo": {"nome_arquivo": f"laudo-v{versao}.pdf", "tipo_conteudo": "application/pdf",
                      "conteudo_base64": base64.b64encode(pdf).decode(),
                      "sha256": sha or hashlib.sha256(pdf).hexdigest()}}
