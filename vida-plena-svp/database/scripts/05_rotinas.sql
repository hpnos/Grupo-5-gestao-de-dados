-- =====================================================================
-- SVP — Rotinas agendadas de manutenção (rodadas pelo job diário)
-- Rodar depois de 04_integration.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Expurgo dos dados temporários
--    Só dados técnicos de vida curta. Nada clínico, cadastral ou
--    financeiro é apagado aqui.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_expurgar_temporarios()
RETURNS TABLE (item TEXT, linhas BIGINT) AS $$
DECLARE n BIGINT;
BEGIN
    DELETE FROM sessao
     WHERE coalesce(revogada_em, expira_em) < now() - INTERVAL '7 days';
    GET DIAGNOSTICS n = ROW_COUNT; item := 'sessoes expiradas'; linhas := n; RETURN NEXT;

    DELETE FROM integracao_evento
     WHERE status = 'ENVIADO' AND enviado_em < now() - INTERVAL '30 days';
    GET DIAGNOSTICS n = ROW_COUNT; item := 'eventos enviados > 30 dias'; linhas := n; RETURN NEXT;

    DELETE FROM integracao_recebida
     WHERE recebido_em < now() - INTERVAL '90 days';
    GET DIAGNOSTICS n = ROW_COUNT; item := 'mensagens recebidas > 90 dias'; linhas := n; RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- 2. Partições do log: garante os próximos 3 meses e lista as que já
--    podem ir para o armazenamento frio (mais de 12 meses)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_manter_particoes_log()
RETURNS TABLE (particao TEXT, situacao TEXT) AS $$
BEGIN
    FOR m IN 0..3 LOOP
        particao := fn_criar_particao_log((date_trunc('month', now()) + make_interval(months => m))::DATE);
        situacao := 'ativa';
        RETURN NEXT;
    END LOOP;

    RETURN QUERY
    SELECT c.relname::TEXT, 'arquivar (exportar para o armazenamento frio e DETACH)'::TEXT
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    WHERE i.inhparent = 'log_auditoria'::regclass
      AND c.relname ~ '^log_auditoria_\d{4}_\d{2}$'
      AND to_date(right(c.relname, 7), 'YYYY_MM') < date_trunc('month', now()) - INTERVAL '12 months';
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- 3. Tutores que já podem ser anonimizados pela política de retenção
-- ---------------------------------------------------------------------
CREATE VIEW vw_tutores_fim_retencao AS
SELECT t.id_tutor,
       max(atd.inicio_em) AS ultimo_atendimento,
       (SELECT max(f.emitida_em) FROM fatura f WHERE f.id_tutor = t.id_tutor) AS ultima_fatura
FROM tutor t
LEFT JOIN animal a       ON a.id_tutor = t.id_tutor
LEFT JOIN agendamento ag ON ag.id_animal = a.id_animal
LEFT JOIN atendimento atd ON atd.id_agendamento = ag.id_agendamento
WHERE t.anonimizado_em IS NULL
GROUP BY t.id_tutor
HAVING coalesce(max(atd.inicio_em), '-infinity') < now() - INTERVAL '5 years'
   AND coalesce((SELECT max(f.emitida_em) FROM fatura f WHERE f.id_tutor = t.id_tutor),
                '-infinity') < now() - INTERVAL '5 years';

-- ---------------------------------------------------------------------
-- 4. Funções administrativas não ficam abertas a qualquer papel
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION fn_expurgar_temporarios(), fn_manter_particoes_log(),
                           fn_criar_particao_log(DATE),
                           fn_anonimizar_tutor(INT, BOOLEAN) FROM PUBLIC;
