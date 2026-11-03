# Entrega 6 — Data Security

A segurança do SVP é em camadas: a API decide quem pode fazer o quê, o banco impede o que a aplicação não deveria conseguir fazer mesmo se for invadida, e o log registra cada acesso a dado clínico ou pessoal. O que o protótipo implementa está listado no fim desta página e é coberto pelos testes em [`tests/`](../../tests); o resto é política definida para a produção.

Scripts e código: [`03_security.sql`](../../database/scripts/03_security.sql), [`api/app/seguranca.py`](../../api/app/seguranca.py), [`api/app/rotas/auth.py`](../../api/app/rotas/auth.py).

## A. Identificação e classificação dos dados

| Classe | Dados | Onde está | Por que nesta classe |
|---|---|---|---|
| Público | Nome, endereço e telefone das unidades; especialidades; serviços divulgados | `unidade`, `especialidade`, `servico` | Já divulgados pela clínica |
| Interno | Catálogos (diagnóstico, exame, insumo), estoque, agenda sem identificação, indicadores do data warehouse | `diagnostico`, `tipo_exame`, `insumo`, `lote`, `dw.*` | Uso da operação; não identifica ninguém |
| Confidencial | Cadastro do tutor, consentimentos, faturas e pagamentos, dados dos funcionários | `tutor`, `consentimento`, `fatura`, `pagamento`, `nota_fiscal`, `funcionario` | Dado pessoal (LGPD, art. 5º, I) e risco de fraude |
| Sensível (restrito) | Prontuário completo, alergias, exames, laudos; log de auditoria; credenciais e segredos | `triagem`, `atendimento`, `evolucao`, `prescricao`, `documento`, `log_auditoria`, `usuario.senha_hash`, `sessao` | Sigilo profissional do médico-veterinário, ligado a um tutor identificado; credencial é a porta de entrada |

A saúde do animal não é "dado pessoal sensível" no sentido do art. 5º, II da LGPD (que trata de pessoa natural), mas o SVP a protege no nível mais alto porque está sob sigilo profissional e sempre vinculada a um tutor identificado.

## B. Controle de acesso

### Quem acessa e o quê

E = lê e edita · L = só lê · R = só relatórios agregados · — = sem acesso.

| Perfil | Cadastro | Agenda | Prontuário | Exames | Financeiro | Estoque | Log |
|---|---|---|---|---|---|---|---|
| Veterinário | L (CPF mascarado) | L | E | E | — | L | — |
| Enfermagem | L (CPF mascarado) | L | E (triagem e evolução) | E (coleta) | — | E (baixa) | — |
| Recepção | E | E | — | — | E (recebimento) | — | — |
| Financeiro | L | L | — | — | E | L | — |
| Diretoria | — | — | — | — | — | — | R (indicadores) |
| Auditoria interna | L | L | L | L | L | L | L |
| Administrador de TI | — | — | — | — | — | — | L (gerencia usuários) |

| Sistema | O que pode | Como é limitado |
|---|---|---|
| API (`svp_api`) | Ler e gravar pela aplicação | Sem `DELETE` em prontuário, cadastro, financeiro; sem `UPDATE` em laudo; não grava o log diretamente |
| ETL (`svp_etl`) | Ler o operacional e gravar o data warehouse | Permissão por coluna: não lê nome, CPF, contato, endereço nem texto clínico |
| Painel de BI (`svp_bi`) | Ler o data warehouse | Só `SELECT` no esquema `dw` |
| Laboratório | Receber pedidos e enviar resultados | Recebe só dados do animal, sem nome nem tutor; só acessa o endpoint de webhook, com assinatura HMAC |
| Gateway de pagamento | Confirmar pagamentos | Só o endpoint de confirmação, com assinatura; o SVP nunca guarda número de cartão |
| Operadora de convênio | Receber faturamento | Sem login: recebe arquivo de lote, e cada exportação fica no log |
| Tutor (portal, evolução futura) | Ver os próprios animais, laudos e faturas | Token com escopo do próprio `id_tutor`; nenhuma rota aceita outro id |

### Como impedir acesso indevido

1. **Negado por padrão.** Toda rota da API declara a permissão que exige (`exige("prontuario", "LER")`). Sem a permissão, a resposta é 403 e a tentativa vai para o log como `ACESSO_NEGADO`.
2. **Permissões no banco, não no código.** A matriz perfil × recurso × ação fica nas tabelas `perfil_permissao` e é lida a cada requisição; tirar um perfil vale na hora.
3. **Banco como segunda barreira.** Mesmo com a aplicação comprometida, o papel `svp_api` não consegue apagar prontuário, alterar laudo ou mexer no log.
4. **Minimização na tela.** Quem só lê o cadastro vê CPF e telefone mascarados (`***.456.789-**`).
5. **Acesso de emergência com justificativa.** Leitura fora do perfil exige justificativa, que fica no log e é revisada pela auditoria.
6. **Desligamento automático.** Ao preencher `data_desligamento`, um gatilho desativa o usuário e revoga todas as sessões.
7. **Revisão trimestral** dos perfis atribuídos, feita pela auditoria interna.

## C. Autenticação e autorização

**Autenticação**

- Login e senha. A senha é guardada como hash **Argon2id** (com sal e custo de memória), nunca em texto.
- **MFA (TOTP)** obrigatório em produção para quem acessa prontuário, financeiro, log ou administração. O segredo do MFA fica cifrado no banco (Fernet, chave no cofre). No protótipo o MFA é ativado por usuário e os usuários de demonstração vêm sem ele.
- Ao acertar, o usuário recebe um **access token JWT de 15 minutos** e um **refresh token de 12 horas**. O banco guarda só o hash do refresh token; cada uso troca o token (rotação) e o logout o revoga.
- Em produção, a clínica pode trocar o login próprio por SSO (OpenID Connect) com o provedor de identidade corporativo; o resto não muda.

**Autorização**

- RBAC com três níveis: **perfil** (VETERINARIO, ENFERMAGEM, RECEPCAO, FINANCEIRO, DIRETORIA, AUDITORIA, ADMIN_TI), **permissão** (recurso + ação: LER, CRIAR, EDITAR, EXCLUIR, EXPORTAR) e **usuário**, que pode ter mais de um perfil.
- A verificação é feita na API, por rota, a partir da visão `vw_permissoes_usuario`.

**Tentativas não autorizadas**

| Situação | Resposta | Registro |
|---|---|---|
| Sem token ou token vencido | 401 | — |
| Senha errada ou login inexistente | 401 com a mesma mensagem e o mesmo tempo de resposta (não revela se o login existe) | `LOGIN_FALHA` com o motivo |
| 5 falhas seguidas | 423, usuário bloqueado por 15 minutos, mesmo com a senha certa | `LOGIN_FALHA` "bloqueado" |
| Rota sem permissão | 403 | `ACESSO_NEGADO` com recurso e ação |
| Webhook com assinatura errada ou fora da janela de 5 minutos | 401 | `ACESSO_NEGADO` com a origem |

Regra de monitoramento definida para a produção: alertar quando um usuário acumular 5 acessos negados em uma hora ou fizer login fora do horário da unidade (consulta periódica ao log).

## D. Proteção dos dados

| Momento | Proteção |
|---|---|
| **Transmissão** | HTTPS com TLS 1.2 ou superior em toda conexão externa, com HSTS. Conexão da aplicação ao banco com `sslmode=verify-full`. Chamadas ao laboratório com token Bearer; webhooks com assinatura HMAC-SHA256, carimbo de tempo e janela de 5 minutos contra reenvio. |
| **Armazenamento** | Disco do banco, réplica, snapshots, object storage e backups criptografados (AES-256, chaves no KMS da nuvem). Senha em Argon2id; refresh token em SHA-256; segredo do MFA cifrado. Nenhum número de cartão (RN12). Data warehouse com ids pseudonimizados por HMAC. SHA-256 em cada documento para detectar alteração. |
| **Processamento** | Só os campos necessários saem na resposta; dado clínico com `Cache-Control: no-store`. SQL sempre parametrizado (sem injeção). Entrada validada por esquema (Pydantic). Logs da aplicação não imprimem conteúdo. Contêiner sem root. O ETL trabalha em memória, sem arquivo intermediário. |
| **Credenciais e segredos** | Nada no código nem no Git. Segredos no cofre da nuvem, entregues como variável de ambiente na hora da execução; no protótipo, arquivo `.env` fora do Git (`.gitignore`), com `.env.example` sem valores reais. O banco guarda só a referência ao segredo (`laboratorio.segredo_ref`). Um papel de banco por sistema; ninguém usa o superusuário no dia a dia. Rotação a cada 90 dias e em todo desligamento de quem tinha acesso. |

## E. Auditoria

| Evento | Como é registrado |
|---|---|
| Login, logout e falha de login | `fn_registrar_acesso` (LOGIN, LOGOUT, LOGIN_FALHA) |
| Leitura de prontuário e de cadastro | API, a cada consulta (LEITURA) |
| Inclusão, alteração e exclusão em dados clínicos, tutor, animal, alergia, consentimento e pagamento | Gatilho `fn_auditar` com o conteúdo antes e depois (JSONB) e o autor |
| Alteração de perfis e permissões | Gatilhos em `usuario_perfil` e `perfil_permissao` |
| Acesso negado | API e webhook (ACESSO_NEGADO) |
| Envio de dados para fora | Pedido ao laboratório, lote ao convênio, exportação de relatório (EXPORTACAO) |
| Acesso de emergência | Campo `justificativa` obrigatório |
| Mensagens trocadas com parceiros | `integracao_evento` (saída) e `integracao_recebida` (entrada) |

O próprio log é protegido: a aplicação não tem `INSERT`, `UPDATE` nem `DELETE` nele (só as funções do banco escrevem), um gatilho bloqueia alteração até para o dono das tabelas, o horário vem do servidor, e só Auditoria e TI conseguem ler. Ele fica 12 meses no banco e até 5 anos no armazenamento frio.

## F. Riscos

| Risco | Impacto | Estratégia de proteção |
|---|---|---|
| Vazamento ou adivinhação de senha | Alto | Argon2id, MFA, bloqueio após 5 tentativas, sessão curta e revogável |
| Funcionário lendo prontuário sem motivo | Alto | RBAC por perfil, log de cada leitura, revisão de acessos, CPF mascarado |
| Interceptação dos dados | Alto | TLS em toda conexão, HSTS, `verify-full` no banco, HMAC nos webhooks |
| Injeção de SQL | Alto | Consultas parametrizadas, validação de entrada e papel sem `DELETE` |
| Exclusão acidental ou maliciosa | Alto | `DELETE` revogado, exclusão lógica, PITR e backup imutável em outra conta |
| Exposição de credenciais | Alto | Cofre de segredos, `.env` fora do Git, varredura de segredos no GitHub, rotação |
| Ransomware | Alto | Backup imutável (object lock) em conta separada e restauração testada todo mês |
| Webhook falso ou reenviado | Médio/Alto | Assinatura HMAC, janela de 5 minutos e chave de idempotência |
| Vazamento pelo ambiente analítico | Médio | Pseudonimização, permissão por coluna no ETL e BI só de leitura |
| Compartilhar amostra sem consentimento | Médio | API exige consentimento ativo para a finalidade (RN14) e envia o mínimo de dados |

**Resposta a incidente.** Se houver incidente com dado pessoal que possa causar risco ou dano relevante, a clínica comunica a ANPD e os titulares em até 3 dias úteis e guarda o registro do incidente por no mínimo 5 anos, como exige a [Resolução CD/ANPD nº 15/2024](https://www.mattosfilho.com.br/unico/regulamento-incidente-seguranca/) (LGPD, art. 48). O log de auditoria é a base para dizer o que foi acessado, por quem e quando.

## O que o protótipo implementa e testa

| Controle | Teste |
|---|---|
| Hash Argon2id, bloqueio após 5 falhas, mensagem igual para login inexistente | `test_seguranca_api.py` |
| Refresh token só como hash, com rotação | `test_refresh_gira_o_token` |
| MFA TOTP com segredo cifrado | `test_mfa_exige_codigo` |
| 403 e `ACESSO_NEGADO` no log; leitura de prontuário no log | `test_recepcao_nao_le_prontuario…`, `test_veterinario_le_prontuario…` |
| CPF mascarado para quem só lê | `test_cpf_mascarado_para_quem_so_le_cadastro` |
| API sem `DELETE` em prontuário e sem alterar o log; log imutável até para o dono | `test_banco.py` |
| ETL sem acesso a CPF e anamnese; BI só leitura; DW sem colunas identificáveis | `test_banco.py`, `test_etl_dw.py` |
| Desligamento desativa o usuário | `test_desligamento_desativa_usuario` |
| Webhook com assinatura errada ou antiga é recusado | `test_integracao.py` |
