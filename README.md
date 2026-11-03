# Sistema Vida Plena (SVP)

Trabalho da disciplina de Gestão de Dados — Entregas 5 a 9, com documentação e protótipo do Sistema Vida Plena, da Vida Plena Clínicas Veterinárias.

## Integrantes

| Nome |
|--- |
| Levi Falcão | 
| Jonatas Paixão | 
| Saulo de Melo | 
| Joabe Irlan  | 
| Otávio vinícius | 
| Moisés Oliveira |
| Rafael Santos | 


## Descrição do sistema

O SVP é o sistema de gestão da rede de clínicas veterinárias Vida Plena: agenda, prontuário eletrônico do animal, pedidos de exame a laboratórios terceirizados, faturamento, estoque e relatórios para a diretoria. O paciente é o animal; o titular dos dados pessoais é o tutor. A empresa e o sistema estão descritos na [etapa 1](docs/data-architecture/etapa-1-empresa-e-sistema.md) e a modelagem na [etapa 2](docs/data-modeling/README.md).

## Entregas

| Entrega | Documento |
|---|---|
| Data Architecture (referência) | [docs/data-architecture](docs/data-architecture/README.md) |
| Data Modeling (etapa 2) | [docs/data-modeling](docs/data-modeling/README.md) |
| 5 — Data Storage | [docs/data-storage](docs/data-storage/README.md) |
| 6 — Data Security | [docs/data-security](docs/data-security/README.md) |
| 7 — Data Integration | [docs/data-integration](docs/data-integration/README.md) |
| 8 — Integração das entregas | [docs/arquitetura-final](docs/arquitetura-final/README.md) |
| 9 — Relação com o negócio | [docs/relacao-negocio](docs/relacao-negocio/README.md) |

## Arquitetura de dados

**Entrega 8 — Arquitetura final:** [visualizar diagrama em PDF](diagrams/entrega-8-svp.pdf).

No protótipo, os dados operacionais ficam no **PostgreSQL**; os documentos são armazenados em arquivos com metadados no banco; e um **data warehouse** separado, em modelo estrela, recebe dados por ETL executado sob demanda. A API concentra as regras e a segurança, enquanto um worker realiza a integração com o laboratório simulado. Réplica, armazenamento externo e backups automatizados/imutáveis fazem parte da arquitetura proposta para produção e não estão configurados no ambiente local.

## Tecnologias

| Camada | Tecnologia |
|---|---|
| Banco operacional e data warehouse | PostgreSQL 16 |
| API | Python 3.12, FastAPI, psycopg 3 |
| Segurança | Argon2id (senhas), JWT (sessão), TOTP (MFA), Fernet (segredos), HMAC-SHA256 (webhooks e pseudonimização) |
| Integração | REST, webhook, transactional outbox, HTTPX |
| Ambiente | Docker Compose |
| Testes | pytest (38 testes) |

## Bancos utilizados

| Banco | Conteúdo | Papel que acessa |
|---|---|---|
| `svp` | 46 tabelas de negócio (42 da modelagem + retenção, sessão, outbox, inbox) e o log particionado por mês | `svp_api` (API e worker), `svp_etl` (só colunas não identificáveis) |
| `svp_dw` | Esquema `dw`: 3 fatos, 6 dimensões e visões de indicadores | `svp_etl` (carga), `svp_bi` e `svp_api` (só leitura) |

Scripts em ordem: [`database/scripts`](database/scripts) `01` a `05`, depois [`database/data/seed.sql`](database/data/seed.sql) (dados fictícios) e [`database/dw/01_dw.sql`](database/dw/01_dw.sql).

## Como executar

Pré-requisito: Docker com Compose.

```bash
cp .env.example .env          # troque todos os valores
docker compose up -d --build  # sobe banco, API, worker e laboratório simulado
docker compose run --rm etl   # carrega o data warehouse
```

Documentação interativa da API: <http://localhost:8000/docs>. Senha de todos os usuários de demonstração: `VidaPlena@2026` (logins: `vet.ana`, `enf.elisa`, `rec.gabriela`, `fin.isabela`, `dir.joao`, `aud.lucas`, `ti.karina`).

### Roteiro de demonstração (integração com o laboratório)

```bash
# 1. login como veterinária
TOKEN=$(curl -s -X POST localhost:8000/auth/login -H 'Content-Type: application/json' \
  -d '{"login":"vet.ana","senha":"VidaPlena@2026"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

# 2. pedido 2 é de um tutor sem consentimento → 409
curl -s -X POST localhost:8000/exames/2/enviar -H "Authorization: Bearer $TOKEN"

# 3. pedido 1 entra no outbox; o worker entrega ao laboratório em segundos
curl -s -X POST localhost:8000/exames/1/enviar -H "Authorization: Bearer $TOKEN"

# 4. veja o protocolo devolvido pelo laboratório
docker compose exec db psql -U postgres -d svp -c \
  "SELECT status, protocolo_laboratorio FROM solicitacao_exame WHERE id_solicitacao = 1"

# 5. o laboratório conclui e chama o webhook assinado (troque LV-XXXX pelo protocolo)
curl -s -X POST localhost:8001/simular/concluir/LV-XXXX

# 6. o resultado aparece no prontuário; a leitura fica no log
curl -s localhost:8000/animais/1/prontuario -H "Authorization: Bearer $TOKEN"

# 7. para ver a retentativa: deixe o laboratório "fora do ar" antes do passo 3
curl -s -X POST localhost:8001/simular/falhas/2
```

Outros testes rápidos: `rec.gabriela` tentando abrir `/animais/1/prontuario` recebe 403 (e o log registra); `dir.joao` em `/relatorios/kpis` vê os indicadores do data warehouse; `aud.lucas` em `/auditoria/logs` consulta a trilha.

### Testes automatizados

Precisa de um PostgreSQL 16 local (ou o do Compose em `localhost:5432`) e do usuário `postgres`:

```bash
pip install -r api/requirements.txt
TEST_PGHOST=localhost TEST_PGUSER=postgres TEST_PGPASSWORD=<senha> pytest -q
```

Os testes criam os bancos `svp_teste` e `svp_dw_teste` do zero, aplicam todos os scripts e conferem banco, segurança da API, integração e ETL.

## Estratégia de segurança

- **Acesso:** RBAC com 7 perfis e permissões por recurso e ação guardadas no banco; toda rota exige uma permissão; negações vão para o log.
- **Autenticação:** senha em Argon2id, MFA (TOTP), bloqueio após 5 falhas, JWT de 15 minutos e refresh token revogável guardado só como hash.
- **Banco como segunda barreira:** a aplicação não apaga prontuário, cadastro ou financeiro, não altera laudo e não escreve no log diretamente; o ETL não lê CPF nem texto clínico.
- **Proteção:** TLS em tudo, criptografia em repouso, nenhum número de cartão, data warehouse pseudonimizado, segredos fora do código (`.env` fora do Git, cofre em produção).
- **Auditoria:** login, leitura de prontuário, alterações, permissões, exportações e acessos negados, num log particionado e imutável.

Detalhes em [docs/data-security](docs/data-security/README.md).

## Integrações realizadas

| Integração | Mecanismo | Situação |
|---|---|---|
| SVP → laboratório (pedido) | REST a partir de outbox, com retentativa e idempotência | Implementada e testada |
| Laboratório → SVP (resultado e laudo) | Webhook com HMAC, janela anti-replay, idempotência e versão | Implementada e testada |
| Banco operacional → data warehouse | ETL com pseudonimização (execução manual no protótipo) | Implementada e testada |
| Pagamento, NFS-e, convênio, notificações, NF-e de fornecedor | REST, webhook, arquivo e mensageria | Especificadas na Entrega 7 |

## Diagramas

- **Entrega 7 — Data Integration:** [Fluxo de integração com o laboratório (PDF)](diagrams/entrega-7-svp.pdf).
- **Entrega 8 — Integração das Entregas:** [Arquitetura final de dados (PDF)](diagrams/entrega-8-svp.pdf).
- **Data Modeling:** [Diagrama entidade-relacionamento (PDF)](docs/data-modeling/modelagem-de-dados-svp.pdf).

O script [`diagrams/gerar_diagramas.py`](diagrams/gerar_diagramas.py) permite gerar versões SVG e PNG localmente (requer `cairosvg` para PNG). Os diagramas publicados neste repositório estão em PDF.

## Principais decisões técnicas

| Decisão | Motivo |
|---|---|
| PostgreSQL para operacional e analítico | Regras garantidas pelo banco, JSONB, particionamento, permissão por coluna; volume pequeno não justifica outra tecnologia |
| Arquivos fora do banco, nomeados pelo SHA-256 | Banco pequeno, backup rápido, deduplicação e prova de integridade |
| Log particionado por mês e imutável | É a tabela que mais cresce; meses antigos vão para o frio sem `DELETE` |
| Exclusão lógica e anonimização | Prontuário não se apaga (RN08); ao fim dos 5 anos o tutor é anonimizado e o histórico fica |
| Transactional outbox em vez de broker | Entrega garantida sem nova infraestrutura para ~150 exames por mês |
| Webhook com HMAC, timestamp e idempotência | Autenticidade, proteção contra reenvio e nenhum efeito duplicado |
| Papéis de banco por sistema | Uma falha na API não vira exclusão de prontuário nem vazamento de CPF pelo ETL |
| Pseudonimização por HMAC no DW | Indicadores por animal sem expor quem é o tutor |

## Estrutura do repositório

```
├── api/                 API (app/), worker, laboratório simulado (mock_lab/), ETL (etl/), Dockerfile
├── database/
│   ├── scripts/         01_modelo_fisico … 05_rotinas
│   ├── dw/              data warehouse
│   ├── data/            seed de demonstração (fictício)
│   └── aplicar.sh       aplica tudo num PostgreSQL sem Docker
├── diagrams/            PDFs das Entregas 7 e 8 e gerador SVG/PNG
├── docs/                uma pasta por entrega
├── infra/initdb/        inicialização do banco no Docker
├── tests/               38 testes (pytest)
├── docker-compose.yml
└── .env.example
```
