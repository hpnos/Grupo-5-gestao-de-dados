"""Worker do outbox: entrega os eventos de integração com retentativa.

Fluxo de cada evento:
  PENDENTE/ERRO --(pega com lease de 5 min, SKIP LOCKED)--> PROCESSANDO
  PROCESSANDO --(2xx)--> ENVIADO
  PROCESSANDO --(timeout, rede, 5xx, 408, 429)--> ERRO (tenta de novo com espera crescente)
  PROCESSANDO --(outros 4xx: dado inválido)--> FALHA_DEFINITIVA (vai para o painel da TI)
  ERRO na 12ª tentativa (~5 h depois) --> FALHA_DEFINITIVA

Se o worker cair no meio, o lease vence e o evento volta para a fila;
como todo envio leva a mesma Idempotency-Key, o laboratório não cria
pedido duplicado.
"""
import logging
import random
import sys
import time

import httpx
from psycopg.types.json import Jsonb

from .config import obter_segredo
from .db import fechar_pools, transacao

log = logging.getLogger("svp.worker")
MAX_TENTATIVAS = 12                 # ~5 horas tentando (30 s, 1, 2, 4 ... até 1 h)
TIMEOUT = httpx.Timeout(10.0, connect=5.0)


def espera_segundos(tentativa: int) -> int:
    """30 s, 1 min, 2 min, 4 min ... até 1 h, com até 20% de variação."""
    base = min(3600, 30 * 2 ** (tentativa - 1))
    return int(base * random.uniform(1.0, 1.2))


def _pegar_lote(limite: int) -> list[dict]:
    with transacao() as conn:
        return conn.execute(
            """UPDATE integracao_evento e
               SET status = 'PROCESSANDO', travado_ate = now() + INTERVAL '5 minutes',
                   tentativas = e.tentativas + 1
               WHERE id_evento IN (
                   SELECT id_evento FROM integracao_evento
                   WHERE (status IN ('PENDENTE','ERRO') AND proxima_tentativa_em <= now())
                      OR (status = 'PROCESSANDO' AND travado_ate < now())   -- worker caiu
                   ORDER BY id_evento
                   LIMIT %s
                   FOR UPDATE SKIP LOCKED)
               RETURNING e.*""", (limite,)).fetchall()


def _destino_laboratorio(id_laboratorio: int) -> tuple[str, str]:
    with transacao() as conn:
        lab = conn.execute("SELECT api_url, segredo_ref FROM laboratorio WHERE id_laboratorio = %s",
                           (id_laboratorio,)).fetchone()
    token = obter_segredo(lab["segredo_ref"] + "/api-token")
    return lab["api_url"], token


def _enviar(cliente: httpx.Client, evento: dict) -> httpx.Response:
    if evento["tipo"] != "EXAME_SOLICITADO":
        raise ValueError(f"tipo de evento sem entregador no protótipo: {evento['tipo']}")
    url, token = _destino_laboratorio(int(evento["destino"].split(":")[1]))
    return cliente.post(f"{url}/api/v1/pedidos", json=evento["payload"],
                        headers={"Authorization": f"Bearer {token}",
                                 "Idempotency-Key": evento["chave_idempotencia"]})


def _concluir(evento: dict, resposta: httpx.Response) -> None:
    corpo = resposta.json()
    protocolo = corpo.get("protocolo")
    if not protocolo:
        raise ValueError("resposta 2xx sem protocolo")
    with transacao() as conn:
        conn.execute(
            """UPDATE integracao_evento SET status = 'ENVIADO', enviado_em = now(), travado_ate = NULL,
                      resposta = %s, ultimo_erro = NULL WHERE id_evento = %s""",
            (Jsonb(corpo), evento["id_evento"]))
        conn.execute(
            """UPDATE solicitacao_exame SET status = 'ENVIADO', protocolo_laboratorio = %s, atualizado_em = now()
               WHERE id_solicitacao = %s AND status = 'COLETADO'""",
            (protocolo, evento["id_agregado"]))


def _falhar(evento: dict, erro: str, definitiva: bool) -> str:
    definitiva = definitiva or evento["tentativas"] >= MAX_TENTATIVAS
    with transacao() as conn:
        conn.execute(
            """UPDATE integracao_evento
               SET status = %s, ultimo_erro = %s, travado_ate = NULL,
                   proxima_tentativa_em = now() + make_interval(secs => %s)
               WHERE id_evento = %s""",
            ("FALHA_DEFINITIVA" if definitiva else "ERRO", erro[:500],
             0 if definitiva else espera_segundos(evento["tentativas"]), evento["id_evento"]))
    return "FALHA_DEFINITIVA" if definitiva else "ERRO"


def processar_lote(cliente: httpx.Client, limite: int = 10) -> dict[str, int]:
    resultado: dict[str, int] = {}
    for evento in _pegar_lote(limite):
        try:
            r = _enviar(cliente, evento)
            if r.is_success:
                _concluir(evento, r)
                situacao = "ENVIADO"
            elif r.status_code in (408, 429) or r.status_code >= 500:
                situacao = _falhar(evento, f"HTTP {r.status_code}: {r.text[:200]}", definitiva=False)
            else:
                situacao = _falhar(evento, f"HTTP {r.status_code} (dado recusado): {r.text[:200]}", definitiva=True)
        except (httpx.TimeoutException, httpx.TransportError) as e:
            situacao = _falhar(evento, f"{type(e).__name__}: {e}", definitiva=False)
        except Exception as e:                      # resposta inesperada, erro ao salvar etc.
            situacao = _falhar(evento, f"{type(e).__name__}: {e}", definitiva=False)
        log.info("evento %s (%s) -> %s", evento["id_evento"], evento["tipo"], situacao)
        resultado[situacao] = resultado.get(situacao, 0) + 1
    return resultado


def main() -> None:
    """Uso: python -m app.worker            (fica rodando)
            python -m app.worker --uma-vez  (processa um lote e sai)"""
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
    try:
        with httpx.Client(timeout=TIMEOUT) as cliente:
            if "--uma-vez" in sys.argv:
                print(processar_lote(cliente))
                return
            while True:
                if not processar_lote(cliente):
                    time.sleep(2)
    finally:
        fechar_pools()


if __name__ == "__main__":
    main()
