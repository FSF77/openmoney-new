# ADR 003: Estratégia e Implementação da Vigência de Fatura (`isVigenteInvoice`)

**Status:** ✅ Aprovado, Implementado e Validado  
**Data do Contexto:** 31/10/2026  
**Data de Conclusão:** 31/10/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade Inicial:** 🔴 Crítica (Divergência eliminada)  

---

## 1. Problema Original

Durante a auditoria técnica, identificou-se que o cliente **Flutter** não possuía a implementação da função [`isVigenteInvoice`](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/Models.swift#L851), que existia no cliente **Swift**.

### Impacto do Problema Antes do Ajuste:
- O Flutter utilizava uma comparação simplória de chaves de texto (`invoiceKey == currentOpenKey`), desconsiderando a janela entre o dia de fechamento e o dia de vencimento da fatura.
- **Dívidas Fantasmas:** Faturas que já haviam fechado, mas cujo vencimento ainda não havia chegado (estando em período regular de pagamento), eram classificadas erroneamente como "vencidas" ou pendentes em listas de "Contas a Pagar".
- **Distorção no Fluxo de Caixa:** O cálculo de saldo previsto e contas em aberto apresentava discrepâncias graves entre o app macOS/iOS (Swift) e o app Flutter (Desktop/Web).

---

## 2. Conceito de "Fatura Vigente" (Regra de Ouro)

No OpenMoney, uma fatura de cartão de crédito é considerada **vigente** se atender a qualquer uma das duas condições temporais:

1. **Fatura do Ciclo Aberto:** É a fatura do ciclo atual onde novos lançamentos de compras com cartão estão sendo debitados no momento presente.
2. **Fatura em Janela de Pagamento (Fechada, mas não vencida):** A fatura já fechou no dia de corte (`closeDate <= today`), mas o dia de vencimento ainda não expirou (`dueDate >= today`). O usuário está dentro do prazo regular para pagar sem que a fatura seja considerada atrasada.

Uma fatura só deixa de ser vigente e passa a ser tratada como **atrasada/vencida** quando a data atual ultrapassa a data de vencimento (`today > dueDate`) e o saldo devedor ainda não foi quitado.

---

## 3. Implementação Canônica em Swift (Fonte da Verdade)

```swift
// OpenMoneySwift/Sources/OpenMoney/Models.swift (L851-L868)
public func isVigenteInvoice(
    cardCfg: CardConfig, 
    invoiceKey: String, 
    account: Account? = nil, 
    today: String = todayISO()
) -> Bool {
    let currentOpenKey = invKeyFor(cardCfg, date: today)
    
    // 1. É a fatura atualmente em aberto para a data de hoje?
    if invoiceKey == currentOpenKey {
        return true
    }
    
    // Obtém as datas efetivas (customizadas da conta ou calculadas pela regra do cartão)
    let dueDate = account?.invoices?[invoiceKey]?.due ?? invDates(cardCfg, key: invoiceKey).due
    let closeDate = account?.invoices?[invoiceKey]?.close ?? invDates(cardCfg, key: invoiceKey).close
    
    // 2. Fatura já fechou, mas o vencimento ainda não passou?
    if closeDate <= today && dueDate >= today {
        return true
    }
    
    return false
}
```

---

## 4. Implementação Replicada no Flutter

A função foi introduzida no Flutter com fidelidade matemática e conceitual absoluta:

```dart
// OpenMoneyFlutter/lib/models/openmoney_models.dart (L442-L457)
bool isVigenteInvoice(
  CardConfig cardCfg,
  String invoiceKey, {
  Account? account,
  String? today,
}) {
  final todayStr = today ?? todayISO();
  final currentOpenKey = invKeyFor(cardCfg, todayStr);

  // Condição 1: É a fatura em aberto do ciclo atual
  if (invoiceKey == currentOpenKey) {
    return true;
  }

  // Obtém datas de fechamento e vencimento
  final customInv = account?.invoices?[invoiceKey];
  final dates = invDates(cardCfg, invoiceKey);
  final dueDate = customInv?.due ?? dates.due;
  final closeDate = customInv?.close ?? dates.close;

  // Condição 2: Fatura fechada recentemente dentro do prazo de vencimento
  if (closeDate.compareTo(todayStr) <= 0 && dueDate.compareTo(todayStr) >= 0) {
    return true;
  }

  return false;
}
```

Além disso, todas as chamadas em [`dueBillItems`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/store/money_store.dart) e rotinas de contas a pagar foram atualizadas para utilizar `isVigenteInvoice`.

---

## 5. Validação e Testes Automatizados

A correção foi coberta por testes unitários dedicados em [`test/parity_audit_fixes_test.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/test/parity_audit_fixes_test.dart):

- Teste de ciclo em aberto: retorno `true`.
- Teste de fatura fechada antes do vencimento (janela de pagamento): retorno `true`.
- Teste de fatura após o vencimento: retorno `false` (classificada como vencida).
- Teste com faturas com datas personalizadas em `account.invoices`: validado com sucesso.
- **Resultado:** 100% de paridade validada contra o comportamento do Swift.
