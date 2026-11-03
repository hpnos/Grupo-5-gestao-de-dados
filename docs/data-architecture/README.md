# Data Architecture — Sistema Vida Plena (SVP)

O SVP separa o dado em quatro lugares, cada um escolhido pelo uso: o banco operacional atende a clínica em tempo real, o object storage guarda os arquivos, o data warehouse responde às perguntas da diretoria e os backups garantem a volta em caso de falha.

Esta é a arquitetura de referência das Entregas 5 a 9. Ela parte da etapa 1 ([empresa e sistema](etapa-1-empresa-e-sistema.md)) e da [modelagem de dados](../data-modeling/README.md), e todas as decisões das entregas seguintes se apoiam nela.

[Arquitetura de dados do SVP](../../diagrams/entrega-8-svp.pdf)

## Componentes

| Camada | Componente | Tecnologia | Papel |
|---|---|---|---|
| Usuários | Equipe da clínica, diretoria | Navegador e app, painel de BI | Usam o sistema e os indicadores |
| Parceiros | Laboratório, pagamento, NFS-e, convênios | APIs e arquivos dos parceiros | Trocam pedidos, resultados e cobranças |
| Borda | Fronteira de rede | HTTPS/TLS, firewall de aplicação | Única porta de entrada |
| Aplicação | API SVP | Python 3.12 + FastAPI | Regras de negócio, autenticação, RBAC e auditoria |
| Aplicação | Worker de integração | Python, padrão *transactional outbox* | Entrega os eventos aos parceiros com retentativa |
| Aplicação | ETL noturno | Python | Leva os dados da réplica para o data warehouse, pseudonimizados |
| Aplicação | Cofre de segredos | Secret manager da nuvem | Senhas, tokens e chaves fora do código |
| Dados | Banco operacional | PostgreSQL 16 gerenciado, região São Paulo | Cadastro, agenda, prontuário, financeiro, estoque e log |
| Dados | Réplica de leitura | PostgreSQL, outra zona da mesma região | Assume se o primário cair e alimenta o ETL |
| Dados | Object storage | Bucket privado, criptografado e versionado | Laudos, exames, imagens e termos digitalizados |
| Dados | Data warehouse | PostgreSQL separado, modelo estrela | Indicadores sem dados do tutor |
| Dados | Backups | PITR + snapshots + cópia imutável em outra conta | Recuperação de falha, erro humano e ransomware |

## Ajustes feitos no modelo da etapa 2

As 42 tabelas da modelagem continuam iguais; as entregas 5 a 7 acrescentaram o que a operação real precisa. Os scripts ficam em [`database/scripts`](../../database/scripts).

| Entrega | Ajuste | Motivo |
|---|---|---|
| 5 — Storage | `log_auditoria` particionada por mês | É a tabela que mais cresce; meses antigos vão para o armazenamento frio sem `DELETE` |
| 5 — Storage | `politica_retencao` e `fn_anonimizar_tutor` | Prazo de guarda e anonimização ao fim dele |
| 5 — Storage | CPF e telefone do tutor só podem ficar vazios depois da anonimização | Permite anonimizar sem perder a regra de cadastro completo |
| 6 — Security | Papéis `svp_api`, `svp_etl` e `svp_bi`; permissões por coluna | Privilégio mínimo por sistema |
| 6 — Security | Tabela `sessao`; colunas de bloqueio e MFA em `usuario` | Login com bloqueio, MFA e sessão revogável |
| 6 — Security | Ações `ACESSO_NEGADO` e `PERMISSAO` no log; log imutável por gatilho | Registrar tentativas negadas e proteger a trilha |
| 7 — Integration | Tabelas `integracao_evento` (outbox) e `integracao_recebida` (inbox) | Entrega garantida e sem duplicidade |
| 7 — Integration | Protocolo e versão do resultado em `solicitacao_exame`; `origem` em `documento` | Reconhecer atualização e registrar quem enviou o laudo |

Com isso o banco tem 46 tabelas de negócio, mais as partições mensais do log.

## Princípios

1. **O banco garante as regras.** Unicidade, chaves estrangeiras e `CHECK` impedem dado inválido mesmo que a aplicação falhe.
2. **Nada se apaga do prontuário nem do financeiro.** Correção vira novo registro; descarte vira anonimização.
3. **Cada sistema enxerga só o que precisa.** A API não apaga prontuário, o ETL não lê CPF, o painel não escreve.
4. **Integração não trava o atendimento.** O evento é gravado no mesmo commit e entregue depois.
5. **Tudo no Brasil.** Banco, arquivos e backups ficam em datacenters no país, como definido na etapa 1.
