# ADR 004: Conciliação e Quitação Automática de Faturas de Cartão (`syncCards`)

**Status:** ✅ Aprovado, Implementado e Validado  
**Data do Contexto:** 31/10/2026  
**Data de Conclusão:** 31/10/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade Inicial:** 🟡 Alta (Divergência eliminada)  

---

## 1. Contexto e Divergências Iniciais

O método `syncCards` é responsável por calcular o valor consolidado das faturas de cartão de crédito e gerar, de forma idempotente, os lançamentos de transferência entre a conta corrente pagadora (`payAccId`) e a conta do cartão de crédito, garantindo que o saldo seja quitado e o fluxo de caixa reflita a realidade financeira.

A auditoria técnica inicial detectou duas divergências críticas:

1. **Parâmetros e Assinatura:**
   - No **Swift**, o método `syncCards()` sempre operava em modo automático e contínuo, sem parâmetros ou flags condicionais, garantindo que qualquer alteração de transação recalcularia os lançamentos automáticos de pagamento.
   - No **Flutter**, o método possuía um parâmetro opcional `syncCards({bool settleCardInvoices = false})`. Com o valor padrão `false`, a conciliação de faturas fechadas deixava de gerar os lançamentos de liquidação a menos que explicitamente solicitado.

2. **Atributo de Competência (`ik`) e Chave de Transferência (`inv`):**
   - No **Swift**, a persistência de lançamentos automáticos criados por `syncCards` e `upsertAutoTxFast` utilizava a chave de conciliação padronizada `inv:$cardId:$k` e persistia o atributo `ik: k`.
   - No **Flutter**, em certos fluxos, o `ik` não era propagado nas transferências de pagamento de fatura, ou a formatação da chave divergia, impedindo a rastreabilidade bidirecional entre stacks.

3. **Cálculo de Saldo Projetado de Cartão (`balance`):**
   - No **Swift** (`Store.swift`), a filtragem de transações de cartão de crédito para saldo projetado de meses futuros exigia ajustes para computar adequadamente os lançamentos quando `tx.auto != true || tx.rec`, respeitando a competência `ik <= month`.

---

## 2. Decisão e Alinhamento Técnico

Adotou-se o comportamento canônico do **Swift** como referência absoluta, com os devidos ajustes de simetria:

### A. Alinhamento no OpenMoneyFlutter (`money_store.dart`):
- O comportamento padrão de `syncCards` foi unificado para processar e atualizar as faturas fechadas de forma contínua e determinística.
- Todas as transações automáticas de pagamento geradas recebem a chave de reconciliação canônica:
  ```dart
  final invKey = 'inv:$cardId:$k';
  ```
- O atributo de competência `ik` passou a ser gravado em ambas as pernas da transferência (débito na conta pagadora e crédito no cartão).
- O identificador de transação automática `auto: true` é preservado, permitindo que a rotina `syncCards` atualize os valores dinamicamente quando novas compras forem lançadas no mesmo ciclo.

### B. Ajustes no OpenMoneySwift (`Store.swift`):
- A função `upsertAutoTxFast` foi ajustada para persistir o campo `ik` explicitamente nas transações geradas.
- O cálculo de saldo em `balance(accId:month:)` foi corrigido para que contas do tipo cartão de crédito incluam transações quando `tx.auto != true || tx.rec`, respeitando a regra `ik <= month`.
- Dessa forma, pagamentos manuais ou transações recorrentes são preservados no cálculo sem duplicar lançamentos gerados dinamicamente.

---

## 3. Mecanismo de Idempotência da Quitação de Fatura

Para evitar duplicidade de transações bancárias, o ciclo de liquidação opera sob o seguinte protocolo:

```
[Compra no Cartão (Ex: R$ 100 em 2026-10-15)] ──► Fatura fecha em 25/10 (Vencimento 05/11)
                                                                 │
                                                   syncCards() é executado
                                                                 │
                                                                 ▼
                                                  Verifica existência de transação com:
                                                  transfer == "inv:card-1:2026-11" E auto == true
                                                                 │
                                ┌────────────────────────────────┴────────────────────────────────┐
                                ▼                                                                 ▼
                      [Não existe lançamento]                                            [Lançamento já existe]
                     Cria débito na Conta Corrente                                      Atualiza o montante (amt)
                     Cria crédito no Cartão                                             caso novas compras tenham
                     amt: -10000 / +10000                                               sido inseridas no ciclo.
                     ik: "2026-11"
```

Se o usuário optar por registrar o pagamento manualmente (desmarcando `auto` ou criando uma transferência manual com outro descritivo), o sistema detecta a quitação manual e não sobrescreve a ação do usuário.

---

## 4. Validação e Testes

- **Testes Unitários:** O teste `test/parity_audit_fixes_test.dart` no Flutter valida a criação e idempotência de transações geradas por `syncCards`, garantindo a chave `inv:cardId:k` e o preenchimento de `ik`.
- **Compilação Swift:** Validada compilação nativa em macOS sem warnings com `swift build`.
- **Integridade do Banco:** Base gravada e validada no schema `v: 7` sem inconsistências entre plataformas.
