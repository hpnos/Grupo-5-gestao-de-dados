"""API do Sistema Vida Plena (protótipo das Entregas 5 a 7)."""
from contextlib import asynccontextmanager

from fastapi import FastAPI

from .db import fechar_pools, transacao
from .rotas import auth, exames, integracoes, prontuario, relatorios


@asynccontextmanager
async def ciclo_de_vida(app: FastAPI):
    yield
    fechar_pools()


app = FastAPI(title="Sistema Vida Plena (SVP) — API", version="0.3.0", lifespan=ciclo_de_vida,
              description="Protótipo de armazenamento, segurança e integração de dados.")


@app.middleware("http")
async def cabecalhos_de_seguranca(request, call_next):
    resposta = await call_next(request)
    resposta.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    resposta.headers["X-Content-Type-Options"] = "nosniff"
    resposta.headers["Cache-Control"] = "no-store"          # dado clínico não fica em cache
    return resposta


@app.get("/saude", tags=["infra"])
def saude():
    with transacao() as conn:
        conn.execute("SELECT 1")
    return {"status": "ok"}


for r in (auth, prontuario, exames, integracoes, relatorios):
    app.include_router(r.router)
