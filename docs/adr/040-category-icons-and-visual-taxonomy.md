# ADR 040: Ícones Vetoriais, Cores Semânticas e Herança Visual nas Categorias

- **Status:** Aceito e Implementado
- **Data:** 2026-11-27
- **Contexto:** Aplicativo Multiplataforma Flutter (`OpenMoneyFlutter` — macOS, Windows, Web PWA e Mobile)

---

## 1. Contexto e Motivação

Com o crescimento do volume de lançamentos e categorias no OpenMoney, a identificação puramente textual nas telas de inclusão (`CategorySelectFormField`) e nas listagens de transações (`AccountLedgerView`, `AllTransactionsView`, `DatagridTransactionTable`) exigia leitura linha a linha, aumentando a carga cognitiva.

Era necessário introduzir identificação visual imediata (ícones + cores semânticas) seguindo boas práticas de UX Design financeiro, sem quebrar bases `openmoney.json` (`v: 7`) existentes, sem exigir configuração manual obrigatória e mantendo consistência estética entre **macOS, Windows, Web PWA e Mobile** (nos temas Claro e Escuro).

---

## 2. Decisão Arquitetural

### 2.1. Modelo de Dados Retrocompatível (`CategoryItem`)
- Adicionados os campos opcionais `icon` (`String?`) e `color` (`String?`) em `CategoryItem` (`lib/models/openmoney_models.dart`).
- Campos nulos ou vazios são omitidos na serialização JSON (`toJson`), preservando total compatibilidade com o schema `v: 7` e sincronização granular **Cloud Sync v2** (`cats` no D1 / Durable Objects) sem necessidade de migração de banco.
- `kDefaultCats` foi enriquecido com ícones e cores padrão em todas as categorias principais de fábrica, mantendo as subcategorias com `icon: null` e `color: null` para herdarem da categoria principal por padrão.

### 2.2. Ícones Vetoriais Curados (`CategoryIconRegistry` + `CategoryIconBadge`)
- Criado `lib/services/category_icon_registry.dart` seguindo o padrão arquitetural de `BankLogoRegistry`.
- Adotados ícones vetoriais nativos `Icons.*_rounded` (em vez de emojis, que variam entre sistemas operacionais e comprometem a estética *Liquid Glass* / *Flat Clean*), encapsulados no widget reutilizável `CategoryIconBadge` (squircle com fundo translúcido na cor semântica).
- Curadoria de ~75+ ícones financeiros e cotidianos agrupados por domínio (`Alimentação`, `Casa`, `Transporte`, `Saúde`, `Compras`, `Lazer`, `Tecnologia`, `Educação`, `Finanças`, `Família & Pessoal`, `Outros`), com busca em português por sinônimos e paleta de 15 cores calibradas para Light e Dark mode.

### 2.3. Resolução em Cascata e Herança Pai → Subcategoria
A resolução visual (`CategoryIconRegistry.resolve`) segue a seguinte precedência:
1. **Transferências** (`xfer:` ou `isTransfer: true`): ícone `swap_horiz_rounded` em azul céu (ou `AccountLogoWidget` da conta destino no seletor `CategorySelectFormField`).
2. **Subcategorias (`parent != null`)**: herdam automaticamente o **ícone** e a **cor** da categoria principal por padrão, permitindo sobrescrever individualmente apenas o ícone, apenas a cor ou ambos.
3. **Categorias Principais (`parent == null`)**:
   - Se houver `icon` e/ou `color` salvos explicitamente, utiliza-os.
   - Caso contrário, aplica *auto-match* semântico pelo nome normalizado (sem acentos), garantindo que bases antigas exibam ícones instantaneamente sem migração.
   - Fallback neutro (`trending_up_rounded` esmeralda para Receitas; `label_outline_rounded` grafite para Despesas).

### 2.4. Pontos de Exibição Unificados
- **Inclusão e Edição:** `CategorySelectFormField` exibe `CategoryIconBadge` tanto no campo fechado quanto no menu suspenso (beneficiando Novo/Editar Lançamento, Lançamento Rápido, Conciliação OFX, Previsões e Investimentos).
- **Gestão:** `CategoriesView` exibe os badges na árvore de categorias e oferece prévia ao vivo + acesso ao `CategoryIconPickerDialog` ao criar/editar.
- **Lançamentos e Controle:** `DatagridTransactionTable`, `AllTransactionsView`, `AccountLedgerView`, `BudgetView`, `DueBillsView`, `InstallmentsView`, `GlobalSearchView` e `CategoryDrillDownModal`.

---

## 3. Consequências e Impacto

- **Zero atrito para usuários existentes:** Nenhuma ação manual ou migração destrutiva é necessária.
- **Consistência multiplataforma:** Renderização vetorial idêntica em macOS, Windows, Web e Mobile com custo de bundle zero.
- **Extensibilidade:** Novos ícones ou cores podem ser adicionados ao `CategoryIconRegistry` mantendo os IDs canônicos existentes.
