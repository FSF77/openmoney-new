# ADR 016: Tela Consolidada de Lançamentos de Todas as Contas, Filtro Temporal e Resolução por Fatura

**Status:** ✅ Aprovado, Implementado e Validado  
**Data:** 09/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade:** 🟢 Evolução Arquitetural / Experiência do Usuário (Multiplataforma)  

---

## 1. Contexto e Motivação

Até a versão 2.3.0, a consulta detalhada de lançamentos no OpenMoney ocorria primordialmente de forma individualizada no extrato de cada conta (**Conta Corrente / Cartão de Crédito / Carteira**). Embora relatórios consolidados existissem nas visões de **Fluxo de Caixa** e **Relatórios por Categoria**, o usuário não dispunha de uma interface única para:
1. Auditar cronologicamente todos os lançamentos financeiros do ecossistema em um único painel.
2. Filtrar transações por granularidade diária imediata (foco padrão em **Hoje** / `todayISO()`), mensal ou anual.
3. Analisar lançamentos de cartão de crédito sob a ótica da **data da compra** (regime de competência da transação) ou sob a ótica da **data de pagamento da fatura** (regime de caixa/desembolso real).
4. Exportar relatórios consolidados em formatos abertos (**CSV** e **PDF** executivo A4).
5. Executar conciliações bancárias rápidas (`rec`), edições e exclusões diretamente da visão geral.

### O Pedido do Usuário
> *"com base na tela de lançamentos por conta, criar uma tela que eu possa visualizar todos os lançamentos de todas as contas, filtrar por mês como é hoje e ter um filtro também por dia, o padrão trazer o dia atual, ter os botões do abatimento de previsões, exportar CSV e PDF, como haverá lançamentos de cartão, criar filtro para trazer de acordo com a data do lançamento (filtro por mês) ou os lançamentos de acordo com a fatura (filtro por pagamento/fatura) no cabeçalho ter card com o total de despesa, de receita e o resultado, o acesso será feito pelo menu lateral, em planejamento como 'Lançamentos'"*
> 
> *Complementos aprovados:*
> - *"Incluir filtro por ano"*
> - *"agrupar cronologicamente por dia quando tiver no filtro mensal, no filtro anual agrupar por dia e depois por mês"*
> - *"quando eu selecionar o filtro Por Fatura / Pagamento, mostre os lançamentos no dia do pagamento da fatura e não a data do lançamento"*

---

## 2. Decisão de Arquitetura

Adotou-se uma implementação com **estrita paridade funcional** entre as plataformas nativas **Swift (macOS & iOS)** e o aplicativo multiplataforma **Flutter/Dart (macOS, Windows, Web e Mobile)**.

```
                             ┌──────────────────────────────────┐
                             │       Navegação do Sistema       │
                             │   Menu Lateral / Tab iOS:        │
                             │   PLANEJAMENTO > "Lançamentos"   │
                             └─────────────────┬────────────────┘
                                               │
                             ┌─────────────────▼────────────────┐
                             │   Motor de Dados Centralizado:   │
                             │   consolidatedTransactions(...)  │
                             └─────────────────┬────────────────┘
                                               │
                    ┌──────────────────────────┴──────────────────────────┐
                    ▼                                                     ▼
      Modo: "Por Data do Lançamento"                        Modo: "Por Fatura / Pagamento"
      ──────────────────────────────                        ──────────────────────────────
      • effectiveDate = tx.date                             • Se Cartão: effectiveDate = invDue
      • Compras de cartão no dia da compra                  • Compras de cartão no dia do pagamento
      • Faturas automáticas (auto=true) exibidas            • Faturas automáticas (auto=true) suprimidas
      • Exibição e agrupamento por tx.date                  • Exibição e agrupamento por invDue
```

---

## 3. Especificação das Regras de Negócio

### 3.1. Localização e Acesso
- **Flutter & Swift macOS:** Inclusão no menu lateral esquerdo sob a seção de agrupamento `PLANEJAMENTO`, identificado como **"Lançamentos"** com ícone `list.bullet.rectangle` / `format_list_bulleted`.
- **Swift iOS:** Tab dedicada **"Lançamentos"** no `TabView` principal.

### 3.2. Filtro Temporal (Dia, Mês, Ano)
1. **Filtro Diário (Padrão Inicial):**
   - Ao abrir a tela, o filtro inicial selecionado é sempre o dia atual (`todayISO()`).
   - Controles de navegação: botões retroceder (`<`) e avançar (`>`), atalho rápido para "Hoje" e seletor de calendário (datepicker nativo).
2. **Filtro Mensal:**
   - Navegação mês a mês (`<` / `>`) ou via seletor popup de mês e ano.
3. **Filtro Anual:**
   - Navegação ano a ano (`<` / `>`) ou seletor de ano fiscal.

### 3.3. Cards de KPI no Cabeçalho
No topo da tela, três cartões métricos calculam os totais consolidados em centavos inteiros sobre as transações filtradas:
- **Total de Receitas:** Soma de transações com `amt > 0` (excluindo transferências `xfer`, transações de contraparte `peer` e faturas automáticas `auto == true`).
- **Total de Despesas:** Soma de transações com `amt < 0` (mesmos critérios de exclusão).
- **Resultado Líquido:** `Receitas - Despesas`. Destaque visual em verde para superávit ($\ge 0$) e vermelho para déficit ($< 0$).

### 3.4. Regime de Cartão de Crédito e Resolução da Data Efetiva
Para lidar com a dualidade contábil de compras em cartão, foi implementado o alternador comutável com 1 clique:
1. **Por Data do Lançamento (`cardByInvoice == false`):**
   - A data considerada para filtro, exibição e ordenação é a data real da transação (`tx.date`).
2. **Por Fatura / Pagamento (`cardByInvoice == true`):**
   - Para contas do tipo cartão de crédito (`isCard == true`), a data considerada passa a ser o **dia do vencimento/pagamento da fatura** (`invDue`), calculado através de:
     $$\text{invDue} = \text{invoices}[\text{ik}]?\text{.due} \;\lor\; \text{invDates}(\text{cardCfg}, \text{ik})\text{.due}$$
   - **Regra de Exibição no Dia do Pagamento:** A transação do cartão tem sua data visual virtualizada como `effectiveDate = invDue`. Dessa forma:
     - Ela é exibida com a data do pagamento da fatura.
     - Ela é agrupada sob o cabeçalho do dia do pagamento da fatura.
     - No filtro diário, ela aparece quando o dia selecionado for o dia do pagamento da fatura.
     - No filtro mensal e anual, ela pertence à competência de pagamento da fatura.
   - **Prevenção de Duplicidade:** No modo por fatura, transações geradas automaticamente para liquidação de fatura (`tx.auto == true`) são suprimidas da listagem consolidada, pois o valor das despesas individuais já totaliza a fatura.
   - **Preservação de Integridade:** As ações de clique para edição (`showTransactionEditModal` / `editingTx`) e cópia recuperam a transação original do banco de dados (`store.db.txs.firstWhere(...)`), garantindo que a data real de compra gravada no `openmoney.json` jamais seja sobrescrita de forma inadvertida pela data de pagamento da fatura.

### 3.5. Agrupamentos Cronológicos
- **Visão Diária:** Apresenta diretamente os lançamentos do dia selecionado.
- **Visão Mensal:** Lançamentos ordenados cronologicamente e agrupados por **Dia**, exibindo no cabeçalho de cada dia a data formatada, o dia da semana e os subtotais de despesa, receita e resultado líquido do dia.
- **Visão Anual:** Agrupamento hierárquico em 2 níveis:
  1. Primeiro agrupado por **Mês**, com banner contendo o nome do mês e os totais acumulados de receitas, despesas e resultado.
  2. Dentro de cada mês, agrupado cronologicamente por **Dia**, com o respectivo subtotal diário.

### 3.6. Abatimento de Previsões e Exportações
- **Previsões:** Botão para disparar o cálculo de abatimento (`adjustPredictions`) com menu suspenso para alternar o modo (`predMode: "month" | "invoice"`).
- **Exportação CSV:** Geração de arquivo delimitado por ponto e vírgula contendo colunas de Data, Conta, Favorecido/Descrição, Categoria, Tipo, Valor, Status de Conciliação e ID.
- **Exportação PDF:** Relatório executivo formal gerado em layout A4 paisagem/retrato com cabeçalho corporativo, sumário dos KPIs, filtros vigentes, tabela paginada com zebrado e subtotalização automática.

---

## 4. Mapeamento de Código e Paridade Multi-Stack

| Plataforma / Arquivo | Responsabilidade |
| :--- | :--- |
| **Flutter:** `lib/store/money_store.dart` | Declaração do `NavModule.transactions` e método `consolidatedTransactions(...)` com virtualização de data efetiva e ordenação cronológica estável. |
| **Flutter:** `lib/ui/views/all_transactions_view.dart` | Tela completa com seletores Dia/Mês/Ano, cards KPI, filtro de cartão, filtro multicontas, busca textual diacrítico-insensível, agrupamentos diário/anual e modais de edição. |
| **Flutter:** `lib/services/pdf_report_generator.dart` | Gerador `buildConsolidatedTransactionsPdfBytes(...)` com paginação automática A4 e cabeçalho executivo. |
| **Flutter:** `lib/ui/app_shell.dart` | Roteamento do módulo e inserção no menu lateral sob `Planejamento`. |
| **Swift:** `Sources/OpenMoney/Store.swift` | Enum `SidebarView.transactions` e método de repositório `consolidatedTransactions(...)` com resolução de `effectiveDate`. |
| **Swift:** `Sources/OpenMoney/Views.swift` | View macOS `AllTransactionsView`, roteamento no `MainWindowView`, item no `SidebarPanel`, exportação CSV e renderizador PDF nativo via CoreGraphics / AppKit. |
| **Swift:** `Sources/OpenMoney/iOSViews.swift` | View iOS `iOSTransactionsTab`, integração na barra de abas e sheet adaptativa `CashFlowCommentEditorSheet`. |
| **Swift:** `Sources/OpenMoney/Models.swift` | Estruturas de dados compartilhadas entre macOS e iOS. |

---

## 5. Validação e Testes Automatizados

A conformidade contábil e estrutural foi verificada e validada em todas as stacks:
1. **Flutter Analysis:**
   - `flutter analyze`: **0 erros** nos arquivos implementados.
2. **Flutter Test Suite:**
   - `flutter test`: **60 de 60 testes unitários passaram** com sucesso (cobertura total de regras de faturas, isolamento de schemas e integridade).
3. **Swift macOS Build:**
   - `swift build`: Compilação nativa concluída com sucesso sem erros.
4. **Swift iOS Simulator Build:**
   - `xcodebuild -project OpenMoney.xcodeproj -scheme OpenMoney -sdk iphonesimulator ...`: **BUILD SUCCEEDED**.
