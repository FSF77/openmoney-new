# ADR 028: Seletor de Fatura na Barra de Inserção Rápida de Lançamentos de Cartão de Crédito

**Status:** ✅ Aprovado, Implementado e Validado  
**Data:** 18/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade:** 🟢 Paridade Multi-Stack / UX de Lançamentos Rápidos de Cartão  

---

## 1. Contexto e Motivação

No ecossistema OpenMoney, compras com cartão de crédito são vinculadas a uma competência de fatura (`ik` — *invoice key*, ex: `"2026-11"`), calculada a partir da data da compra em relação ao dia de fechamento do cartão (`invKeyFor(card, date)`).

Na tela completa de novo lançamento (`_TransactionCreateDialog`), o usuário sempre teve visibilidade clara da fatura de destino através do campo **"Fatura do Cartão (Competência)"**, com indicação explícita da opção padrão calculada (`[Padrão]`) e a possibilidade de alterar a fatura de cobrança quando o banco lança em competência distinta.

Entretanto, na tela de extrato do cartão de crédito (`AccountLedgerView`), ao utilizar a **barra de inserção rápida de lançamentos**, esse seletor não era exibido. O usuário que estivesse visualizando uma fatura específica não tinha como saber em qual fatura o lançamento seria debitado, nem podia selecionar uma fatura diferente caso a compra caísse após o fechamento ou devesse ser lançada em outra competência.

---

## 2. Decisões de Arquitetura e Implementação

### 2.1. Inclusão do Seletor na Barra Rápida (`AccountLedgerView`)
- Quando a conta ativa for um cartão de crédito (`isCard && acc.card != null`), a barra de inserção rápida renderiza o campo dropdown **"Fatura do Cartão (Competência)"** imediatamente após o campo de **Data**.
- **Cálculo da Opção Padrão:** Avalia a data informada no campo de data (`_resolveIsoDate()`) contra o dia de fechamento do cartão (`invKeyFor(card, date)`), adicionando a marcação visual `[Padrão]`.
- **Janela de Competências Disponíveis:** Gera opções com `invoiceOptions(card, aroundDate, existingKeys)` cobrindo faturas existentes, histórico recente e projeções futuras, com label amigável (ex.: `Novembro/2026 (Vence 15/11/2026)`).
- **Reatividade com a Data:** Ao alterar a data via calendário (`_pickDate`) ou digitação direta no campo de data, a fatura padrão é recalculada automaticamente.
- **Limpeza Pós-Gravação:** Ao salvar o lançamento rápido (`_submitQuickEntry`), o estado `_customIk` é redefinido para `null`, garantindo que novos lançamentos utilizem o padrão da data vigente.

### 2.2. Reatividade de Formulários em Modais (`transaction_modal.dart`)
- Nos modais de criação (`_TransactionCreateDialog`), edição (`_TransactionEditDialog`) e cópia (`_TransactionCopyDialog`), os campos de fatura foram migrados para binding controlado (`value:` em vez de `initialValue:`), assegurando sincronismo instantâneo caso a data seja modificada sem reabertura do diálogo.

### 2.3. Alinhamento de Layout no Modal de Edição (`_TransactionEditDialog`)
- **Posicionamento Superior:** O campo de competência de fatura, que anteriormente ficava no final do formulário de edição após valor, nota e tags, foi reposicionado para o topo logo abaixo de **Conta** e **Data**.
- **Linha Unificada Conta + Data:** Os campos de Conta e Data foram dispostos lado a lado (`flex: 3` e `flex: 2`), exatamente como na tela de novo lançamento (`_TransactionCreateDialog`), com o seletor `Fatura do Cartão (Competência)` imediatamente abaixo.
- **Equalização de Rótulos e Opção Padrão:** Padronizado o rótulo para `Fatura do Cartão (Competência)` e adicionado o sufixo explicativo `[Padrão]` na competência natural da data.

### 2.4. Paridade Estrita com Swift
- No **Swift macOS** (`AccountDetailView`), a barra rápida inline já continha o `Picker` de faturas com marcação `[Padrão]` e binding reativo de `txInvoiceKey`. No `TransactionEditSheet`, o campo de fatura já se posicionava logo após Conta e Data.
- No **Swift iOS** (`iOSNewTransactionSheet`), o formulário de inclusão já continha o seletor correspondente.
- A paridade entre Flutter e Swift passa a ser 100% equivalente.

---

## 3. Validação e Testes

- **Test 38 (`test/widget_test.dart`)**:
  1. Valida que contas correntes/bancárias convencionais não exibem o seletor de fatura.
  2. Valida que cartões de crédito no desktop exibem o seletor `Fatura do Cartão (Competência)` com a indicação `[Padrão]`.
  3. Valida que no mobile (360x740), a barra recolhida abre via botão `+` e renderiza o seletor de fatura perfeitamente sem estouros de layout.
- **Suite Completa:** 98 testes automatizados aprovados no Flutter (`flutter test`) e compilação nativa `swift build` aprovada com código 0.
