# ADR 013: Motor de Sincronização Granular por Registro em Tempo Real (Sync v2)

- **Status:** Aceito e Implementado (Web, Desktop macOS/Windows e Mobile Flutter & Swift — com Blindagem Anti-Wipe v2)
- **Data:** 2026-11-07 *(Atualizado em 2026-11-16 com Regras de Inicialização Segura e Anti-Wipe >10MB)*
- **Contexto:** OpenMoney Cloud (`functions/api/[[route]].js`, `cloudflare/sync-worker`, `lib/services/sync_engine.dart`)

---

## 1. Contexto e Problema (Por que o Sync v1 falhou)

No modelo anterior (Sync v1), cada alteração local disparava o envio do arquivo inteiro `openmoney.json` (`PUT /api/db`). Quando múltiplos dispositivos ou abas operavam simultaneamente ou ficavam temporariamente sem conexão:
1. Um dispositivo com estado antigo podia sobrescrever alterações feitas em outro aparelho (`force: true`), ou travar em erro `409 Conflict`.
2. Exigia botões manuais ("Baixar da Nuvem" / "Enviar para Nuvem") para resolver divergências.

---

## 2. Decisão Arquitetural (Sync v2)

Substituímos a sincronização de arquivo monolítico por um **Motor de Sincronização Granular por Registro em Tempo Real (`SyncEngine`)** com arquitetura **LSM (Base Snapshot + Log Incremental por Registro)** e **Zero Botões Manuais**:

1. **Granularidade por Registro (`coll` + `id`):**
   - Cada entidade é sincronizada individualmente:
     - `accounts/<id>`
     - `cats/<path>`
     - `txs/<id>`
     - `recs/<id>`
     - `budgets/<key>`
     - `comments/<key>`
     - `meta/predMode` e `meta/accountOrder`
     - `prefs/userPrefs`
   - Exclusões são propagadas como *tombstones* (`deleted: true, data: null`) com número de sequência monotônico (`seq`).

2. **Detecção Automática de Diffs + Fila Offline Persistente (`Outbox`):**
   - O `SyncEngine` mantém um mapa `_baseline` em memória (`"$coll/$id" -> jsonString`).
   - A cada `store.save()`, apenas os registros efetivamente inseridos, editados ou removidos entram na fila persistente `_outbox` (`localStorage`) e são enviados imediatamente em lote atômico (`POST /api/sync`) com chave de idempotência `opId`.
   - Ao receber deltas remotos (`applyChangesToDatabase`), o `_baseline` é atualizado simultaneamente e `store.onRemoteChangesApplied()` reconstrói saldos sem chamar `save()`, eliminando loops de eco.

3. **Tempo Real e Eficiência no Plano Gratuito da Cloudflare:**
   - **Tabelas D1 (`user_sync_meta`, `user_sync_records`, `user_sync_ops`):** Cada edição grava apenas os registros alterados criptografados com `AES-256-GCM` por usuário (`rec:v1:<iv>:<cipher>`), enquanto a compactação no snapshot principal (`user_databases`) e no backup diário (`user_database_backups`) roda em background via `context.waitUntil()` com 0ms de impacto na resposta.
   - **Durable Object (`UserSyncRoom`) + Canal Delta Adaptativo + `BroadcastChannel`:** Suporta WebSocket Hibernation (`new_sqlite_classes = ["UserSyncRoom"]`), sincronização instantânea entre abas via `BroadcastChannel` (0ms) e canal delta ultraleve (`GET /api/sync?since=<seq>`).

---

## 3. Rollout em Etapas

- **Etapa 1 (Homologado):** Ativação na versão **Web (`kIsWeb` em `OpenMoneyFlutter`)** em `https://openmoney.app.br`.
- **Etapa 2 (Em Produção — Ver [ADR 014](014-desktop-hybrid-sync-audit-and-safety-backups.md)):** Habilitação no **Flutter Desktop (macOS e Windows)** com arquitetura híbrida (Local ↔ Online), Welcome Screen, backups locais de segurança e logs de auditoria no D1.
- **Etapa 3 (Concluído — Ver [ADR 019](019-swift-cloud-sync-v2-parity.md)):** Paridade integral implementada no aplicativo nativo em Swift (**OpenMoneySwift macOS e iOS**), com operação híbrida nativa (`GzipHelper`, `CloudSyncService`, `SyncEngine`, `WelcomeDatabaseView`, `CloudAccountSheet`), compressão Gzip/zlib nativa, WebSockets via `URLSessionWebSocketTask` e alternância rápida Local ↔ Online, eliminando qualquer exceção ou assimetria funcional entre as stacks.

---

## 4. Regras de Inicialização Segura e Blindagem Anti-Wipe para Bases Grandes (>10MB)

Após análise de regressões pós-atualização em bases volumosas (`>10MB`), foram institucionalizadas as seguintes regras obrigatórias em ambas as stacks (Flutter e Swift) e no servidor Cloudflare D1:

1. **Inicialização Síncrona antes do Primeiro Frame (`main.dart`):**
   - `store.boot()` deve ser executado sincronamente antes de `runApp()` em todas as plataformas, evitando que a UI renderize ou dispare ações sobre um `Database()` transitório antes do carregamento da sessão e do cache.
2. **Tela de Carregamento Cloud Universal no Modo Online (`app_shell.dart`):**
   - Sempre que `store.isCloudMode && CloudSyncService.instance.isAuthenticated && !SyncEngine.instance.hasLoadedRemoteState`, Web, Desktop e Mobile exibem obrigatoriamente a tela `_buildCloudLoadingScreen`, bloqueando a exibição de tela zerada enquanto o snapshot binário Gzip é baixado.
3. **Retentativas no Pull Completo (`_pullFullSnapshotAndDeltas`):**
   - O download inicial do snapshot via `/api/db?format=binary` realiza até **3 tentativas** automáticas com backoff incremental (800ms, 1600ms) para tolerar instabilidades transitórias ou reinícios pós-update.
4. **Proibição de Deltas Antes do Snapshot Inicial (`_applyIncomingDelta` / `applyIncomingDelta`):**
   - Nenhuma alteração incremental pode ser aplicada nem promover `hasLoadedRemoteState = true` se o snapshot completo ainda não tiver sido carregado; nessa situação, o motor dispara `syncNow(forceFullPull: true)`.
5. **Rejeição de Cache Local Vazio Envenenado (`_isValidCloudCachePayload` / `isValidCloudCachePayload`):**
   - No `boot()` e em `switchToCloudMode()`, caches que contenham `txs.isEmpty` com apenas a conta padrão `'a1'` zerada quando `revision > 1` são rejeitados e apagados, garantindo download integral na nuvem.
6. **Barreira de 50 KB no Endpoint `PUT /api/db` para Bases Chunked (`functions/api/[[route]].js`):**
   - Como um `Database()` vazio serializado com as 66 categorias padrão (`kDefaultCats`) ocupa cerca de **4,2 KB** (acima do antigo teto de `2 KB`), o servidor passa a exigir **mínimo de 50 KB (`sizeBytes < 50000`)** para qualquer sobrescrita sem `force=true` explícito sobre bases armazenadas em blocos (`chunked:*`), bloqueando também qualquer requisição de compactação (`compactSeq`) `< 50 KB` com `HTTP 409`.
7. **Parada Compulsória do `SyncEngine` ao Desconectar Base Local (`disconnectLocalDatabase`):**
   - Ao desconectar uma base local, o `SyncEngine` é encerrado imediatamente (`stop()`), `showWelcomeScreen = true` e `isCloudMode` retorna `false` para impedir qualquer interação de sincronização sobre `db = Database()`.
