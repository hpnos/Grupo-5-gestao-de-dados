"""Cadastro e prontuário: cada leitura de dado clínico vai para o log."""
from fastapi import APIRouter, Depends, HTTPException

from ..db import transacao
from ..seguranca import Usuario, exige, mascarar_cpf, mascarar_telefone

router = APIRouter(tags=["cadastro e prontuário"])


@router.get("/tutores/{id_tutor}")
def ver_tutor(id_tutor: int, usuario: Usuario = Depends(exige("cadastro", "LER"))):
    with transacao(usuario.id_usuario) as conn:
        t = conn.execute(
            """SELECT id_tutor, nome, cpf, telefone, email, cidade, uf, contato_validado_em, anonimizado_em
               FROM tutor WHERE id_tutor = %s""", (id_tutor,)).fetchone()
        if t is None:
            raise HTTPException(404, "Tutor não encontrado")
        conn.execute("SELECT fn_registrar_acesso(%s, 'LEITURA', 'tutor', %s, %s, NULL)",
                     (usuario.id_usuario, id_tutor, usuario.ip))
        animais = conn.execute("SELECT id_animal, nome FROM animal WHERE id_tutor = %s ORDER BY id_animal",
                               (id_tutor,)).fetchall()
    # quem só lê o cadastro vê CPF e telefone mascarados (minimização)
    if not usuario.pode("cadastro", "EDITAR"):
        t["cpf"], t["telefone"] = mascarar_cpf(t["cpf"]), mascarar_telefone(t["telefone"])
    return {**t, "animais": animais}


@router.get("/animais/{id_animal}/prontuario")
def ver_prontuario(id_animal: int, usuario: Usuario = Depends(exige("prontuario", "LER"))):
    with transacao(usuario.id_usuario) as conn:
        a = conn.execute(
            """SELECT a.id_animal, a.nome, e.nome AS especie, r.nome AS raca, a.sexo, a.porte,
                      a.data_nascimento, a.castrado, a.data_obito
               FROM animal a JOIN especie e USING (id_especie) LEFT JOIN raca r USING (id_raca, id_especie)
               WHERE a.id_animal = %s""", (id_animal,)).fetchone()
        if a is None:
            raise HTTPException(404, "Animal não encontrado")
        conn.execute("SELECT fn_registrar_acesso(%s, 'LEITURA', 'atendimento', %s, %s, %s)",
                     (usuario.id_usuario, id_animal, usuario.ip, "prontuário completo do animal"))
        alergias = conn.execute("SELECT substancia, gravidade FROM alergia WHERE id_animal = %s",
                                (id_animal,)).fetchall()
        atendimentos = conn.execute(
            """SELECT atd.id_atendimento, atd.inicio_em, ag.modalidade, f.nome AS veterinario,
                      atd.anamnese, atd.conduta, d.descricao AS diagnostico_principal
               FROM agendamento ag
               JOIN atendimento atd ON atd.id_agendamento = ag.id_agendamento
               JOIN funcionario f ON f.id_funcionario = atd.id_veterinario
               LEFT JOIN atendimento_diagnostico ad ON ad.id_atendimento = atd.id_atendimento AND ad.tipo = 'PRINCIPAL'
               LEFT JOIN diagnostico d ON d.id_diagnostico = ad.id_diagnostico
               WHERE ag.id_animal = %s ORDER BY atd.inicio_em DESC LIMIT 50""", (id_animal,)).fetchall()
        exames = conn.execute(
            """SELECT s.id_solicitacao, te.nome AS exame, s.status, s.resultado_em, s.resultado_resumo,
                      s.id_documento
               FROM solicitacao_exame s
               JOIN tipo_exame te USING (id_tipo_exame)
               JOIN atendimento atd USING (id_atendimento)
               JOIN agendamento ag USING (id_agendamento)
               WHERE ag.id_animal = %s ORDER BY s.coletado_em DESC NULLS LAST LIMIT 50""", (id_animal,)).fetchall()
    return {"animal": a, "alergias": alergias, "atendimentos": atendimentos, "exames": exames}
