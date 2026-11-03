# Entrega 9 — Relação com o negócio

As decisões de dados do SVP servem diretamente aos cinco objetivos estratégicos da Vida Plena: cada objetivo tem um dado que o mede, um lugar onde esse dado fica guardado com segurança e uma visão pronta no data warehouse para a diretoria acompanhar.

| Objetivo estratégico (etapa 1) | Decisão que o sustenta | Como é medido |
|---|---|---|
| Reduzir o tempo médio de espera | `agendamento.chegada_em` + `atendimento.inicio_em`; agenda que não aceita horário duplicado | `vw_tempo_espera` e `dw.vw_kpi_mensal.espera_media_min` |
| Aumentar os animais atendidos por mês | Atendimento sempre ligado ao agendamento e ao animal; DW conta animais distintos por pseudônimo | `dw.vw_kpi_mensal.animais_atendidos` |
| Digitalizar 100% dos prontuários | Prontuário eletrônico com campos obrigatórios; laudos e papel digitalizado no object storage, com hash | Documentos por atendimento; pedidos concluídos sem laudo |
| Expandir a telemedicina | `modalidade = TELECONSULTA`, consentimento próprio para teleconsulta | `dw.vw_kpi_mensal.teleconsulta_pct` |
| Conformidade total com a LGPD | Consentimento por finalidade, RBAC, log de leitura, retenção e anonimização, pseudonimização no DW | Log de auditoria, `vw_tutores_fim_retencao`, `vw_integracao_pendencias` |

Nos dados de demonstração (fictícios), o painel mostra como a diretoria acompanharia esses objetivos: na unidade Centro, a espera média cai de 31,1 minutos em maio para 18,3 em outubro, e a teleconsulta sobe de 4,2% para 19,8% dos atendimentos. Os números servem para provar que o indicador é calculável a partir do modelo, não como resultado real.

## A. Data Storage

O armazenamento contribui para o negócio de três formas:

- **O atendimento não para.** Réplica em outra zona, failover automático e metas de RPO de 5 minutos e RTO de 1 hora significam que uma falha de servidor não fecha a recepção.
- **O histórico do paciente está sempre lá.** O veterinário vê todo o prontuário e os laudos na hora da consulta, e a clínica cumpre o prazo de guarda de 5 anos do CFMV sem depender de papel.
- **Custo proporcional ao uso.** Arquivos no object storage (barato por GB, com camada fria), banco pequeno e um data warehouse na mesma tecnologia evitam licenças e mantêm o custo baixo enquanto a rede cresce até 2030.

## B. Data Security

- **Protege o cliente:** o tutor só tem seus dados vistos por quem precisa, com CPF mascarado para os demais, e seus dados não saem para o laboratório; ele decide por finalidade o que autoriza.
- **Protege o negócio:** o prontuário não pode ser apagado nem adulterado, nem por um funcionário nem por um invasor que tome a aplicação; backups imutáveis tornam o ransomware recuperável.
- **Protege a empresa juridicamente:** o log mostra quem acessou o quê e quando, a clínica consegue comunicar um incidente à ANPD no prazo de 3 dias úteis com base em fatos, e a política de retenção e anonimização atende à LGPD e ao CFMV. Confiança é parte da visão da empresa ("a rede mais confiável"); segurança é como ela se prova.

## C. Data Integration

- **Menos trabalho manual e menos erro:** o pedido de exame sai sozinho e o laudo volta direto para o prontuário, sem digitação, e-mail ou PDF perdido.
- **Processo que não trava:** se o laboratório estiver fora do ar, a consulta termina normalmente e o pedido é entregue depois, sem duplicar.
- **Informação no tempo certo:** a recepção vê exames atrasados, o financeiro concilia pagamentos pelo código de autorização, a diretoria recebe os indicadores toda manhã e o tutor é avisado da consulta e do resultado (o que reduz faltas).
- **Resolve um problema da etapa 1:** a "dificuldade de integração entre o sistema da clínica e os sistemas dos pagamentos" passa a ter um padrão único (REST + webhook + idempotência) para todo parceiro.

## D. Data Architecture + Data Modeling

| A empresa passa a… | Porque a arquitetura e a modelagem… |
|---|---|
| Ter dados mais organizados | Separam operacional (3FN, 46 tabelas) e analítico (estrela), cada um com um dono e uma finalidade |
| Reduzir inconsistências | Põem as regras no banco: CPF e microchip únicos, raça da espécie certa, veterinário com a especialidade, um horário por veterinário, um diagnóstico principal, preço do dia na fatura |
| Melhorar a decisão | Entregam indicadores prontos (espera, volume, telemedicina, faltas, receita) a partir de um modelo pensado para agregação |
| Aumentar a segurança | Classificam cada dado, dão a cada sistema só o que ele precisa e registram cada acesso a dado sensível |
| Integrar sistemas | Têm um ponto único de saída (outbox) e de entrada (inbox), com formato, assinatura e idempotência definidos |
| Facilitar a evolução | Cada peça pode ser trocada sem refazer as outras: o outbox pode virar um broker, o DW pode virar colunar, o login pode virar SSO, a pasta local vira S3 |
| Gerar valor com os dados | Os dados pseudonimizados permitem estudar doenças crônicas por espécie (`vw_cronicos_por_especie`), dimensionar equipe por horário e criar novos programas de acompanhamento, sem expor nenhum tutor |

**A solução foi aplicada, não só descrita.** O repositório sobe com `docker compose`: banco com as 46 tabelas e seis meses de dados fictícios, API com login, RBAC e auditoria, worker de integração, laboratório simulado e ETL para o data warehouse. Os 38 testes automatizados conferem as regras de armazenamento, segurança e integração descritas nas entregas.
