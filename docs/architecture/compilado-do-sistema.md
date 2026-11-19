# Compilado de Engenharia, Regras de Negócio e Funcionalidades do OpenMoney

> **Schema da Base:** `v: 7` (Retrocompatível com a antiga stack Swift descontinuada na `v2.5.0` — ver [ADR 029](../adr/029-swift-deprecation-and-flutter-single-stack-unification.md))  
> **Stack Oficial Única:** **OpenMoney Flutter** (macOS, Windows, Web PWA e Mobile iOS/Android — Flutter/Dart + Cloudflare D1/Durable Objects)  
> **Governança:** Base de código única unificada para todas as plataformas em `/Users/fabiano/Developer/OpenMoneyFlutter`  
> **Licença:** MIT (Código Aberto)

---

## 1. Visão Geral e Filosofia do Sistema

O **OpenMoney** é um sistema financeiro pessoal e patrimonial de alta precisão contábil, inspirado nos conceitos do clássico *Microsoft Money 99*, modernizado com arquitetura multiplataforma reativa, sincronização granular em tempo real e design translúcido.

### Princípios Fundamentais
1. **Operação Híbrida Unificada (Modo Local ↔ Modo Online Cloud Sync v2):**
   - **Modo Local (100% Offline):** opera diretamente sobre um arquivo único `openmoney.json` armazenado no disco local ou em pastas sincronizadas pelo usuário (iCloud Drive, Dropbox, Google Drive, OneDrive), com gravação atômica (`.tmp` + `rename`) e *debounce* de 350ms.
   - **Modo Online (OpenMoney Cloud — Sync v2):** sincronização granular por registro em tempo real via Cloudflare D1 / Durable Objects (`WebSockets`) e `Outbox` offline resiliente, com criptografia `AES-256-GCM` por usuário (`HKDF-SHA256`), autenticação em duas etapas por código de 6 dígitos (Resend), snapshots binários Gzip, backups locais e em nuvem e **Anti-Wipe Guard em 3 camadas**.
2. **Precisão Financeira em Centavos Inteiros (`Int` / `int`) & Suporte Multi-Moeda:**
   - Todos os valores monetários (`amt`, `opening`, `budgets`, `minBalance`) são armazenados estritamente como inteiros na menor unidade da moeda da conta, eliminando erros de arredondamento de ponto flutuante binário (IEEE-754).
   - Suporte nativo a **11 moedas** (`BRL`, `USD`, `EUR`, `CAD`, `AUD`, `GBP`, `PYG`, `ARS`, `UYU`, `CHF`, `CLP`) com invariante canônico de câmbio histórico (`Transaction.rate` sempre normalizada de `moeda da conta → BRL`).
3. **Desempenho Extremo ($O(1)$) com Mais de 30.000 Lançamentos:**
   - Indexação em memória por conta e por competência (`cachedTxsByAccount`, `cachedMonthData`), busca textual diacrítico-insensível e persistência assíncrona não-bloqueante.
4. **Design System Liquid Glass & Personalização Completa:**
   - Superfícies translúcidas (*Liquid Glass* vs. *Flat Clean*), temas Claro/Escuro, **6 paletas de cor de destaque** (`sky`, `emerald`, `indigo`, `orange`, `cyan`, `slate`), barra lateral expansível ou compacta (*Mini Rail*) e extratos em **Lista Diária** ou **Datagrid Contínua**.

---

## 2. Modelagem de Dados e Estrutura dos Arquivos (Schema `v: 7`)

Referência completa no [Dicionário de Dados Completo](dicionario-de-dados.md).

### 2.1 Tipos de Conta Suportados (`ACCOUNT_TYPES` / `kAccountTypes`)
- `"Corrente"`: movimentação rotineira, transferências e pagamentos.
- `"Poupança"`: reservas de liquidez e aplicações de curto prazo.
- `"Cartão de crédito"` (`CARD_TYPE` / `kCardType`): gestão de limites, ciclo de fechamento/vencimento e faturas.
- `"Investimento"`: ativos financeiros, renda fixa/variável e aportes.
- `"Dinheiro"`: carteira física e pequenos gastos em espécie.

### 2.2 Raiz da Base (`Database`)
- `v: Int` (`7`): versão canônica do schema (Flutter `lib/models/openmoney_models.dart`).
- `accounts`: lista de contas (`Account`).
- `cats`: hierarquia de categorias e subcategorias (`CategoryItem`).
- `txs`: livro-razão de transações (`Transaction`).
- `recs`: regras de recorrência (`RecurrenceRule`).
- `budgets`: mapa `CategoryItem.path → Int` (teto mensal em centavos).
- `comments`: mapa `periodId → String` com anotações da linha *Saldo Final Acumulado* no Fluxo de Caixa (omitido quando vazio).
- `predMode`: `"month"` (padrão) ou `"invoice"` (regime de abatimento de previsões).
- `baseCurrency`: código ISO da moeda padrão de consolidação (`"BRL"` por padrão).
- `rates`: mapa `currencyCode → CurrencyRateInfo` (`rate`, `updatedAt`, `manual`, `source`).
- `tags`: catálogo global de etiquetas personalizadas (`List<String>`, omitido quando vazio).

### 2.3 Estruturas Principais
- **`Account`:** `id`, `name`, `type`, `opening`, `card` (`CardConfig?`), `invoices` (`[String: InvoiceInfo]?`), `inactive`, `favorite`, `business`, `bankCode`, `agency`, `accountNumber`, `comments`, `minBalance`, `logo`, `currency`.
- **`CardConfig` & `InvoiceInfo`:** `closeDay` (`1..31`), `dueDay` (`1..31`), `pay` (ID da conta corrente de débito); `InvoiceInfo` registra overrides manuais (`close`, `due`, `pay`, `manual`).
- **`Transaction`:** `id`, `acc`, `peer`, `date` (`YYYY-MM-DD`), `payee`, `cat`, `memo`, `amt` (centavos inteiros com sinal), `rec`, `xfer`, `auto`, `card`, `ik` (`YYYY-MM`), `inv` (`inv:{cardId}:{ik}`), `plan`, `pn`, `pt`, `recId`, `recFreq`, `recSeq`, `createdAt`, `rate` (`moeda da conta → BRL`), `tags`.
- **`RecurrenceRule`:** `id`, `acc`, `peer`, `start`, `freq` (`daily`, `weekly`, `biweekly`, `monthly`, `bimonthly`, `quarterly`, `semiannual`, `yearly`), `payee`, `cat`, `memo`, `amt`, `nextSeq`, `end` (nulo = tempo indeterminado).
- **`CategoryItem`:** `name`, `parent`, `type` (`"Despesa"` / `"Receita"`), `includeInReports`, `blocked` (oculta de novos lançamentos preservando histórico; bloqueio do pai propaga para subcategorias). Separador canônico: `SEP = " › "`.

### 2.4 Persistência Local de Sincronização e Cache (`Sync v2`)
- **Flutter Desktop / Mobile:** metadados leves (`seq`, `outbox`) em `sync_kv_store.json`; snapshots por usuário isolados em `cloud_cache/<key>.json` via escrita atômica (`.tmp.<pid>` + `renameSync`); credenciais/preferências em `config.json` (na Web, tudo utiliza `window.localStorage`).

---

## 3. Regras de Negócio e Governança Financeira

### 3.1 Gestão e Integridade de Contas
1. **Bloqueio Físico contra Exclusão de Contas com Lançamentos:** contas com `txCount > 0` **não podem ser excluídas**; o sistema oferece a desativação/arquivamento com 1 clique.
2. **Desativação (Arquivamento):** contas inativas mantêm o histórico integral em relatórios e fluxo de caixa, mas bloqueiam novos lançamentos e transferências.
3. **Exclusão Definitiva:** permitida apenas para contas com **0 lançamentos**, mediante confirmação expressa.
4. **Favoritar e Reordenar Contas:** contas favoritas são fixadas no topo da barra lateral e no card do Dashboard, seguindo a mesma ordem personalizada em todas as telas.

### 3.2 Cartão de Crédito e Ciclo de Faturas (`Schema v: 7`)
1. **Identificação da Fatura pelo Mês de Vencimento (`invKeyFor`):**
   - Calcula o mês base da fatura a partir do fechamento (`date.day <= closeDay` $\rightarrow$ mês corrente; `date.day > closeDay` $\rightarrow$ mês seguinte).
   - Quando **`dueDay <= closeDay`**, aplica a virada de competência (+1 mês via `addMonthsYM(k, 1)`), garantindo que a chave `ik` corresponda sempre ao **mês de vencimento** da fatura.
2. **Vigência de Faturas (`isVigenteInvoice`):**
   - Uma fatura é vigente se pertencer ao ciclo atualmente em aberto (`invoiceKey == currentOpenKey`) **ou** se estiver fechada dentro da janela regular de pagamento (`closeDate <= today && dueDate >= today`), eliminando falsos atrasos em Contas a Pagar.
3. **Seleção Manual de Fatura (Override) e Direcionamento Inteligente:**
   - O usuário pode sobrescrever manualmente `tx.ik` na inclusão ou edição.
   - Ao inserir ou navegar para lançamento em cartão, a tela posiciona a visualização no mês da fatura (`ik`); ao alternar entre cartão e conta bancária tradicional na barra lateral, ajusta adequadamente para a fatura aberta do cartão ou mês corrente da conta.
4. **Pagamento Parcial, Adiantamento e Conciliação Automática (`syncCards`):**
   - Pagamentos manuais parciais ou antecipados geram transferência para o cartão vinculada à competência `ik`.
   - `syncCards` consolida $\text{Charges} = \sum |\text{Despesas}|$ e $\text{Payments} = \sum \text{Pagamentos}$ do ciclo, mantendo de forma idempotente (`inv:{cardId}:{ik}`, `auto: true`, `ik`) uma transação automática no vencimento cobrando **apenas o saldo remanescente** — ou cancelando-a quando liquidada (badge verde **LIQUIDADA**).

### 3.3 Edição, Cópia, Movimentação entre Contas e Transferências
- **Copiar Lançamento como Novo (`TransactionCopySheet`):** preenche descrição (removendo sufixo de parcela `(x/y)`), categoria/transferência, nota e valor, inicializando a data com **hoje** e permitindo escolher conta, repetição e tags sem alterar o original (desabilitado para transações `auto == true`).
- **Mover Lançamento de Conta:** ajusta automaticamente `ik` ao mover para/de cartão de crédito, propaga para ocorrências futuras não conciliadas no escopo `.forward` e mantém íntegra a contraparte (`peer`) em transferências.
- **Transferências Espelhadas & Multi-Moeda:** débito e crédito vinculados pelo mesmo `xfer`; em contas de moedas distintas, permite edição bidirecional do valor convertido e da taxa efetiva, gravando a taxa histórica na operação.

### 3.4 Confirmações, Seleção Múltipla, Edição e Exclusão em Lote
- **Escopo em Séries (`ScopeChoice`):** *Apenas este*, *Este e todos os futuros não conciliados* ou *Toda a série*. Transações já conciliadas (`rec == true`) nunca são alteradas ou excluídas em edições em série.
- **Edição em Massa (`BatchTransactionEditPayload`):** na tela consolidada **Lançamentos**, seleção múltipla com aplicação seletiva de Nome/Favorecido, Categoria, Tags (`Adicionar`, `Substituir`, `Remover`), Notas, Valor (`Manter sinal`, `Forçar Despesa`, `Forçar Receita`), Data (recalculando `ik`), Conta e Conciliação. Transações `auto == true` são bloqueadas para seleção, e em transferências os campos de categoria, conta e valor são protegidos.
- **Exclusão em Lote:** tanto na seleção múltipla quanto no utilitário por Período/Conta (`BatchDeleteTransactionsSheet`), cria obrigatoriamente um **Backup de Segurança preventivo** antes de remover registros e registra o evento no log de auditoria (`AuditAction.batchEdit` / `AuditAction.batchDelete`).

### 3.5 Gestão Centralizada e Ajuste de Previsões Orçamentárias
- **Módulo Dedicado (`PredictionsManagementView`):** painel sob *Planejamento* com KPIs (Teto Previsto, Total Abatido, Saldo Remanescente, Quantidade), barras de progresso por categoria, drill-down dos lançamentos reais que consumiram o teto e botão **Restaurar Teto**.
- **Modos de Abatimento (`predMode`):**
  - `"month"` (padrão): abate gastos reais cuja data pertence ao mês alvo.
  - `"invoice"`: abate gastos bancários pela data no mês + gastos de cartão pela competência de vencimento da fatura (`ik`), avaliando janela estendida (`[M, M+1, M+2]`).
- **Memorização de Base & Retenção com Saldo Zerado:**
  - A base original é preservada no memo (`[Previsão base: R$ X,XX]`), garantindo idempotência em execuções repetidas de **Ajustar**.
  - Quando $\text{Base} - \text{Gastos} \le 0$, a previsão **não é excluída**: seu valor (`amt`) é atualizado para **`0` (R$ 0,00)** e recebe a tag visual **ESGOTADA**, preservando o histórico contábil (ADR 020).

### 3.6 Projeção Temporal Adaptativa de Recorrências (`syncRecs`)
- **Anual:** 5 anos (60 meses) | **Semestral:** 4 anos (48 meses) | **Trimestral:** 3 anos (36 meses) | **Bimestral/Mensal:** 2 anos (24 meses) | **Diário/Semanal/Quinzenal:** 1 ano (12 meses).
- Materialização sob demanda ao avançar no calendário e suporte integral a **Transferências Recorrentes** espelhadas.

### 3.7 Relatórios Analíticos vs. Fluxo de Caixa
- **Relatórios Mensais/Anuais (`ReportsView` / `iOSReportsTab`):** excluem estritamente transferências entre contas (`xfer != nil || peer != nil`), transações automáticas de fatura (`auto == true`) e categorias com `includeInReports == false`. Suportam filtros por contas/negócios, status de conciliação e **Tag** (`#tag`).
- **Fluxo de Caixa Matricial (`CashFlowEngine`):** apura rigorosamente $\text{Saldo Anterior Acumulado} + \text{Rendimento} - \text{Despesas} = \text{Saldo Final Acumulado}$, suprimindo apenas transferências internas *entre as contas incluídas no filtro ativo* (para conciliar corretamente grupos ou contas individuais) e suportando anotações por período (`comments`).

### 3.8 Verificação Ativa de Limite de Gastos (`checkBudgetExceeded`)
- Ao registrar uma despesa real (`amt < 0`, não-transferência e não-previsão) nos modais de criação/cópia ou barra rápida, o sistema soma os gastos reais do mês na moeda base (incluindo impacto da 1ª parcela em parcelamentos e herdando o teto da categoria pai caso a subcategoria não tenha limite próprio) e exibe alerta detalhado caso o teto em `db.budgets` seja ultrapassado, permitindo **Cancelar** ou **Continuar** (ADR 021).

### 3.9 Multi-Moeda, Câmbio em Transferências e Cotações Históricas
- Atualização diária automática via AwesomeAPI (no máximo 1 vez a cada 24h e apenas se houver conta estrangeira ativa, respeitando taxas marcadas como `manual: true`).
- Prioridade de resolução histórica (`resolveDefaultRateToBrl`) para lançamentos em conta estrangeira:
  1. Taxa efetiva da última transferência de câmbio na conta até a data da compra (`lastTransferRateForAccount`).
  2. Consulta oficial histórica no **Banco Central do Brasil (Olinda PTAX)** com janela de 7 dias anteriores para fins de semana/feriados e fallback **AwesomeAPI diária**.
  3. Cotação corrente de `db.rates`.
- Ferramenta **Corrigir Passados** em *Ajustes & Personalização → Moedas & Cotações* para atualizar em lote transações antigas com cotações históricas da época, e subtotais `≈` históricos nos cards de relatórios filtrados por moeda estrangeira (ADR 018).

### 3.10 Inicialização Segura e Blindagem Anti-Wipe em 3 Camadas (Sync v2 `>10MB`)
1. `store.boot()` executa sincronamente antes do primeiro frame; no Modo Online, enquanto `!hasLoadedRemoteState`, a UI exibe a tela de carregamento Cloud (nunca tela zerada).
2. Caches locais vazios (`txs.isEmpty` e conta `'a1'` zerada) para contas com `revision > 1` são descartados automaticamente no boot, disparando `forceFullPull: true` com até **3 retentativas**.
3. Deltas recebidos antes da carga do snapshot (`applyIncomingDelta`) não promovem estado carregado; `_isSuspiciousEmptyDb` bloqueia gravações/compactações vazias no cliente (`SyncEngine` / `CloudSyncService`); `disconnectLocalDatabase()` para obrigatoriamente o `SyncEngine`; e o backend Cloudflare (`PUT /api/db`) rejeita com `HTTP 409` payloads e `compactSeq` `< 50 KB` sobre bases `chunked:*` sem `force=true`.

---

## 4. Funcionalidades Detalhadas por Módulo

- **Dashboard Geral (`DashboardOverviewView`):** grid responsivo (1 a 3 colunas alinhadas pelo topo) com reordenação por setas e ativação configurável dos cards: **Patrimônio Consolidado** (privacidade isolada por card), **Contas Bancárias**, **Investimentos & Poupança**, **A Pagar**, **A Receber**, **Faturas de Cartão** (total + conciliado), **Gastos por Categoria** e **Ações Rápidas**.
- **Extrato da Conta (`AccountLedger`):** barra rápida configurável (pode ser ocultada em *Ajustes*, exibindo botão circular `+` no cabeçalho), autocompletar preditivo de favorecidos, seletor rápido de mês/ano (`MonthYearQuickPicker`), alternância **Lista Diária vs. Datagrid**, ordenação crescente/decrescente pelo cabeçalho **DIA**, conciliação em 1 clique e geração de **Fatura PDF** / **Extrato PDF** em A4.
- **Lançamentos Consolidados (`AllTransactionsView` / `iOSTransactionsTab`):** visão unificada de todas as contas com filtro temporal **Dia (padrão Hoje) / Mês / Ano**, toggle **Por Data do Lançamento vs. Por Fatura/Pagamento**, filtros combináveis (**Conta**, **Categoria**, **Tag**, **Tipo**, **Conciliação**, **Busca**), seleção múltipla e edição/exclusão em lote, cabeçalho recolhível no mobile e exportação CSV/PDF.
- **Pesquisa Global (`Cmd + Shift + F`):** busca simultânea em descrição, categoria, observação, tag e valor com navegação direta ao registro e destaque visual.
- **Contas a Pagar & Receber (`DueBillsView` / `NotificationManager`):** janela configurável (padrão 3 dias), classificação (`ATRASADO`, `HOJE`, `EM X DIAS`), notificações locais nativas no macOS/iOS às 08:30 e badge no ícone do app.
- **Categorias & Tags (`CategoriesView`, `TagsView`):** árvore de 2 níveis, bloqueio de categorias, prevenção de exclusão em uso com substituição assistida, catálogo de `#tags` com renomeação/exclusão em massa e modal de detalhamento unificado (`CategoryTransactionsDetailSheet` / `CategoryDrillDownDialog`) com filtro de conciliação e botão compacto de CSV (ADR 023 e ADR 024).
- **Fluxo de Caixa (`CashFlowView`) & Relatórios (`ReportsView`):** escalas diária/mensal/trimestral/semestral/anual, filtro multiconta e por Negócio (`PF`/`PJ`), comentários por período, exportação CSV UTF-8 com BOM e PDF mensal/anual em 1 página A4.
- **Importação & Exportação (CSV, QIF, OCR & Coletor Mobile):**
  - Central CSV (`17 colunas` com suporte a faturas `MM/AAAA`, tags, status de contas e multi-moeda) e QIF (Money 99 / CP1252) com pré-criação/inferência automática de contas e controle de duplicidade.
  - Importação em lote de recibos via OCR nativo (`Apple Vision` / `PDFKit` no macOS e `Windows.Media.Ocr` no Windows) + **Google Gemini Flash Multimodal (BYOK)** com conferência em Split View e arquivamento em `processados/`.
  - **OpenMoney Coletor PWA** (`https://fsf77.github.io/openmoney-new/coletor/`): entrada offline no celular, OCR local em WebAssembly, resolução de contas em 4 níveis para Atalhos do iOS / Apple Wallet e importação revisada via `openmoney_inbox.json` (`Cmd + Option + M`).
- **Central de Ajustes & Personalização (`SettingsView`):** tela inicial, widgets e filtros do dashboard, ordenação padrão, exibição da barra inline, aparência/paletas, zoom, densidade, *Moedas & Cotações* (incluindo *Corrigir Passados*) e chave Gemini BYOK.
- **Backups (`BackupManager`), Logs (`AuditLogManager`) e Auto-Update:** backups diários `.zip` locais (7+ dias) + 15 dias na nuvem, logs sincronizados em `user_audit_logs` (30 dias) e atualização automática pela internet no Desktop.

---

## 5. Atalhos de Teclado Principais (Desktop)

| Atalho | Ação |
|---|---|
| `Cmd + K` / `Ctrl + K` | Command Palette (busca e navegação rápida no Flutter) |
| `Cmd + ,` / `Ctrl + ,` | Abrir Ajustes & Personalização |
| `Cmd + Shift + F` | Pesquisa Global em toda a base de dados |
| `Cmd + Option + 1..5` | Fluxo de Caixa (`1`), Relatórios (`2`), Limite de Gastos (`3`), Categorias (`4`), Vencimentos (`5`) |
| `Cmd + Option + I` | Central de Importação / Exportação CSV |
| `Cmd + Option + M` | Importar lançamentos do celular (`openmoney_inbox.json`) |
| `Cmd + Shift + B` | Histórico de Backups de Segurança |
| `Cmd + Shift + Q` | Importar arquivo QIF (Microsoft Money 99) |
| `Cmd + Shift + E` | Exportar backup completo (`.zip` / `.json`) |
| `Cmd + N` / `Cmd + O` / `Cmd + Shift + M` | Nova base local / Abrir base / Mover base |
| `Cmd + P` / `Cmd + ?` | Imprimir / Exportar PDF e Ajuda integrada (`README.md`) |

---

## 6. Procedimentos de Build e Publicação (OpenMoney Flutter)

### OpenMoney Flutter (`/Users/fabiano/Developer/OpenMoneyFlutter`)
- **Testes e análise estática:** `flutter analyze` e `flutter test`.
- **macOS e Web (publicar release):** `./scripts/publish_release_macos.sh [VERSÃO] ["Notas da Versão"]` (incrementa build no `pubspec.yaml`, compila macOS release e `web-dist/`, sincroniza `version.json` e envia para `FSF77/openmoney-new`).
- **Windows (encadeado após o macOS):** `scripts\publish_release_windows.bat` (puxa versão/notas do macOS via `git pull origin main`, compila binário Windows, atualiza `version.json` e faz push da tag `v${VERSION}-windows`).
