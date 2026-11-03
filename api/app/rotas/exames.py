"""Envio do pedido de exame ao laboratório (transactional outbox).

A API não chama o laboratório. Ela grava o evento na tabela
integracao_evento na MESMA transação que valida o pedido; o worker
entrega depois, com retentativa. Se o laboratório estiver fora do ar,
o atendimento continua e nada se perde.
"""
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from psycopg.types.json import Jsonb

from ..config import config
from ..db import transacao
from ..seguranca import Usuario, exige

router = APIRouter(prefix="/exames", tags=["exames"])


def _idade_anos(nascimento: date | None) -> int | None:
    if nascimento is None:
        return None
    hoje = date.today()
    return hoje.year - nascimento.year - ((hoje.month, hoje.day) < (nascimento.month, nascimento.day))


@router.post("/{id_solicitacao}/enviar", status_code=202)
def enviar_ao_laboratorio(id_solicitacao: int, usuario: Usuario = Depends(exige("exames", "EDITAR"))):
    with transacao(usuario.id_usuario) as conn:
        s = conn.execute(
            """SELECT s.id_solicitacao, s.status, s.id_laboratorio, s.coletado_em,
                      te.nome AS exame, te.material,
                      a.id_animal, a.id_tutor, a.sexo, a.porte, a.data_nascimento,
                      e.nome AS especie, r.nome AS raca, tr.peso_kg,
                      v.crmv, v.uf_crmv, u.nome AS unidade
               FROM solicitacao_exame s
               JOIN tipo_exame te  ON te.id_tipo_exame = s.id_tipo_exame
               JOIN atendimento atd ON atd.id_atendimento = s.id_atendimento
               JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento
               JOIN animal a       ON a.id_animal = ag.id_animal
               JOIN especie e      ON e.id_especie = a.id_especie
               LEFT JOIN raca r    ON r.id_raca = a.id_raca
               LEFT JOIN triagem tr ON tr.id_agendamento = ag.id_agendamento
               JOIN veterinario v  ON v.id_veterinario = atd.id_veterinario
               JOIN unidade u      ON u.id_unidade = ag.id_unidade
               WHERE s.id_solicitacao = %s
               FOR UPDATE OF s""", (id_solicitacao,)).fetchone()
        if s is None:
            raise HTTPException(404, "Pedido de exame não encontrado")
        if s["status"] != "COLETADO" or s["id_laboratorio"] is None:
            raise HTTPException(409, f"Só um pedido COLETADO e com laboratório pode ser enviado (atual: {s['status']})")

        # RN14: compartilhamento com o laboratório exige consentimento ativo
        consentiu = conn.execute(
            """SELECT 1 FROM consentimento WHERE id_tutor = %s AND finalidade = 'COMPARTILHAMENTO_LAB'
               AND revogado_em IS NULL""", (s["id_tutor"],)).fetchone()
        if not consentiu:
            raise HTTPException(409, "O tutor não deu consentimento para compartilhar amostras com laboratório")

        chave = f"exame-{id_solicitacao}-envio"
        # minimização: nada de nome, CPF ou contato do tutor; nem nome do animal
        payload = {
            "referencia_svp": id_solicitacao,
            "exame": s["exame"],
            "material": s["material"],
            "coletado_em": s["coletado_em"].isoformat(),
            "paciente": {
                "codigo": f"VP-A-{s['id_animal']:06d}",
                "especie": s["especie"],
                "raca": s["raca"] or "SRD",
                "sexo": s["sexo"],
                "porte": s["porte"],
                "idade_anos": _idade_anos(s["data_nascimento"]),
                "peso_kg": float(s["peso_kg"]) if s["peso_kg"] is not None else None,
            },
            "solicitante": {"crmv": f"{s['crmv']}-{s['uf_crmv']}", "unidade": s["unidade"]},
            "callback_url": f"{config().url_publica}/integracoes/laboratorio/{s['id_laboratorio']}/resultados",
        }
        evento = conn.execute(
            """INSERT INTO integracao_evento (tipo, destino, id_agregado, chave_idempotencia, payload)
               VALUES ('EXAME_SOLICITADO', %s, %s, %s, %s)
               ON CONFLICT (chave_idempotencia) DO NOTHING
               RETURNING id_evento""",
            (f"laboratorio:{s['id_laboratorio']}", id_solicitacao, chave, Jsonb(payload))).fetchone()
        if evento is None:
            atual = conn.execute("SELECT id_evento, status FROM integracao_evento WHERE chave_idempotencia = %s",
                                 (chave,)).fetchone()
            return {"situacao": "ja_enfileirado", "id_evento": atual["id_evento"], "status": atual["status"]}
        conn.execute("SELECT fn_registrar_acesso(%s, 'EXPORTACAO', 'solicitacao_exame', %s, %s, %s)",
                     (usuario.id_usuario, id_solicitacao, usuario.ip, "pedido enfileirado para o laboratório"))
    return {"situacao": "enfileirado", "id_evento": evento["id_evento"]}
