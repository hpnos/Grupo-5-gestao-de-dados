-- =====================================================================
-- SVP — Dados de demonstração (todos fictícios)
-- 2 unidades, 13 funcionários, 300 tutores, ~450 animais e seis meses
-- de agenda (mai–out/2026) com atendimentos, faturas e exames.
-- Senha de todos os usuários de demonstração: VidaPlena@2026
-- =====================================================================
SELECT setseed(0.42);

-- ------------------------------- estrutura ---------------------------
INSERT INTO unidade (nome, cnpj, telefone, logradouro, numero, bairro, cidade, uf, cep) VALUES
 ('Vida Plena Centro', '11222333000101', '7133330001', 'Av. Sete de Setembro', '100', 'Centro',   'Salvador',         'BA', '40060000'),
 ('Vida Plena Norte',  '11222333000282', '7533330002', 'Av. Getúlio Vargas',  '2000', 'Centro',  'Feira de Santana', 'BA', '44001000');

INSERT INTO funcionario (id_unidade, nome, cpf, cargo, email, data_admissao) VALUES
 (1, 'Ana Ribeiro',     '90000000001', 'VETERINARIO',   'ana.ribeiro@vidaplena.vet',   '2023-02-01'),
 (1, 'Bruno Teixeira',  '90000000002', 'VETERINARIO',   'bruno.teixeira@vidaplena.vet','2023-05-15'),
 (2, 'Clara Mendes',    '90000000003', 'VETERINARIO',   'clara.mendes@vidaplena.vet',  '2024-01-10'),
 (2, 'Diego Santana',   '90000000004', 'VETERINARIO',   'diego.santana@vidaplena.vet', '2024-03-04'),
 (1, 'Elisa Souza',     '90000000005', 'ENFERMEIRO',    'elisa.souza@vidaplena.vet',   '2023-02-01'),
 (2, 'Fábio Lima',      '90000000006', 'ENFERMEIRO',    'fabio.lima@vidaplena.vet',    '2024-01-10'),
 (1, 'Gabriela Rocha',  '90000000007', 'RECEPCIONISTA', 'gabriela.rocha@vidaplena.vet','2023-02-01'),
 (2, 'Hugo Barbosa',    '90000000008', 'RECEPCIONISTA', 'hugo.barbosa@vidaplena.vet',  '2024-01-10'),
 (1, 'Isabela Nunes',   '90000000009', 'FINANCEIRO',    'isabela.nunes@vidaplena.vet', '2023-02-01'),
 (1, 'João Pereira',    '90000000010', 'DIRETOR',       'joao.pereira@vidaplena.vet',  '2022-11-01'),
 (1, 'Karina Alves',    '90000000011', 'TI',            'karina.alves@vidaplena.vet',  '2023-02-01'),
 (1, 'Lucas Moreira',   '90000000012', 'AUDITOR',       'lucas.moreira@vidaplena.vet', '2024-06-01'),
 (2, 'Marina Castro',   '90000000013', 'VETERINARIO',   'marina.castro@vidaplena.vet', '2025-02-01');

INSERT INTO veterinario (id_veterinario, crmv, uf_crmv) VALUES
 (1, '10001', 'BA'), (2, '10002', 'BA'), (3, '10003', 'BA'), (4, '10004', 'BA'), (13, '10013', 'BA');

INSERT INTO especialidade (nome) VALUES
 ('Clínica geral'), ('Dermatologia'), ('Cardiologia'), ('Nefrologia'), ('Grandes animais');

INSERT INTO veterinario_especialidade VALUES
 (1, 1), (1, 3), (2, 1), (2, 2), (3, 1), (3, 4), (4, 5), (4, 1), (13, 1);

-- usuários: login, perfil (hash Argon2id da senha de demonstração)
INSERT INTO usuario (id_funcionario, login, senha_hash, mfa_ativo)
SELECT f.id_funcionario, l.login,
       '$argon2id$v=19$m=65536,t=3,p=4$1/GqU6fwPS4KMJ/RQa5+SA$+Bz/hw3sNyRwFMHAvZeVi0pbvsTlA5okwhaSfN9gnmc',
       FALSE
FROM (VALUES (1,'vet.ana'),(2,'vet.bruno'),(3,'vet.clara'),(4,'vet.diego'),(5,'enf.elisa'),
             (6,'enf.fabio'),(7,'rec.gabriela'),(8,'rec.hugo'),(9,'fin.isabela'),(10,'dir.joao'),
             (11,'ti.karina'),(12,'aud.lucas'),(13,'vet.marina')) AS l(id, login)
JOIN funcionario f ON f.id_funcionario = l.id;

INSERT INTO usuario_perfil (id_usuario, id_perfil)
SELECT u.id_usuario, p.id_perfil
FROM usuario u
JOIN funcionario f ON f.id_funcionario = u.id_funcionario
JOIN perfil p ON p.nome = CASE f.cargo
     WHEN 'VETERINARIO' THEN 'VETERINARIO' WHEN 'ENFERMEIRO' THEN 'ENFERMAGEM'
     WHEN 'RECEPCIONISTA' THEN 'RECEPCAO'  WHEN 'FINANCEIRO' THEN 'FINANCEIRO'
     WHEN 'DIRETOR' THEN 'DIRETORIA'       WHEN 'TI' THEN 'ADMIN_TI'
     WHEN 'AUDITOR' THEN 'AUDITORIA' END;

-- ------------------------------- catálogos ---------------------------
INSERT INTO raca (id_especie, nome) VALUES
 (1,'Labrador'),(1,'Poodle'),(1,'Shih-tzu'),(1,'Pastor alemão'),(1,'Golden retriever'),
 (2,'Persa'),(2,'Siamês'),(2,'Maine coon'),
 (3,'Mangalarga marchador'),(3,'Quarto de milha'),
 (4,'Nelore'),(4,'Girolando');

INSERT INTO diagnostico (codigo, descricao, cronico) VALUES
 ('VN-0101', 'Doença renal crônica',          TRUE),
 ('VN-0102', 'Dermatite atópica',             TRUE),
 ('VN-0103', 'Cardiomiopatia',                TRUE),
 ('VN-0104', 'Diabetes mellitus',             TRUE),
 ('VN-0201', 'Otite externa',                 FALSE),
 ('VN-0202', 'Gastroenterite aguda',          FALSE),
 ('VN-0203', 'Verminose',                     FALSE),
 ('VN-0204', 'Fratura de membro',             FALSE),
 ('VN-0205', 'Consulta de rotina / check-up', FALSE),
 ('VN-0301', 'Laminite',                      FALSE),
 ('VN-0302', 'Mastite',                       FALSE);

INSERT INTO servico (descricao, tipo, valor_base) VALUES
 ('Consulta clínica presencial',  'CONSULTA',     180.00),
 ('Teleconsulta',                 'TELECONSULTA', 120.00),
 ('Hemograma completo',           'EXAME',         60.00),
 ('Perfil bioquímico renal',      'EXAME',         90.00),
 ('Urinálise',                    'EXAME',         45.00),
 ('Programa renal (mensalidade)', 'PROGRAMA',     150.00),
 ('Consulta a campo (grandes)',   'CONSULTA',     350.00);

INSERT INTO laboratorio (razao_social, cnpj, email_integracao, api_url, segredo_ref) VALUES
 ('LabVet Análises Clínicas Ltda.', '44555666000177', 'integracao@labvet.example',
  'http://mock-lab:8001', 'svp/laboratorio/1');

INSERT INTO tipo_exame (id_servico, nome, material, prazo_dias) VALUES
 (3, 'Hemograma completo',      'sangue', 2),
 (4, 'Perfil bioquímico renal', 'sangue', 3),
 (5, 'Urinálise',               'urina',  2);

INSERT INTO programa_cronico (id_servico, nome, descricao, intervalo_retorno_dias) VALUES
 (6, 'Programa Rim Saudável', 'Acompanhamento de doença renal crônica', 30),
 (6, 'Programa Pele em Dia',  'Acompanhamento de dermatite atópica',    45);

INSERT INTO fornecedor (razao_social, cnpj, telefone, email) VALUES
 ('VetSupri Distribuidora', '77888999000155', '7130001000', 'pedidos@vetsupri.example');

INSERT INTO insumo (nome, categoria, unidade_medida, controlado, estoque_minimo) VALUES
 ('Seringa 5 ml',             'DESCARTAVEL', 'unidade', FALSE, 200),
 ('Luva de procedimento M',   'DESCARTAVEL', 'par',     FALSE, 300),
 ('Dipirona 500 mg/ml',       'MEDICAMENTO', 'ml',      FALSE, 500),
 ('Cetamina 10%',             'MEDICAMENTO', 'ml',      TRUE,  100),
 ('Vacina V10',               'VACINA',      'dose',    FALSE,  50);

INSERT INTO lote (id_insumo, id_fornecedor, id_unidade, numero_lote, validade, custo_unitario)
SELECT i.id_insumo, 1, u.id_unidade, 'L2026-' || i.id_insumo || u.id_unidade, '2027-12-31',
       (ARRAY[0.45, 0.60, 0.08, 1.90, 38.00])[i.id_insumo]
FROM insumo i CROSS JOIN unidade u;

INSERT INTO movimentacao_estoque (id_lote, tipo, quantidade, id_usuario, realizada_em, motivo)
SELECT id_lote, 'ENTRADA', 1000, 9, '2026-05-01 08:00-03', 'Compra inicial'
FROM lote;

-- ------------------------------- tutores e animais -------------------
INSERT INTO tutor (nome, cpf, data_nascimento, telefone, email, logradouro, numero, bairro,
                   cidade, uf, cep, contato_validado_em)
SELECT (ARRAY['Ana','Bruno','Carla','Daniel','Eduarda','Felipe','Gisele','Henrique','Irene','Jorge',
              'Laura','Mateus','Natália','Otávio','Patrícia','Rafael','Sabrina','Tiago','Vanessa','Wagner'])[1 + (i % 20)]
       || ' ' ||
       (ARRAY['Almeida','Batista','Cardoso','Dias','Esteves','Ferreira','Gomes','Hora','Jesus','Lopes',
              'Macedo','Nascimento','Oliveira','Pinto','Queiroz','Reis','Silva','Torres'])[1 + ((i * 7) % 18)],
       lpad((31000000000 + i * 7919)::TEXT, 11, '0'),
       DATE '1960-01-01' + (i * 37 % 18000),
       '719' || lpad((88000000 + i)::TEXT, 8, '0'),
       'tutor' || i || '@email.example',
       'Rua ' || (ARRAY['das Flores','do Sol','da Paz','Nova','Bela Vista'])[1 + (i % 5)], (i % 900 + 1)::TEXT,
       (ARRAY['Barra','Pituba','Itapuã','Brotas','Centro','Tomba'])[1 + (i % 6)],
       CASE WHEN i % 3 = 0 THEN 'Feira de Santana' ELSE 'Salvador' END, 'BA',
       '40000' || lpad((i % 999)::TEXT, 3, '0'),
       DATE '2026-04-01' + (i % 180)
FROM generate_series(1, 300) AS i;

-- consentimentos por finalidade (tutor 2 propositalmente SEM compartilhamento com laboratório)
INSERT INTO consentimento (id_tutor, finalidade, versao_termo, aceito_em, canal)
SELECT t.id_tutor, f.finalidade, 'v1.0', '2026-04-01 09:00-03'::TIMESTAMPTZ + make_interval(hours => t.id_tutor),
       (ARRAY['PRESENCIAL','APP','SITE'])[1 + (t.id_tutor % 3)]
FROM tutor t
CROSS JOIN (VALUES ('ATENDIMENTO'), ('COMPARTILHAMENTO_LAB'), ('TELECONSULTA'), ('COMUNICACAO')) AS f(finalidade)
WHERE f.finalidade = 'ATENDIMENTO'
   OR (f.finalidade = 'COMPARTILHAMENTO_LAB' AND t.id_tutor % 5 <> 2)
   OR (f.finalidade = 'TELECONSULTA'         AND t.id_tutor % 5 IN (0, 1, 3))
   OR (f.finalidade = 'COMUNICACAO'          AND t.id_tutor % 10 < 7);

-- 1 animal por tutor + um segundo para 1 em cada 2 tutores
INSERT INTO animal (id_tutor, id_especie, id_raca, nome, sexo, data_nascimento,
                    nascimento_estimado, porte, microchip, castrado)
SELECT t.id_tutor, esp.id_especie,
       (SELECT r.id_raca FROM raca r WHERE r.id_especie = esp.id_especie
         ORDER BY r.id_raca OFFSET (t.id_tutor + k) % 2 LIMIT 1),
       (ARRAY['Thor','Luna','Mel','Bob','Nina','Fred','Lola','Max','Pipoca','Amora',
              'Simba','Belinha','Tufão','Estrela','Pingo'])[1 + ((t.id_tutor * 3 + k) % 15)],
       CASE WHEN (t.id_tutor + k) % 2 = 0 THEN 'M' ELSE 'F' END,
       DATE '2012-01-01' + ((t.id_tutor * 53 + k * 101) % 5000),
       (t.id_tutor % 4 = 0),
       CASE WHEN esp.id_especie IN (3, 4) THEN 'G' WHEN esp.id_especie = 2 THEN 'P'
            ELSE (ARRAY['P','M','G'])[1 + (t.id_tutor % 3)] END,
       CASE WHEN t.id_tutor % 3 <> 0 THEN '9820' || lpad((t.id_tutor * 10 + k)::TEXT, 11, '0') END,
       (t.id_tutor % 2 = 0)
FROM tutor t
CROSS JOIN generate_series(0, 1) AS k
CROSS JOIN LATERAL (SELECT CASE
        WHEN (t.id_tutor + k) % 20 = 0 THEN 3          -- equino
        WHEN (t.id_tutor + k) % 25 = 0 THEN 4          -- bovino
        WHEN (t.id_tutor + k) % 3 = 0 THEN 2           -- felino
        ELSE 1 END AS id_especie) esp
WHERE k = 0 OR t.id_tutor % 2 = 0;

-- ------------------------------- agenda (mai–out/2026) ---------------
-- espaços de 30 min, 8h–17h30, segunda a sábado; ~55% ocupados
CREATE TEMP TABLE tmp_slot AS
SELECT v.id_vet, v.id_unidade, v.id_esp,
       (d + make_interval(hours => h, mins => mm)) AT TIME ZONE 'America/Bahia' AS data_hora,
       (extract(year FROM d) * 12 + extract(month FROM d) - (2026 * 12 + 5))::INT AS mes_idx
FROM generate_series('2026-05-01'::TIMESTAMP, '2026-10-31'::TIMESTAMP, INTERVAL '1 day') AS d
CROSS JOIN generate_series(8, 17) AS h
CROSS JOIN (VALUES (0), (30)) AS m(mm)
CROSS JOIN (VALUES (1, 1, 1), (2, 1, 1), (3, 2, 1), (4, 2, 5), (13, 2, 1)) AS v(id_vet, id_unidade, id_esp)
WHERE extract(isodow FROM d) < 7;

INSERT INTO agendamento (id_animal, id_veterinario, id_especialidade, id_unidade, data_hora,
                         duracao_min, modalidade, status, motivo, criado_por, criado_em, chegada_em)
SELECT a.id_animal, s.id_vet, s.id_esp, s.id_unidade, s.data_hora, 30,
       s.modalidade, s.status,
       (ARRAY['Rotina','Vômito','Coceira','Retorno','Claudicação','Perda de apetite'])[1 + (a.id_animal % 6)],
       CASE s.id_unidade WHEN 1 THEN 7 ELSE 8 END,
       s.data_hora - make_interval(days => 1 + (a.id_animal % 10)),
       CASE WHEN s.status = 'REALIZADO' AND s.modalidade = 'PRESENCIAL'
            THEN s.data_hora - make_interval(mins => (random() * 15)::INT) END
FROM (
    SELECT sl.*,
           CASE WHEN random() < 0.05 + 0.025 * sl.mes_idx THEN 'TELECONSULTA' ELSE 'PRESENCIAL' END AS modalidade,
           CASE WHEN r < 0.82 THEN 'REALIZADO' WHEN r < 0.90 THEN 'FALTOU' ELSE 'CANCELADO' END AS status,
           1 + floor(random() * (SELECT count(*) FROM animal))::INT AS n_animal
    FROM (SELECT *, random() AS r, random() AS ocupa FROM tmp_slot) sl
    WHERE sl.ocupa < 0.55
) s
JOIN animal a ON a.id_animal = s.n_animal
-- grandes animais só com o veterinário de grandes animais e vice-versa
WHERE (a.id_especie IN (3, 4)) = (s.id_esp = 5)
  AND (s.modalidade = 'PRESENCIAL' OR s.id_esp <> 5);

-- triagem: presenciais realizados (teleconsulta dispensa — RN07)
INSERT INTO triagem (id_agendamento, id_funcionario, realizada_em, peso_kg, temperatura_c,
                     freq_cardiaca, freq_respiratoria, queixa_principal, prioridade)
SELECT ag.id_agendamento, CASE ag.id_unidade WHEN 1 THEN 5 ELSE 6 END,
       ag.chegada_em + INTERVAL '3 minutes',
       CASE a.porte WHEN 'P' THEN 4 + random() * 6 WHEN 'M' THEN 12 + random() * 12
                    ELSE CASE WHEN a.id_especie IN (3, 4) THEN 350 + random() * 150 ELSE 28 + random() * 15 END END,
       38 + round((random() * 2)::NUMERIC, 1), 80 + (random() * 60)::INT, 18 + (random() * 20)::INT,
       ag.motivo,
       CASE WHEN random() < 0.04 THEN 'EMERGENCIA' WHEN random() < 0.15 THEN 'URGENTE'
            WHEN random() < 0.5 THEN 'POUCO_URGENTE' ELSE 'NAO_URGENTE' END
FROM agendamento ag JOIN animal a ON a.id_animal = ag.id_animal
WHERE ag.status = 'REALIZADO' AND ag.modalidade = 'PRESENCIAL';

-- atendimentos: a espera cai mês a mês (efeito esperado da agenda digital)
INSERT INTO atendimento (id_agendamento, id_veterinario, inicio_em, fim_em, anamnese,
                         exame_fisico, conduta, finalizado)
SELECT ag.id_agendamento, ag.id_veterinario, x.inicio, x.inicio + make_interval(mins => 15 + (random() * 25)::INT),
       'Tutor relata: ' || lower(ag.motivo) || '. Sem outras queixas.',
       'Mucosas normocoradas, hidratado, linfonodos sem alteração.',
       'Orientações gerais e retorno se necessário.', TRUE
FROM agendamento ag
CROSS JOIN LATERAL (SELECT CASE WHEN ag.modalidade = 'TELECONSULTA' THEN ag.data_hora
       ELSE ag.chegada_em + make_interval(mins => greatest(2, (24 - 2.5 * (extract(month FROM ag.data_hora) - 5))
                                                     + random() * 14)::INT) END AS inicio) x
WHERE ag.status = 'REALIZADO';

-- diagnóstico principal (um por atendimento — RN09)
INSERT INTO atendimento_diagnostico (id_atendimento, id_diagnostico, tipo)
SELECT atd.id_atendimento,
       CASE WHEN a.id_especie IN (3, 4) THEN (ARRAY[10, 11, 9, 8])[1 + (atd.id_atendimento % 4)]
            ELSE (ARRAY[9, 9, 5, 6, 7, 2, 1, 3, 4, 9, 6, 5])[1 + (atd.id_atendimento % 12)] END,
       'PRINCIPAL'
FROM atendimento atd
JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento
JOIN animal a ON a.id_animal = ag.id_animal;

-- ------------------------------- faturamento -------------------------
INSERT INTO fatura (id_tutor, id_atendimento, id_unidade, emitida_em, vencimento, desconto, status)
SELECT a.id_tutor, atd.id_atendimento, ag.id_unidade, atd.fim_em, atd.fim_em::DATE,
       CASE WHEN random() < 0.1 THEN 20 ELSE 0 END,
       CASE WHEN random() < 0.93 THEN 'PAGA' ELSE 'ABERTA' END
FROM atendimento atd
JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento
JOIN animal a ON a.id_animal = ag.id_animal;

INSERT INTO item_fatura (id_fatura, id_servico, quantidade, valor_unitario)
SELECT f.id_fatura,
       CASE WHEN ag.modalidade = 'TELECONSULTA' THEN 2 WHEN ag.id_especialidade = 5 THEN 7 ELSE 1 END,
       1,
       CASE WHEN ag.modalidade = 'TELECONSULTA' THEN 120 WHEN ag.id_especialidade = 5 THEN 350 ELSE 180 END
FROM fatura f
JOIN atendimento atd ON atd.id_atendimento = f.id_atendimento
JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento;

-- 15% dos atendimentos presenciais pedem exame (item na fatura + pedido)
CREATE TEMP TABLE tmp_exame AS
SELECT atd.id_atendimento, f.id_fatura, 1 + (atd.id_atendimento % 3) AS id_tipo_exame, atd.fim_em
FROM atendimento atd
JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento
JOIN fatura f ON f.id_atendimento = atd.id_atendimento
WHERE ag.modalidade = 'PRESENCIAL' AND atd.id_atendimento % 7 = 0;

INSERT INTO item_fatura (id_fatura, id_servico, quantidade, valor_unitario)
SELECT e.id_fatura, te.id_servico, 1, s.valor_base
FROM tmp_exame e JOIN tipo_exame te ON te.id_tipo_exame = e.id_tipo_exame
JOIN servico s ON s.id_servico = te.id_servico;

INSERT INTO pagamento (id_fatura, forma, valor, parcelas, codigo_autorizacao, pago_em)
SELECT f.id_fatura, fp.forma, vt.valor_total, 1,
       CASE WHEN fp.forma <> 'DINHEIRO' THEN 'TX' || lpad(f.id_fatura::TEXT, 10, '0') END,
       f.emitida_em + INTERVAL '5 minutes'
FROM fatura f
JOIN vw_fatura_total vt ON vt.id_fatura = f.id_fatura
CROSS JOIN LATERAL (SELECT (ARRAY['PIX','PIX','CREDITO','DEBITO','DINHEIRO'])[1 + (f.id_fatura % 5)] AS forma) fp
WHERE f.status = 'PAGA';

-- ------------------------------- exames ------------------------------
-- pedidos de demonstração do fluxo de integração (ids 1 e 2):
--  1 = animal do tutor 1 (com consentimento de laboratório), coletado hoje
--  2 = animal do tutor 2 (SEM consentimento), coletado hoje
INSERT INTO agendamento (id_animal, id_veterinario, id_especialidade, id_unidade, data_hora,
                         modalidade, status, motivo, criado_por, chegada_em)
SELECT a.id_animal, 1, 1, 1, ('2026-11-02 08:00'::TIMESTAMP + make_interval(mins => 30 * a.id_tutor)) AT TIME ZONE 'America/Bahia',
       'PRESENCIAL', 'REALIZADO', 'Check-up com exames', 7,
       ('2026-11-02 07:55'::TIMESTAMP + make_interval(mins => 30 * a.id_tutor)) AT TIME ZONE 'America/Bahia'
FROM animal a WHERE a.id_tutor IN (1, 2) AND a.id_animal IN (SELECT min(id_animal) FROM animal GROUP BY id_tutor);

INSERT INTO atendimento (id_agendamento, id_veterinario, inicio_em, fim_em, anamnese, finalizado)
SELECT ag.id_agendamento, 1, ag.chegada_em + INTERVAL '10 minutes', ag.chegada_em + INTERVAL '35 minutes',
       'Check-up anual; tutor solicita exames de rotina.', TRUE
FROM agendamento ag WHERE ag.motivo = 'Check-up com exames';

INSERT INTO solicitacao_exame (id_atendimento, id_tipo_exame, id_laboratorio, status, coletado_em, coletado_por)
SELECT atd.id_atendimento, 1, 1, 'COLETADO', atd.fim_em, 5
FROM atendimento atd
JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento
WHERE ag.motivo = 'Check-up com exames'
ORDER BY ag.data_hora;

-- histórico: pedidos concluídos
INSERT INTO solicitacao_exame (id_atendimento, id_tipo_exame, id_laboratorio, status, coletado_em,
                               coletado_por, resultado_em, resultado_resumo, protocolo_laboratorio, versao_resultado)
SELECT e.id_atendimento, e.id_tipo_exame, 1, 'CONCLUIDO', e.fim_em, 5,
       e.fim_em + make_interval(days => 1 + (e.id_atendimento % 2)),
       'Valores dentro da referência para a espécie.', 'LV-H' || e.id_atendimento, 1
FROM tmp_exame e;

-- inscrições em programas crônicos (animais com DRC ou dermatite)
INSERT INTO inscricao_programa (id_animal, id_programa, id_veterinario, inicio, status)
SELECT DISTINCT ON (ag.id_animal, p.id_programa) ag.id_animal, p.id_programa, ag.id_veterinario,
       atd.inicio_em::DATE, 'ATIVA'
FROM atendimento_diagnostico ad
JOIN atendimento atd ON atd.id_atendimento = ad.id_atendimento
JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento
JOIN programa_cronico p ON p.id_programa = CASE ad.id_diagnostico WHEN 1 THEN 1 WHEN 2 THEN 2 END
ORDER BY ag.id_animal, p.id_programa, atd.inicio_em;

-- baixa de material usado nos atendimentos (RN13), amostra
INSERT INTO movimentacao_estoque (id_lote, tipo, quantidade, id_atendimento, id_usuario, realizada_em, motivo)
SELECT l.id_lote, 'SAIDA', 1, atd.id_atendimento, CASE ag.id_unidade WHEN 1 THEN 5 ELSE 6 END,
       atd.fim_em, 'Uso em atendimento'
FROM atendimento atd
JOIN agendamento ag ON ag.id_agendamento = atd.id_agendamento
JOIN lote l ON l.id_unidade = ag.id_unidade AND l.id_insumo = 1
WHERE ag.modalidade = 'PRESENCIAL' AND atd.id_atendimento % 4 = 0;

DROP TABLE tmp_slot, tmp_exame;

ANALYZE;
