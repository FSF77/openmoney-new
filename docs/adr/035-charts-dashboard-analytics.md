# ADR 035 — Dashboard de Gráficos (Analytics) com `fl_chart`

## Contexto
O app tinha tabelas (Fluxo de Caixa, Relatórios) e o Dashboard Geral (saldos), mas nenhuma visão analítica interativa com KPIs de gestão financeira pessoal.

## Decisão
- Novo módulo de menu **Gráficos** (`NavModule.charts`, logo após Relatórios; também na paleta de comandos).
- Biblioteca **`fl_chart`** (multiplataforma: macOS, Windows, Web, iOS, Android).
- Cálculo isolado e puro em `lib/services/analytics_engine.dart` (somente leitura, centavos inteiros, conversão via `convertToBase`). Não grava no `openmoney.json` nem interfere no Sync v2/Anti-Wipe.
- UI em `lib/ui/views/charts_dashboard_view.dart` e `lib/ui/views/charts/chart_widgets.dart`.
- Preferências (período, contas, transferências, metas) em `chartsPrefs` na config local (`setChartsPrefs`).

## KPIs e fórmulas
| KPI | Fórmula |
|---|---|
| Patrimônio líquido | saldo de contas ativas (+ cartões negativos) em moeda base; série mensal acumulada |
| Receitas / Despesas / Resultado | competência efetiva (fatura para cartão), sem transferências por padrão, comparação com período anterior de mesmo tamanho |
| Taxa de poupança | (receita − despesa) / receita; meta padrão 20% |
| Gasto médio diário e projeção | despesa do mês final / dias decorridos × dias do mês |
| Reserva (runway) | saldo líquido (exceto cartão e investimento) / média de despesas dos últimos 3 meses; meta padrão 6 meses |
| Comprometimento fixo | despesas recorrentes e parceladas / receita |
| Orçado × realizado | `db.budgets` vs. gasto da categoria no mês final |
| Previsão 90 dias | patrimônio de hoje + lançamentos futuros já cadastrados |
| Score de saúde (0–100) | poupança 30 + reserva 25 + comprometimento 15 + orçamento 15 + tendência 15 |

## Interatividade
Filtros de período (Mês, 3M, 6M, 12M, ano atual, ano anterior), contas, transferências; toque numa categoria do donut filtra o painel inteiro; tooltips; metas configuráveis.

## Consequências
Nova dependência (`fl_chart`). Uso de cartão vs. limite não foi incluído porque `CardConfig` não possui limite de crédito.
