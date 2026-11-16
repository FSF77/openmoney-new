# ADR 020: Tela Dedicada de Gestão de Previsões e Retenção de Previsões Esgotadas com Saldo Zerado

**Status:** ✅ Aprovado, Implementado e Validado  
**Data:** 12/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade:** 🟢 Evolução Arquitetural / Usabilidade e Controle Contábil  

---

## 1. Contexto e Motivação

Até a versão 2.4.3, o conceito de previsões orçamentárias no OpenMoney baseava-se em lançamentos com prefixo `Previsão` acionados exclusivamente via botão pontual *"Ajustar Previsões"* em telas de conta ou lançamentos.

Duas limitações críticas foram identificadas:
1. **Ausência de Painel Centralizado de Controle**: O usuário não possuía uma visão consolidada de quais previsões estavam vigentes no mês e no ano, quanto do orçamento havia sido abatido por categoria e quais transações específicas consumiram o saldo.
2. **Exclusão de Previsões Esgotadas**: Quando as despesas reais superavam o teto planejado ($Base - Gastos \le 0$), a rotina anterior de ajuste excluía permanentemente a transação (`db.txs.removeAll { idsToDelete.contains($0.id) }`). Com isso, perdia-se o histórico do que fora orçado para a categoria, impedindo a visualização analítica até o encerramento do mês.

---

## 2. Decisões de Arquitetura

### 2.1. Retenção de Previsão Zerada (Substituição da Exclusão)
A regra de negócio do motor de ajuste (`adjustPredictions`) foi reformulada em ambas as stacks (**Swift** e **Flutter**):
- Quando o teto for atingido ou superado, a transação **não é mais excluída**.
- O valor da transação é atualizado para **R$ 0,00** (`db.txs[idx].amt = 0`), mantendo a base original gravada no memo: `[Previsão base: R$ X,XX]`.
- No painel visual, a previsão recebe a marcação **ESGOTADA** e permanece auditável.
- É fornecida a ação de **Restaurar Teto Base** (`restorePredictionBase`), permitindo ao usuário reverter o lançamento para a base inicial a qualquer momento.

### 2.2. Nova Tela de Gestão de Previsões (`PredictionsManagementView`)
Criada como módulo nativo sob a seção **PLANEJAMENTO** do menu principal (localizada acima de *Limite de Gastos*), com paridade estrita:
- **Swift macOS / iOS**: `Sources/OpenMoney/PredictionsManagementView.swift` e `PredictionModels.swift`.
- **Flutter Desktop / Web / Mobile**: `lib/ui/views/predictions_management_view.dart` e `prediction_models.dart`.

### 2.3. Agrupamento Analítico e Drill-Down
A tela calcula e exibe em tempo real:
- **Cards de KPIs**: Teto Previsto, Total Abatido, Saldo Remanescente e Total de Previsões.
- **Progresso Visual por Categoria**: Barras coloridas por percentual de consumo (< 70% verde, 70-90% amarelo, ≥ 100% vermelho).
- **Drill-down de Lançamentos Abatidos**: Expansão com data formatada `dd/mm/aaaa`, favorecido, observação e valor de cada despesa real da categoria no período.
- **Formulário de Nova Previsão**: Modal de 580px com seleção hierárquica de categorias e subcategorias indentadas (`   ↳ Subcategoria`), campo de data e prompt descritivo padronizado.

---

## 3. Estruturas de Dados (`PredictionModels`)

```swift
public struct PredictionItemDetail: Identifiable {
    public let tx: Transaction
    public let accountName: String
    public let accountCurrency: String
    public let baseCents: Int
    public let currentCents: Int
    public let deductedCents: Int
    public let isExhausted: Bool
}

public struct PredictionCategoryGroup: Identifiable {
    public let category: String
    public let totalBaseCents: Int
    public let totalCurrentCents: Int
    public let totalSpentCents: Int
    public let totalDeductedCents: Int
    public let remainingCents: Int
    public let percentSpent: Double
    public let predictions: [PredictionItemDetail]
    public let spentTransactions: [Transaction]
}

public struct PredictionsSummaryReport {
    public let periodLabel: String
    public let totalPlannedBaseCents: Int
    public let totalCurrentCents: Int
    public let totalSpentCents: Int
    public let totalDeductedCents: Int
    public let totalRemainingCents: Int
    public let groups: [PredictionCategoryGroup]
    public let allPredictions: [PredictionItemDetail]
}
```

---

## 4. Validação

- **Swift macOS / iOS**: Compilação e assinatura com `./build-app.sh` (Build 169) concluída com 100% de sucesso.
- **Flutter macOS / Windows / Web / Mobile**: `flutter analyze` validado com 0 erros de compilação.
