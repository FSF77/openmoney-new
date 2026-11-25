# Guia do Usuário: Gestão e Acompanhamento de Previsões Orçamentárias

Este guia mostra como usar a tela de **Previsões** no OpenMoney (**Desktop macOS/Windows**, **Web PWA** e **Mobile iOS/Android**) para reservar tetos mensais de gastos, acompanhar o consumo real por categoria e evitar surpresas no orçamento.

---

## 1. Passo a Passo Prático de Uso

### 1.1 Onde acessar
No menu lateral (ou gaveta no Mobile), dentro da seção **PLANEJAMENTO**, clique em **Previsões** (ícone de varinha mágica, logo acima de *Limite de Gastos*).

### 1.2 Criando uma Nova Previsão em 1 Clique
1. Clique no botão **+ Nova Previsão** no canto superior direito.
2. Preencha os campos do formulário:
   - **Conta**: escolha a conta bancária ou cartão de crédito onde a previsão será lançada.
   - **Data**: selecione a data de competência (`dd/mm/aaaa`).
   - **Categoria**: escolha a categoria ou subcategoria de despesa (listadas de forma hierárquica e indentada).
   - **Descrição**: digite apenas o complemento (ex.: `Mercado`, `Combustível`, `Farmácia`). O sistema mantém automaticamente o prefixo padrão **`Previsão`**.
   - **Valor do Teto**: informe o valor máximo planejado para o mês.
   - **Observações**: anotações opcionais.
   - **Tipo de Previsão**: escolha entre **Única** (apenas o mês selecionado) ou **Recorrente** (repete automaticamente nos meses seguintes conforme a frequência escolhida).
   - **Ajustar com gastos do mês imediatamente**: mantenha marcado se quiser que o sistema já abata os gastos existentes daquela categoria ao salvar.
3. Clique em **Salvar**.

### 1.3 Entendendo os 4 Indicadores (KPIs) do Topo
No topo da tela de **Previsões**, você acompanha a saúde do seu orçamento mensal por meio de 4 cards:

1. **Teto Previsto**:
   - Soma de todos os valores base planejados para o mês.
   - Exibe no subtítulo quantas previsões e categorias estão ativas no período.
2. **Gasto Real**:
   - Soma real e integral de **todas as despesas** lançadas nas categorias que possuem previsão no mês (sem travar ou ocultar valores que ultrapassaram o teto).
   - Exibe no subtítulo o percentual já consumido do teto global previsto (ex.: `92% do teto previsto`).
3. **Estouro**:
   - Soma exata apenas do valor que **ultrapassou** o teto nas categorias estouradas.
   - Fica em **vermelho** quando há estouro (ex.: `2 cats. estouradas`) ou em **verde** (`Dentro dos tetos`) quando nenhuma categoria excedeu o planejado.
4. **Saldo**:
   - É o **Saldo Líquido Global** do orçamento (`Teto Previsto − Gasto Real`), mostrando quanto dinheiro real ainda resta antes de estourar o orçamento total do mês.
   - Quando houver estouro em alguma categoria, o subtítulo exibe **`Nos tetos: ...`**, informando quanto ainda existe disponível somando apenas as categorias que não estouraram.

### 1.4 Acompanhando por Categoria e Ajustando em 1 Clique
- **Barra de Progresso**:
  - 🟢 **Verde**: consumo saudável (< 70% do teto).
  - 🟡 **Amarelo**: atenção (entre 70% e 99% do teto).
  - 🔴 **Vermelho**: teto atingido ou ultrapassado (≥ 100%).
- **Botão "Ajustar"**: no cabeçalho (ou no botão de abatimento do extrato de contas), recalcula e abate os gastos reais sobre os tetos das previsões.
  - **Considera Sempre o Mês Atual Real**: por padrão, o abatimento inicia sempre a partir do **mês atual real do calendário** (e não do mês selecionado na tela), avaliando a quantidade de meses definida em *Ajustes & Personalização* (`predMonths`, padrão: 3 meses).
  - **Confirmação para Meses Futuros Além do Horizonte**: caso o mês selecionado na tela seja maior que o horizonte configurável (`predMonths`) a partir do mês atual, o OpenMoney pergunta se você deseja considerar o abatimento **a partir do mês atual** ou **a partir do mês selecionado**.
  - Se uma previsão atingir o teto, ela fica zerada (`0,00`) com o badge **ESGOTADA** — **nunca é excluída**, preservando o histórico para conferência.
- **Restaurar Teto (🔄)** e **Editar (✏️)**: em cada previsão dentro do card da categoria, você pode editar o lançamento ou restaurar o valor atual para a base original com 1 clique.
- **Ver lançamentos que abateram este teto**: clique na linha expansível abaixo da previsão para ver cada despesa real da categoria (`dd/mm/aaaa`, favorecido, `• observação` e valor).
- **Analisar IA** *(quando o Assistente de IA estiver habilitado)*: abre uma análise detalhada das suas previsões e aumentos de categoria no mês.

---

## 2. Caso Prático do Dia a Dia

Imagine que você planejou **R$ 5.000,00** distribuídos em 7 previsões no mês, e durante o mês realizou os seguintes gastos:

| Categoria | Base Planejada | Gasto Real | Saldo no Teto | Estouro |
| :--- | ---: | ---: | ---: | ---: |
| Alimentação › Almoço | 200,00 | 143,45 | 56,55 | 0,00 |
| Alimentação › Bares e Restaurantes | 400,00 | 946,82 | 0,00 *(Esgotada)* | **546,82** |
| Alimentação › Mercado | 3.000,00 | 2.397,79 | 602,21 | 0,00 |
| Cuidados Pessoais | 150,00 | 27,98 | 122,02 | 0,00 |
| Farmácia | 150,00 | 463,05 | 0,00 *(Esgotada)* | **313,05** |
| Transporte › Combustível | 800,00 | 369,35 | 430,65 | 0,00 |
| Transporte › Metro, Ônibus e Taxi | 300,00 | 263,88 | 36,12 | 0,00 |
| **Totais** | **5.000,00** | **4.612,32** | **1.247,55** | **859,87** |

Nos **4 KPIs do topo**, você enxergará instantaneamente:
- **Teto Previsto**: `5.000,00` (`7 previsões (7 cats.)`)
- **Gasto Real**: `4.612,32` (`92% do teto previsto`)
- **Estouro**: `859,87` (`2 cats. estouradas`)
- **Saldo**: `387,68` (`Nos tetos: 1.247,55`)

Assim fica claro que, embora ainda existam `1.247,55` livres nos tetos de Mercado, Combustível, Almoço, etc., você já estourou `859,87` em Bares e Farmácia — portanto, seu **saldo real global** antes de ultrapassar os `5.000,00` do mês é **`387,68`**.

---

## 3. Dúvidas Comuns (FAQ) e Controle de Segurança

- **Por que o "Saldo" no card superior pode ser menor que a soma dos saldos das categorias?**
  Porque o card **Saldo** reflete o orçamento global (`Teto Previsto − Gasto Real`). Se você estourou uma categoria (ex.: gastou R$ 946,82 em um teto de R$ 400,00), esse excesso consome parte da folga global. O subtítulo `Nos tetos: ...` continua mostrando exatamente quanto falta para esgotar as categorias que ainda têm saldo.
- **Por que uma previsão esgotada fica com valor R$ 0,00 em vez de ser apagada?**
  Para que você não perca o controle nem o histórico do que foi planejado. Mantendo o lançamento zerado com o badge **ESGOTADA**, o sistema continua listando os gastos daquela categoria e permite restaurar a base original com 1 clique.
- **A previsão em cartão de crédito muda de mês conforme a fatura?**
  Não. A previsão sempre pertence ao mês da sua **data de lançamento** (`tx.date`). O que muda conforme o modo escolhido no botão de engrenagem/filtro (`Por Mês` vs. `Por Fatura do Cartão`) é quais gastos reais abatem aquela previsão.
- **Os dados das previsões ficam salvos com segurança?**
  Sim. Cada previsão é uma transação padrão com prefixo `Previsão` e tag `[Previsão base: ...]` no campo de notas, compatível com o backup automático local em `.zip`, Sync v2 na nuvem e proteção Anti-Wipe.

---

## 4. Detalhamento Técnico e Arquitetura (Desenvolvedores)

### 4.1 Identificação e Preservação da Base
- **Prefixo obrigatório**: `isPredictionPayee(payee)` verifica o prefixo normalizado `"previsao"`.
- **Tag de base no `memo`**: `[Previsão base: R$ X,XX]` gravada por `memoWithBaseTag(memo, baseCents)` e lida por `parseBaseFromMemo(memo)`. Isso garante recálculo determinístico sem dedução duplicada ao acionar `adjustPredictions`.

### 4.2 Modos de Apuração (`predMode`) e Horizonte (`predMonths`)
- **`predMode == "month"` (Padrão)**: filtra despesas reais da categoria pela data do lançamento (`t.date.startsWith(targetMonth)`).
- **`predMode == "invoice"` (Por Fatura de Cartão)**: despesas em contas bancárias entram pela data do lançamento, enquanto compras em cartão de crédito entram pela competência de vencimento da fatura (`(t.ik ?? invKeyFor(cardCfg, t.date)) == targetMonth`).
- **`predMonths` e Resolução do Mês Inicial**: configurável em *Ajustes & Personalização* (1, 2, 3 [padrão], 6 ou 12 meses), define quantas competências consecutivas são ajustadas por `adjustPredictions`. O disparo na interface (`runPredictionsAdjustmentWithPrompt`) inicia sempre pelo mês atual real (`realCurrentMonthYM`), exceto quando o mês selecionado ultrapassa a janela `predMonths` (`isSelectedMonthBeyondPredictionsHorizon`), ocasião em que exibe diálogo para o usuário escolher entre iniciar pelo mês atual ou pelo mês selecionado.

### 4.3 Estruturas e Arquivos no Flutter (`lib/`)
- **`lib/models/prediction_models.dart`**:
  - `PredictionItemDetail`: item individual com `baseCents`, `currentCents`, `deductedCents`, `isExhausted`.
  - `PredictionCategoryGroup`: agrupamento por categoria com `totalBaseCents`, `totalSpentCents`, `remainingCents`, `overrunCents`, `isOverrun`, `percentSpent`, `predictions` e `spentTransactions`.
  - `PredictionsSummaryReport`: consolidação mensal com `totalPlannedBaseCents`, `totalSpentCents`, `totalOverrunCents`, `overrunCategoriesCount`, `totalRemainingCents` (soma nos tetos) e `globalRemainingCents` (`totalPlannedBaseCents - totalSpentCents`).
- **`lib/store/money_store.dart`**: métodos `getPredictionsReport(targetMonth)`, `adjustPredictions(targetMonth)` e `restorePredictionBase(txId)`.
- **`lib/ui/views/predictions_management_view.dart`**: tela responsiva para Desktop, Web e Mobile com `KpiMetricCard`, `Wrap` e `LayoutBuilder`.
