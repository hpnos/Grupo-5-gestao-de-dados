# Data Modeling — Sistema Vida Plena (SVP)

A modelagem completa (modelo conceitual, ER, modelo lógico, dicionário de dados, classificação e modelo físico) está em [modelagem-de-dados-svp.pdf](modelagem-de-dados-svp.pdf). O script físico correspondente é [`database/scripts/01_modelo_fisico.sql`](../../database/scripts/01_modelo_fisico.sql), executado sem alterações de conteúdo (só o `CREATE ROLE` ficou idempotente para poder rodar mais de uma vez no mesmo servidor).

## O que mudou depois da etapa 2

Nenhuma tabela foi removida. Os acréscimos estão listados em [Data Architecture](../data-architecture/README.md#ajustes-feitos-no-modelo-da-etapa-2) e ficam nos scripts:

| Script | Entrega | Conteúdo |
|---|---|---|
| `02_storage.sql` | 5 | Log particionado, retenção, anonimização, índices |
| `03_security.sql` | 6 | Papéis do banco, revogações, log imutável, sessões, RBAC |
| `04_integration.sql` | 7 | Outbox, inbox, protocolo e versão do exame |
| `05_rotinas.sql` | 5 e 6 | Expurgo de temporários, manutenção de partições |
| `database/dw/01_dw.sql` | 5 | Data warehouse em modelo estrela |

## Modelo analítico (data warehouse)

| Tabela | Grão | Medidas |
|---|---|---|
| `fato_agendamento` | um agendamento | status, modalidade, antecedência |
| `fato_atendimento` | um atendimento | espera, duração, perfil do paciente (pseudonimizado) |
| `fato_faturamento` | uma fatura | bruto, desconto, líquido, recebido |
| `dim_tempo`, `dim_unidade`, `dim_especie`, `dim_veterinario`, `dim_diagnostico`, `dim_servico` | — | dimensões |
