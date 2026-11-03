-- =====================================================================
-- Sistema Vida Plena (SVP) — Modelo físico
-- PostgreSQL 12 ou superior
-- =====================================================================
-- ---------------------------------------------------------------------
-- 1. Equipe e acesso
-- ---------------------------------------------------------------------
CREATE TABLE unidade (
     id_unidade              INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     nome                    VARCHAR(100) NOT NULL,
     cnpj                    CHAR(14)         NOT NULL UNIQUE,
     telefone                VARCHAR(15),
     logradouro              VARCHAR(150),
     numero                  VARCHAR(10),
     bairro                  VARCHAR(80),
     cidade                  VARCHAR(80)      NOT NULL,
     uf                      CHAR(2)          NOT NULL,
     cep                     CHAR(8),
     ativa                   BOOLEAN          NOT NULL DEFAULT TRUE
);
CREATE TABLE funcionario (
     id_funcionario                   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_unidade                       INT          NOT NULL REFERENCES unidade (id_unidade),
     nome                             VARCHAR(120) NOT NULL,
     cpf                              CHAR(11)    NOT NULL UNIQUE,
     cargo                            VARCHAR(30) NOT NULL
                                      CHECK (cargo IN
('VETERINARIO','ENFERMEIRO','RECEPCIONISTA',
                                                          'FINANCEIRO','TI','DIRETOR','AUDITOR')),
     email                            VARCHAR(120) NOT NULL UNIQUE,
     data_admissao                    DATE         NOT NULL,
     data_desligamento DATE,
     CHECK (data_desligamento IS NULL OR data_desligamento >= data_admissao)
);
CREATE TABLE veterinario (
     id_veterinario INT PRIMARY KEY REFERENCES funcionario (id_funcionario),
     crmv           VARCHAR(10) NOT NULL,
     uf_crmv                    CHAR(2)       NOT NULL,
     UNIQUE (crmv, uf_crmv)
);
CREATE TABLE especialidade (
     id_especialidade INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     nome             VARCHAR(80) NOT NULL UNIQUE
);
CREATE TABLE veterinario_especialidade (
  id_veterinario   INT REFERENCES veterinario (id_veterinario),
     id_especialidade INT REFERENCES especialidade (id_especialidade),
     PRIMARY KEY (id_veterinario, id_especialidade)
);
CREATE TABLE perfil (
     id_perfil INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     nome      VARCHAR(40) NOT NULL UNIQUE,
     descricao VARCHAR(200)
);
CREATE TABLE permissao (
     id_permissao INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     recurso                 VARCHAR(60) NOT NULL,             -- ex.: 'prontuario', 'fatura'
     acao                    VARCHAR(10) NOT NULL
                             CHECK (acao IN ('LER','CRIAR','EDITAR','EXCLUIR','EXPORTAR')),
     UNIQUE (recurso, acao)
);
CREATE TABLE perfil_permissao (
  id_perfil    INT REFERENCES perfil (id_perfil),
     id_permissao INT REFERENCES permissao (id_permissao),
     PRIMARY KEY (id_perfil, id_permissao)
);
CREATE TABLE usuario (
     id_usuario                 INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_funcionario INT                           NOT NULL UNIQUE REFERENCES funcionario
(id_funcionario),
     login                      VARCHAR(50)       NOT NULL UNIQUE,
     senha_hash                 VARCHAR(255) NOT NULL,       -- bcrypt/Argon2; nunca a senha
     mfa_ativo                  BOOLEAN      NOT NULL DEFAULT FALSE,
     ativo                      BOOLEAN           NOT NULL DEFAULT TRUE,
     ultimo_acesso              TIMESTAMPTZ,
     criado_em                  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE usuario_perfil (
  id_usuario INT REFERENCES usuario (id_usuario),
     id_perfil           INT REFERENCES perfil (id_perfil),
     PRIMARY KEY (id_usuario, id_perfil)
);
CREATE TABLE log_auditoria (
     id_log                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_usuario               INT REFERENCES usuario (id_usuario),
     ocorrido_em              TIMESTAMPTZ NOT NULL DEFAULT now(),
     acao                     VARCHAR(12) NOT NULL
                              CHECK (acao IN ('LOGIN','LOGIN_FALHA','LOGOUT','LEITURA',
'INSERCAO','ALTERACAO','EXCLUSAO','EXPORTACAO')),
     tabela                   VARCHAR(60),
     id_registro              BIGINT,
     dados_antes              JSONB,
     dados_depois             JSONB,
     ip_origem                INET,
     justificativa VARCHAR(200)                                     -- obrigatória em acesso de emergência
);
CREATE INDEX ix_log_usuario_data ON log_auditoria (id_usuario, ocorrido_em);
CREATE INDEX ix_log_registro                         ON log_auditoria (tabela, id_registro);
-- ---------------------------------------------------------------------
-- 2. Cadastro
-- ---------------------------------------------------------------------
CREATE TABLE tutor (
  id_tutor                                INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     nome                                 VARCHAR(120) NOT NULL,
  cpf                                     CHAR(11)      NOT NULL UNIQUE CHECK (cpf ~ '^[0-9]{11}$'),
     data_nascimento                      DATE,
     telefone                             VARCHAR(15)   NOT NULL,
     email                                VARCHAR(120),
     logradouro                           VARCHAR(150),
     numero                               VARCHAR(10),
     complemento                          VARCHAR(60),
     bairro                               VARCHAR(80),
     cidade                               VARCHAR(80),
     uf                                   CHAR(2),
     cep                                  CHAR(8),
     contato_validado_em DATE,
     criado_em                            TIMESTAMPTZ    NOT NULL DEFAULT now(),
     atualizado_em                        TIMESTAMPTZ    NOT NULL DEFAULT now(),
     anonimizado_em                       TIMESTAMPTZ
);
CREATE TABLE consentimento (
     id_consentimento INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_tutor                       INT              NOT NULL REFERENCES tutor (id_tutor),
     finalidade                     VARCHAR(30) NOT NULL
                                    CHECK (finalidade IN
('ATENDIMENTO','TELECONSULTA','COMUNICACAO',
'MARKETING','COMPARTILHAMENTO_LAB')),
     versao_termo                   VARCHAR(10) NOT NULL,
     aceito_em                      TIMESTAMPTZ NOT NULL,
     revogado_em                    TIMESTAMPTZ,
     canal                          VARCHAR(20) NOT NULL
                                    CHECK (canal IN ('PRESENCIAL','APP','SITE','TELEFONE')),
     CHECK (revogado_em IS NULL OR revogado_em >= aceito_em)
);
CREATE TABLE especie (
     id_especie INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     nome       VARCHAR(50) NOT NULL UNIQUE
);
CREATE TABLE raca (
     id_raca             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_especie INT                           NOT NULL REFERENCES especie (id_especie),
     nome       VARCHAR(60) NOT NULL,
     UNIQUE (id_especie, nome),
     UNIQUE (id_raca, id_especie)                                  -- permite a FK composta em animal
);
CREATE TABLE animal (
     id_animal                            INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_tutor                             INT         NOT NULL REFERENCES tutor (id_tutor),
     id_especie                           INT          NOT NULL REFERENCES especie (id_especie),
     id_raca                              INT,                     -- nulo = SRD
     nome                                 VARCHAR(60) NOT NULL,
     sexo                                 CHAR(1)      NOT NULL CHECK (sexo IN ('M','F')),
     data_nascimento                      DATE,
     nascimento_estimado BOOLEAN                       NOT NULL DEFAULT FALSE,
     porte               CHAR(1)                       NOT NULL CHECK (porte IN ('P','M','G')),
     microchip                            VARCHAR(15) UNIQUE,
     castrado                             BOOLEAN,
     data_obito                           DATE,
     criado_em                            TIMESTAMPTZ NOT NULL DEFAULT now(),
     -- a raça precisa ser da mesma espécie do animal (RN03)
     FOREIGN KEY (id_raca, id_especie) REFERENCES raca (id_raca, id_especie)
);
CREATE INDEX ix_animal_tutor ON animal (id_tutor);
-- evita o mesmo animal cadastrado duas vezes para o mesmo tutor
CREATE UNIQUE INDEX ux_animal_tutor_nome
     ON animal (id_tutor, id_especie, lower(nome)) WHERE data_obito IS NULL;
CREATE TABLE alergia (
     id_alergia                 INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_animal                  INT          NOT NULL REFERENCES animal (id_animal),
     substancia                 VARCHAR(100) NOT NULL,
  gravidade      VARCHAR(10) NOT NULL CHECK (gravidade IN
('LEVE','MODERADA','GRAVE')),
  observacao     TEXT,
     registrada_por INT          NOT NULL REFERENCES usuario (id_usuario),
     registrada_em TIMESTAMPTZ NOT NULL DEFAULT now(),
     UNIQUE (id_animal, substancia)
);
CREATE TABLE convenio (
  id_convenio INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  razao_social VARCHAR(120) NOT NULL,
     cnpj                    CHAR(14)             NOT NULL UNIQUE,
     ativo                   BOOLEAN              NOT NULL DEFAULT TRUE
);
CREATE TABLE animal_convenio (
  id_animal       INT REFERENCES animal (id_animal),
     id_convenio     INT REFERENCES convenio (id_convenio),
     numero_carteira VARCHAR(30) NOT NULL,
     validade        DATE,
     PRIMARY KEY (id_animal, id_convenio)
);
-- ---------------------------------------------------------------------
-- 3. Catálogo de serviços (base do faturamento)
-- ---------------------------------------------------------------------
CREATE TABLE servico (
  id_servico INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     descricao           VARCHAR(120) NOT NULL UNIQUE,
     tipo                VARCHAR(15)    NOT NULL
                         CHECK (tipo IN
('CONSULTA','TELECONSULTA','EXAME','PROCEDIMENTO',
                             'PROGRAMA','MATERIAL')),
  valor_base NUMERIC(10,2) NOT NULL CHECK (valor_base >= 0),
     ativo               BOOLEAN              NOT NULL DEFAULT TRUE
);
-- ---------------------------------------------------------------------
-- 4. Agenda
-- ---------------------------------------------------------------------
CREATE TABLE agendamento (
  id_agendamento   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_animal        INT                         NOT NULL REFERENCES animal (id_animal),
     id_veterinario   INT                         NOT NULL,
     id_especialidade INT                         NOT NULL,
     id_unidade                     INT           NOT NULL REFERENCES unidade (id_unidade),
     data_hora                      TIMESTAMPTZ   NOT NULL,
     duracao_min                    SMALLINT      NOT NULL DEFAULT 30 CHECK (duracao_min > 0),
  modalidade       VARCHAR(12) NOT NULL CHECK (modalidade IN
('PRESENCIAL','TELECONSULTA')),
  status           VARCHAR(12) NOT NULL DEFAULT 'AGENDADO'
                   CHECK (status IN
('AGENDADO','CONFIRMADO','CANCELADO','FALTOU','REALIZADO')),
     motivo                         VARCHAR(200),
     criado_por                     INT          NOT NULL REFERENCES usuario (id_usuario),
     criado_em                      TIMESTAMPTZ NOT NULL DEFAULT now(),
  chegada_em       TIMESTAMPTZ,               -- chegada registrada na recepção
  -- o veterinário precisa atender a especialidade escolhida (RN04)
     FOREIGN KEY (id_veterinario, id_especialidade)
       REFERENCES veterinario_especialidade (id_veterinario, id_especialidade)
);
CREATE INDEX ix_agendamento_animal ON agendamento (id_animal);
CREATE INDEX ix_agendamento_agenda ON agendamento (id_unidade, data_hora);
-- um veterinário não tem dois horários ativos iguais (RN05)
CREATE UNIQUE INDEX ux_agenda_vet_horario
  ON agendamento (id_veterinario, data_hora) WHERE status <> 'CANCELADO';
-- ---------------------------------------------------------------------
-- 5. Prontuário
-- ---------------------------------------------------------------------
CREATE TABLE triagem (
  id_triagem        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_agendamento                      INT         NOT NULL UNIQUE REFERENCES agendamento
(id_agendamento),
  id_funcionario                      INT         NOT NULL REFERENCES funcionario
(id_funcionario),
  realizada_em                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  peso_kg                             NUMERIC(7,2) CHECK (peso_kg > 0),
     temperatura_c                    NUMERIC(4,1),
     freq_cardiaca                    SMALLINT,
     freq_respiratoria SMALLINT,
     queixa_principal VARCHAR(300) NOT NULL,
     prioridade        VARCHAR(15) NOT NULL
                    CHECK (prioridade IN
('EMERGENCIA','URGENTE','POUCO_URGENTE','NAO_URGENTE'))
);
CREATE TABLE atendimento (
  id_atendimento INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_agendamento INT                          NOT NULL UNIQUE REFERENCES agendamento
(id_agendamento),
  id_veterinario INT                          NOT NULL REFERENCES veterinario
(id_veterinario),
  inicio_em       TIMESTAMPTZ NOT NULL,
     fim_em                     TIMESTAMPTZ,
     anamnese                   TEXT        NOT NULL,
     exame_fisico               TEXT,
     conduta        TEXT,
     finalizado     BOOLEAN     NOT NULL DEFAULT FALSE,
     CHECK (fim_em IS NULL OR fim_em >= inicio_em),
     CHECK (NOT finalizado OR fim_em IS NOT NULL)
);
CREATE TABLE diagnostico (
  id_diagnostico INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo         VARCHAR(15) NOT NULL UNIQUE, -- catálogo veterinário padronizado
  descricao                     VARCHAR(200) NOT NULL,
     cronico                    BOOLEAN        NOT NULL DEFAULT FALSE
);
CREATE TABLE atendimento_diagnostico (
  id_atendimento INT REFERENCES atendimento (id_atendimento),
  id_diagnostico INT REFERENCES diagnostico (id_diagnostico),
  tipo           VARCHAR(10) NOT NULL CHECK (tipo IN
('PRINCIPAL','SECUNDARIO','SUSPEITA')),
  PRIMARY KEY (id_atendimento, id_diagnostico)
);
-- no máximo um diagnóstico principal por atendimento (RN09)
CREATE UNIQUE INDEX ux_diag_principal
     ON atendimento_diagnostico (id_atendimento) WHERE tipo = 'PRINCIPAL';
CREATE TABLE evolucao (
     id_evolucao                INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_animal                  INT         NOT NULL REFERENCES animal (id_animal),
  id_atendimento INT                          REFERENCES atendimento (id_atendimento),
  id_funcionario INT                          NOT NULL REFERENCES funcionario
(id_funcionario),
     registrada_em              TIMESTAMPTZ NOT NULL DEFAULT now(),
     texto                      TEXT        NOT NULL
);
CREATE INDEX ix_evolucao_animal ON evolucao (id_animal, registrada_em);
-- ---------------------------------------------------------------------
-- 6. Estoque
-- ---------------------------------------------------------------------
CREATE TABLE fornecedor (
     id_fornecedor INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     razao_social VARCHAR(120) NOT NULL,
     cnpj                     CHAR(14)     NOT NULL UNIQUE,
     telefone                 VARCHAR(15),
     email                    VARCHAR(120)
);
CREATE TABLE insumo (
     id_insumo                  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     nome                       VARCHAR(120) NOT NULL UNIQUE,
     categoria                  VARCHAR(15)   NOT NULL
                 CHECK (categoria IN
('MEDICAMENTO','DESCARTAVEL','VACINA','OUTRO')),
  unidade_medida VARCHAR(10)   NOT NULL,      -- ml, comprimido, unidade
     controlado     BOOLEAN       NOT NULL DEFAULT FALSE,
     estoque_minimo NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (estoque_minimo >= 0)
);
CREATE TABLE lote (
     id_lote                    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_insumo                  INT           NOT NULL REFERENCES insumo (id_insumo),
     id_fornecedor              INT           NOT NULL REFERENCES fornecedor
(id_fornecedor),
     id_unidade                 INT              NOT NULL REFERENCES unidade (id_unidade),
     numero_lote                VARCHAR(30)      NOT NULL,
     validade       DATE          NOT NULL,
     custo_unitario NUMERIC(10,2) NOT NULL CHECK (custo_unitario >= 0),
     UNIQUE (id_insumo, numero_lote, id_unidade)
);
CREATE TABLE movimentacao_estoque (
  id_movimentacao INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_lote         INT           NOT NULL REFERENCES lote (id_lote),
     tipo         VARCHAR(15)    NOT NULL
                  CHECK (tipo IN
('ENTRADA','SAIDA','PERDA','AJUSTE_ENTRADA','AJUSTE_SAIDA')),
  quantidade                      NUMERIC(10,2) NOT NULL CHECK (quantidade > 0),
  id_atendimento                  INT           REFERENCES atendimento (id_atendimento),        -- RN13
     id_usuario                   INT               NOT NULL REFERENCES usuario (id_usuario),
     realizada_em                 TIMESTAMPTZ       NOT NULL DEFAULT now(),
     motivo                       VARCHAR(200)
);
CREATE INDEX ix_mov_lote ON movimentacao_estoque (id_lote);
-- ---------------------------------------------------------------------
-- 7. Prescrição
-- ---------------------------------------------------------------------
CREATE TABLE prescricao (
  id_prescricao INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_atendimento INT          NOT NULL REFERENCES atendimento
(id_atendimento),
  emitida_em      TIMESTAMPTZ NOT NULL DEFAULT now(),
     observacao                 TEXT
);
CREATE TABLE item_prescricao (
  id_item           INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_prescricao     INT          NOT NULL REFERENCES prescricao
(id_prescricao),
  id_insumo                           INT           REFERENCES insumo (id_insumo),   -- nulo = comprado fora
  medicamento_texto VARCHAR(150),
  dose              VARCHAR(40) NOT NULL,
     via                              VARCHAR(20)   NOT NULL,
     frequencia                       VARCHAR(40)   NOT NULL,
     duracao_dias                     SMALLINT      CHECK (duracao_dias > 0),
     CHECK (id_insumo IS NOT NULL OR medicamento_texto IS NOT NULL)
);
-- ---------------------------------------------------------------------
-- 8. Exames
-- ---------------------------------------------------------------------
CREATE TABLE laboratorio (
  id_laboratorio   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     razao_social     VARCHAR(120) NOT NULL,
     cnpj             CHAR(14)     NOT NULL UNIQUE,
     email_integracao VARCHAR(120),
     ativo                          BOOLEAN      NOT NULL DEFAULT TRUE
);
CREATE TABLE tipo_exame (
  id_tipo_exame INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_servico    INT          NOT NULL REFERENCES servico (id_servico),
     nome                     VARCHAR(100) NOT NULL UNIQUE,
     material                 VARCHAR(40) NOT NULL,         -- sangue, urina, fezes
     prazo_dias               SMALLINT     CHECK (prazo_dias > 0)
);
CREATE TABLE documento (
  id_documento INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_animal    INT          NOT NULL REFERENCES animal (id_animal),
     tipo         VARCHAR(15) NOT NULL
                  CHECK (tipo IN ('LAUDO','EXAME','TERMO','IMAGEM','OUTRO')),
     nome_arquivo VARCHAR(200) NOT NULL,
  caminho                    VARCHAR(400) NOT NULL,            -- chave no repositório de arquivos
  hash_sha256                CHAR(64)         NOT NULL,        -- garante a integridade do arquivo
  enviado_por                INT              NOT NULL REFERENCES usuario (id_usuario),
  enviado_em                 TIMESTAMPTZ      NOT NULL DEFAULT now()
);
CREATE TABLE solicitacao_exame (
  id_solicitacao   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_atendimento   INT         NOT NULL REFERENCES atendimento
(id_atendimento),
  id_tipo_exame                     INT         NOT NULL REFERENCES tipo_exame
(id_tipo_exame),
     id_laboratorio                 INT         REFERENCES laboratorio (id_laboratorio),
     status                         VARCHAR(12) NOT NULL DEFAULT 'SOLICITADO'
                                    CHECK (status IN
('SOLICITADO','COLETADO','ENVIADO','CONCLUIDO','CANCELADO')),
  coletado_em      TIMESTAMPTZ,
  coletado_por     INT         REFERENCES funcionario (id_funcionario),
     resultado_em     TIMESTAMPTZ,
     resultado_resumo TEXT,
     id_documento     INT         REFERENCES documento (id_documento),                     -- laudo
     CHECK (status <> 'CONCLUIDO' OR resultado_em IS NOT NULL)
);
-- ---------------------------------------------------------------------
-- 9. Programas de doenças crônicas
-- ---------------------------------------------------------------------
CREATE TABLE programa_cronico (
  id_programa            INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_servico                                  INT          NOT NULL REFERENCES servico
(id_servico),
  nome                                        VARCHAR(80) NOT NULL UNIQUE,
     descricao              TEXT,
     intervalo_retorno_dias SMALLINT                       NOT NULL CHECK (intervalo_retorno_dias >
0)
);
CREATE TABLE inscricao_programa (
  id_inscricao   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_animal      INT         NOT NULL REFERENCES animal (id_animal),
  id_programa    INT                                NOT NULL REFERENCES programa_cronico
(id_programa),
  id_veterinario INT                                NOT NULL REFERENCES veterinario
(id_veterinario),
  inicio          DATE                              NOT NULL,
  fim             DATE,
     status         VARCHAR(10) NOT NULL DEFAULT 'ATIVA'
                    CHECK (status IN ('ATIVA','PAUSADA','ENCERRADA')),
     CHECK (fim IS NULL OR fim >= inicio)
);
CREATE UNIQUE INDEX ux_inscricao_ativa
     ON inscricao_programa (id_animal, id_programa) WHERE status = 'ATIVA';
-- ---------------------------------------------------------------------
-- 10. Financeiro
-- ---------------------------------------------------------------------
CREATE TABLE fatura (
     id_fatura      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_tutor       INT           NOT NULL REFERENCES tutor (id_tutor),
     id_atendimento INT           UNIQUE REFERENCES atendimento
(id_atendimento),
  id_unidade      INT                                NOT NULL REFERENCES unidade (id_unidade),
  emitida_em      TIMESTAMPTZ                        NOT NULL DEFAULT now(),
     vencimento                 DATE                 NOT NULL,
     desconto                   NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (desconto >= 0),
     status                     VARCHAR(10)   NOT NULL DEFAULT 'ABERTA'
                                CHECK (status IN ('ABERTA','PARCIAL','PAGA','CANCELADA'))
);
CREATE TABLE item_fatura (
  id_item_fatura INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_fatura                  INT              NOT NULL REFERENCES fatura (id_fatura),
     id_servico                 INT              NOT NULL REFERENCES servico (id_servico),
     quantidade                 NUMERIC(8,2)     NOT NULL DEFAULT 1 CHECK (quantidade > 0),
   valor_unitario NUMERIC(10,2) NOT NULL CHECK (valor_unitario >= 0)                      -- preço do dia (RN11)
);
CREATE TABLE pagamento (
     id_pagamento                       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     id_fatura                          INT           NOT NULL REFERENCES fatura (id_fatura),
     forma                              VARCHAR(15)   NOT NULL
                     CHECK (forma IN
('PIX','CREDITO','DEBITO','DINHEIRO','BOLETO','CONVENIO')),
  valor              NUMERIC(10,2) NOT NULL CHECK (valor > 0),
  parcelas           SMALLINT                         NOT NULL DEFAULT 1 CHECK (parcelas BETWEEN
1 AND 12),
  codigo_autorizacao VARCHAR(40),                                 -- NSU/ID da transação; nunca o cartão
  id_convenio                           INT           REFERENCES convenio (id_convenio),
  pago_em                               TIMESTAMPTZ   NOT NULL DEFAULT now(),
     -- convênio informado se, e somente se, a forma for CONVENIO (RN12)
     CHECK ((forma = 'CONVENIO') = (id_convenio IS NOT NULL))
);
CREATE TABLE nota_fiscal (
  id_nota                               INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_fatura                             INT           NOT NULL UNIQUE REFERENCES fatura
(id_fatura),
     numero             VARCHAR(15)                   NOT NULL,
     serie              VARCHAR(5)                    NOT NULL,
     codigo_verificacao VARCHAR(50)                   NOT NULL,   -- NFS-e
     emitida_em         TIMESTAMPTZ   NOT NULL,
     valor              NUMERIC(10,2) NOT NULL CHECK (valor >= 0),
     UNIQUE (numero, serie)
);
-- ---------------------------------------------------------------------
-- 11. Auditoria automática (RN15)
-- A aplicação informa o usuário logado com:                      SET LOCAL svp.id_usuario = '42';
-- Leituras (SELECT) são registradas pela aplicação com acao = 'LEITURA'.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auditar() RETURNS trigger AS $$
DECLARE
  linha JSONB := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE
to_jsonb(NEW) END;
BEGIN
  INSERT INTO log_auditoria (id_usuario, acao, tabela, id_registro,
dados_antes, dados_depois)
  VALUES (
    NULLIF(current_setting('svp.id_usuario', true), '')::INT,
    CASE TG_OP WHEN 'INSERT' THEN 'INSERCAO' WHEN 'UPDATE' THEN 'ALTERACAO'
ELSE 'EXCLUSAO' END,
        TG_TABLE_NAME,
        (linha ->> TG_ARGV[0])::BIGINT,
        CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
      CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END
    );
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER tg_audit_tutor       AFTER INSERT OR UPDATE OR DELETE ON tutor
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_tutor');
CREATE TRIGGER tg_audit_animal      AFTER INSERT OR UPDATE OR DELETE ON
animal
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_animal');
CREATE TRIGGER tg_audit_alergia     AFTER INSERT OR UPDATE OR DELETE ON
alergia
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_alergia');
CREATE TRIGGER tg_audit_triagem     AFTER INSERT OR UPDATE OR DELETE ON
triagem
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_triagem');
CREATE TRIGGER tg_audit_atendimento AFTER INSERT OR UPDATE OR DELETE ON
atendimento
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_atendimento');
CREATE TRIGGER tg_audit_diagnostico AFTER INSERT OR UPDATE OR DELETE ON
atendimento_diagnostico
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_atendimento');
CREATE TRIGGER tg_audit_evolucao              AFTER INSERT OR UPDATE OR DELETE ON
evolucao
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_evolucao');
CREATE TRIGGER tg_audit_prescricao AFTER INSERT OR UPDATE OR DELETE ON
prescricao
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_prescricao');
CREATE TRIGGER tg_audit_exame                 AFTER INSERT OR UPDATE OR DELETE ON
solicitacao_exame
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_solicitacao');
CREATE TRIGGER tg_audit_documento   AFTER INSERT OR UPDATE OR DELETE ON
documento
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_documento');
CREATE TRIGGER tg_audit_pagamento   AFTER INSERT OR UPDATE OR DELETE ON
pagamento
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_pagamento');
-- ---------------------------------------------------------------------
-- 12. Visões (valores derivados e indicadores estratégicos)
-- ---------------------------------------------------------------------
CREATE VIEW vw_fatura_total AS
SELECT f.id_fatura,
       COALESCE(SUM(i.quantidade * i.valor_unitario), 0) - f.desconto AS
valor_total
FROM fatura f
LEFT JOIN item_fatura i ON i.id_fatura = f.id_fatura
GROUP BY f.id_fatura, f.desconto;
CREATE VIEW vw_saldo_lote AS
SELECT l.id_lote, l.id_insumo, l.id_unidade, l.validade,
       COALESCE(SUM(CASE WHEN m.tipo IN ('ENTRADA','AJUSTE_ENTRADA')
                         THEN m.quantidade ELSE -m.quantidade END), 0) AS
saldo
FROM lote l
LEFT JOIN movimentacao_estoque m ON m.id_lote = l.id_lote
GROUP BY l.id_lote, l.id_insumo, l.id_unidade, l.validade;
-- objetivo: reduzir o tempo médio de espera
CREATE VIEW vw_tempo_espera AS
SELECT ag.id_unidade,
       date_trunc('month', ag.data_hora) AS mes,
       AVG(atd.inicio_em - ag.chegada_em) AS espera_media
FROM agendamento ag
JOIN atendimento atd ON atd.id_agendamento = ag.id_agendamento
WHERE ag.chegada_em IS NOT NULL
GROUP BY ag.id_unidade, date_trunc('month', ag.data_hora);
-- objetivos: mais animais atendidos por mês e expansão da telemedicina
CREATE VIEW vw_atendimentos_mes AS
SELECT ag.id_unidade,
       date_trunc('month', atd.inicio_em) AS mes,
             ag.modalidade,
             COUNT(*)                         AS atendimentos,
             COUNT(DISTINCT ag.id_animal) AS animais_atendidos
FROM atendimento atd
JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento
GROUP BY ag.id_unidade, date_trunc('month', atd.inicio_em), ag.modalidade;
-- ---------------------------------------------------------------------
-- 13. Permissões do banco
-- ---------------------------------------------------------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'svp_app') THEN
    CREATE ROLE svp_app NOLOGIN;
  END IF;
END $$;   -- papel usado pela aplicação
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO
svp_app;
-- o log só recebe inclusões
REVOKE UPDATE, DELETE ON log_auditoria FROM svp_app;
-- prontuário não se apaga (RN08)
REVOKE DELETE ON triagem, atendimento, atendimento_diagnostico, evolucao,
                                prescricao, item_prescricao, solicitacao_exame, documento
    FROM svp_app;
-- ---------------------------------------------------------------------
-- 14. Dados iniciais
-- ---------------------------------------------------------------------
INSERT INTO perfil (nome, descricao) VALUES
  ('VETERINARIO', 'Prontuário completo dos animais atendidos'),
  ('ENFERMAGEM', 'Triagem, evolução, coleta e baixa de estoque'),
    ('RECEPCAO',                  'Cadastro, agenda e recebimento'),
    ('FINANCEIRO',                'Faturamento, pagamentos e notas fiscais'),
    ('DIRETORIA',                 'Relatórios agregados'),
    ('AUDITORIA',                 'Leitura de registros e do log'),
    ('ADMIN_TI',                  'Usuários e perfis, sem acesso a dados de negócio');
INSERT INTO especie (nome) VALUES
  ('Canina'), ('Felina'), ('Equina'), ('Bovina'), ('Ovina'), ('Caprina'),
('Suína'), ('Ave');
