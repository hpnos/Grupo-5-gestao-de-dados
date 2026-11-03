# Entrega 7 — Data Integration

O SVP troca dados com seis parceiros e com o próprio data warehouse; a integração principal, com o laboratório, foi implementada de ponta a ponta: o pedido sai por REST a partir de um *outbox* gravado no mesmo commit, e o resultado volta por webhook assinado, sem perda nem duplicidade.

Código: [`api/app/rotas/exames.py`](../../api/app/rotas/exames.py) (envio), [`api/app/worker.py`](../../api/app/worker.py) (entrega), [`api/app/rotas/integracoes.py`](../../api/app/rotas/integracoes.py) (webhook), [`api/mock_lab/main.py`](../../api/mock_lab/main.py) (laboratório simulado), [`api/etl/carregar_dw.py`](../../api/etl/carregar_dw.py) (ETL). Estrutura no banco: [`04_integration.sql`](../../database/scripts/04_integration.sql).

## A. Sistemas integrados

| # | Envia | Recebe | Por que precisam trocar dados | Mecanismo | No protótipo |
|---|---|---|---|---|---|
| 1 | SVP | Laboratório terceirizado | A clínica coleta a amostra e o laboratório analisa | REST + outbox | Implementado |
| 2 | Laboratório | SVP | O resultado e o laudo voltam para o prontuário | Webhook | Implementado |
| 3 | SVP ↔ Gateway de pagamento | — | Gerar cobrança PIX/cartão e receber a confirmação com o código de autorização | REST + webhook | Especificado |
| 4 | SVP | Emissor de NFS-e da prefeitura | Emitir a nota fiscal de serviço de cada fatura paga | REST + outbox | Especificado |
| 5 | SVP | Operadora de convênio | Enviar o faturamento do mês para reembolso | Arquivo (lote) por SFTP | Especificado |
| 6 | SVP | Tutor (WhatsApp, SMS, e-mail) | Confirmar consulta e avisar que o resultado saiu; reduz faltas | Mensageria via outbox | Especificado |
| 7 | Banco operacional (réplica) | Data warehouse | Gerar os indicadores da diretoria | ETL pelo banco | Implementado |
| 8 | Fornecedor | SVP | Dar entrada de lote e validade no estoque a partir da NF-e | Arquivo XML | Especificado |

## B. Dados integrados (laboratório)

### 1. Pedido: SVP → laboratório

`POST {api_url}/api/v1/pedidos` · cabeçalhos `Authorization: Bearer <token>` e `Idempotency-Key: exame-1-envio`

```json
{
  "referencia_svp": 1,
  "exame": "Hemograma completo",
  "material": "sangue",
  "coletado_em": "2026-11-02T09:00:00-03:00",
  "paciente": {
    "codigo": "VP-A-000001",
    "especie": "Canina",
    "raca": "Poodle",
    "sexo": "F",
    "porte": "M",
    "idade_anos": 14,
    "peso_kg": null
  },
  "solicitante": { "crmv": "10001-BA", "unidade": "Vida Plena Centro" },
  "callback_url": "https://api.vidaplena.vet/integracoes/laboratorio/1/resultados"
}
```

Resposta `201`: `{"protocolo": "LV-C1C1BF58", "previsao_resultado_dias": 2}`

| Campo | Obrigatório | Origem no SVP | Transformação |
|---|---|---|---|
| `referencia_svp` | Sim | `solicitacao_exame.id_solicitacao` | — |
| `exame`, `material` | Sim | `tipo_exame.nome`, `tipo_exame.material` | — |
| `coletado_em` | Sim | `solicitacao_exame.coletado_em` | ISO 8601 com fuso |
| `paciente.codigo` | Sim | `animal.id_animal` | Vira código `VP-A-000001`; o laboratório não recebe nome do animal nem do tutor |
| `paciente.idade_anos` | Não | `animal.data_nascimento` | Data vira idade em anos (minimização) |
| `paciente.peso_kg` | Não | `triagem.peso_kg` | — |
| `solicitante.crmv` | Sim | `veterinario.crmv` + `uf_crmv` | Concatenados |
| `callback_url` | Sim | Configuração | Endereço do webhook deste laboratório |

### 2. Resultado: laboratório → SVP

`POST /integracoes/laboratorio/1/resultados` · cabeçalhos `X-SVP-Timestamp`, `X-SVP-Assinatura: sha256=<HMAC do timestamp + corpo>` e `Idempotency-Key: LV-C1C1BF58-v1`

```json
{
  "protocolo": "LV-C1C1BF58",
  "referencia_svp": 1,
  "versao": 1,
  "status": "CONCLUIDO",
  "concluido_em": "2026-11-03T15:00:00-03:00",
  "resumo": "Hemácias, leucócitos e plaquetas dentro da referência para a espécie.",
  "laudo": {
    "nome_arquivo": "laudo-LV-C1C1BF58-v1.pdf",
    "tipo_conteudo": "application/pdf",
    "conteudo_base64": "JVBERi0xLjQK...",
    "sha256": "9f2c…(64 caracteres)"
  }
}
```

Resposta `200`: `{"situacao": "processado", "id_solicitacao": 1, "id_documento": 1, "versao": 1}` — ou `duplicado`, ou `versao_antiga`.

| Transformação na entrada | Destino |
|---|---|
| `laudo.conteudo_base64` → bytes → SHA-256 conferido | Arquivo no object storage, nome = hash |
| Caminho + hash + `origem = 'laboratorio:1'` | Nova linha em `documento` |
| `status`, `concluido_em`, `resumo`, `versao` | `solicitacao_exame` (status `CONCLUIDO`, `resultado_em`, `resultado_resumo`, `versao_resultado`) |
| Chave + hash do corpo + resultado | `integracao_recebida` |

### Outras integrações (formato)

| Integração | Formato | Campos principais |
|---|---|---|
| Confirmação de pagamento | JSON por webhook assinado | `id_cobranca`, `id_fatura`, `forma`, `valor`, `codigo_autorizacao`, `pago_em` → `pagamento` (o código é único: webhook repetido não duplica) |
| NFS-e | JSON (API do emissor) | Prestador, tomador (nome e CPF do tutor), serviço, valor → devolve `numero`, `serie`, `codigo_verificacao` para `nota_fiscal` |
| Lote do convênio | CSV UTF-8, um arquivo por operadora e mês | `numero_carteira`, `codigo_animal`, `data_atendimento`, `servico`, `valor`, `id_fatura` |
| Notificação ao tutor | JSON para o provedor de mensagens | Telefone, modelo da mensagem, data e hora; só se houver consentimento `COMUNICACAO` |
| ETL | Linhas do banco → linhas do DW | `id_animal` e `id_tutor` viram HMAC; nascimento vira faixa etária; horários viram minutos de espera e de consulta |

## C. Forma de integração

| Mecanismo | Onde | Por que é adequado |
|---|---|---|
| **REST** | Pedido ao laboratório, NFS-e, cobrança | O parceiro responde na hora com um protocolo; é o padrão que laboratórios e gateways oferecem |
| **Webhook** | Resultado do laboratório, confirmação de pagamento | O resultado leva de horas a dias; o parceiro avisa quando fica pronto, sem o SVP perguntar a cada minuto |
| **Outbox no PostgreSQL** (mensageria) | Todo envio para fora | O evento é gravado no mesmo commit do dado de negócio: ou os dois existem, ou nenhum. Se o parceiro cair, o atendimento segue e o worker entrega depois. Para ~150 exames por mês não vale manter um broker (RabbitMQ, Kafka); a tabela usa `FOR UPDATE SKIP LOCKED` e pode ser trocada por um broker sem mudar a API |
| **Arquivo** | Convênio, NF-e de fornecedor | É como operadoras e fornecedores trabalham; o lote mensal fecha com o ciclo de reembolso |
| **Banco de dados** | ETL para o data warehouse | Carga noturna em lote basta para indicadores; lendo da réplica, não pesa no atendimento |

## D. Fluxo de dados

O desenho abaixo detalha a integração SVP ↔ laboratório; no desenho geral da arquitetura ([Entrega 8](../arquitetura-final/README.md)) ela aparece como as setas *pedidos* (Worker → Parceiros) e *webhooks* (Parceiros → API).

![Fluxo da integração com o laboratório](../../diagrams/fluxo-integracao-laboratorio.png)

1. O veterinário pede o envio (`POST /exames/1/enviar`). A API confere o perfil, se o pedido está `COLETADO` e se o tutor consentiu em compartilhar com laboratório (RN14).
2. Na mesma transação, grava o evento `EXAME_SOLICITADO` em `integracao_evento` e responde `202`.
3. O worker pega o evento com um *lease* de 5 minutos (`FOR UPDATE SKIP LOCKED`).
4. Envia o pedido ao laboratório com o token e a chave de idempotência.
5. O laboratório responde `201` com o protocolo. Se responder `503` ou não responder, o evento fica `ERRO` e é reenviado depois.
6. O worker grava `ENVIADO` e o protocolo no pedido.
7. Quando o resultado sai, o laboratório chama o webhook com assinatura, horário e chave.
8. A API confere assinatura, chave, formato, protocolo, versão e o SHA-256 do laudo.
9. Grava o PDF no object storage, com o hash como nome.
10. Numa única transação, cria o `documento`, marca o pedido `CONCLUIDO` e registra a mensagem em `integracao_recebida`.
11. Responde `200` ao laboratório.

## E. Tratamento de erros

| Situação | O que acontece | Onde a equipe vê |
|---|---|---|
| Laboratório indisponível (5xx, conexão recusada) | Evento vai para `ERRO` e é reenviado com espera crescente: 30 s, 1, 2, 4 … até 1 h. São até 12 tentativas, cerca de 5 horas; depois vira `FALHA_DEFINITIVA`. O atendimento não para. | `vw_integracao_pendencias` |
| Timeout (5 s para conectar, 10 s para responder) | Igual ao anterior. O reenvio usa a mesma chave, então, se o laboratório tiver recebido, devolve o mesmo protocolo em vez de criar outro pedido. | `integracao_evento.ultimo_erro` |
| Dados inválidos na saída (4xx) | `FALHA_DEFINITIVA` na hora, porque repetir não resolve. A TI corrige o cadastro e reenfileira. | `vw_integracao_pendencias` |
| Dados inválidos na entrada | Resposta `422` com os erros; a mensagem fica `REJEITADA` em `integracao_recebida`. O laboratório corrige e reenvia. | `integracao_recebida` |
| Assinatura errada ou mensagem antiga (> 5 min) | `401`; nada é processado; tentativa registrada no log. | `log_auditoria` (ACESSO_NEGADO) |
| Dados duplicados | Mesma chave na entrada → `200 duplicado`, nada muda. Mesma chave na saída → laboratório devolve o protocolo original. Mesmo arquivo → mesmo documento. | `integracao_recebida` |
| Falha durante a transmissão | Quem enviou não recebe resposta e reenvia; a idempotência garante um único efeito. | — |
| Falha ao salvar (entrada) | A transação inteira volta; a API responde `500` e o laboratório reenvia. Se o PDF já tiver sido gravado, ele é reaproveitado (mesmo hash); arquivos sem `documento` são apagados por um job semanal. | Log da aplicação |
| Falha ao salvar (saída) ou worker caiu | O evento fica `PROCESSANDO`; o lease vence em 5 minutos e outro worker reenvia com a mesma chave. | `integracao_evento` |
| Resultado não chega | Pedidos `ENVIADO` além do prazo do exame aparecem na visão de atrasos; a recepção cobra o laboratório. | `vw_exames_atrasados` |

## F. Consistência dos dados

**Dados corretos.** Só entra mensagem com assinatura HMAC válida e dentro da janela de 5 minutos. O JSON é validado por esquema (tipos, tamanhos, `status` permitido, hash com 64 caracteres). O pedido precisa existir, ser do mesmo laboratório e ter o mesmo protocolo. O SHA-256 do laudo precisa bater com o conteúdo.

**Sem duplicidade.** Chave de idempotência nos dois sentidos, com índice único (`integracao_evento.chave_idempotencia`, `integracao_recebida (origem, chave)`), e um *advisory lock* para duas entregas simultâneas da mesma mensagem. Restrições únicas no protocolo do laboratório, no código de autorização do pagamento e no hash do documento.

**Identificar atualização.** Cada resultado tem um número de `versao`. Laudo retificado chega com versão maior e substitui o resumo; versão igual ou menor é ignorada (`versao_antiga`). O laudo anterior continua guardado, porque documento é imutável. `atualizado_em` marca a última mudança.

**Dados inconsistentes entre sistemas.** Cada dado tem um dono: o SVP é a fonte do cadastro, da agenda e do pedido; o laboratório, do resultado; o gateway, do pagamento. Rotinas diárias de conciliação comparam os dois lados: pedidos em atraso (`vw_exames_atrasados`) são consultados no laboratório pelo protocolo; pagamentos são conferidos com o extrato do gateway pelo código de autorização. No ETL, cada carga fica em `dw.etl_execucao` com a contagem de linhas, e a recarga da janela de 90 dias corrige diferenças.
