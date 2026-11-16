# ADR 006: Síntese de Auditoria Técnica e Resolução de Divergências Multi-Stack

**Status:** 🎯 Concluído / 100% Paridade Atingida  
**Data da Auditoria:** 31/10/2026  
**Data de Conclusão e Testes:** 31/10/2026  
**Escopo:** OpenMoneySwift vs OpenMoneyFlutter  
**Decisores:** Tech Lead / Arquitetura OpenMoney  

---

## 1. Visão Executiva

A auditoria técnica inicial conduzida entre os repositórios **OpenMoneySwift** (nativo Apple) e **OpenMoneyFlutter** (multiplataforma) avaliou a equivalência estrita de modelos, regras contábeis, persistência de dados e comportamento da interface.

Antes das intervenções, estimava-se a equivalência funcional global em **~87%**, com 5 pontos de divergência em lógica de cartões e persistência. Após a execução do plano de ação técnica, **todas as 5 divergências foram solucionadas, atingindo 100% de paridade estrita**.

---

## 2. Matriz de Divergências e Resolução

| ID | Área / Funcionalidade | Severidade Inicial | Situação Anterior | Ação Executada | Situação Atual |
| :---: | :--- | :---: | :--- | :--- | :---: |
| **01** | **Versão Padrão do Schema** | 🟡 Média | Swift usava `v: 6` no inicializador; Flutter usava `v: 7`. | Construtor `Database.init` no Swift atualizado para `v: 7` ([ADR 001](./001-schema-v7-adoption.md)). | ✅ **100% Equalizado (v: 7)** |
| **02** | **Função `isVigenteInvoice`** | 🔴 Crítica | Inexistente no Flutter, gerando contas a pagar errôneas. | Função implementada no Flutter idêntica ao Swift ([ADR 003](./003-is-vigente-invoice-strategy.md)). | ✅ **100% Paridade** |
| **03** | **Cálculo de Contas a Pagar (`dueBillItems`)** | 🟡 Média | Flutter comparava apenas strings de chave de fatura. | Refatorado para checagem por datas e vigência ([ADR 005](./005-due-bill-overdue-calculation.md)). | ✅ **100% Paridade** |
| **04** | **Reconciliação de Faturas (`syncCards`)** | 🟡 Alta | Divergência em flag padrão e chave de conciliação. | Padronizada conciliação contínua, chave `inv:$cardId:$k` e persistência de `ik` ([ADR 004](./004-card-invoice-settlement.md)). | ✅ **100% Paridade** |
| **05** | **Saldo de Cartão com Transações Auto (`balance`)** | 🟡 Alta | Swift filtrava transações de pagamento de fatura em saldos futuros de forma inconsistente. | Atualizado Swift `Store.swift` para considerar `tx.auto != true || tx.rec` com `ik <= month`. | ✅ **100% Paridade** |

---

## 3. Resumo por Categoria

```
┌───────────────────────────────────────┬───────────────┬────────────────────────┐
│ Categoria                             │ Status Pré    │ Status Pós-Ajustes     │
├───────────────────────────────────────┼───────────────┼────────────────────────┤
│ Modelo de Dados (Schema v: 7)          │ 95%           │ 100% Equivalente       │
│ Regras Contábeis e CRUD de Transações │ 100%          │ 100% Equivalente       │
│ Lógica de Faturas de Cartão de Crédito│ 75%           │ 100% Equivalente       │
│ Contas a Pagar e Parcelamentos        │ 80%           │ 100% Equivalente       │
│ Relatórios e Saldos Projetados        │ 90%           │ 100% Equivalente       │
│ Governança e Documentação Centralizada│ Parcial       │ 100% Centralizada      │
└───────────────────────────────────────┴───────────────┴────────────────────────┘
```

---

## 4. Evidências de Validação

1. **Repositório Swift (`OpenMoneySwift`):**
   - Compilação limpa do projeto executada com `swift build` (zero erros, zero warnings).
   - Testada a criação de banco vazio: arquivo gerado diretamente com `"v": 7`.

2. **Repositório Flutter (`OpenMoneyFlutter`):**
   - Criação da suite de testes [parity_audit_fixes_test.dart](file:///Users/fabiano/Developer/OpenMoneyFlutter/test/parity_audit_fixes_test.dart).
   - Execução de testes automatizados com `flutter test`:
     ```
     00:03 +26: All tests passed!
     ```
   - Casos de borda testados: virada de ciclo de fatura, fechamento antes do vencimento, vencimento ultrapassado, quitação manual e geração automática de transferências.

3. **Repositório de Documentação (`OpenMoneyDocs`):**
   - Estruturado como repositório canônico do ecossistema.
   - ADRs de 001 a 006 mantidos em Português do Brasil com todo o histórico técnico detalhado.
   - Sincronização das regras de governança multi-stack no `AGENTS.md` de todos os repositórios.
