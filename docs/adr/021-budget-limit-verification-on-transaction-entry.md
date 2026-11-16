# ADR 021: Verificação Ativa de Limite de Gastos (Budget Excess Warning) na Inserção de Lançamentos

**Status:** ✅ Aprovado, Implementado e Validado  
**Data:** 12/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade:** 🟢 Funcionalidade de Controle Financeiro & Governança Orçamentária  

---

## 1. Contexto e Motivação

Até esta versão, os limites de gastos mensais configurados na tela **Limite de Gastos** (`db.budgets`) eram utilizados de forma analítica e passiva, sendo consultados apenas quando o usuário navegava até a respectiva tela de limites ou relatórios.

Para prevenir estouros de orçamento no momento da tomada de decisão e registro, solicitou-se que o sistema valide preventivamente o teto orçamentário ao registrar despesas, calculando o consumo mensal acumulado e alertando caso o novo lançamento ultrapasse o limite disponível, com opção de cancelar ou prosseguir.

---

## 2. Decisões de Arquitetura

### 2.1. Regras de Disparo e Escopo
A verificação é acionada **no momento da gravação** da transação nos seguintes pontos de entrada do ecossistema:
1. **Modal de Novo Lançamento**: `TransactionCreateSheet` (Swift macOS), `_TransactionCreateDialog` (Flutter), `iOSNewTransactionSheet` (Swift iOS).
2. **Modal de Duplicar Lançamento**: `TransactionCopySheet` (Swift macOS), `_TransactionDuplicateDialog` (Flutter).
3. **Linha de Inserção Rápida (Quick Entry)**: `AccountDetailView` (Swift macOS) e `_AccountLedgerViewState` (Flutter).

### 2.2. Critérios de Exclusão e Filtragem
- **Apenas Despesas Reais (`signedAmt < 0`)**: Lançamentos de receita (`signedAmt > 0`), valores zerados e transferências entre contas (`xfer != null`, `isXfer` ou `catSelection.startsWith("xfer:")`) são ignorados pela verificação de limite.
- **Exclusão Estrita de Previsões (`isPredictionPayee`)**: Lançamentos de previsão orçamentária (com favorecido iniciando por "Previsão", indiferente a maiúsculas e acentos) **não entram na soma de gastos** acumulados do mês e também não disparam aviso de limite caso uma nova previsão seja cadastrada.
- **Competência Mensal**: Avalia-se o mês da data do lançamento (`String(date.prefix(7))`, e.g., `2026-11`).
- **Lançamentos Considerados**: Soma apenas despesas reais realizadas do mês da mesma categoria (`t.amt < 0 && t.xfer == nil && t.peer == nil && t.auto != true && !isPredictionPayee(t.payee) && store.isCategoryIncludedInReports(t.cat)`).
- **Consolidação em Moeda Base**: As despesas existentes e o novo lançamento são devidamente convertidos para a moeda base do sistema (`store.baseCurrency`), garantindo compatibilidade multi-moeda exata com os tetos orçados.
- **Parcelamento (`mode == "installment"`)**: Quando a despesa for parcelada, apenas o impacto da primeira parcela no mês corrente (`parts[0]`) é comparado contra o saldo orçamentário do período.

### 2.3. Hierarquia de Categorias (Herança de Teto)
1. **Teto Direto da Categoria / Subcategoria**: Se a categoria utilizada tiver limite próprio configurado em `db.budgets[cat] > 0`, este limite prevalece.
2. **Herança do Teto da Categoria Pai**: Se for uma subcategoria (e.g. `Alimentação › Restaurante`) e não tiver limite individual, mas a categoria pai (`Alimentação`) possuir `db.budgets[parent] > 0`, a validação utiliza o teto da categoria pai, somando todas as despesas da família (`parent` e quaisquer de suas subcategorias).
3. **Sem Limite Definido**: Se nem a categoria nem seu pai tiverem limite maior que zero, nenhuma validação é necessária e a gravação prossegue normalmente.

### 2.4. Condição de Alerta e Interação do Usuário
- **Condição de Alerta**: O alerta é disparado sempre que:
  $$\text{currentSpentCents} + \text{newAmountCents} > \text{budgetCents}$$
- **Informações Exibidas no Diálogo**:
  - Nome da Categoria avaliada.
  - Mês de competência formatado (e.g., `Novembro de 2026`).
  - Limite definido.
  - Gasto atual acumulado no mês.
  - Saldo disponível antes do lançamento ($\max(0, \text{Limite} - \text{Gasto Atual})$).
  - Valor do novo lançamento.
  - Valor excedente projetado ($\text{Gasto Projetado} - \text{Limite}$).
- **Ações Disponíveis**:
  - **Cancelar**: Aborta a gravação imediata, mantendo a tela ou formulário aberto com todos os dados preenchidos para que o usuário possa reajustar o valor, trocar a categoria ou desistir.
  - **Continuar**: Confirma a exceção orçamentária e efetua a inclusão normal da transação.

---

## 3. Modelo de Dados e Paridade Multi-Stack

### 3.1. Swift (`BudgetCheckResult` em `Models.swift` e `Store.swift`)
```swift
public struct BudgetCheckResult: Identifiable, Equatable {
    public var id: String { "\(categoryPath)_\(month)" }
    public let categoryPath: String
    public let budgetCents: Int
    public let currentSpentCents: Int
    public let newAmountCents: Int
    public let currency: String
    public let month: String

    public var availableBeforeCents: Int { max(0, budgetCents - currentSpentCents) }
    public var totalProjectedCents: Int { currentSpentCents + newAmountCents }
    public var excessCents: Int { max(0, totalProjectedCents - budgetCents) }
    public var monthLabel: String { fmtMonth(month) }
}
```

Método de verificação em `MoneyStore`:
```swift
public func checkBudgetExceeded(
    accId: String,
    date: String,
    catSelection: String,
    signedAmt: Int,
    mode: String = "single",
    installments: Int = 1,
    txRate: Double? = nil
) -> BudgetCheckResult?
```

### 3.2. Flutter (`BudgetCheckResult` em `openmoney_models.dart` e `money_store.dart`)
```dart
class BudgetCheckResult {
  final String categoryPath;
  final int budgetCents;
  final int currentSpentCents;
  final int newAmountCents;
  final String currency;
  final String month;

  int get availableBeforeCents => (budgetCents - currentSpentCents) > 0 ? (budgetCents - currentSpentCents) : 0;
  int get totalProjectedCents => currentSpentCents + newAmountCents;
  int get excessCents => (totalProjectedCents - budgetCents) > 0 ? (totalProjectedCents - budgetCents) : 0;
  String get monthLabel => fmtMonth(month);
}
```

Método de verificação em `MoneyStore`:
```dart
BudgetCheckResult? checkBudgetExceeded({
  required String accId,
  required String date,
  required String catSelection,
  required int signedAmt,
  String mode = 'single',
  int installments = 1,
  double? txRate,
});
```

---

## 4. Testes e Validação de Conformidade

1. **Testes Unitários Automatizados no Flutter (`test/budget_check_test.dart`)**:
   - Validação de retorno `null` para categorias sem limite orçado.
   - Validação de retorno `null` para receitas e transferências cross-account.
   - Validação de retorno `null` para despesas estritamente dentro do limite.
   - Cálculo exato de excedente, gasto atual e saldo remanescente quando ultrapassado.
   - Herança de limite da categoria pai quando subcategoria não tem teto próprio.
   - Prevalência do teto da subcategoria quando esta possui limite configurado.
   - Validação proporcional do impacto da parcela mensal em compras parceladas (`mode == "installment"`).
2. **Build e Compilação Nativa Swift**:
   - `swift build` executado com 0 erros no macOS e iOS.
