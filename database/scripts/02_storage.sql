-- =====================================================================
-- SVP — Entrega 5 (Data Storage): ajustes físicos de armazenamento
-- Rodar depois de 01_modelo_fisico.sql. PostgreSQL 16.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. log_auditoria particionado por mês
--    É a tabela que mais cresce (~40 linhas por atendimento). Partições
--    mensais mantêm índices pequenos e permitem arquivar meses antigos
--    em armazenamento frio sem DELETE (DETACH + export + DROP).
--    A PK passa a incluir ocorrido_em (exigência do particionamento).
-- ---------------------------------------------------------------------
ALTER TABLE log_auditoria RENAME TO log_auditoria_antigo;
DROP INDEX ix_log_usuario_data, ix_log_registro;   -- recriados na tabela nova

CREATE TABLE log_auditoria (
    id_log        BIGINT GENERATED ALWAYS AS IDENTITY,
    id_usuario    INT REFERENCES usuario (id_usuario),
    ocorrido_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
    acao          VARCHAR(14) NOT NULL
                  CHECK (acao IN ('LOGIN','LOGIN_FALHA','LOGOUT','LEITURA',
                                  'INSERCAO','ALTERACAO','EXCLUSAO','EXPORTACAO',
                                  'ACESSO_NEGADO','PERMISSAO')),
    tabela        VARCHAR(60),
    id_registro   BIGINT,
    dados_antes   JSONB,
    dados_depois  JSONB,
    ip_origem     INET,
    justificativa VARCHAR(200),
    PRIMARY KEY (id_log, ocorrido_em)
) PARTITION BY RANGE (ocorrido_em);

-- partição de segurança: nada se perde se o job mensal atrasar
CREATE TABLE log_auditoria_default PARTITION OF log_auditoria DEFAULT;

CREATE INDEX ix_log_usuario_data ON log_auditoria (id_usuario, ocorrido_em);
CREATE INDEX ix_log_registro     ON log_auditoria (tabela, id_registro);

INSERT INTO log_auditoria (id_usuario, ocorrido_em, acao, tabela, id_registro,
                           dados_antes, dados_depois, ip_origem, justificativa)
SELECT id_usuario, ocorrido_em, acao, tabela, id_registro,
       dados_antes, dados_depois, ip_origem, justificativa
FROM log_auditoria_antigo;
DROP TABLE log_auditoria_antigo;

-- cria a partição de um mês (o job de rotina cria os próximos meses)
CREATE OR REPLACE FUNCTION fn_criar_particao_log(p_mes DATE) RETURNS TEXT AS $$
DECLARE
    v_ini  DATE := date_trunc('month', p_mes)::DATE;
    v_fim  DATE := (date_trunc('month', p_mes) + INTERVAL '1 month')::DATE;
    v_nome TEXT := 'log_auditoria_' || to_char(v_ini, 'YYYY_MM');
BEGIN
    IF to_regclass(v_nome) IS NULL THEN
        EXECUTE format('CREATE TABLE %I PARTITION OF log_auditoria
                        FOR VALUES FROM (%L) TO (%L)', v_nome, v_ini, v_fim);
    END IF;
    RETURN v_nome;
END;
$$ LANGUAGE plpgsql;

SELECT fn_criar_particao_log((date_trunc('month', now()) + make_interval(months => m))::DATE)
FROM generate_series(-12, 3) AS m;

-- ---------------------------------------------------------------------
-- 2. Retenção e anonimização (LGPD Art. 16 + Res. CFMV 1.321/2020)
--    O prontuário é guardado por no mínimo 5 anos após o último
--    atendimento. Depois disso, a pedido do tutor ou pela política, os
--    dados pessoais do tutor são anonimizados e o histórico clínico fica.
--    Para isso, CPF e telefone deixam de ser obrigatórios SÓ depois da
--    anonimização (CHECK abaixo); antes continuam obrigatórios.
-- ---------------------------------------------------------------------
ALTER TABLE tutor ALTER COLUMN cpf      DROP NOT NULL;
ALTER TABLE tutor ALTER COLUMN telefone DROP NOT NULL;
ALTER TABLE tutor ADD CONSTRAINT ck_tutor_identificado
    CHECK (anonimizado_em IS NOT NULL OR (cpf IS NOT NULL AND telefone IS NOT NULL));

CREATE TABLE politica_retencao (
    categoria      VARCHAR(30) PRIMARY KEY,
    prazo_anos     SMALLINT    NOT NULL CHECK (prazo_anos > 0),
    contado_a_partir VARCHAR(80) NOT NULL,
    base_legal     VARCHAR(200) NOT NULL,
    acao_ao_fim    VARCHAR(20) NOT NULL CHECK (acao_ao_fim IN ('ANONIMIZAR','ARQUIVAR','EXCLUIR'))
);

INSERT INTO politica_retencao VALUES
 ('PRONTUARIO',    5, 'último atendimento do animal',
  'Res. CFMV 1.321/2020, art. 9º, §3º (mínimo de 5 anos)', 'ANONIMIZAR'),
 ('FISCAL',        5, '1º dia do exercício seguinte ao da emissão',
  'CTN, art. 173 (prazo decadencial)', 'ARQUIVAR'),
 ('LOG_AUDITORIA', 5, 'data do evento',
  'LGPD art. 37 (registro das operações); prazo definido pela clínica', 'ARQUIVAR'),
 ('INCIDENTE',     5, 'data do registro do incidente',
  'Res. CD/ANPD 15/2024, art. 10', 'ARQUIVAR');

CREATE OR REPLACE FUNCTION fn_anonimizar_tutor(p_id_tutor INT, p_forcar BOOLEAN DEFAULT FALSE)
RETURNS VOID AS $$
DECLARE
    v_ultimo_atend TIMESTAMPTZ;
    v_ultima_fatura TIMESTAMPTZ;
BEGIN
    SELECT max(atd.inicio_em) INTO v_ultimo_atend
    FROM animal a
    JOIN agendamento ag ON ag.id_animal = a.id_animal
    JOIN atendimento atd ON atd.id_agendamento = ag.id_agendamento
    WHERE a.id_tutor = p_id_tutor;

    SELECT max(emitida_em) INTO v_ultima_fatura FROM fatura WHERE id_tutor = p_id_tutor;

    IF NOT p_forcar AND (
         v_ultimo_atend  > now() - INTERVAL '5 years' OR
         v_ultima_fatura > now() - INTERVAL '5 years') THEN
        RAISE EXCEPTION 'Tutor % ainda está no prazo legal de guarda (último atendimento %, última fatura %)',
                        p_id_tutor, v_ultimo_atend, v_ultima_fatura;
    END IF;

    UPDATE tutor SET
        nome = 'TUTOR ANONIMIZADO ' || id_tutor,
        cpf = NULL, data_nascimento = NULL, telefone = NULL, email = NULL,
        logradouro = NULL, numero = NULL, complemento = NULL, bairro = NULL, cep = NULL,
        -- cidade e UF ficam: servem a estatísticas regionais e não identificam
        anonimizado_em = now(), atualizado_em = now()
    WHERE id_tutor = p_id_tutor AND anonimizado_em IS NULL;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- 3. Índices para as consultas mais frequentes do operacional
-- ---------------------------------------------------------------------
CREATE INDEX ix_tutor_nome          ON tutor (lower(nome));
CREATE INDEX ix_agendamento_vet_dia ON agendamento (id_veterinario, data_hora);
CREATE INDEX ix_atendimento_inicio  ON atendimento (inicio_em);
CREATE INDEX ix_fatura_tutor        ON fatura (id_tutor, emitida_em);
CREATE INDEX ix_pagamento_fatura    ON pagamento (id_fatura);
CREATE INDEX ix_solicitacao_status  ON solicitacao_exame (status) WHERE status IN ('SOLICITADO','COLETADO','ENVIADO');
CREATE INDEX ix_documento_animal    ON documento (id_animal, enviado_em);
CREATE INDEX ix_lote_validade       ON lote (id_unidade, validade);

-- o mesmo arquivo (mesmo hash) não é guardado duas vezes para o mesmo animal
CREATE UNIQUE INDEX ux_documento_hash ON documento (id_animal, hash_sha256);
