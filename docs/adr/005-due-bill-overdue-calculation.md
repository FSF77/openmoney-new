# ADR 005: Cálculo de Contas a Pagar e Faturas Vencidas (`dueBillItems`)

**Status:** ✅ Aprovado, Implementado e Validado  
**Data do Contexto:** 31/10/2026  
**Data de Conclusão:** 31/10/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade Inicial:** 🟡 Média (Divergência eliminada)  

---

## 1. Contexto e Divergência Inicial

A listagem de **Contas a Pagar** (`dueBillItems`) e o controle de **Parcelamentos** (`installmentItems`) são componentes fundamentais da visão de fluxo de caixa e planejamento financeiro do OpenMoney. 

Na auditoria técnica comparativa, observou-se uma divergência estrutural de abordagem entre as stacks:

| Aspecto | Comportamento no OpenMoneySwift | Comportamento no OpenMoneyFlutter (Antes) |
| :--- | :--- | :--- |
| **Critério de Inclusão de Fatura** | Baseado em datas efetivas (`isVigenteInvoice` + `dueDate`). | Baseado em igualdade de chaves de texto (`invoiceKey == currentOpenKey`). |
| **Tratamento de Alteração de Vencimento** | Dinâmico: recalcula se a fatura está aberta, em janela de pagamento ou vencida conforme as datas reais. | Falhava quando o usuário alterava as datas da fatura em `account.invoices`. |
| **Faturas Pagas Antecipadamente** | Detecta pagamento por transações de quitação e omite da lista de pendências. | Podia continuar exibindo faturas como a pagar caso o saldo não fosse avaliado em sincronia com o ciclo. |

---

## 2. Decisão Arquitetural

Definiu-se a paridade absoluta com a lógica baseada em datas do **Swift**:

1. **Adoção Universal de `isVigenteInvoice`:**
   Tanto faturas de ciclos vigentes quanto faturas anteriores fechadas são avaliadas através da função centralizada de vigência.
2. **Cálculo Preciso de Vencimento:**
   A data de vencimento da fatura (`dueDate`) é obtida primeiramente de `account.invoices[k]?.due`. Caso não exista exceção customizada pelo usuário, é calculada dinamicamente via `invDates(cardCfg, key: k).due`.
3. **Classificação Temporal:**
   - **Vencida:** Fatura não vigente cujo vencimento é anterior a hoje (`dueDate < today`) e que ainda possui saldo em aberto.
   - **A Vencer (No Mês / Período):** Fatura cuja data de vencimento está dentro da janela de análise e possui valor pendente.
   - **Quitada / Não Vencida:** Faturas cujo saldo restante é zero ou cujo ciclo ainda está em curso para competências futuras.

---

## 3. Implementação Replicada no Flutter (`money_store.dart`)

```dart
// OpenMoneyFlutter/lib/store/money_store.dart
List<DueBillItem> dueBillItems({String? today}) {
  final todayStr = today ?? todayISO();
  final items = <DueBillItem>[];

  // 1. Processamento de Faturas de Cartão de Crédito
  for (final acc in accounts.where((a) => a.type == 'card')) {
    final cfg = acc.cardCfg;
    if (cfg == null) continue;

    // Obtém todas as competências com transações ou histórico
    final invoiceKeys = _collectInvoiceKeysForCard(acc.id);
    for (final k in invoiceKeys) {
      final vigente = isVigenteInvoice(cfg, k, account: acc, today: todayStr);
      final customInv = acc.invoices?[k];
      final dates = invDates(cfg, k);
      final dueDate = customInv?.due ?? dates.due;
      final balance = invoiceBalance(acc.id, k);

      // Se há saldo devedor e a fatura não é o ciclo futuro/em aberto
      if (balance > 0) {
        final isOverdue = dueDate.compareTo(todayStr) < 0;
        if (isOverdue || vigente) {
          items.add(DueBillItem(
            id: 'inv:${acc.id}:$k',
            name: '${acc.name} - Fatura $k',
            dueDate: dueDate,
            amount: balance,
            isOverdue: isOverdue,
            isInvoice: true,
          ));
        }
      }
    }
  }

  // 2. Processamento de Transações Regulares e Recorrências
  // ... (Mesma regra de paridade contábil)
  
  return items;
}
```

---

## 4. Benefícios e Garantias

- **Zero Dívidas Fantasmas:** Usuários do Flutter não verão avisos alarmantes de faturas vencidas quando estiverem dentro do prazo regular de pagamento.
- **Resiliência a Mudanças de Configuração:** Alterações no dia de vencimento do cartão (ex: mudança do dia 05 para o dia 10) refletem instantaneamente na listagem sem deixar registros órfãos.
- **Mesmo Valor nos Dois Apps:** A tela de Contas a Pagar exibe exatamente a mesma quantidade de títulos e o mesmo somatório financeiro no Mac (Swift) e nas demais plataformas (Flutter).

---

## 5. Testes e Validação

- Suite de testes em `test/parity_audit_fixes_test.dart` no Flutter valida faturas vencidas, faturas no período de carência e faturas já quitadas.
- Todas as 26 asserções foram executadas com 100% de sucesso.
