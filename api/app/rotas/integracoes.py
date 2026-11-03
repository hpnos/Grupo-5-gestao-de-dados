"""Webhook de resultado do laboratório.

Ordem das verificações (cada uma com resposta própria):
 1. tamanho do corpo                         → 413
 2. assinatura HMAC + janela de 5 minutos    → 401 (registrado no log)
 3. chave de idempotência já processada      → 200 "duplicado" (nada muda)
 4. formato do JSON (Pydantic)               → 422 + registro REJEITADA
 5. pedido existe e protocolo confere        → 422 + registro REJEITADA
 6. versão mais antiga que a gravada         → 200 "versao_antiga" (ignorada)
 7. hash do laudo confere com o conteúdo     → 422 + registro REJEITADA
 8. grava arquivo, documento, pedido e inbox → 200, tudo em UMA transação
"""
import base64
import binascii
import hashlib
import hmac
import time
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, Field, ValidationError

from .. import armazenamento
from ..config import config, obter_segredo
from ..db import transacao
from ..seguranca import ip_do_cliente

router = APIRouter(prefix="/integracoes", tags=["integrações"])


class Laudo(BaseModel):
    nome_arquivo: str = Field(max_length=200, pattern=r"^[\w\-. ]+\.pdf$")
    tipo_conteudo: Literal["application/pdf"]
    conteudo_base64: str = Field(min_length=4)
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")


class ResultadoExame(BaseModel):
    protocolo: str = Field(min_length=1, max_length=40)
    referencia_svp: int = Field(gt=0)
    versao: int = Field(ge=1, le=100)
    status: Literal["CONCLUIDO"]
    concluido_em: datetime
    resumo: str = Field(max_length=2000)
    laudo: Laudo


def assinar(segredo: str, timestamp: str, corpo: bytes) -> str:
    return "sha256=" + hmac.new(segredo.encode(), timestamp.encode() + b"." + corpo, hashlib.sha256).hexdigest()


def _registrar(conn, origem, chave, corpo, status, detalhe):
    conn.execute(
        """INSERT INTO integracao_recebida (origem, chave_idempotencia, payload_sha256, status, detalhe)
           VALUES (%s, %s, %s, %s, %s) ON CONFLICT (origem, chave_idempotencia) DO NOTHING""",
        (origem, chave, hashlib.sha256(corpo).hexdigest(), status, detalhe[:300]))


@router.post("/laboratorio/{id_laboratorio}/resultados")
async def receber_resultado(
    id_laboratorio: int,
    request: Request,
    x_svp_timestamp: str = Header(...),
    x_svp_assinatura: str = Header(...),
    idempotency_key: str = Header(..., max_length=80),
):
    corpo = await request.body()
    if len(corpo) > config().max_corpo_webhook:
        raise HTTPException(413, "Corpo maior que o limite de 10 MB")
    origem = f"laboratorio:{id_laboratorio}"

    # --- 2. autenticidade --------------------------------------------------
    with transacao() as conn:
        lab = conn.execute("SELECT segredo_ref FROM laboratorio WHERE id_laboratorio = %s AND ativo",
                           (id_laboratorio,)).fetchone()
    try:
        ts_ok = abs(time.time() - int(x_svp_timestamp)) <= config().janela_webhook_s
    except ValueError:
        ts_ok = False
    assinatura_ok = bool(lab and lab["segredo_ref"]) and hmac.compare_digest(
        assinar(obter_segredo(lab["segredo_ref"] + "/webhook"), x_svp_timestamp, corpo), x_svp_assinatura)
    if not (ts_ok and assinatura_ok):
        with transacao() as conn:
            conn.execute("SELECT fn_registrar_acesso(NULL, 'ACESSO_NEGADO', 'integracao_recebida', NULL, %s, %s)",
                         (ip_do_cliente(request),
                          f"webhook {origem} com assinatura inválida ou expirada"))
        raise HTTPException(401, "Assinatura inválida ou fora da janela de 5 minutos")

    erro: HTTPException | None = None
    with transacao() as conn:
        # trava a chave: duas entregas simultâneas da mesma mensagem não passam juntas
        conn.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (origem + idempotency_key,))

        # --- 3. duplicidade ------------------------------------------------
        if conn.execute("SELECT 1 FROM integracao_recebida WHERE origem = %s AND chave_idempotencia = %s",
                        (origem, idempotency_key)).fetchone():
            return {"situacao": "duplicado"}

        # --- 4. formato ----------------------------------------------------
        try:
            r = ResultadoExame.model_validate_json(corpo)
        except ValidationError as e:
            _registrar(conn, origem, idempotency_key, corpo, "REJEITADA", f"formato: {e.error_count()} erro(s)")
            erro = HTTPException(422, {"erro": "payload inválido", "detalhes": e.errors(include_url=False,
                                                                                    include_input=False)})
        if erro is None:
            # --- 5. pedido e protocolo -----------------------------------------
            s = conn.execute(
                """SELECT s.id_solicitacao, s.status, s.protocolo_laboratorio, s.versao_resultado, ag.id_animal
                   FROM solicitacao_exame s
                   JOIN atendimento atd ON atd.id_atendimento = s.id_atendimento
                   JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento
                   WHERE s.id_solicitacao = %s AND s.id_laboratorio = %s
                   FOR UPDATE OF s""", (r.referencia_svp, id_laboratorio)).fetchone()
            if s is None or s["protocolo_laboratorio"] != r.protocolo or s["status"] not in ("ENVIADO", "CONCLUIDO"):
                _registrar(conn, origem, idempotency_key, corpo, "REJEITADA",
                           f"pedido {r.referencia_svp} / protocolo {r.protocolo} não confere")
                erro = HTTPException(422, "Pedido inexistente, de outro laboratório ou protocolo divergente")

        if erro is None:
            # --- 6. versão -----------------------------------------------------
            if r.versao <= s["versao_resultado"]:
                _registrar(conn, origem, idempotency_key, corpo, "IGNORADA",
                           f"versão {r.versao} <= gravada {s['versao_resultado']}")
                return {"situacao": "versao_antiga", "versao_gravada": s["versao_resultado"]}

            # --- 7. integridade do laudo ---------------------------------------
            try:
                pdf = base64.b64decode(r.laudo.conteudo_base64, validate=True)
            except (binascii.Error, ValueError):
                pdf = b""
            if not pdf or armazenamento.sha256(pdf) != r.laudo.sha256:
                _registrar(conn, origem, idempotency_key, corpo, "REJEITADA", "hash do laudo não confere")
                erro = HTTPException(422, "O SHA-256 informado não confere com o conteúdo do laudo")

        if erro is None:
            # --- 8. grava ------------------------------------------------------
            caminho, h = armazenamento.gravar(pdf)
            # laudo é imutável: o mesmo arquivo (mesmo hash) reaproveita o registro
            doc = conn.execute("SELECT id_documento FROM documento WHERE id_animal = %s AND hash_sha256 = %s",
                               (s["id_animal"], h)).fetchone()
            if doc is None:
                doc = conn.execute(
                    """INSERT INTO documento (id_animal, tipo, nome_arquivo, caminho, hash_sha256, origem)
                       VALUES (%s, 'LAUDO', %s, %s, %s, %s) RETURNING id_documento""",
                    (s["id_animal"], r.laudo.nome_arquivo, caminho, h, origem)).fetchone()
            conn.execute(
                """UPDATE solicitacao_exame
                   SET status = 'CONCLUIDO', resultado_em = %s, resultado_resumo = %s,
                       id_documento = %s, versao_resultado = %s, atualizado_em = now()
                   WHERE id_solicitacao = %s""",
                (r.concluido_em, r.resumo, doc["id_documento"], r.versao, s["id_solicitacao"]))
            _registrar(conn, origem, idempotency_key, corpo, "PROCESSADA",
                       f"pedido {s['id_solicitacao']} versão {r.versao}")
            return {"situacao": "processado", "id_solicitacao": s["id_solicitacao"],
                    "id_documento": doc["id_documento"], "versao": r.versao}
    raise erro           # depois do commit: a rejeição fica registrada
