# Entrega 8 — Integração das entregas

O desenho final mostra o SVP em quatro camadas (usuários e parceiros, aplicação, dados, análise e cópias), com a fronteira TLS entre a internet e a aplicação; as siglas em cada caixa indicam qual entrega está presente ali.

![Arquitetura de dados do SVP com as cinco entregas marcadas](../../diagrams/arquitetura-final.png)

Fonte do desenho: [`diagrams/gerar_diagramas.py`](../../diagrams/gerar_diagramas.py) (diagrama como código; gera SVG e PNG).

## Onde está cada conceito

| Conceito | Onde aparece no desenho | O que foi decidido | Artefato no repositório |
|---|---|---|---|
| **Data Architecture** (ARQ) | O desenho inteiro: camadas, componentes e setas | Banco operacional + réplica, object storage, data warehouse, backups, API, worker, ETL e cofre; tudo no Brasil | [`docs/data-architecture`](../data-architecture/README.md), `docker-compose.yml` |
| **Data Modeling** (MOD) | PostgreSQL 16 e Data warehouse | 46 tabelas em 3FN no operacional; modelo estrela (3 fatos, 6 dimensões) no analítico | [`docs/data-modeling`](../data-modeling/README.md), `database/scripts/01_modelo_fisico.sql`, `database/dw/01_dw.sql` |
| **Data Storage** (STO) | PostgreSQL, Réplica, Object storage, Backups, Data warehouse | Log particionado, retenção de 5 anos, anonimização, PITR + snapshots + cópia imutável, arquivos por SHA-256 | [`docs/data-storage`](../data-storage/README.md), `02_storage.sql`, `05_rotinas.sql` |
| **Data Security** (SEC) | Fronteira TLS, API, Cofre, Object storage, Backups, ETL | RBAC, Argon2id + MFA, papéis de banco com privilégio mínimo, log imutável, criptografia, pseudonimização | [`docs/data-security`](../data-security/README.md), `03_security.sql`, `api/app/seguranca.py` |
| **Data Integration** (INT) | Parceiros externos, API (webhooks), Worker (pedidos), ETL | REST + outbox na saída, webhook assinado na entrada, idempotência, ETL noturno | [`docs/data-integration`](../data-integration/README.md), `04_integration.sql`, `api/app/worker.py` |

## Como os conceitos se ligam

1. A **arquitetura** decidiu separar operacional e analítico; a **modelagem** desenhou um modelo para cada lado (3FN e estrela).
2. A **modelagem** colocou as regras no banco; o **storage** apoiou-se nelas para evitar duplicidade e perda (índices únicos, chaves estrangeiras, transações).
3. O **storage** guardou o arquivo fora do banco; a **segurança** cifrou o bucket e a **integração** usou o SHA-256 para provar que o laudo recebido é o laudo guardado.
4. A **segurança** proibiu `DELETE` no prontuário; o **storage** respondeu com exclusão lógica e anonimização ao fim do prazo.
5. A **integração** grava o evento no mesmo commit (outbox); isso só funciona porque o **storage** é um banco transacional.
6. O **ETL** é integração e segurança ao mesmo tempo: leva os dados ao analítico já pseudonimizados, com um papel que não enxerga CPF.
