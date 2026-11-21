# ADR 010: Rotina de Abatimento de Previsões Orçamentárias (`adjustPredictions`) — Modos por Mês e por Fatura de Cartão

**Status:** ✅ Aprovado, Implementado e Validado  
**Data do Contexto:** 29/10/2026  
**Data de Conclusão:** 04/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade Inicial:** 🟢 Evolução Arquitetural / Regra de Negócio Crítica  

---

## 1. Contexto e Motivação

No OpenMoney, transações orçamentárias com descrição iniciada pelo prefixo `"Previsão"` (ex.: `"Previsão Mercado"`, `"Previsão Combustível"`, `"Previsão Farmácia"`) representam reservas de despesa estimada no fluxo financeiro futuro.

À medida que os gastos reais ocorrem, o usuário aciona a funcionalidade **"Ajustar Previsões"** (`adjustPredictions`). A rotina avalia o consumo orçamentário por categoria e abate os valores correspondentes das previsões, prevenindo duplicidade no saldo projetado e no fluxo de caixa.

### O Princípio Fundamental da Previsão Orçamentária
- Uma transação do tipo `"Previsão"` pertence ao mês com base estritamente na sua **data de lançamento** (`tx.date`).
- **A data da fatura da própria previsão não é calculada:** se uma previsão tem data em Novembro (ex.: `05/11/2026`), ela é a previsão de **Novembro**, independentemente de ter sido lançada em conta bancária ou em conta de cartão de crédito. Isso garante que a estimativa orçamentária do usuário para o mês não seja deslocada para faturas futuras.

### A Diferença de Regime nos Gastos Reais
O ponto de divergência contábil reside em **quando as despesas reais consomem o caixa do usuário**:
1. **Compras em Conta Bancária / Dinheiro / Débito:** consomem o saldo imediatamente no próprio mês da data da transação (`tx.date`).
2. **Compras em Cartão de Crédito:** consomem o saldo do usuário apenas quando a **fatura é paga** (mês de vencimento da fatura `tx.ik`). Compras feitas no ciclo de outubro cuja fatura vence em novembro saem do bolso do usuário em novembro; compras feitas em novembro cuja fatura vence em dezembro só sairão do bolso em dezembro.

Para acomodar essa realidade contábil sem quebrar o modelo histórico simples, foi implementado o parâmetro `predMode`.

---

## 2. Decisão de Arquitetura

Estabeleceu-se a inclusão do parâmetro de persistência `predMode` no banco de dados e a estruturação simétrica da rotina em ambas as stacks (**Swift** e **Flutter**), preservando total retrocompatibilidade e simetria contábil.

```
                     ┌──────────────────────────────────────────────┐
                     │            Banco openmoney.json              │
                     │                 Schema v: 7                  │
                     │          "predMode": "month" | "invoice"     │
                     └──────────────────────┬───────────────────────┘
                                            │
                     ┌──────────────────────┴───────────────────────┐
                     │        adjustPredictions(targetMonth)        │
                     └──────────────────────┬───────────────────────┘
                                            │
                     ┌──────────────────────┴───────────────────────┐
                     ▼                                              ▼
          Modo: "month" (Padrão)                         Modo: "invoice" (Por Fatura)
          ───────────────────────                        ────────────────────────────
          • Previsão: Data do lançamento                 • Previsão: Data do lançamento
          • Escopo: Mês alvo                             • Escopo: Mês alvo + 2 meses futuros
          • Gastos Bancários: Data do mês                • Gastos Bancários: Data do mês
          • Gastos Cartão: Data do mês                   • Gastos Cartão: Vencimento da fatura no mês
```

### 2.1. Persistência dos Parâmetros (`predMode` e `predMonths`) no Schema `v: 7`
- **Chave no JSON:** `"predMode"` (tipo `string`).
  - `"month"`: Abatimento por mês civil (comportamento clássico).
  - `"invoice"`: Abatimento por desembolso real (regime de caixa / fatura de cartão).
- **Chave no JSON:** `"predMonths"` (tipo `int`, padrão `3`).
  - Define o horizonte de meses consecutivos avaliados ao rodar a rotina (`1`, `2`, `3`, `6` ou `12` meses), aplicável a ambos os modos (`month` e `invoice`).
- **Retrocompatibilidade estrita:** Se as chaves forem omitidas, assumem-se `"month"` e `3`. Na gravação, se os valores forem os padrões, os campos são suprimidos da serialização, garantindo bases limpas e retrocompatíveis.
- **Controle de Interface:**
  - Tela de **Ajustes & Personalização**: seletor visual de horizonte (`1 mês`, `2 meses`, `3 meses (Padrão)`, `6 meses`, `12 meses`) e modo de abatimento (`Por Mês` vs `Por Fatura`).
  - Cabeçalho do extrato de lançamentos: menu discreto (`tune`) para alternância rápida de modo e botão de disparo com tooltip dinâmico indicando o horizonte configurado.

---

## 3. Especificação das Regras de Negócio

### 3.1. Regra "Por Mês" (`predMode == "month"` — Regime Civil)
1. **Previsões Consideradas:** Transações com `date.startsWith(targetMonth)`, `auto != true` e `payee` iniciando por `"Previsão"`, em qualquer conta.
2. **Despesas que Abatem:**
   - Todos os lançamentos da mesma categoria com **data de lançamento no próprio mês** (`date.startsWith(targetMonth)`).
   - Abrange todas as contas (bancos e cartões) sem distinção de fatura.
   - Desconsidera outras previsões, transações automáticas (`auto == true`) e transferências bancárias (`xfer != nil`).
3. **Abatimento:** `netSpent = Σ abs(despesas) - Σ receitas/estornos`. O saldo é deduzido em cascata das previsões da categoria no mês.

---

### 3.2. Regra "Por Fatura" (`predMode == "invoice"` — Regime de Desembolso / Caixa)
1. **Janela Estendida de Avaliação:** A rotina avalia três competências consecutivas: o mês selecionado e os dois meses subsequentes (`[M, M+1, M+2]`). Isso mantém as previsões dos meses futuros sempre sincronizadas conforme os ciclos de faturas evoluem.
2. **Previsões Consideradas:**
   - No mês `m`, avaliam-se todas as previsões cuja **data de lançamento** pertença ao mês `m` (`date.startsWith(m)`), **independentemente de a conta ser bancária ou cartão de crédito**.
   - A data da fatura da própria previsão **não é calculada nem deslocada**.
3. **Despesas que Abatem as Previsões do Mês `m`:**
   - **Gastos em contas bancárias / corrente / dinheiro:** entram pela **data do lançamento** (`date.startsWith(m)`), pois o dinheiro sai da conta no próprio mês `m`.
   - **Gastos em contas de cartão de crédito:** entram pela **competência de vencimento da fatura** (`(t.ik ?? invKeyFor(cardCfg, t.date)) == m`), pois o desembolso do pagamento da fatura ocorre no mês `m`.
   - Despesas de cartão cuja fatura vença no mês seguinte (`m + 1`) **não entram** no mês `m` (entrarão no abatimento das previsões do mês `m + 1`).

---

### 3.3. Idempotência e Gestão da Tag de Base Original
Para evitar que sucessivas execuções do botão de ajuste consumam valores já deduzidos ou reduzam previsões a zero por engano, utiliza-se a memorização da base no campo `memo`:

1. Ao avaliar uma previsão de R$ 1.000,00, a base inicial é calculada por:
   $$\text{base} = \text{parseBaseFromMemo(memo)} \;\lor\; |\text{amt}|$$
2. Ao deduzir um valor $D$, calcula-se:
   $$\text{novoSaldo} = \text{base} - D$$
3. Se $\text{novoSaldo} > 0$:
   - A transação tem seu `amt` atualizado para $\text{novoSaldo}$ (respeitando o sinal negativo de despesa).
   - O campo `memo` recebe a tag imutável: `[Previsão base: R$ 1.000,00]`.
4. Se $\text{novoSaldo} \le 0$:
   - A previsão é considerada **esgotada** e o seu identificador é incluído em `idsToDelete`, removendo o lançamento da base e alertando o usuário no resumo da execução.
   > **Nota de Evolução:** A remoção automática ao atingir $\text{novoSaldo} \le 0$ foi posteriormente substituída pela **retenção com saldo zerado (`R$ 0,00` e tag `ESGOTADA`)** para preservar o histórico do planejamento, conforme documentado no [ADR 020](020-predictions-management-view-and-zero-balance-retention.md).

---

## 4. Exemplo Prático Demonstrativo (Mês de Novembro/2026)

### Cenário Inicial
- **Configuração da Conta:** Cartão XP (`closeDay: 25`, `dueDay: 5`).
- **Parâmetro Ativo:** `predMode = "invoice"`.
- **Competência Selecionada:** Novembro de 2026 (`2026-11`).
- **Previsão Cadastrada:**
  - Conta: *Cartão XP* (ou Conta Corrente Banco)
  - Data: `05/11/2026`
  - Descrição: `"Previsão Mercado"`
  - Categoria: `"Mercado"`
  - Valor: `-R$ 1.000,00` (100.000 centavos)
  - Mês da Previsão: `2026-11` (definido pela data do lançamento).

---

### Lançamentos Reais no Período

| # | Lançamento Real | Conta | Data da Compra | Vencimento da Fatura (`ik`) | Entra no Abatimento de Novembro? |
| :-: | :--- | :--- | :-: | :-: | :--- |
| **1** | -R$ 200,00 Mercado | Conta Banco (Corrente) | `02/11/2026` | N/A | **SIM**. Dinheiro saiu da conta corrente em novembro. |
| **2** | -R$ 300,00 Mercado | Cartão XP | `15/10/2026` | `05/11/2026` (`ik: 2026-11`) | **SIM**. Compra feita em outubro cuja fatura fecha em 25/10 e vence/sai em novembro. |
| **3** | -R$ 150,00 Mercado | Cartão XP | `28/11/2026` | `05/12/2026` (`ik: 2026-12`) | **NÃO**. Compra feita após o fechamento de novembro; vence e sairá na fatura de dezembro. |

---

### Execução da Rotina (`adjustPredictions`)

```
================================================================================
                    CÁLCULO DO ABATIMENTO (Modo Fatura)
================================================================================
Mês Avaliado: Novembro/2026 (2026-11)
Previsão Base Encontrada: R$ 1.000,00 (Previsão Mercado em 05/11/2026)

Gastos Elegíveis para Novembro/2026:
  • 02/11/2026: R$ 200,00 (Conta Banco — Desembolso bancário no mês)
  • 15/10/2026: R$ 300,00 (Cartão XP — Fatura com vencimento em 05/11/2026)
  ----------------------------------------------------------------------
  Total de Gastos de Mercado em Novembro: R$ 500,00

Dedução Aplicada: min(R$ 1.000,00, R$ 500,00) = R$ 500,00
Novo Saldo da Previsão: R$ 1.000,00 - R$ 500,00 = R$ 500,00

Lançamento Atualizado na Base:
  • Payee: "Previsão Mercado"
  • Valor: -R$ 500,00 (-50.000 centavos)
  • Memo:  "[Previsão base: R$ 1.000,00]"
================================================================================
```

---

## 5. Implementação no Código-Fonte

### 5.1. OpenMoney Swift (`Store.swift`)
```swift
for (cat, preds) in predsByCategory {
    let spent: [Transaction]
    if invoiceMode {
        // No modo por fatura: despesas bancárias com data do mês + compras de cartão cuja fatura vence no mês
        spent = db.txs.filter { t in
            guard t.auto != true, t.cat == cat, !isPredictionPayee(t.payee), t.xfer == nil else { return false }
            if let cfg = cardCfgs[t.acc] {
                return (t.ik ?? invKeyFor(cfg, date: t.date)) == m
            } else {
                return t.date.hasPrefix(m)
            }
        }
    } else {
        // No modo por mês: todas as despesas com data do mês
        spent = monthTxs.filter { $0.cat == cat && !isPredictionPayee($0.payee) && $0.xfer == nil }
    }
    groups.append(AbateGroup(cat: cat, preds: preds, spent: spent, label: monthLabel))
}
```

### 5.2. OpenMoney Flutter (`money_store.dart`)
```dart
predsByCategory.forEach((cat, preds) {
  final List<Transaction> spent;
  if (invoiceMode) {
    // No modo por fatura: despesas bancárias com data do mês + compras de cartão cuja fatura vence no mês
    spent = db.txs.where((t) {
      if (t.auto == true || t.cat != cat || t.xfer != null) return false;
      if (isPredictionPayee(t.payee)) return false;
      final cfg = cardCfgs[t.acc];
      if (cfg != null) {
        return (t.ik ?? invKeyFor(cfg, t.date)) == m;
      } else {
        return t.date.startsWith(m);
      }
    }).toList();
  } else {
    // No modo por mês: todas as despesas com data do mês
    spent = monthTxs
        .where((t) =>
            t.cat == cat && !isPredictionPayee(t.payee) && t.xfer == null)
        .toList();
  }
  groups.add((cat: cat, preds: preds, spent: spent, label: monthLabel));
});
```

---

## 6. Validação e Testes Automatizados

O caso de teste unitário foi homologado com 100% de sucesso em `test/adjust_predictions_test.dart`:

```bash
flutter test test/adjust_predictions_test.dart
```

```
00:00 +0: loading /Users/fabiano/Developer/OpenMoneyFlutter/test/adjust_predictions_test.dart
00:00 +0: modo por fatura: previsao com base na data do mes + gastos de banco do mes + gastos de cartao com fatura no mes
00:00 +1: modo por mes padrao: abate apenas despesas com data do proprio mes
00:00 +2: All tests passed!
```

E no Swift (`swift build`):
```
Build complete! (13,44 seg)
```

---

## 7. Referências e Documentos Relacionados

- **[ADR 001: Adoção do Schema v: 7](001-schema-v7-adoption.md)**
- **[ADR 003: Vigência de Fatura (`isVigenteInvoice`)](003-is-vigente-invoice-strategy.md)**
- **[ADR 004: Reconciliação Automática de Faturas (`syncCards`)](004-card-invoice-settlement.md)**
- **[ADR 020: Tela Dedicada de Gestão de Previsões e Retenção de Previsões Esgotadas com Saldo Zerado](020-predictions-management-view-and-zero-balance-retention.md)**
- **[Dicionário de Dados do Schema v: 7](../architecture/dicionario-de-dados.md)**
