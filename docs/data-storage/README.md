# Entrega 5 — Data Storage

O SVP usa um PostgreSQL operacional com réplica, um object storage para arquivos e um data warehouse separado; o volume é pequeno (menos de 1 GB de banco por ano mesmo em 2030), então o desafio não é tamanho, e sim integridade, sigilo e disponibilidade.

Scripts: [`02_storage.sql`](../../database/scripts/02_storage.sql), [`05_rotinas.sql`](../../database/scripts/05_rotinas.sql), [`dw/01_dw.sql`](../../database/dw/01_dw.sql).

## A. Armazenamento

### Banco operacional — PostgreSQL 16 (com réplica de leitura)

- **Tecnologia:** PostgreSQL 16 em serviço gerenciado na região de São Paulo (por exemplo, Amazon RDS ou Azure Database for PostgreSQL), com uma réplica em outra zona da mesma região.
- **Por quê:** os dados são muito relacionais e precisam de transação ACID. O próprio banco garante as regras de negócio (RN03, RN04, RN05, RN09 e RN12 viram `FOREIGN KEY`, `UNIQUE` parcial e `CHECK`). Tem JSONB para o log, particionamento, permissão por coluna, é gratuito e há serviço gerenciado no Brasil.
- **Dados:** cadastro (tutor, animal, consentimento), agenda, prontuário, exames, programas crônicos, financeiro, estoque, usuários e perfis, log de auditoria e as filas de integração.
- **Organização:** 46 tabelas na 3ª forma normal, agrupadas em 8 módulos, com chave substituta `id_…`. Valores derivados ficam em visões (`vw_fatura_total`, `vw_saldo_lote`). O `log_auditoria` é particionado por mês (`log_auditoria_2026_11`…), com uma partição padrão de segurança.
- **Crescimento:** primeiro aumenta-se a máquina (vertical); leituras pesadas vão para a réplica; o log já é particionado e os meses antigos vão para o armazenamento frio; se `atendimento` passar de dezenas de milhões de linhas, particiona-se por ano. Um pool de conexões (PgBouncer) segura o aumento de usuários simultâneos.

### Object storage — laudos, exames e imagens

- **Tecnologia:** bucket privado de object storage na região de São Paulo (por exemplo, Amazon S3 ou Azure Blob Storage), com criptografia no servidor, versionamento e bloqueio de acesso público. No protótipo, uma pasta em volume Docker com a mesma interface.
- **Por quê:** arquivo grande no banco encarece backup e deixa o banco lento. O object storage cobra pouco por GB, cresce sem limite e move automaticamente o que é antigo para camadas mais baratas.
- **Dados:** PDFs de laudos, resultados de exame, imagens e termos de consentimento digitalizados.
- **Organização:** o nome do arquivo é o próprio SHA-256 (`documentos/ab/cd/abcd…`). O banco guarda só o caminho e o hash (tabela `documento`). O mesmo arquivo nunca é gravado duas vezes, e qualquer alteração é detectada na leitura.
- **Crescimento:** automático. Regras de ciclo de vida movem arquivos com mais de 1 ano para a camada fria.

### Data warehouse — indicadores

- **Tecnologia:** PostgreSQL separado (banco `svp_dw`, esquema `dw`), carregado toda noite pelo ETL a partir da réplica.
- **Por quê:** o volume analítico é de dezenas de MB por ano; um banco colunar pago não se justifica agora. Usar a mesma tecnologia reduz o que a equipe precisa saber.
- **Dados:** fatos de agendamento, atendimento e faturamento, com dimensões de tempo, unidade, espécie, veterinário, diagnóstico e serviço. Nenhum nome, CPF, contato ou texto clínico; animal e tutor aparecem só como pseudônimo (HMAC).
- **Organização:** modelo estrela, uma linha por evento de negócio, e visões prontas por objetivo (`vw_kpi_mensal`, `vw_cronicos_por_especie`).
- **Crescimento:** se passar de centenas de milhões de linhas, migra-se o esquema para um banco colunar (BigQuery, Redshift ou ClickHouse); o ETL muda só o destino.

### Volume esperado

Medido no protótipo: os dados de demonstração (2 unidades, 5.398 atendimentos em seis meses) ocupam 29 MB no banco operacional, incluindo 22.980 linhas de log. Com textos clínicos reais e o log de leitura, estimamos 30 KB por atendimento.

| Armazenamento | Por atendimento | Hoje: 2 unidades, ~10,8 mil atend./ano | 2030: 5 unidades, ~30 mil atend./ano | 5 anos guardados (2030) |
|---|---|---|---|---|
| Banco operacional (dados, índices, log) | ~30 KB | ~330 MB/ano | ~0,9 GB/ano | ~4,5 GB |
| Object storage (laudos, termos, imagens) | ~120 KB | ~1,3 GB/ano + ~6 GB de prontuários em papel digitalizados uma vez | ~3,6 GB/ano | ~18 GB + legado |
| Data warehouse | ~1,5 KB | ~16 MB/ano | ~45 MB/ano | ~0,25 GB |

Premissas: 30% dos atendimentos geram um documento de ~400 KB; a digitalização do legado é de ~20 mil páginas a 300 KB; o cenário de 2030 segue a visão de expansão da etapa 1.

## B. Persistência

### O que é persistido e o que é temporário

| Dado | Tipo | Quanto tempo |
|---|---|---|
| Cadastro, agenda, prontuário, exames, laudos, financeiro, estoque | Persistente | Prontuário: mínimo de 5 anos após o último atendimento; fiscal: 5 anos |
| Consentimentos (aceite e revogação) | Persistente | Enquanto houver dado do tutor; é a prova do consentimento |
| Log de auditoria | Persistente | 12 meses no banco; até 5 anos no armazenamento frio |
| Access token (JWT) | Temporário, não fica gravado | 15 minutos |
| Refresh token (só o hash, tabela `sessao`) | Temporário | 12 horas; apagado 7 dias depois de expirar |
| Eventos de integração já enviados (`integracao_evento`) | Temporário | 30 dias |
| Chaves de idempotência recebidas (`integracao_recebida`) | Temporário | 90 dias (maior que a janela de reenvio do parceiro) |
| Arquivo `.tmp` durante a gravação de laudo | Temporário | Segundos (renomeado ao fim) |

O expurgo dos temporários é a função `fn_expurgar_temporarios()`, rodada pelo job diário. Ela nunca toca em dado clínico, cadastral ou financeiro.

### Como os dados entram, mudam e saem

| Operação | Como é feita |
|---|---|
| Inserção | Só pela API, em transação, com SQL parametrizado. A API informa o usuário (`SET LOCAL svp.id_usuario`) e os gatilhos gravam o log com autor. |
| Atualização | Pela API, com o mesmo log de antes e depois. O prontuário não é reescrito: correção vira nova `evolucao` (RN08). Laudo é imutável: retificação vira novo documento. |
| Exclusão | `DELETE` está revogado para a aplicação em prontuário, cadastro, financeiro e log. A saída é lógica: agendamento `CANCELADO`, fatura `CANCELADA`, `data_obito` no animal, usuário desativado e, ao fim do prazo legal, `fn_anonimizar_tutor()`. |

### Integridade e prevenção de perda ou duplicidade

| Risco | Proteção | Onde |
|---|---|---|
| Dado inválido | `CHECK`, `NOT NULL`, tipos, validação Pydantic na API | Modelo físico, API |
| Referência quebrada | Chaves estrangeiras, inclusive compostas (raça da espécie certa, veterinário com a especialidade) | Modelo físico |
| Tutor ou animal duplicado | CPF e microchip únicos; nome único por tutor e espécie entre animais vivos | Modelo físico |
| Dois horários para o mesmo veterinário | Índice único parcial `(id_veterinario, data_hora)` fora dos cancelados | Modelo físico |
| Pagamento registrado duas vezes | Índice único `(forma, codigo_autorizacao)` | `04_integration.sql` |
| Mesmo laudo duas vezes | Índice único `(id_animal, hash_sha256)` | `02_storage.sql` |
| Mensagem de integração repetida | Chave de idempotência na saída e na entrada | `04_integration.sql` |
| Queda no meio de uma operação | Transação ACID; arquivo gravado em `.tmp` e renomeado; outbox no mesmo commit | API |
| Arquivo corrompido | SHA-256 conferido a cada leitura | `armazenamento.py` |
| Perda do servidor | Réplica em outra zona + backups (item C) | Infraestrutura |

## C. Backup e recuperação

| O quê | Como | Frequência | Onde | Retenção |
|---|---|---|---|---|
| Banco operacional | Arquivamento contínuo do WAL (recuperação para um instante, PITR) | Contínuo | Storage da nuvem, região São Paulo, criptografado | 35 dias |
| Banco operacional | Snapshot completo | Diário, 02:00 | Mesmo local + cópia em outra conta | 35 diários e 12 mensais |
| Banco operacional | Dump lógico (`pg_dump -Fc`) | Semanal | Outra conta, com bloqueio contra exclusão (object lock) | 12 semanas |
| Object storage | Versionamento + replicação para bucket em outra conta | Contínuo | Outra conta, com object lock | Versões antigas por 90 dias |
| Partições antigas do log | Exportação comprimida antes do `DETACH` | Mensal | Camada fria do object storage | 5 anos |
| Data warehouse | Snapshot (é recriável pelo ETL) | Semanal | Storage da nuvem | 4 semanas |
| Infraestrutura e configuração | Infraestrutura como código no Git; cofre com versões | A cada mudança | Git e cofre | Histórico completo |

Uma cópia mensal vai também para um segundo provedor com datacenter no Brasil, para o caso de perda da região inteira. A conta de backup é separada da conta de produção: quem invadir a produção não consegue apagar os backups.

**Metas:** perder no máximo 5 minutos de dados (RPO) e voltar a atender em até 1 hora (RTO) nos cenários comuns.

| Falha | Como recuperar | Perda de dados | Tempo |
|---|---|---|---|
| Servidor primário cai | Failover automático para a réplica | Segundos | Minutos |
| Erro humano (ex.: atualização errada) | PITR para uma instância nova no minuto anterior; copiar as linhas certas de volta | Nenhuma além do erro | ~1 hora |
| Arquivo apagado ou corrompido | Restaurar a versão anterior do objeto; o hash em `documento` confirma | Nenhuma | Minutos |
| Ransomware ou conta comprometida | Restaurar da cópia imutável na conta separada; trocar todos os segredos | Até o último backup (≤ 24 h) | Algumas horas |
| Perda da região | Subir no segundo provedor a partir da cópia mensal + WAL | Até 24 h | Até 1 dia |

**Teste:** todo mês o último backup é restaurado num ambiente isolado; conferem-se contagens, chaves estrangeiras e o hash de uma amostra de laudos, e o tempo é registrado. Backup que nunca foi restaurado não conta como backup.

## D. Transacional vs analítico

| | Banco operacional (OLTP) | Data warehouse (OLAP) |
|---|---|---|
| Pergunta que responde | "Qual o histórico deste animal?" | "A espera caiu este trimestre?" |
| Dados | Tudo, identificado, incluindo texto clínico | Fatos e dimensões, pseudonimizados, sem texto clínico |
| Modelo | 3FN, 46 tabelas | Estrela, 3 fatos e 6 dimensões |
| Atualização | Em tempo real, pela API | Toda noite, a partir da réplica |
| Acesso | Equipe por perfil (RBAC) | Diretoria (só leitura) e API de relatórios |

**Fica no operacional:** todo o cadastro, a agenda, o prontuário completo (o veterinário precisa do histórico na consulta), o financeiro, o estoque e os últimos 12 meses do log.

**Vai para o analítico:** um registro por agendamento, por atendimento e por fatura, com unidade, data, espécie, porte, faixa etária, modalidade, prioridade da triagem, diagnóstico principal, minutos de espera e de consulta, valores e status. Animal e tutor viram pseudônimo; nome, CPF, contato, endereço e anamnese não saem do operacional.

**Atende ao transacional** porque cada operação da recepção ou do consultório é uma transação curta em tabelas normalizadas e indexadas, com as regras garantidas pelo banco e sem relatórios pesados competindo com o atendimento.

**Atende ao analítico** porque as consultas da diretoria rodam num banco próprio, alimentado pela réplica (sem carga no primário), com o modelo já desenhado para agregação e visões prontas para os objetivos estratégicos: tempo de espera, animais atendidos, participação da telemedicina, faltas e receita.

O ETL ([`api/etl/carregar_dw.py`](../../api/etl/carregar_dw.py)) recarrega uma janela de 90 dias toda noite numa única transação: rodar de novo dá o mesmo resultado, e mudanças tardias (uma fatura paga depois, um agendamento marcado como falta) são corrigidas na carga seguinte.
