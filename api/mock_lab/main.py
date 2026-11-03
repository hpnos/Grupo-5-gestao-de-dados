"""Laboratório simulado (LabVet) para demonstrar a integração de ponta a ponta.

POST /api/v1/pedidos              recebe o pedido do SVP (Bearer + Idempotency-Key)
POST /simular/concluir/{protocolo} gera um laudo PDF e chama o webhook do SVP
POST /simular/falhas/{n}          faz as próximas n chamadas devolverem 503
"""
import base64
import hashlib
import hmac
import json
import os
import time
import uuid
from datetime import datetime, timezone

import httpx
from fastapi import FastAPI, Header, HTTPException

app = FastAPI(title="LabVet (simulado)")
TOKEN = os.environ.get("LAB_API_TOKEN", "")
SEGREDO_WEBHOOK = os.environ.get("LAB_WEBHOOK_SECRET", "")
pedidos: dict[str, dict] = {}          # protocolo -> pedido
por_chave: dict[str, str] = {}         # Idempotency-Key -> protocolo
falhas_restantes = {"n": 0}


@app.post("/api/v1/pedidos", status_code=201)
def receber_pedido(pedido: dict, authorization: str = Header(""), idempotency_key: str = Header(...)):
    if not TOKEN or authorization != f"Bearer {TOKEN}":
        raise HTTPException(401, "token inválido")
    if falhas_restantes["n"] > 0:
        falhas_restantes["n"] -= 1
        raise HTTPException(503, "laboratório em manutenção")
    if idempotency_key in por_chave:                       # reenvio: mesmo protocolo
        return {"protocolo": por_chave[idempotency_key], "reenvio": True}
    for campo in ("referencia_svp", "exame", "material", "paciente", "callback_url"):
        if campo not in pedido:
            raise HTTPException(422, f"campo obrigatório ausente: {campo}")
    protocolo = "LV-" + uuid.uuid4().hex[:8].upper()
    pedidos[protocolo] = {**pedido, "versao": 0}
    por_chave[idempotency_key] = protocolo
    return {"protocolo": protocolo, "previsao_resultado_dias": 2}


@app.post("/simular/falhas/{n}")
def simular_falhas(n: int):
    falhas_restantes["n"] = n
    return {"proximas_falhas": n}


def _pdf_ficticio(protocolo: str, versao: int) -> bytes:
    texto = f"Laudo {protocolo} v{versao} - LabVet (ficticio)"
    return (b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
            b"2 0 obj<</Type/Pages/Count 0/Kids[]>>endobj\n% " + texto.encode() + b"\n%%EOF\n")


@app.post("/simular/concluir/{protocolo}")
def concluir(protocolo: str, versao: int | None = None):
    if protocolo not in pedidos:
        raise HTTPException(404, "protocolo desconhecido")
    p = pedidos[protocolo]
    p["versao"] = versao or p["versao"] + 1
    pdf = _pdf_ficticio(protocolo, p["versao"])
    corpo = json.dumps({
        "protocolo": protocolo,
        "referencia_svp": p["referencia_svp"],
        "versao": p["versao"],
        "status": "CONCLUIDO",
        "concluido_em": datetime.now(timezone.utc).isoformat(),
        "resumo": "Hemácias, leucócitos e plaquetas dentro da referência para a espécie.",
        "laudo": {"nome_arquivo": f"laudo-{protocolo}-v{p['versao']}.pdf",
                  "tipo_conteudo": "application/pdf",
                  "conteudo_base64": base64.b64encode(pdf).decode(),
                  "sha256": hashlib.sha256(pdf).hexdigest()},
    }).encode()
    ts = str(int(time.time()))
    assinatura = "sha256=" + hmac.new(SEGREDO_WEBHOOK.encode(), ts.encode() + b"." + corpo,
                                      hashlib.sha256).hexdigest()
    r = httpx.post(p["callback_url"], content=corpo, timeout=10,
                   headers={"Content-Type": "application/json", "X-SVP-Timestamp": ts,
                            "X-SVP-Assinatura": assinatura,
                            "Idempotency-Key": f"{protocolo}-v{p['versao']}"})
    return {"webhook_status": r.status_code, "resposta": r.json()}
