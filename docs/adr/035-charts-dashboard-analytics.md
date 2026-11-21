# ADR 035 — Dashboard de Gráficos (Analytics) com `fl_chart`

## Contexto
O app possuía tabelas contábeis (Fluxo de Caixa, Relatórios) e o Dashboard Geral (saldos imediatos), mas carecia de uma visão analítica interativa com KPIs modernos e dinâmica visual de gestão financeira pessoal.

## Decisão
- Novo módulo de menu **Gráficos** (`NavModule.charts`, posicionado logo após Relatórios; acessível também na paleta de comandos `Ctrl/Cmd + K`).
- Biblioteca **`fl_chart`** (compatível e testada em macOS, Windows, Web PWA, iOS e Android).
- Motor contábil puro e isolado em `lib/services/analytics_engine.dart` (somente leitura, centavos inteiros, conversão via `convertToBase`).
  - **Paridade 100% rigorosa com `buildMonthlyReport`**:
    - Alinhamento rigoroso com a competência contábil de `t.date` utilizada nos relatórios oficiais do OpenMoney.
    - Exclusão estrita de transferências entre contas (`t.xfer != null || t.peer != null`).
    - Exclusão estrita de categorias desmarcadas de relatórios (`!store.isCategoryIncludedInReports(t.cat)`).
    - Divisão de categorias de despesa via `kCategorySep` idêntica ao relatório.
  - **Filtro de Status de Conciliação**:
    - Suporte a `CashFlowStatusFilter`: **Todos os status**, **Apenas Conciliados** (`t.rec == true`) e **Apenas Não Conciliados** (`t.rec == false`), idêntico à tela de Relatórios e Fluxo de Caixa.
- **Reserva de Emergência (Runway):**
  - Considera **todo o patrimônio líquido consolidado do usuário** (`netWorthNow`), contemplando saldo de contas correntes, poupanças e investimentos, dividido pela despesa média mensal. Exemplo: R$ 200.000,00 de patrimônio e R$ 10.000,00 de despesa média mensal = 20 meses de reserva.
- **Filtros de Período Flexíveis:**
  - Opções: Mês (com seletor rápido `<` `>` para navegar entre qualquer mês), 3M, 6M, 12M, Ano atual, Ano anterior e **Todo período**.
  - No modo "Todo período", os gráficos de barras de fluxo de caixa ativam rolagem horizontal suave para permitir a visualização de dezenas de meses históricos sem perda de legibilidade.
- UI responsiva em `lib/ui/views/charts_dashboard_view.dart` e `lib/ui/views/charts/chart_widgets.dart`.
- Preferências de filtros persistidas no `config.json` via `setChartsPrefs`.
