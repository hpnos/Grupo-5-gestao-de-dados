# Vida Plena Clínicas Veterinárias

Trabalho da disciplina de Gestão de Dados — modelagem de uma empresa fictícia e do sistema de software que sustenta seu negócio.

---

## 1. A Empresa

### Nome da empresa
**Vida Plena Clínicas Veterinárias Ltda.**

### Segmento de atuação
Saúde — clínica veterinária multiespecialidades (atendimento ambulatorial particular), com foco em atendimento em animais de grande, médio e pequeno porte.

### Missão
Oferecer atendimento médico de qualidade e acessível, promovendo saúde e bem-estar para os animais que atendemos.

### Visão
Ser reconhecida, até 2030, como a rede de clínicas veterinárias mais confiável e tecnológica da região, referência em atendimento veterinário e em uso responsável da tecnologia.

### Valores
- Ética e transparência
- Respeito e cuidado com o animal
- Excelência no atendimento
- Inovação constante
  

### Produtos/serviços
- Consultas presenciais
- Teleconsultas (telemedicina)
- Exames laboratoriais básicos (coleta própria, análise terceirizada)
- Programas de acompanhamento de doenças crônicas 


### Clientes
- Pacientes particulares


### Fornecedores e parceiros
- Laboratórios de análises clínicas (terceirizados)
- Operadoras de planos de saúde (convênios)
- Fornecedores de insumos médicos (materiais descartáveis, medicamentos)
- Empresa de TI responsável pelo sistema e infraestrutura
- Farmácias parceiras

### Organograma 
```
Diretoria Geral
├── Diretoria Clínica
│   └── Corpo médico veterinário 
├── Diretoria Administrativa
│   ├── Financeiro
|   |
│   └── TI
└── Coordenação de Atendimento
    ├── Recepção
    └── Enfermagem
```

### Principais processos
1. Agendamento de consultas
2. Recepção e triagem do animal
3. Atendimento médico e registro em prontuário
4. Faturamento e cobrança (particular)
5. Gestão de estoque de materiais e insumos
6. Geração de relatórios gerenciais

### Objetivos estratégicos
- Reduzir o tempo médio de espera
- Aumentar o número de animais atendidos por mês
- Digitalizar 100% dos prontuários
- Expandir o serviço de telemedicina
- Garantir conformidade total com a LGPD

---

## 2. Projeto de Software — Sistema Vida Plena (SVP)

Sistema de gestão clínica que cobre agendamento, prontuário eletrônico, faturamento e relatórios gerenciais.

### Dados que o sistema produz e utiliza
- **Cadastrais:** nome, data de nascimento, endereço, telefone do responsável 
- **Clínicos:** histórico médico, diagnósticos (CID), prescrições, resultados de exames, alergias, evolução do animal
- **Agendamento:** data/hora da consulta, médico responsável, especialidade, status (confirmado/cancelado/faltou)
- **Financeiros:** forma de pagamento, valores cobrados, notas fiscais
- **Operacionais/usuários do sistema:** login e perfil de acesso de médicos, recepcionistas e administradores; logs de acesso e alterações

### Quem utiliza esses dados
- Médicos e enfermeiros (dados clínicos)
- Recepcionistas/atendentes (agendamento e cadastro)
- Setor financeiro (dados de cobrança)
- Diretoria/coordenação (relatórios gerenciais)
- Auditoria interna e, parcialmente, operadoras de convênio (dados de faturamento)

### Onde os dados são armazenados
- Banco de dados relacional em nuvem (ex.: PostgreSQL), com servidores localizados no Brasil
- Backups automatizados periódicos (diários/semanais)
- Documentos digitalizados (exames, laudos) em repositório de arquivos vinculado ao prontuário

### Dados sensíveis
- **Dados de saúde:** diagnósticos, exames, histórico clínico e alergias — classificados como dado sensível pela LGPD (Art. 5º, II)
- **Dados de identificação:** nome do responsável do animal
- **Dados financeiros:** forma de pagamento e informações de convênio

### Problemas relacionados aos dados
- Cadastros duplicados 
- Prontuários incompletos ou preenchidos de forma não padronizada
- Dados desatualizados (telefone, endereço)
- Dificuldade de integração entre o sistema da clínica e os sistemas dos pagamentos 

### Riscos
- Vazamento de dados sensíveis de saúde (violação da LGPD e possíveis multas)
- Acesso indevido a prontuários por funcionários sem permissão
- Perda de dados por falha de backup
- Indisponibilidade do sistema impactando o atendimento
- Uso indevido de dados para finalidades não autorizadas

### Necessidades do negócio
- Garantir conformidade com a LGPD (consentimento do paciente, controle de acesso, política de retenção/descarte)
- Implementar controle de acesso por perfil de usuário (RBAC), limitando quem vê dados clínicos completos
- Rotina consistente de backup e plano de recuperação de desastres
- Auditoria e log de todos os acessos a dados sensíveis
- Treinamento periódico da equipe sobre proteção de dados e sigilo médico
