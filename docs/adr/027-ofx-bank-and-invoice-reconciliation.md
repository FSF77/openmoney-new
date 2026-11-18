# ADR 027: Importação OFX/QFX de Extratos e Faturas com Rotina de Conciliação Bancária

**Status:** ✅ Aprovado, Implementado e Validado  
**Data do Contexto:** 18/11/2026  
**Data de Conclusão:** 18/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  

---

## 1. Contexto e Motivação

Embora o OpenMoney suporte importação em lote via CSV e QIF, arquivos **OFX/QFX** (*Open Financial Exchange*) são o padrão oficial emitido por bancos e operadoras de cartão no Brasil para extratos de conta corrente (`BANKMSGSRSV1 / STMTRS`) e faturas de cartão de crédito (`CREDITCARDMSGSRSV1 / CCSTMTRS`).

Diferentemente de uma importação cega, a rotina de **Conciliação Bancária** precisa:
1. Parear lançamentos já digitados pelo usuário (despesas pendentes, transferências, parcelas `pn/pt` ou pagamentos automáticos de fatura do `syncCards`) com o extrato real do banco, **preservando categoria e descrição originais**, marcando `rec = true` e permitindo optar por manter ou atualizar a data para `<DTPOSTED>`.
2. Classificar lançamentos inéditos pelo histórico (`lastCategoryAndType`) ou detectar transferências entre contas próprias pelos dados bancários do PIX/TED.
3. Garantir idempotência absoluta em reimportações do mesmo período sem falhar diante de peculiaridades reais de exportadores brasileiros (como `<FITID>` compartilhado entre compra internacional + IOF ou disputas/estornos, e cabeçalhos `CHARSET:1252` com conteúdo em UTF-8).
4. Conferir matematicamente o saldo final `<LEDGERBAL>` contra o saldo conciliado projetado no OpenMoney.

---

## 2. Decisões Arquiteturais

### A. Extensão Retrocompatível do Schema v: 7 (`Transaction.fitid`)
- Adicionado atributo opcional `fitid: String?` ao modelo `Transaction` em **Swift** (`Models.swift`) e **Dart** (`openmoney_models.dart`), omitido da serialização JSON quando nulo ou vazio.
- O **Cloud Sync v2** (`SyncEngine` em ambas as stacks) trafega e preserva `fitid` automaticamente via serialização granular `txs/<id>`.

### B. Chave Composta Determinística para `<FITID>` Compartilhado
Bancos/emissores (ex.: Nubank) reutilizam o mesmo `<FITID>` entre uma compra internacional e seu IOF na mesma data, ou entre os múltiplos lançamentos de uma disputa (`compra`, `crédito de confiança`, `reversão`, `estorno`).
- O identificador gravado em `Transaction.fitid` segue o formato determinístico:
  ```
  <rawFitId>|<YYYY-MM-DD>|<rawAmountCents>[|#occ]
  ```
- Quando `<FITID>` não existe no arquivo, usa-se fallback `ofx|<YYYY-MM-DD>|<rawAmountCents>|<normPayee>[|#occ]`.

### C. Decodificação UTF-8 Estrita Prioritária
- O decodificador valida primeiro UTF-8 estrito (`utf8.decode(bytes, allowMalformed: false)` / `String(data: data, encoding: .utf8)`) antes de recorrer ao fallback Windows-1252 / Latin-1, prevenindo corrupção de acentos em arquivos que declaram `CHARSET:1252` no cabeçalho mas emitem bytes UTF-8.

### D. Pareamento 1-para-1 Determinístico e Proteções Contábeis
- **Exclusão de Envelopes de Previsão:** Transações com `isPredictionPayee(tx.payee)` nunca são consumidas pelo pareador automático.
- **Tolerância e Pontuação:**
  - Conta bancária: janela padrão de `±4 dias`, estendida para `±7 dias` em quitações de fatura (`auto == true` / `card != null` / `"pagamento de fatura"`).
  - Cartão de crédito: busca por toda a competência alvo (`effectiveIk == targetInvoiceKey`) ou `±5 dias`, pontuando número de parcela (`pn/pt`) e tokens identificadores.
- **Pagamento de Fatura Anterior no Cartão (`CCSTMTRS`):** Créditos como `"Pagamento recebido"` são pareados com transferências pendentes na fatura anterior ou ignorados automaticamente por padrão (`isInvoicePaymentCredit`), evitando distorção no total da fatura atual e convergindo com `<LEDGERBAL>`.
- **Preservação em `syncCards`:** Pagamentos automáticos (`auto == true`) conciliados via OFX (`fitid != null && rec == true`) mantêm o status conciliado mesmo quando a data real do débito antecede `inv.due`.

### E. Assistente Interativo Lado a Lado (Paridade Multiplataforma)
- **Flutter:** `OfxReconciliationService` + `showOfxReconciliationModal` (`lib/ui/modals/ofx_reconciliation_modal.dart`) disponível no Desktop (macOS/Windows), Web e Mobile, integrado ao extrato da conta/fatura, à Central de Importação/Exportação (`⌘⌥I`), à Command Palette e ao atalho `⌘⇧O` / `Ctrl+Shift+O`.
- **Swift:** `OFXReconciliationService` + `OFXReconciliationSheet` integrado ao macOS (`HSplitView` + `NSOpenPanel` + menu `⌘⇧O`) e ao iOS (`NavigationStack` + `.fileImporter`).

---

## 3. Validação

- Testes unitários dedicados em `test/ofx_reconciliation_test.dart` cobrindo `STMTRS` (PIX, boleto, transferência entre contas próprias, pagamento antecipado de fatura, `LEDGERBAL`), `CCSTMTRS` (UTF-8 com `CHARSET:1252`, `<FITID>` duplicado em IOF/estornos, competência `ik`, `Pagamento recebido`, parcelas 1-para-1, idempotência) e roundtrip no `SyncEngine`.
- Compilação validada em macOS Swift, iOS Simulator (`xcodebuild`), Flutter macOS, Flutter Web e `flutter analyze`.
