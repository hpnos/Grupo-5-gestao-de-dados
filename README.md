# Vida Plena Clínicas Médicas

Trabalho da disciplina de Gestão de Dados — modelagem de uma empresa fictícia e do sistema de software que sustenta seu negócio.

---

## 1. A Empresa

### Nome da empresa
**Vida Plena Clínicas Médicas Ltda.**

### Segmento de atuação
Saúde — clínica médica multiespecialidades (atendimento ambulatorial particular e por convênio), com foco em clínico geral, pediatria, cardiologia, dermatologia e nutrição.

### Missão
Oferecer atendimento médico de qualidade, humanizado e acessível, promovendo saúde e bem-estar para a comunidade que atendemos.

### Visão
Ser reconhecida, até 2030, como a rede de clínicas médicas mais confiável e tecnológica da região, referência em atendimento humanizado e em uso responsável da tecnologia.

### Valores
- Ética e transparência
- Respeito e cuidado com o paciente
- Excelência no atendimento
- Inovação constante
- Confidencialidade das informações
- Compromisso social

### Produtos/serviços
- Consultas médicas presenciais
- Teleconsultas (telemedicina)
- Exames laboratoriais básicos (coleta própria, análise terceirizada)
- Programas de acompanhamento de doenças crônicas (diabetes, hipertensão)
- Check-ups preventivos
- Emissão de laudos, receitas e atestados

### Clientes
- Pacientes particulares
- Pacientes de planos de saúde/convênios
- Empresas parceiras (programas de saúde ocupacional/exames admissionais)

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
│   └── Corpo médico (clínico geral, pediatria, cardiologia, dermatologia, nutrição)
├── Diretoria Administrativa
│   ├── Financeiro
│   ├── Recursos Humanos
│   └── TI
└── Coordenação de Atendimento
    ├── Recepção
    └── Enfermagem
```

### Principais processos
1. Agendamento de consultas
2. Recepção e triagem do paciente
3. Atendimento médico e registro em prontuário
4. Faturamento e cobrança (particular ou convênio)
5. Gestão de estoque de materiais e insumos
6. Geração de relatórios gerenciais

### Objetivos estratégicos
- Reduzir o tempo médio de espera do paciente
- Aumentar o número de pacientes atendidos por mês
- Digitalizar 100% dos prontuários
- Expandir o serviço de telemedicina
- Garantir conformidade total com a LGPD

---

## 2. Projeto de Software — Sistema Vida Plena (SVP)

Sistema de gestão clínica que cobre agendamento, prontuário eletrônico, faturamento e relatórios gerenciais.

### Dados que o sistema produz e utiliza
- **Cadastrais:** nome, CPF, RG, data de nascimento, endereço, telefone, e-mail
- **Clínicos:** histórico médico, diagnósticos (CID), prescrições, resultados de exames, alergias, evolução do paciente
- **Agendamento:** data/hora da consulta, médico responsável, especialidade, status (confirmado/cancelado/faltou)
- **Financeiros:** forma de pagamento, valores cobrados, convênio utilizado, notas fiscais
- **Operacionais/usuários do sistema:** login e perfil de acesso de médicos, recepcionistas e administradores; logs de acesso e alterações

### Quem utiliza esses dados
- Médicos e enfermeiros (dados clínicos)
- Recepcionistas/atendentes (agendamento e cadastro)
- Setor financeiro (dados de cobrança e convênio)
- Diretoria/coordenação (relatórios gerenciais)
- O próprio paciente, via portal (seus próprios dados)
- Auditoria interna e, parcialmente, operadoras de convênio (dados de faturamento)

### Onde os dados são armazenados
- Banco de dados relacional em nuvem (ex.: PostgreSQL), com servidores localizados no Brasil
- Backups automatizados periódicos (diários/semanais)
- Documentos digitalizados (exames, laudos) em repositório de arquivos vinculado ao prontuário

### Dados sensíveis
- **Dados de saúde:** diagnósticos, exames, histórico clínico e alergias — classificados como dado sensível pela LGPD (Art. 5º, II)
- **Dados de identificação:** CPF, RG
- **Dados financeiros:** forma de pagamento e informações de convênio

### Problemas relacionados aos dados
- Cadastros duplicados de pacientes
- Prontuários incompletos ou preenchidos de forma não padronizada
- Dados desatualizados (telefone, endereço)
- Dificuldade de integração entre o sistema da clínica e os sistemas dos convênios

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
