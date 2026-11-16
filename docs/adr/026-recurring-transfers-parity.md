# ADR 026: Paridade e Habilitação de Transferências Recorrentes Entre Contas

**Status:** ✅ Aprovado, Implementado e Validado  
**Data:** 16/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade:** 🟢 Funcionalidade Core / Paridade Multi-Stack e Governança de Séries  

---

## 1. Contexto e Motivação

No ecossistema OpenMoney, os usuários podem configurar despesas e receitas de forma única, recorrente ou parcelada. No entanto, ao selecionar o tipo **Transferência** (`isXfer` ou `catSelection.startsWith("xfer:")`), as interfaces desktop e web ocultavam o seletor de modalidade por completo.

Isso impedia a criação de transferências recorrentes programadas (ex: investimentos mensais automáticos, custeio mensal de dependentes, transferências regulares entre conta corrente e poupança).

Uma auditoria arquitetural no *engine* revelou que a infraestrutura subjacente de dados (`RecurrenceRule` com o campo `peer` no Schema v7) e o gerador de séries em lote (`syncRecs()`) já continham suporte para transferências pareadas. O bloqueio residia estritamente em verificações de interface (`if (!isXfer)`), que deveriam ocultar apenas o modo "Parcelado" (que não se aplica a transferências), liberando os modos "Único" e "Recorrente".

---

## 2. Decisões de Arquitetura

### 2.1. Modelo de Dados e Compatibilidade de Schema (v: 7)
- **Zero Alteração de Schema**: O modelo `RecurrenceRule` (`db.recs`) já possui o atributo opcional `peer: String?` em Swift e Dart.
- **Sincronização Cloud v2**: Totalmente transparente. As regras e os lançamentos gerados transitam pelos diffs granulares (`computeDiff`) e snapshots binários sem necessidade de migrações.

### 2.2. Geração Pareada via `syncRecs()`
Ao processar regras recorrentes que possuam `peer != null`:
1. **Perna de Origem**:
   - `id`: `rec:${r.id}:${seq}`
   - `acc`: `r.acc`
   - `peer`: `r.peer`
   - `amt`: `-abs(r.amt)` (débito)
   - `xfer`: `xrec:${r.id}:${seq}`
   - `cat`: `Transferência: [Nome da Conta Destino]`
   - `rate`: taxa de conversão para BRL caso não seja conta em BRL.
2. **Perna de Destino (Espelho)**:
   - `id`: `rec:${r.id}:${seq}:peer`
   - `acc`: `r.peer`
   - `peer`: `r.acc`
   - `amt`: `+abs(convertedAmt)` (crédito, convertido com `convertCents` caso as moedas divirjam)
   - `xfer`: `xrec:${r.id}:${seq}`
   - `cat`: `Transferência: [Nome da Conta Origem]`
   - `rate`: taxa de conversão para BRL da conta de destino.
   - `ik`: chave de fatura calculada caso a conta de destino seja cartão de crédito.

### 2.3. Paridade de Interface (UI)
Nas telas de criação e edição:
- **Despesas e Receitas**: O seletor de modo oferece `[ Único | Recorrente | Parcelado ]`.
- **Transferências**: O seletor de modo oferece dinamicamente `[ Único | Recorrente ]` (omite "Parcelado").
- **Proteção contra Estado Inválido**: Ao alternar para o tipo Transferência, caso o modo estivesse selecionado como "Parcelado", o sistema força a seleção automaticamente para "Único".
- **Configuração de Recorrência**: Quando selecionado "Recorrente", exibe-se a escolha de periodicidade (`freq`: Diário, Semanal, Quinzenal, Mensal, Bimestral, Trimestral, Semestral, Anual) e data de término opcional.

### 2.4. Escopo de Edição e Exclusão em Séries Pareadas
- **Escopo "Apenas Este" (`only`)**: Exclui ou atualiza simultaneamente a perna selecionada e sua contrapartida pareada através da chave `xfer` (`xrec:...`).
- **Escopo "Deste em Diante" (`forward`)**: Trunca o término da regra (`rule.end = date - 1 dia`) e remove todas as instâncias futuras de ambas as pernas (`(x.recSeq ?? 0) >= seq`).
- **Escopo "Toda a Série" (`all`)**: Remove a regra `RecurrenceRule` e todas as instâncias geradas (`recId == rule.id`) em ambas as contas.

---

## 3. Plataformas Impactadas

| Plataforma | Componentes Modificados | Status |
| :--- | :--- | :--- |
| **Flutter (macOS, Windows, Web, Mobile)** | `money_store.dart`, `transaction_modal.dart`, `account_ledger_view.dart` | ✅ Implementado e testado |
| **Swift macOS** | `Views.swift` (`TransactionCreateSheet`, `TransactionCopySheet`, `AccountDetailView`) | ✅ Implementado e compilado |
| **Swift iOS** | `iOSViews.swift` (`iOSNewTransactionSheet`) | ✅ Implementado e compilado |

---

## 4. Testes e Validação

1. **Testes Unitários de Regra e Geração (`widget_test.dart`)**:
   - `test 35`: Inserção de transferência recorrente mensal entre conta corrente e poupança.
   - Validação da persistência de `rule.peer` no banco.
   - Validação da geração idêntica de lançamentos espelho interligados por `xrec:...`.
   - Validação da exclusão em lote de toda a série e remoção de ambas as contas.
2. **Testes de Regressão da Suite**:
   - 91 testes automatizados executados e aprovados com 100% de sucesso.
   - Compilação nativa `swift build` aprovada sem warnings ou erros de tipos.
