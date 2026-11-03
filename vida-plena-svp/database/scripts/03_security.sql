-- =====================================================================
-- SVP — Entrega 6 (Data Security): controle de acesso no banco
-- Rodar depois de 02_storage.sql. As senhas dos papéis com LOGIN NÃO
-- ficam aqui: o script de inicialização as define a partir de secrets.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Papéis do banco (privilégio mínimo)
--    svp_app  → NOLOGIN, conjunto de permissões da aplicação (01_modelo)
--    svp_api  → LOGIN usado pela API e pelo worker; herda svp_app
--    svp_etl  → LOGIN do ETL; só lê colunas não identificáveis
--    svp_bi   → LOGIN do painel; só lê o data warehouse (05_dw.sql)
--    Ninguém usa o superusuário no dia a dia.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'svp_api') THEN
        CREATE ROLE svp_api LOGIN IN ROLE svp_app;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'svp_etl') THEN
        CREATE ROLE svp_etl LOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'svp_bi') THEN
        CREATE ROLE svp_bi LOGIN;
    END IF;
END $$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO svp_app, svp_etl;

-- reaplica o GRANT da etapa 2 (inclui as tabelas criadas no 02_storage)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO svp_app;

-- ---------------------------------------------------------------------
-- 2. O que a aplicação NÃO pode fazer, mesmo se for comprometida
-- ---------------------------------------------------------------------
-- log: a aplicação não grava direto; usa as funções SECURITY DEFINER
REVOKE INSERT, UPDATE, DELETE ON log_auditoria FROM svp_app;
-- prontuário não se apaga (RN08), agora também nas tabelas novas
REVOKE DELETE ON triagem, atendimento, atendimento_diagnostico, evolucao,
                 prescricao, item_prescricao, solicitacao_exame, documento
          FROM svp_app;
-- laudo arquivado é imutável: uma correção é um novo documento
REVOKE UPDATE ON documento FROM svp_app;
-- cadastro e financeiro: exclusão lógica (anonimização, status CANCELADA)
REVOKE DELETE ON tutor, animal, consentimento, fatura, item_fatura,
                 pagamento, nota_fiscal, usuario, funcionario
          FROM svp_app;
-- consentimento: o aceite é prova; só a revogação pode ser gravada depois
REVOKE UPDATE ON consentimento FROM svp_app;
GRANT  UPDATE (revogado_em) ON consentimento TO svp_app;
-- política de retenção só muda por migração
REVOKE INSERT, UPDATE, DELETE ON politica_retencao FROM svp_app;

-- ---------------------------------------------------------------------
-- 3. Log imutável também para o dono das tabelas (defesa em profundidade)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_log_imutavel() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'log_auditoria é somente inclusão (operação % bloqueada)', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_log_imutavel BEFORE UPDATE OR DELETE ON log_auditoria
    FOR EACH ROW EXECUTE FUNCTION fn_log_imutavel();

-- o gatilho de auditoria roda com o privilégio do dono, não da aplicação
ALTER FUNCTION fn_auditar() SECURITY DEFINER SET search_path = public, pg_temp;

-- eventos que não são INSERT/UPDATE/DELETE (login, leitura, exportação,
-- acesso negado) entram por esta função; a aplicação não escolhe
-- dados_antes/dados_depois nem o horário
CREATE OR REPLACE FUNCTION fn_registrar_acesso(
    p_id_usuario    INT,
    p_acao          VARCHAR,
    p_tabela        VARCHAR DEFAULT NULL,
    p_id_registro   BIGINT  DEFAULT NULL,
    p_ip            INET    DEFAULT NULL,
    p_justificativa VARCHAR DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF p_acao NOT IN ('LOGIN','LOGIN_FALHA','LOGOUT','LEITURA','EXPORTACAO','ACESSO_NEGADO') THEN
        RAISE EXCEPTION 'Ação % não pode ser registrada por esta função', p_acao;
    END IF;
    INSERT INTO log_auditoria (id_usuario, acao, tabela, id_registro, ip_origem, justificativa)
    VALUES (p_id_usuario, p_acao, p_tabela, p_id_registro, p_ip, p_justificativa);
END;
$$;
REVOKE ALL ON FUNCTION fn_registrar_acesso(INT, VARCHAR, VARCHAR, BIGINT, INET, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_registrar_acesso(INT, VARCHAR, VARCHAR, BIGINT, INET, VARCHAR) TO svp_app;

-- mudanças de perfil e de permissão também vão para o log
CREATE TRIGGER tg_audit_usuario_perfil AFTER INSERT OR UPDATE OR DELETE ON usuario_perfil
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_usuario');
CREATE TRIGGER tg_audit_perfil_permissao AFTER INSERT OR UPDATE OR DELETE ON perfil_permissao
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_perfil');
CREATE TRIGGER tg_audit_consentimento AFTER INSERT OR UPDATE ON consentimento
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_consentimento');

-- ---------------------------------------------------------------------
-- 4. Autenticação: bloqueio por tentativas, MFA e sessões
-- ---------------------------------------------------------------------
ALTER TABLE usuario
    ADD COLUMN falhas_login     SMALLINT    NOT NULL DEFAULT 0,
    ADD COLUMN bloqueado_ate    TIMESTAMPTZ,
    ADD COLUMN mfa_segredo_cif  BYTEA,          -- segredo TOTP cifrado pela aplicação (chave no cofre)
    ADD COLUMN senha_alterada_em TIMESTAMPTZ NOT NULL DEFAULT now();

-- refresh tokens: o banco guarda só o hash do token
CREATE TABLE sessao (
    id_sessao     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario    INT         NOT NULL REFERENCES usuario (id_usuario),
    refresh_hash  CHAR(64)    NOT NULL UNIQUE,
    criada_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
    expira_em     TIMESTAMPTZ NOT NULL,
    revogada_em   TIMESTAMPTZ,
    ip_origem     INET,
    CHECK (expira_em > criada_em)
);
CREATE INDEX ix_sessao_usuario ON sessao (id_usuario) WHERE revogada_em IS NULL;
GRANT SELECT, INSERT, UPDATE ON sessao TO svp_app;

-- desligamento do funcionário desativa o usuário e derruba as sessões
CREATE OR REPLACE FUNCTION fn_desligamento() RETURNS trigger AS $$
BEGIN
    IF NEW.data_desligamento IS NOT NULL AND OLD.data_desligamento IS NULL THEN
        UPDATE usuario SET ativo = FALSE WHERE id_funcionario = NEW.id_funcionario;
        UPDATE sessao s SET revogada_em = now()
          FROM usuario u
         WHERE u.id_usuario = s.id_usuario AND u.id_funcionario = NEW.id_funcionario
           AND s.revogada_em IS NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE TRIGGER tg_desligamento AFTER UPDATE OF data_desligamento ON funcionario
    FOR EACH ROW EXECUTE FUNCTION fn_desligamento();

-- ---------------------------------------------------------------------
-- 5. ETL: lê só o que o data warehouse precisa (permissão por coluna)
--    Nada de nome, CPF, contato, endereço, anamnese ou texto clínico.
-- ---------------------------------------------------------------------
GRANT SELECT (id_tutor, cidade, uf, anonimizado_em)                   ON tutor       TO svp_etl;
GRANT SELECT (id_animal, id_tutor, id_especie, porte, sexo,
              data_nascimento, castrado, data_obito)                  ON animal      TO svp_etl;
GRANT SELECT (id_agendamento, id_animal, id_veterinario, id_especialidade,
              id_unidade, data_hora, duracao_min, modalidade, status,
              criado_em, chegada_em)                                  ON agendamento TO svp_etl;
GRANT SELECT (id_atendimento, id_agendamento, id_veterinario,
              inicio_em, fim_em, finalizado)                          ON atendimento TO svp_etl;
GRANT SELECT (id_triagem, id_agendamento, prioridade)                 ON triagem     TO svp_etl;
GRANT SELECT ON especie, raca, unidade, especialidade, diagnostico,
                atendimento_diagnostico, servico, fatura, item_fatura,
                pagamento, programa_cronico, inscricao_programa       TO svp_etl;
GRANT SELECT (id_veterinario)                                         ON veterinario TO svp_etl;
GRANT SELECT (id_funcionario, id_unidade, nome, cargo)                ON funcionario TO svp_etl;

-- ---------------------------------------------------------------------
-- 6. RBAC da aplicação: permissões por recurso e ação (matriz da etapa 2)
-- ---------------------------------------------------------------------
INSERT INTO permissao (recurso, acao)
SELECT r, a
FROM unnest(ARRAY['cadastro','agenda','prontuario','exames','financeiro',
                  'estoque','relatorios','log','usuarios']) AS r,
     unnest(ARRAY['LER','CRIAR','EDITAR','EXCLUIR','EXPORTAR']) AS a;

-- cada linha: perfil, recurso, ações permitidas
WITH matriz (perfil, recurso, acoes) AS (VALUES
    ('VETERINARIO', 'cadastro',   ARRAY['LER']),
    ('VETERINARIO', 'agenda',     ARRAY['LER']),
    ('VETERINARIO', 'prontuario', ARRAY['LER','CRIAR','EDITAR']),
    ('VETERINARIO', 'exames',     ARRAY['LER','CRIAR','EDITAR']),
    ('VETERINARIO', 'estoque',    ARRAY['LER']),
    ('ENFERMAGEM',  'cadastro',   ARRAY['LER']),
    ('ENFERMAGEM',  'agenda',     ARRAY['LER']),
    ('ENFERMAGEM',  'prontuario', ARRAY['LER','CRIAR']),
    ('ENFERMAGEM',  'exames',     ARRAY['LER','EDITAR']),
    ('ENFERMAGEM',  'estoque',    ARRAY['LER','CRIAR','EDITAR']),
    ('RECEPCAO',    'cadastro',   ARRAY['LER','CRIAR','EDITAR']),
    ('RECEPCAO',    'agenda',     ARRAY['LER','CRIAR','EDITAR']),
    ('RECEPCAO',    'financeiro', ARRAY['LER','CRIAR']),
    ('FINANCEIRO',  'cadastro',   ARRAY['LER']),
    ('FINANCEIRO',  'agenda',     ARRAY['LER']),
    ('FINANCEIRO',  'financeiro', ARRAY['LER','CRIAR','EDITAR','EXPORTAR']),
    ('FINANCEIRO',  'estoque',    ARRAY['LER']),
    ('DIRETORIA',   'relatorios', ARRAY['LER','EXPORTAR']),
    ('AUDITORIA',   'cadastro',   ARRAY['LER']),
    ('AUDITORIA',   'agenda',     ARRAY['LER']),
    ('AUDITORIA',   'prontuario', ARRAY['LER']),
    ('AUDITORIA',   'exames',     ARRAY['LER']),
    ('AUDITORIA',   'financeiro', ARRAY['LER']),
    ('AUDITORIA',   'estoque',    ARRAY['LER']),
    ('AUDITORIA',   'log',        ARRAY['LER']),
    ('ADMIN_TI',    'usuarios',   ARRAY['LER','CRIAR','EDITAR']),
    ('ADMIN_TI',    'log',        ARRAY['LER'])
)
INSERT INTO perfil_permissao (id_perfil, id_permissao)
SELECT p.id_perfil, pm.id_permissao
FROM matriz m
JOIN perfil p     ON p.nome = m.perfil
JOIN permissao pm ON pm.recurso = m.recurso AND pm.acao = ANY (m.acoes);

-- a aplicação lê a matriz, mas não a altera (só o ADMIN_TI por migração)
REVOKE INSERT, UPDATE, DELETE ON perfil, permissao, perfil_permissao FROM svp_app;

CREATE VIEW vw_permissoes_usuario AS
SELECT u.id_usuario, u.login, p.nome AS perfil, pm.recurso, pm.acao
FROM usuario u
JOIN usuario_perfil up   ON up.id_usuario = u.id_usuario
JOIN perfil p            ON p.id_perfil = up.id_perfil
JOIN perfil_permissao pp ON pp.id_perfil = p.id_perfil
JOIN permissao pm        ON pm.id_permissao = pp.id_permissao
WHERE u.ativo;
GRANT SELECT ON vw_permissoes_usuario TO svp_app;
