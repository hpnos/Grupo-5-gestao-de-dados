-- =====================================================================
-- SVP — Entrega 7 (Data Integration): estruturas de integração
-- Rodar depois de 03_security.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Laboratório: endereço da API e referência ao segredo no cofre
--    O segredo do webhook NUNCA fica no banco, só o nome dele no cofre.
-- ---------------------------------------------------------------------
ALTER TABLE laboratorio
    ADD COLUMN api_url     VARCHAR(200),
    ADD COLUMN segredo_ref VARCHAR(100);   -- prefixo no cofre: <ref>/webhook e <ref>/api-token

-- ---------------------------------------------------------------------
-- 2. Pedido de exame: protocolo devolvido pelo laboratório e versão do
--    resultado, para reconhecer duplicidade e atualização
-- ---------------------------------------------------------------------
ALTER TABLE solicitacao_exame
    ADD COLUMN protocolo_laboratorio VARCHAR(40),
    ADD COLUMN versao_resultado      SMALLINT    NOT NULL DEFAULT 0,
    ADD COLUMN atualizado_em         TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE UNIQUE INDEX ux_solicitacao_protocolo
    ON solicitacao_exame (id_laboratorio, protocolo_laboratorio)
    WHERE protocolo_laboratorio IS NOT NULL;

-- ---------------------------------------------------------------------
-- 3. Outbox (saída): o evento é gravado NA MESMA transação que muda o
--    dado de negócio; um worker envia depois, com retentativa.
--    Assim, ou o pedido e o evento existem juntos, ou nenhum existe.
-- ---------------------------------------------------------------------
CREATE TABLE integracao_evento (
    id_evento            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo                 VARCHAR(30)  NOT NULL
                         CHECK (tipo IN ('EXAME_SOLICITADO','COBRANCA_CRIADA',
                                         'NFSE_EMITIR','NOTIFICACAO_ENVIAR','CONVENIO_LOTE')),
    destino              VARCHAR(40)  NOT NULL,           -- ex.: 'laboratorio:1'
    id_agregado          BIGINT       NOT NULL,           -- id do registro de origem
    chave_idempotencia   VARCHAR(80)  NOT NULL UNIQUE,    -- enviada ao destino em todo envio
    payload              JSONB        NOT NULL,
    status               VARCHAR(18)  NOT NULL DEFAULT 'PENDENTE'
                         CHECK (status IN ('PENDENTE','PROCESSANDO','ENVIADO','ERRO','FALHA_DEFINITIVA')),
    tentativas           SMALLINT     NOT NULL DEFAULT 0,
    proxima_tentativa_em TIMESTAMPTZ  NOT NULL DEFAULT now(),
    travado_ate          TIMESTAMPTZ,                      -- lease do worker
    ultimo_erro          VARCHAR(500),
    resposta             JSONB,
    criado_em            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    enviado_em           TIMESTAMPTZ
);
CREATE INDEX ix_evento_fila ON integracao_evento (proxima_tentativa_em)
    WHERE status IN ('PENDENTE','ERRO');

-- ---------------------------------------------------------------------
-- 4. Inbox (entrada): toda mensagem recebida fica registrada pela chave
--    de idempotência; a mesma chave duas vezes é reconhecida e ignorada
-- ---------------------------------------------------------------------
CREATE TABLE integracao_recebida (
    id_recebida        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    origem             VARCHAR(40)  NOT NULL,            -- ex.: 'laboratorio:1'
    chave_idempotencia VARCHAR(80)  NOT NULL,
    payload_sha256     CHAR(64)     NOT NULL,
    status             VARCHAR(12)  NOT NULL
                       CHECK (status IN ('PROCESSADA','IGNORADA','REJEITADA')),
    detalhe            VARCHAR(300),
    recebido_em        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (origem, chave_idempotencia)
);

GRANT SELECT, INSERT, UPDATE ON integracao_evento, integracao_recebida TO svp_app;

-- ---------------------------------------------------------------------
-- 5. Pagamento: o mesmo código de autorização do gateway não entra duas
--    vezes (webhook repetido não duplica o recebimento)
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX ux_pagamento_autorizacao
    ON pagamento (forma, codigo_autorizacao)
    WHERE codigo_autorizacao IS NOT NULL;

-- ---------------------------------------------------------------------
-- 6. Painel de pendências de integração (para a TI e a coordenação)
-- ---------------------------------------------------------------------
CREATE VIEW vw_integracao_pendencias AS
SELECT tipo, destino, status,
       count(*)                 AS eventos,
       min(criado_em)           AS mais_antigo,
       max(tentativas)          AS max_tentativas
FROM integracao_evento
WHERE status <> 'ENVIADO'
GROUP BY tipo, destino, status;

-- exames enviados que passaram do prazo do laboratório sem resultado
CREATE VIEW vw_exames_atrasados AS
SELECT s.id_solicitacao, s.id_laboratorio, s.protocolo_laboratorio,
       te.nome AS exame, s.coletado_em, te.prazo_dias,
       s.coletado_em + make_interval(days => te.prazo_dias) AS prazo_em
FROM solicitacao_exame s
JOIN tipo_exame te ON te.id_tipo_exame = s.id_tipo_exame
WHERE s.status = 'ENVIADO'
  AND te.prazo_dias IS NOT NULL
  AND s.coletado_em + make_interval(days => te.prazo_dias) < now();

GRANT SELECT ON vw_integracao_pendencias, vw_exames_atrasados TO svp_app;

-- ---------------------------------------------------------------------
-- 7. Documento recebido por integração: não há usuário humano que o
--    enviou; a origem (ex.: 'laboratorio:1') fica registrada no lugar
-- ---------------------------------------------------------------------
ALTER TABLE documento ALTER COLUMN enviado_por DROP NOT NULL;
ALTER TABLE documento ADD COLUMN origem VARCHAR(40);
ALTER TABLE documento ADD CONSTRAINT ck_documento_autor
    CHECK (enviado_por IS NOT NULL OR origem IS NOT NULL);
