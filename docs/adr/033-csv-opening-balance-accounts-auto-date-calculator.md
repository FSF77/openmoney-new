# ADR 033: Exportação de Saldo Inicial, Importação/Exportação CSV de Contas, Máscara Automática de Data e Calculadora de Valores

## Contexto e Motivação
A evolução contínua da experiência de uso do **OpenMoney Flutter** demandou 6 aprimoramentos nos fluxos de importação/exportação, visualização no Dashboard e digitação rápida de dados:

1. **Saldo Inicial no CSV de Lançamentos:** Ao exportar o extrato em CSV, a primeira linha de cada conta não registrava o saldo inicial (`acc.opening`), dificultando conferências externas em planilhas ou migrações.
2. **Exportação e Importação de Contas em CSV:** Havia exportação e importação de lançamentos e categorias, mas não de contas bancárias e cartões com todos os seus atributos cadastrais (instituição, saldo inicial, moeda, agência, conta, datas de fatura, atalhos, etc.).
3. **Dashboard — Remoção de Cabeçalhos de Contas:** Os textos `"CONTAS FAVORITAS ★"` e `"DEMAIS CONTAS ATIVAS"` ocupavam espaço visual desnecessário no card de Contas, devendo ser removidos preservando a ordenação das contas (favoritas primeiro, seguidas pelas demais ativas).
4. **Dashboard — Formato de Data Compacto em Faturas (`dd/mm/aa`):** O card de faturas exibia datas de fechamento e vencimento com o ano completo (`dd/mm/aaaa`), ocupando espaço horizontal em resoluções menores.
5. **Máscara Automática de Barra (`/`) em Campos de Data:** Usuários digitavam números contínuos (ex: `15112026`) ou precisavam digitar a barra manualmente, gerando lentidão e atrito na inserção de datas.
6. **Calculadora e Avaliação Matemática em Campos de Valor:** Usuários frequentemente precisam somar, subtrair, multiplicar ou dividir parcelas e despesas (ex.: `10 + 10` ou `50 / 2`).

## Decisões Arquiteturais e Implementação

### 1. Saldo Inicial no CSV (`CSVExporter.generateCSV`)
- Quando a conta possuir `acc.opening != 0` (seja positivo ou negativo), é gerado um lançamento sintético de saldo inicial:
  - `date`: `startDate ?? (filtered.isNotEmpty ? filtered.first.date : todayISO())`.
  - `payee`: `"SALDO INICIAL"`.
  - `cat`: `""` (vazia conforme especificação).
  - `amt`: `acc.opening`.
  - `rec`: `true` (`"Sim"`).
  - `createdAt`: `-9999999999.0` para garantir ordenação anterior a todos os lançamentos normais da mesma data.
- Suporta tanto exportação filtrada por conta quanto exportação consolidada de todas as contas.

### 2. Exportação e Importação de Contas (`AccountCSVExporter` & `AccountCSVImporter`)
- **Colunas:** `"ID";"Nome";"Tipo";"Saldo Inicial";"Moeda";"Favorita";"Inativa";"Entidade";"Código Banco";"Agência";"Número Conta";"Observações";"Saldo Mínimo";"Logo";"Dia Fechamento";"Dia Vencimento";"Conta Pagamento Fatura";"Atalhos Carteira"`.
- **Parsing resiliente:** Delimitador automático (`;` ou `,`), cabeçalhos flexíveis sem distinção de acentos ou maiúsculas/minúsculas.
- **Atualização inteligente:** Contas existentes (pelo `id` ou `name`) são atualizadas mantendo faturas e metadados; novas contas recebem IDs atômicos via `uid()`.
- **UI:** Integrado no modal `CsvQifCenterModal` abaixo das categorias nas abas **Importar** e **Exportar**, com métodos `store.importAccountsCSVBytes` e `store.exportAccountsCSVString`.

### 3. Dashboard — Limpeza de Cabeçalhos no Card de Contas
- Removidos os widgets de texto `"CONTAS FAVORITAS ★"` e `"DEMAIS CONTAS ATIVAS"` em `DashboardOverviewView`.
- A ordenação estrita é mantida: `favAccounts` renderizadas primeiro, seguidas por `regActive`.

### 4. Formato de Data Compacto em Faturas (`fmtDateShortYear`)
- Adicionada a função auxiliar `fmtDateShortYear(String iso)` em `openmoney_models.dart`, convertendo datas `yyyy-mm-dd` para `dd/mm/aa` (ex.: `10/11/26`).
- Atualizada a linha do ciclo de fatura no card de cartões do Dashboard para usar `fmtDateShortYear`.

### 5. Formatador de Entrada de Data (`DateInputFormatter`)
- Criado `lib/ui/widgets/date_input_formatter.dart` herdando de `TextInputFormatter`:
  - Insere automaticamente `/` após 2 dígitos do dia e após 4 dígitos (dia e mês).
  - Trata backspace/delete com suavidade sem travar ou recolocar a barra.
  - Formata colagem de 8 dígitos (`ddmmyyyy`) instantaneamente para `dd/mm/aaaa`.
  - Aplicado a todas as telas de inserção/edição: `transaction_modal.dart`, `account_ledger_view.dart`, `receipt_ocr_import_modal.dart` e `wallet_import_modal.dart`.

### 6. Avaliação Matemática e Mini Calculadora (`MathExpressionEvaluator` & `MiniCalculatorDialog`)
- **Avaliador de Expressões:** `MathExpressionEvaluator` processa operadores `+`, `-`, `*`/`x`/`X`, `/`/`÷` respeitando precedência aritmética e números decimais com vírgula (`10,50`) ou ponto (`10.50`).
- **Avaliação Automática:** Ao pressionar **Enter** (`onSubmitted`) ou mudar de campo (perda de foco via `FocusNode.addListener`), expressões como `10 + 10` são automaticamente avaliadas e substituídas pelo valor formatado em centavos (ex: `20,00`).
- **Mini Calculadora Integrada:** Ícone de calculadora (`Icons.calculate_outlined`) no campo de valor abre o modal interativo `showMiniCalculatorDialog` com teclado numérico, operadores, preview em tempo real e botão "Aplicar Valor".

## Status
Aprovado e implementado integralmente. 100% dos testes unitários e de integração aprovados (112 testes passando).
