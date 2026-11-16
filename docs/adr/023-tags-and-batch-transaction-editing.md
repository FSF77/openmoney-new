# ADR 023: Sistema de Tags nos Lançamentos, Filtros Avançados e Edição em Massa

**Status:** ✅ Aprovado, Implementado e Validado  
**Data:** 14/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade:** 🟢 Evolução Arquitetural / Experiência do Usuário (Multiplataforma)  

---

## 1. Contexto e Motivação

Embora a árvore de **Categorias e Subcategorias** estruture a contabilidade principal do OpenMoney, usuários frequentemente precisam de um eixo transversal de classificação (ex: `#Viagem`, `#Reembolso`, `#Trabalho`, `#Férias`) que possa cruzar múltiplas categorias sem duplicar a árvore contábil.

Adicionalmente, na tela consolidada de **Lançamentos** ([ADR 016](./016-consolidated-transactions-view.md)), faltavam filtros combináveis por atributos (categoria, tag, tipo e conciliação) e ferramentas de produtividade para **seleção múltipla e edição/exclusão em lote** de lançamentos.

### Pedidos do Usuário Incorporados
1. **Edição em massa e filtros avançados na tela de Lançamentos Gerais:** permitir filtrar por categoria, tag, tipo e conciliação, selecionar múltiplos lançamentos e editar em lote nome/favorecido, categoria, tags, notas, valor, data, conta e status de conciliação.
2. **Sistema de Tags nos Lançamentos:**
   - Tela dedicada de **Tags** no menu lateral com botão `+` para criar novas tags, busca, contagem de lançamentos, renomeação, exclusão e **drill-down ao clicar na linha** abrindo a mesma tela de detalhes de lançamentos usada em Categorias.
   - Criação/atribuição inline no momento de criar/editar/copiar um lançamento, separando por **vírgula (`,`)** ou pressionando **Enter**, com sugestões clicáveis.
   - Exibição dos chips `#tag` tanto nos **Lançamentos Gerais** quanto nos **Lançamentos de Conta / Cartão**.
   - **Filtro por Tag na tela de Relatórios** (mensal e anual), propagando o filtro para o detalhamento por categoria.

---

## 2. Decisão de Arquitetura

A implementação segue **paridade funcional estrita** entre **Swift (macOS & iOS)** e **Flutter/Dart (macOS, Windows, Web e Mobile)**, mantendo compatibilidade retroativa integral com o **Schema `v: 7`** e sincronização granular **Sync v2**.

### 2.1. Modelo de Dados (`v: 7`) e Sync v2
- **`Transaction.tags` (`[String]?` / `List<String>?`):** Lista opcional de tags associadas à transação. Omitida do JSON (`openmoney.json`) quando nula ou vazia.
- **`Database.tags` (`[String]` / `List<String>`):** Catálogo global de tags cadastradas pelo usuário. Omitido do JSON quando vazio, preservando 100% de compatibilidade com leitores legados `v: 7`.
- **Sync v2 (`SyncEngine`):** Adicionada a coleção `"tags"` (`tags/<nome>`) no snapshot e na aplicação incremental de alterações remotas em ambas as stacks.
- **Normalização:** Deduplicação case-insensitive preservando a capitalização informada pelo usuário (`normalizeTagList`). Ao salvar um lançamento com novas tags, o sistema registra automaticamente essas tags no catálogo `Database.tags`.

### 2.2. Fluxo de Tags na Interface
1. **Menu Lateral / Navegação:** Novo item **Tags** posicionado abaixo de **Categorias** (`SidebarView.tags` no Swift, `NavModule.tags` no Flutter).
2. **Tela de Tags (`TagsManagementView` / `iOSTagsView` / `TagsView`):**
   - Botão `+` / **Nova Tag**, busca instantânea, renomeação em massa (atualizando o catálogo e todos os lançamentos vinculados), exclusão (removendo do catálogo e dos lançamentos) e contagem de lançamentos por tag.
   - **Drill-down unificado:** clicar na linha de qualquer tag abre `CategoryTransactionsDetailSheet(tagFilter: tag)` (Swift) / `showCategoryDrillDownModal(..., tagFilter: tag)` (Flutter) — reutilizando exatamente a mesma tela de auditoria das Categorias.
3. **Entrada Inline (`TagEditorField` no Swift / `TagInputField` no Flutter):**
   - Integrado às telas de Novo Lançamento, Edição e Cópia.
   - Converte texto em chips `#tag` automaticamente ao digitar vírgula (`,`) ou pressionar `Enter`, exibindo sugestões filtradas do catálogo existente.
   - No Swift macOS, usa `LabeledContent(label)` com `prompt` no campo de texto para manter alinhamento idêntico aos demais campos do `Form`.
4. **Exibição e Exportação:**
   - Chips `#tag` exibidos nas linhas da tela de **Lançamentos Gerais** e nas linhas de **Lançamentos por Conta/Cartão**.
   - Busca textual inclui tags; exportação CSV (`CSVExporter.generateCSV`) inclui a coluna `"Tags"` ao final.

### 2.3. Filtros Avançados e Edição em Massa (`AllTransactionsView` / `iOSTransactionsTab`)
1. **Filtros Combináveis em `consolidatedTransactions`:**
   - **Categoria:** `Todas`, `Sem categoria` (`__uncategorized__`) ou categoria/subcategorias específicas.
   - **Tag:** `Todas`, `Sem tag` (`__untagged__`) ou tag específica (case-insensitive).
   - **Tipo:** `Todos`, `Despesas` (`expense`), `Receitas` (`income`) ou `Transferências` (`transfer`).
   - **Conciliação:** `Todos`, `Conciliados` (`reconciled`) ou `Pendentes` (`pending`).
2. **Seleção Múltipla e Guardrails:**
   - Modo de seleção exibe checkboxes por linha; lançamentos automáticos de pagamento de fatura (`tx.auto == true`) são bloqueados para seleção e ignorados nas operações em lote.
   - Barra contextual exibe contagem de selecionados, soma líquida na moeda de consolidação, **Selecionar todos**, **Limpar**, ações rápidas (**Conciliar**, **Pendente**), **Editar em Lote** e **Excluir** (com criação automática de **Backup de Segurança** preventivo antes da remoção).
3. **Edição em Lote (`BatchTransactionEditPayload`):**
   - Cada campo possui flag independente de aplicação (`applyPayee`, `applyCategory`, `applyTags`, `applyMemo`, `applyAmount`, `applyDate`, `applyAccount`, `applyReconciled`).
   - **Tags em lote:** suporta os modos `Adicionar`, `Substituir` e `Remover`.
   - **Valor em lote:** suporta `Manter sinal original`, `Forçar Despesa (-)` e `Forçar Receita (+)`.
   - **Proteção de Transferências:** em transferências entre contas (`xfer != null || peer != null`), alterações de categoria, conta e valor são ignoradas para preservar o pareamento contábil.
   - **Auditoria:** registra evento `AuditAction.batchEdit` / `AuditEntity.tag` no `AuditLogManager`.

### 2.4. Filtro de Tags nos Relatórios
- `MonthlyReportData.build` (Swift) e `buildMonthlyReport` (Flutter) aceitam `tagFilter` (`"all"`, `"__untagged__"` ou nome da tag).
- O filtro é exibido no cabeçalho de `ReportsView` (macOS), `iOSReportsTab` (iOS) e `ReportsView` (Flutter) e propagado automaticamente ao clicar em qualquer categoria para detalhar lançamentos.

### 2.5. Otimização do Cabeçalho Mobile na Tela de Lançamentos Gerais (`AllTransactionsView`)
- **Problema de Densidade:** Em dispositivos móveis ou telas estreitas, a inclusão de múltiplos seletores (Cartão, Multicontas, Previsões, CSV, PDF, Busca, Ordenação, Categoria, Tag, Tipo, Conciliação e Selecionar) ocupava quase todo o viewport vertical.
- **Padrão de Recolhimento da Tela de Extrato (`AccountLedgerView`):**
  - Botão de alternância no cabeçalho: `Icons.tune` (expandir) / `Icons.expand_less` (recolher), com destaque em cor `accent` quando há filtros ativos.
  - **Sempre visíveis:** Título, KPIs de resumo financeiro (Receitas, Despesas, Resultado) e Seletor de Período (Dia, Mês, Ano) com navegação temporal.
  - **Recolhidos por padrão no mobile:** Filtros secundários, ferramentas de exportação, busca textual, alternador de visualização e filtros avançados/seleção em lote.
  - **Indicador de Filtros Ativos:** Exibe badge compacto informativo `Filtros ativos aplicados [Limpar]` quando recolhido com filtros ativos, permitindo restauração instantânea em 1 toque.

---

## 3. Verificação e Validação

- **Swift macOS:** `swift build` concluído com sucesso (`exit code 0`).
- **Swift iOS:** `xcodebuild -project OpenMoney.xcodeproj -scheme OpenMoney -sdk iphonesimulator -configuration Debug CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build` (`** BUILD SUCCEEDED **`).
- **Flutter:** `flutter analyze` com 0 erros; `flutter test` com **86 testes passando**, incluindo a suíte dedicada [`tags_and_batch_edit_test.dart`](file:///Users/fabiano/Developer/OpenMoneyFlutter/test/tags_and_batch_edit_test.dart).
