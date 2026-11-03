-- =====================================================================
-- SVP — Ambiente analítico (data warehouse) — banco svp_dw
-- Modelo estrela, sem dados que identifiquem o tutor. Os ids de animal
-- e tutor chegam pseudonimizados (HMAC-SHA256 com chave do cofre):
-- dá para contar animais distintos, mas não voltar ao cadastro.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS dw;

-- ------------------------------- dimensões ---------------------------
CREATE TABLE dw.dim_tempo (
    data         DATE PRIMARY KEY,
    ano          SMALLINT NOT NULL,
    trimestre    SMALLINT NOT NULL,
    mes          SMALLINT NOT NULL,
    dia          SMALLINT NOT NULL,
    dia_semana   SMALLINT NOT NULL,          -- 1 = segunda ... 7 = domingo
    nome_mes     VARCHAR(10) NOT NULL
);

INSERT INTO dw.dim_tempo
SELECT d::DATE, extract(year FROM d), extract(quarter FROM d), extract(month FROM d),
       extract(day FROM d), extract(isodow FROM d),
       (ARRAY['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'])[extract(month FROM d)]
FROM generate_series('2024-01-01'::DATE, '2030-12-31'::DATE, INTERVAL '1 day') AS d;

CREATE TABLE dw.dim_unidade (
    id_unidade INT PRIMARY KEY,
    nome       VARCHAR(100) NOT NULL,
    cidade     VARCHAR(80),
    uf         CHAR(2)
);

CREATE TABLE dw.dim_especie (
    id_especie INT PRIMARY KEY,
    nome       VARCHAR(50) NOT NULL
);

CREATE TABLE dw.dim_veterinario (
    id_veterinario INT PRIMARY KEY,
    nome           VARCHAR(120) NOT NULL,   -- dado interno do colaborador (produtividade)
    id_unidade     INT
);

CREATE TABLE dw.dim_diagnostico (
    id_diagnostico INT PRIMARY KEY,
    codigo         VARCHAR(15) NOT NULL,
    descricao      VARCHAR(200) NOT NULL,
    cronico        BOOLEAN NOT NULL
);

CREATE TABLE dw.dim_servico (
    id_servico INT PRIMARY KEY,
    descricao  VARCHAR(120) NOT NULL,
    tipo       VARCHAR(15) NOT NULL
);

-- -------------------------------- fatos ------------------------------
-- um agendamento por linha: taxa de falta, cancelamento e telemedicina
CREATE TABLE dw.fato_agendamento (
    id_agendamento INT PRIMARY KEY,
    data           DATE NOT NULL REFERENCES dw.dim_tempo (data),
    id_unidade     INT  NOT NULL REFERENCES dw.dim_unidade (id_unidade),
    id_veterinario INT  NOT NULL REFERENCES dw.dim_veterinario (id_veterinario),
    modalidade     VARCHAR(12) NOT NULL,
    status         VARCHAR(12) NOT NULL,
    antecedencia_dias INT                      -- marcação → consulta
);

-- um atendimento por linha: volume, espera, duração, perfil do paciente
CREATE TABLE dw.fato_atendimento (
    id_atendimento   INT PRIMARY KEY,
    data             DATE NOT NULL REFERENCES dw.dim_tempo (data),
    id_unidade       INT  NOT NULL REFERENCES dw.dim_unidade (id_unidade),
    id_veterinario   INT  NOT NULL REFERENCES dw.dim_veterinario (id_veterinario),
    id_especie       INT  NOT NULL REFERENCES dw.dim_especie (id_especie),
    id_diagnostico   INT  REFERENCES dw.dim_diagnostico (id_diagnostico),  -- principal
    modalidade       VARCHAR(12) NOT NULL,
    porte            CHAR(1) NOT NULL,
    faixa_etaria     VARCHAR(12),             -- filhote, adulto, idoso, sem data
    prioridade       VARCHAR(15),             -- da triagem; nulo na teleconsulta
    espera_min       NUMERIC(8,1),            -- chegada → início
    duracao_min      NUMERIC(8,1),            -- início → fim
    animal_pseudo    CHAR(64) NOT NULL,       -- HMAC do id_animal
    tutor_pseudo     CHAR(64) NOT NULL,       -- HMAC do id_tutor
    cidade_tutor     VARCHAR(80),
    uf_tutor         CHAR(2)
);
CREATE INDEX ix_fato_atend_data ON dw.fato_atendimento (data, id_unidade);

-- uma fatura por linha: receita, desconto, inadimplência, forma de pagamento
CREATE TABLE dw.fato_faturamento (
    id_fatura      INT PRIMARY KEY,
    data           DATE NOT NULL REFERENCES dw.dim_tempo (data),
    id_unidade     INT  NOT NULL REFERENCES dw.dim_unidade (id_unidade),
    valor_bruto    NUMERIC(12,2) NOT NULL,
    desconto       NUMERIC(12,2) NOT NULL,
    valor_liquido  NUMERIC(12,2) NOT NULL,
    valor_pago     NUMERIC(12,2) NOT NULL,
    forma_principal VARCHAR(15),
    status         VARCHAR(10) NOT NULL,
    teleconsulta   BOOLEAN NOT NULL
);

-- controle de cada carga (rastreabilidade do ETL)
CREATE TABLE dw.etl_execucao (
    id_execucao   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iniciada_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
    terminada_em  TIMESTAMPTZ,
    janela_inicio DATE NOT NULL,
    janela_fim    DATE NOT NULL,
    linhas        JSONB,
    status        VARCHAR(10) NOT NULL DEFAULT 'RODANDO'
                  CHECK (status IN ('RODANDO','OK','ERRO')),
    erro          TEXT
);

-- ------------------- indicadores dos objetivos estratégicos ----------
CREATE VIEW dw.vw_kpi_mensal AS
WITH atd AS (
    SELECT date_trunc('month', data)::DATE AS mes, id_unidade,
           count(*)                                       AS atendimentos,
           count(DISTINCT animal_pseudo)                  AS animais_atendidos,
           count(*) FILTER (WHERE modalidade = 'TELECONSULTA') AS teleconsultas,
           round(avg(espera_min), 1)                      AS espera_media_min
    FROM dw.fato_atendimento GROUP BY 1, 2
), ag AS (
    SELECT date_trunc('month', data)::DATE AS mes, id_unidade,
           round(100.0 * count(*) FILTER (WHERE status = 'FALTOU')
                 / NULLIF(count(*) FILTER (WHERE status IN ('REALIZADO','FALTOU')), 0), 1) AS taxa_falta_pct
    FROM dw.fato_agendamento GROUP BY 1, 2
), fat AS (
    SELECT date_trunc('month', data)::DATE AS mes, id_unidade,
           sum(valor_liquido) AS receita_faturada,
           sum(valor_pago)    AS receita_recebida
    FROM dw.fato_faturamento WHERE status <> 'CANCELADA' GROUP BY 1, 2
)
SELECT atd.mes, u.nome AS unidade, atd.atendimentos, atd.animais_atendidos,
       atd.teleconsultas,
       round(100.0 * atd.teleconsultas / NULLIF(atd.atendimentos, 0), 1) AS teleconsulta_pct,
       atd.espera_media_min, ag.taxa_falta_pct,
       fat.receita_faturada, fat.receita_recebida
FROM atd
JOIN dw.dim_unidade u ON u.id_unidade = atd.id_unidade
LEFT JOIN ag  ON ag.mes = atd.mes AND ag.id_unidade = atd.id_unidade
LEFT JOIN fat ON fat.mes = atd.mes AND fat.id_unidade = atd.id_unidade;

CREATE VIEW dw.vw_cronicos_por_especie AS
SELECT e.nome AS especie, d.descricao AS diagnostico,
       count(DISTINCT f.animal_pseudo) AS animais
FROM dw.fato_atendimento f
JOIN dw.dim_diagnostico d ON d.id_diagnostico = f.id_diagnostico AND d.cronico
JOIN dw.dim_especie e     ON e.id_especie = f.id_especie
GROUP BY e.nome, d.descricao;

-- ------------------------------ permissões ---------------------------
-- svp_etl escreve; svp_bi (painel da diretoria) e svp_api só leem
GRANT USAGE ON SCHEMA dw TO svp_etl, svp_bi, svp_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA dw TO svp_etl;
GRANT SELECT ON ALL TABLES IN SCHEMA dw TO svp_bi, svp_api;
