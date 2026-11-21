# ADR 030: Assistente Financeira Multi-Provedor com IA (Gemini, Claude, ChatGPT, Apple Intelligence e Siri) na Stack Única Flutter

**Status:** ✅ Aceito e Implementado  
**Data:** 20/11/2026  
**Escopo:** `OpenMoneyFlutter` (Desktop macOS/Windows, Web PWA, Mobile iOS/Android) e Cloudflare Pages Functions (`/api/ai/*`)

---

## 1. Contexto e Motivação

Embora o OpenMoney já contasse com extração de comprovantes via OCR nativo e Google Gemini Flash ([ADR 007](007-receipts-ocr-ai-import.md)), o usuário necessitava de uma **Assistente Financeira real e integrada** que entendesse os dados existentes na base (`openmoney.json` Schema `v: 7`), fosse simples de configurar/consumir e atuasse em quatro frentes principais:
1. **Lançar:** registrar despesas, receitas, compras parceladas, transferências, `#tags` e previsões por linguagem natural ou comando de voz (Siri / Atalhos), sempre com pré-visualização e confirmação em 1 clique.
2. **Ler Documentos:** interpretar comprovantes unitários, faturas de cartão em PDF/imagem e extratos, pareando itens já lançados (`reconcileExisting`) para evitar duplicidade ([ADR 027](027-ofx-bank-and-invoice-reconciliation.md)).
3. **Organizar:** identificar lançamentos sem categoria, possíveis duplicidades e aplicar edições em massa (`BatchTransactionEditPayload` da [ADR 023](023-tags-and-batch-transaction-editing.md)).
4. **Analisar e Explicar:** explicar nominalmente os aumentos em categorias (*Category Spikes* com os principais favorecidos responsáveis), radiografar faturas de cartão (à vista vs parcelado vs comprometimento futuro) e detectar assinaturas/recorrências implícitas e reajustes de preço.

---

## 2. Decisão de Arquitetura

### 2.1. Motor Determinístico Local (`FinancialInsightsEngine`) — Privacy-First & Zero-Token Base
Para garantir velocidade instantânea ($O(N)$ em memória), funcionamento 100% offline e privacidade (nunca enviando o arquivo `openmoney.json` bruto para provedores externos):
- **`explainCategorySpikes`:** compara cada categoria no mês de referência contra o mês anterior e a média trimestral na moeda base (`baseCurrency`), excluindo transferências, categorias ocultas de relatórios (`effectiveIncludeInReports == false`) e envelopes de previsão (`isPredictionPayee`). Identifica os **Top 5 Favorecidos Causadores** (`PayeeSpikeDriver`) e verifica estouro de `budgets` ([ADR 021](021-budget-limit-verification-on-transaction-entry.md)) e previsões `ESGOTADAS` ([ADR 020](020-predictions-management-view-and-zero-balance-retention.md)).
- **`analyzeCardInvoice`:** decompõe faturas por competência de vencimento (`ik`) em compras à vista, parcelamentos (`pt > 1`) e recorrências (`recId != null`), comparando com a média das 3 faturas anteriores e projetando o comprometimento já contratado para os 3 meses seguintes.
- **`detectImplicitRecurrences`:** varre os últimos 12 meses excluindo compras parceladas (`pt > 1`) e transferências, agrupando por favorecido normalizado e detectando ciclos periódicos (`weekly`, `biweekly`, `monthly`, `yearly`) e **reajustes de preço** (`hasPriceIncrease`).
- **`buildCompactContextSnapshot` & `executeLocalQuery`:** gera um resumo JSON compacto (< 4 KB) e permite consultas filtradas sob demanda (*tool-calling* local).

### 2.2. Modelo Híbrido de Consumo em 3 Níveis + Apple Intelligence (`AIAssistantService`)
Pensando na facilidade para o usuário final, o consumo de IA opera em 3 modos complementares:
1. **Nível 1 — BYOK Guiado Simples (`byok`):** suporte nativo a **Google Gemini**, **Anthropic Claude** e **OpenAI ChatGPT**, com teste de conexão em 1 clique e armazenamento estritamente local das chaves (`config.json` / `localStorage`, jamais sincronizadas no `openmoney.json`). Na Web, chamadas para Claude/OpenAI utilizam automaticamente o proxy anti-CORS no Cloudflare (`/api/ai/chat`).
2. **Nível 2 — Nuvem Gerenciada (`cloudManaged`):** usuários autenticados no OpenMoney Cloud podem utilizar chaves gerenciadas no Cloudflare Pages Functions (`AI_MANAGED_GEMINI_KEY`, `AI_MANAGED_ANTHROPIC_KEY`, `AI_MANAGED_OPENAI_KEY`) com controle atômico de cota diária por usuário (`AI_DAILY_LIMIT`, padrão de 25 consultas/dia) na tabela D1 `user_ai_usage` auto-provisionada pelo schema. O handshake é realizado via `GET /api/ai/capabilities`, informando ao cliente se o servidor possui capacidade gerenciada disponível (`managedAvailable: true`).
3. **Nível 3 — Modo "Sem Chave / Assinatura Externa" (`promptBridge`):** gera com 1 clique o pacote de contexto compacto + pergunta para ser colado diretamente no ChatGPT, Claude ou Gemini Web que o usuário já assina, e interpreta a resposta/JSON colado de volta em cartões de ação.
4. **Apple Intelligence On-Device (`FoundationModels`) & Siri (`AppIntents`):** nos Runners nativos do Flutter (`macos/Runner/MainFlutterWindow.swift` e `ios/Runner/AppDelegate.swift`), o canal `openmoney/apple_intelligence` conecta o app ao modelo local da Apple (`SystemLanguageModel` / `LanguageModelSession` no macOS 26+ / iOS 26+) e expõe `OpenMoneyAskAssistantIntent` para a Siri e Spotlight, além do URL Scheme `openmoney://?prompt=...` no `ShortcutUrlService`.

### 2.3. Confirmação Obrigatória em 1 Clique (`AIActionProposal`)
Toda alteração sugerida pela IA (`create_transaction`, `create_transfer`, `create_recurrence`, `batch_edit_transactions`, `create_prediction`, `set_budget`, `reconcile_document_items`) é renderizada como um cartão interativo no painel Copilot (`Cmd/Ctrl + J`), exibindo alerta preventivo de limite de gastos (ADR 021) e permitindo confirmar em 1 clique, editar no modal padrão ou descartar. Ao confirmar, a gravação no `MoneyStore` propaga-se em tempo real via **Cloud Sync v2**.

### 2.4. Chave Mestre de Ativação e Ocultação Global (`isAiAssistantEnabled`)
Para usuários que optam por não utilizar recursos de inteligência artificial, o sistema introduz a preferência persistida `isAiAssistantEnabled` no `MoneyStore`:
- Quando desativada em **Ajustes & Personalização**, o aplicativo oculta compulsoriamente todos os pontos de contato da Assistente:
  - Botão na barra superior (`AppShell`), atalhos de teclado (`Cmd/Ctrl + J`) e paleta de comandos.
  - Botões contextuais de análise em **Relatórios**, **Extrato de Contas**, **Faturas de Cartão**, **Contas a Pagar & Receber**, **Previsões** e **Leitura de Recibos/Comprovantes**.
  - O card de *Insights Financeiros com IA* no **Dashboard Geral** e sua respectiva opção de configuração.

### 2.5. Cache Reativo Desacoplado & Performance em Tempo Real (`AiInsightsCache`)
Para prevenir qualquer lentidão, congelamento da interface (*spinning wheel* do sistema) ou travamentos durante a digitação de mensagens no painel da Assistente:
- **Revisão de Dados $O(1)$ (`dataRevision`):** O `MoneyStore` mantém um contador atômico incremental que é atualizado exclusivamente em operações de escrita/mutação na base de dados (`saveTransaction`, `deleteTransaction`, `setAccount`, etc.).
- **`AiInsightsCache` com Debounce (1500ms):** As operações analíticas pesadas do `FinancialInsightsEngine` (`explainCategorySpikes`, `detectImplicitRecurrences`, `findOrganizationOpportunities`) são cacheadas reativamente e nunca recalculadas de forma síncrona dentro do método `build()` dos widgets. Quando a base é modificada, o cache aguarda um intervalo de 1500ms de inatividade antes de recomputar os diagnósticos em background.
- **Isolamento de Renderização:** O campo de texto do painel lateral e os blocos de mensagens utilizam `RepaintBoundary` e componentes leves de texto, garantindo digitação instantânea a 60/120 fps.

### 2.6. Deduplicação Inteligente com Filtro Anti-Falso-Positivo
Na auditoria de saneamento da base (`findOrganizationOpportunities`), a detecção de duplicidades foi blindada para prevenir falsos positivos em operações legítimas:
- **Exclusão de Lançamentos Conciliados:** Registros com `rec == true` já foram auditados e conferidos contra extratos bancários, sendo desconsiderados como duplicidades potenciais.
- **Exclusão de Parcelamentos e Antecipações:** Transações pertencentes a compras parceladas (`plan != null` ou `pn`/`pt` definidos) ou identificadas com termos de antecipação/parcela nas notas são ignoradas pelo detector de duplicidades, permitindo amortizações e compras parceladas no mesmo estabelecimento sem alertas indevidos.

### 2.7. Design Compacto, Tooltips e Prompt Bridge Condicional
- **Barra de Ações Rápidas sem Badges Poluídos:** Os botões superiores adotam formato de ícones compactos (`IconButton`) com tooltips informativos e discretos, eliminando rótulos longos que estouram o layout e removendo badges vermelhos intrusivos.
- **Barra "Prompt Bridge" Condicional:** Os atalhos rápidos de **Copiar Contexto** e **Colar Resposta** são exibidos no rodapé exclusivamente quando o usuário seleciona o **Modo Sem Chave**, mantendo o painel totalmente limpo nos modos BYOK e Nuvem Cloud.
- **Badge de Privacidade:** Etiqueta `Privado` reduzida e alinhada ao centro no cabeçalho do painel.

---

## 3. Verificação e Validação

- Suíte automatizada [`test/financial_insights_engine_test.dart`](../../test/financial_insights_engine_test.dart) validando cálculo de *Category Spikes*, análise de faturas, detecção de assinaturas implícitas com exclusão de parcelamentos, regras anti-falso-positivo em duplicidades, reconciliação de documentos sem duplicidade, parser de linguagem natural com `#tags` e renderização completa dos componentes de UI do painel lateral sem estouros.
- Sintaxe do backend Cloudflare validada via `node --check functions/api/[[route]].js`.
- Verificação estática com 0 erros via analisador Dart (`dart analyze`).
