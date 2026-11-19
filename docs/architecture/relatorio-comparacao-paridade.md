# 📊 Relatório de Comparação Técnica e Paridade Multi-Stack: OpenMoneySwift vs OpenMoneyFlutter

> **Versão:** 2.1 (Pós-Ajustes e Paridade 100%)  
> **Data de Atualização:** 16/11/2026  
> **Status:** ✅ 100% Paridade Funcional Estrita Atingida  
> **Escopo:** Comparativo arquitetural e funcional detalhado entre OpenMoneySwift e OpenMoneyFlutter  

> [!NOTE]
> **Marco Histórico Concluído (`v2.5.0`):** Este relatório documenta o atingimento de 100% de paridade funcional entre as duas stacks até a versão `v2.5.0`. Após essa conclusão, a stack Swift foi oficialmente descontinuada e arquivada, consolidando o **OpenMoney Flutter** como a única stack ativa e oficial do ecossistema (consulte o [ADR 029](../adr/029-swift-deprecation-and-flutter-single-stack-unification.md)).

---

## 🎯 1. Objetivo da Análise e Governança

O objetivo deste relatório é documentar a auditoria técnica e a consolidação da **equivalência funcional estrita** entre:
- **OpenMoneySwift** (macOS/iOS) — **Fonte da verdade** para regras contábeis, modelos e comportamento.
- **OpenMoneyFlutter** (macOS, Windows, Web, iOS, Android) — **Replicador multiplataforma** de alta performance.

Ambas as stacks operam sobre a mesma base de dados JSON (`openmoney.json`), devendo garantir leitura e escrita simétricas e idênticas.

---

## 📋 2. Regras de Ouro do Ecossistema (`AGENTS.md`)

| Diretriz | Descrição e Garantia |
| :--- | :--- |
| **1. Equivalência Funcional Estrita** | O aplicativo em Swift é a referência canônica. Qualquer funcionalidade, ajuste ou correção deve ser replicada com o mesmo comportamento no Flutter/Dart, cobrindo todas as plataformas suportadas. |
| **2. Schema Unificado (`v: 7`)** | Regras idênticas de leitura/escrita, campos monetários em centavos inteiros (`amt`, `opening`), debounce de persistência de 350ms, migração de competência de faturas quando `dueDay <= closeDay` e backup atômico diário. |
| **3. Política de Versionamento** | Versão Semântica (SemVer, ex: `2.1.1`) rigorosamente equalizada entre Swift e Flutter; Build Number mantido de forma independente por plataforma com incremento automático (`+1`) no fluxo de release. |

---

## 🏗️ 3. Arquitetura Comparativa

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Ecossistema OpenMoney                           │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  OpenMoneySwift (macOS / iOS)          OpenMoneyFlutter (Multi-OS)     │
│  ├─ SwiftUI nativo (Apple UX)          ├─ Flutter / Dart (Liquid Glass)│
│  ├─ Models.swift (Fonte da Verdade)   ├─ openmoney_models.dart         │
│  ├─ Store.swift (Regras Contábeis)    ├─ money_store.dart              │
│  └─ Schema v: 7 Default                └─ Schema v: 7 Default          │
│                 ▲                                     ▲                │
│                 │                                     │                │
│                 └──────────────┬──────────────────────┘                │
│                                │                                       │
│                                ▼                                       │
│                 Base Única: openmoney.json                             │
│                 - Schema Version: 7                                    │
│                 - Valores em centavos inteiros (Int)                   │
│                 - Debounce 350ms / Backup Atômico                      │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🗂️ 4. Estrutura dos Repositórios

### OpenMoneySwift
- `Sources/OpenMoney/Models.swift`: Estruturas de dados (`Account`, `Transaction`, `Category`, `CardConfig`, `InvoiceSummary`), funções de data (`invDates`, `invKeyFor`, `isVigenteInvoice`) e decodificadores JSON do Schema `v: 7`.
- `Sources/OpenMoney/Store.swift`: Gestor global de estado (`MoneyStore`), conciliação automática de faturas (`syncCards`), cômputo de saldos projetados (`balance`), contas a pagar e limite de gastos.
- `Sources/OpenMoney/Views.swift`: Telas em SwiftUI nativo com design Liquid Glass, suporte a macOS e iOS/iPadOS.

### OpenMoneyFlutter
- `lib/models/openmoney_models.dart`: Modelos de dados espelhados em Dart, incluindo `CardConfig`, `InvoiceInfo`, datas de ciclo e a implementação de `isVigenteInvoice`.
- `lib/store/money_store.dart`: Motor contábil reativo com suporte a `syncCards`, `dueBillItems`, `installmentItems` e cálculo de balanço financeiro.
- `lib/ui/`: Telas e componentes visuais multi-plataforma (macOS, Windows, Web e Mobile).
- `test/parity_audit_fixes_test.dart`: Suite de testes automatizados com 26 testes validando paridade com o Swift.

---

## ⚙️ 5. Resolução das Divergências Técnicas

### 5.1. Versão Padrão do Schema (`Database.init`)
- **Situação Anterior:** O construtor padrão de base de dados vazia no Swift inicializava `v: 6`, enquanto o Flutter utilizava `v: 7`.
- **Ajuste Realizado:** O construtor padrão do `Database` em [Models.swift](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/Models.swift#L480) foi unificado para `v: 7`.
- **Resultado:** Qualquer nova base criada por qualquer uma das plataformas nasce padronizada no Schema `v: 7`.

### 5.2. Vigência de Faturas (`isVigenteInvoice`)
- **Situação Anterior:** O Flutter não possuía essa função e utilizava uma comparação direta de chave de texto, resultando em faturas normais sendo marcadas indevidamente como vencidas.
- **Ajuste Realizado:** Implementada a função [`isVigenteInvoice`](file:///Users/fabiano/Developer/OpenMoneyFlutter/lib/models/openmoney_models.dart#L442) no Flutter, reproduzindo exatamente a lógica do Swift:
  1. Verifica se a chave corresponde ao ciclo em aberto para o dia de hoje (`invoiceKey == currentOpenKey`).
  2. Obtém as datas de fechamento e vencimento (sejam personalizadas em `account.invoices` ou calculadas por `invDates`).
  3. Reconhece como vigente a fatura cujo corte já passou mas cujo vencimento ainda não expirou (`closeDate <= today && dueDate >= today`).
- **Resultado:** Eliminação de falsos atrasos e paridade perfeita no cômputo de pendências de cartão.

### 5.3. Reconciliação Automática de Faturas (`syncCards`)
- **Situação Anterior:** No Flutter, a geração de transações de quitação dependia de uma flag opcional e por vezes omitia a competência `ik`. No Swift, o saldo de cartões não projetava adequadamente transações `auto` e `rec` no filtro de mês.
- **Ajuste Realizado:**
  - No Flutter, `syncCards` opera de forma contínua, gravando lançamentos automáticos com a chave canônica `inv:$cardId:$k` e persistindo `ik`.
  - No Swift, `Store.swift` foi ajustado em `upsertAutoTxFast` para gravar `ik` e no cálculo de `balance` de cartões para computar transações quando `tx.auto != true || tx.rec`, respeitando `ik <= month`.
- **Resultado:** Idempotência total na reconciliação de cartão em todas as plataformas.

### 5.4. Cálculo de Contas a Pagar (`dueBillItems`)
- **Situação Anterior:** `dueBillItems` no Flutter não sincronizava as datas de vencimento em caso de cartões com datas personalizadas ou alteradas.
- **Ajuste Realizado:** Refatoração completa em `money_store.dart` utilizando `isVigenteInvoice` e busca de datas em cascata (`customInv?.due ?? dates.due`).
- **Resultado:** A listagem de Contas a Pagar exibe idênticos valores, títulos e status de vencimento em todas as plataformas.

---

## 📊 6. Matriz de Equivalência Atualizada

| Módulo / Funcionalidade | Swift | Flutter | Status de Equivalência |
| :--- | :---: | :---: | :---: |
| **Schema JSON e Persistência (v: 7)** | ✅ Schema v: 7 | ✅ Schema v: 7 | **100% Idêntico** |
| **Centavos Inteiros (`amt`, `opening`)** | ✅ Inteiro | ✅ Inteiro | **100% Idêntico** |
| **Cálculo de Ciclo e Chave (`invKeyFor`, `invDates`)** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |
| **Determinação de Vigência (`isVigenteInvoice`)** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |
| **Reconciliação e Transferências (`syncCards`)** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |
| **Contas a Pagar e Atrasos (`dueBillItems`)** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |
| **Parcelamentos (`installmentItems`)** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |
| **Cálculo de Saldos e Projeções (`balance`)** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |
| **Limite de Gastos e Categorias (incl. Bloqueio)** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |
| **Fluxo de Caixa: Cards KPI e Comentários por Período (`comments`)** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |
| **Lançamentos Consolidados (`consolidatedTransactions`, Filtros Dia/Mês/Ano e Fatura)** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |
| **Multi-Moeda, Câmbio em Transferências e Cotações Históricas (PTAX/AwesomeAPI, Campo Editável & Correção em Lote)** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |
| **Sincronização Cloud & Base de Dados Local** | ✅ Conforme | ✅ Conforme | **100% Idêntico** |

---

## 🧪 7. Validação e Qualidade de Código

### Validação no Swift
- Compilador: Apple Swift 6.x
- Comando: `swift build`
- Resultado: **Build concluído com sucesso**, zero erros e zero avisos de compilação.

### Validação no Flutter
- Framework: Flutter 3.x / Dart 3.x
- Suites de Testes: `test/parity_audit_fixes_test.dart` (26 testes) e `test/widget_test.dart` (25 suítes de testes)
- Comando: `flutter test`
- Resultado: **100% dos testes aprovados** cobrindo ciclo de fatura, persistência de `ik`, cálculo de vencimento, idempotência de conciliação, bloqueio de categorias, botões compactos, inibição de base local quando Cloud ativo e comentários de período no Fluxo de Caixa.

---

## 🔗 8. Documentos de Referência

### Arquitetura e Dados
- [Compilado de Engenharia, Regras de Negócio e Funcionalidades](./compilado-do-sistema.md)
- [Dicionário de Dados Completo (Schema v: 7)](./dicionario-de-dados.md)

### Decisões de Arquitetura (ADRs)
- [ADR 001: Adoção do Schema v: 7 como Padrão Unificado Multi-Stack](../adr/001-schema-v7-adoption.md)
- [ADR 002: Histórico de Versões do Schema e Alinhamento de Versão Padrão](../adr/002-schema-default-version.md)
- [ADR 003: Estratégia e Implementação da Vigência de Fatura (`isVigenteInvoice`)](../adr/003-is-vigente-invoice-strategy.md)
- [ADR 004: Conciliação e Quitação Automática de Faturas de Cartão (`syncCards`)](../adr/004-card-invoice-settlement.md)
- [ADR 005: Cálculo de Contas a Pagar e Faturas Vencidas (`dueBillItems`)](../adr/005-due-bill-overdue-calculation.md)
- [ADR 006: Síntese de Auditoria Técnica e Resolução de Divergências Multi-Stack](../adr/006-divergence-summary.md)
- [ADR 007: Arquitetura de Importação de Comprovantes via OCR Nativo e IA Multimodal (BYOK)](../adr/007-receipts-ocr-ai-import.md)
- [ADR 008: Arquitetura do Coletor Mobile PWA, Automação via Atalhos do iOS e Resolução de Contas em 4 Níveis](../adr/008-coletor-smart-account-ios-automation.md)
- [ADR 009: Padronização de Design System, Visibilidade de Patrimônio e Fluxo de Novo Lançamento](../adr/009-design-system-patrimony-and-transaction-flow.md)
- [ADR 010: Rotina de Abatimento de Previsões Orçamentárias (`adjustPredictions`) — Modos por Mês e por Fatura de Cartão](../adr/010-smart-predictions-offset-modes.md)
- [ADR 011: Arquitetura Web Multiusuário Cloudflare e Manutenção do Modo Tradicional Local no Desktop](../adr/011-web-multiuser-cloudflare-architecture.md)
- [ADR 012: Design Responsivo Mobile Web e Otimização para Telas Estreitas](../adr/012-mobile-responsive-web-design.md)
- [ADR 013: Motor de Sincronização Granular por Registro em Tempo Real (Sync v2)](../adr/013-realtime-record-sync.md)
- [ADR 014: Arquitetura Híbrida Desktop (Local ↔ Nuvem), Backups de Segurança Locais e Logs de Auditoria Online](../adr/014-desktop-hybrid-sync-audit-and-safety-backups.md)
- [ADR 015: Hardening de Segurança Web, Proteção Anti-Força-Bruta D1, Isolamento de Segredos e Mitigação de Ataques](../adr/015-web-and-d1-security-hardening.md)
- [ADR 016: Tela Consolidada de Lançamentos de Todas as Contas, Filtro Temporal e Resolução por Fatura](../adr/016-consolidated-transactions-view.md)
- [ADR 017: Modernização de UI/UX Desktop & Web, Central de Ajustes, Dashboard Customizável, Mini Rail, Datagrid e Paridade Multi-Stack](../adr/017-desktop-web-ui-dashboard-and-customization.md)
- [ADR 018: Arquitetura Multi-Moeda, Câmbio em Transferências e Cotações Históricas](../adr/018-multi-currency-and-historical-rates.md)
- [ADR 019: Paridade Integral do Modo Online e Sync v2 no OpenMoney Swift (macOS e iOS)](../adr/019-swift-cloud-sync-v2-parity.md)
- [ADR 020: Tela Dedicada de Gestão de Previsões e Retenção de Previsões Esgotadas com Saldo Zerado](../adr/020-predictions-management-view-and-zero-balance-retention.md)
- [ADR 021: Verificação Ativa de Limite de Gastos (Budget Excess Warning) na Inserção de Lançamentos](../adr/021-budget-limit-verification-on-transaction-entry.md)
- [ADR 022: Padronização Visual Integral da Cor de Destaque, Eliminação de Resíduos Lilases do M3 e Otimização do Fluxo de Lançamentos e Extratos](../adr/022-complete-accent-color-standardization-and-entry-flow-optimizations.md)
- [ADR 023: Sistema de Tags nos Lançamentos, Filtros Avançados e Edição em Massa](../adr/023-tags-and-batch-transaction-editing.md)
- [ADR 024: Aperfeiçoamento do Modal de Detalhe de Lançamentos (Drill-Down), Filtro de Conciliação e Limpeza Visual](../adr/024-drill-down-reconciliation-filter-and-ui-cleanup.md)
- [ADR 025: Persistência Local do Key-Value Store de Sincronização (sync_kv_store.json) e Paridade Multiplataforma](../adr/025-sync-kv-store-local-persistence.md)

### Guias e Manuais do Usuário
- [Guia do Usuário: Boas-Vindas e Primeiros Passos](../manual/guia-boas-vindas.md)
- [Guia do Usuário: Dashboard Geral, Cockpit e Central de Personalização](../manual/guia-dashboard-e-personalizacao.md)
- [Guia do Usuário: Filtros Avançados e Edição em Massa (Lote)](../manual/guia-edicao-em-massa.md)
- [Guia do Usuário: Gestão e Acompanhamento de Previsões Orçamentárias](../manual/guia-gestao-de-previsoes.md)
- [Guia do Usuário: Limite de Gastos e Alerta Preventivo de Orçamento](../manual/guia-limite-de-gastos-e-alertas.md)
- [Guia do Usuário: Contas Multi-Moeda, Câmbio e Cotações Históricas](../manual/guia-multi-moeda-e-cambio.md)
- [Guia do Usuário: Sincronização em Tempo Real (OpenMoney Cloud — Sync v2)](../manual/guia-sincronizacao-cloud.md)
- [Guia do Usuário: Sistema de Tags (`#tags`)](../manual/guia-tags.md)
