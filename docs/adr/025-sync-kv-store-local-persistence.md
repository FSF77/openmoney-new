# ADR 025: Persistência Local do Key-Value Store de Sincronização (sync_kv_store.json) e Paridade Multiplataforma

- **Status:** ✅ Aceito, Implementado e Reforçado (Flutter macOS, Windows, Web, Mobile & Paridade Swift)  
- **Data:** 15 de Novembro de 2026 *(Revisão de Blindagem & Isolamento de Cache: 16 de Novembro de 2026)*  
- **Contexto:** Ecossistema OpenMoney Multi-Stack (`OpenMoneyFlutter/lib/services/platform_io_native.dart`, `sync_engine.dart`, `cloud_sync_service.dart`, `OpenMoneySwift/Sources/OpenMoney/SyncEngine.swift`)  
- **Decisores:** Tech Lead / Arquitetura OpenMoney  
- **Severidade:** 🟢 Arquitetura de Dados / Sincronização / Resiliência Offline / Anti-Wipe  

---

## 1. Contexto e Motivação

O ecossistema **OpenMoney** suporta operação híbrida integral: trabalho 100% offline sobre arquivo local (`openmoney.json`) ou operação online em nuvem com sincronização granular em tempo real (**Sync v2**) via Cloudflare D1 e Durable Objects ([ADR 013](013-realtime-record-sync.md), [ADR 014](014-desktop-hybrid-sync-audit-and-safety-backups.md) e [ADR 019](019-swift-cloud-sync-v2-parity.md)).

No modo online, o motor de sincronização precisa manter metadados essenciais e voláteis de forma persistente:
1. O identificador sequencial da última alteração recebida da nuvem (`lastSeq`), para viabilizar consultas incrementais ultrarrápidas (`GET /api/sync?since=<lastSeq>`) sem transferir o banco de dados inteiro;
2. A fila de alterações pendentes geradas enquanto o usuário estava offline (`outbox`), para garantir que nenhuma transação seja perdida caso o app seja fechado antes da conexão restabelecer;
3. O cache local do snapshot dos dados da nuvem (`cache`), viabilizando inicialização *offline-first* imediata;
4. As credenciais e tokens da sessão ativa (`sync_session`) e o catálogo de contas salvas no dispositivo (`saved_accounts`).

### O Desafio Multiplataforma no Flutter

No **Flutter Web**, o motor utiliza nativamente a API síncrona `window.localStorage` do navegador para armazenar esses pares chave-valor.

Entretanto, em plataformas nativas de Desktop (macOS, Windows, Linux) e Mobile (iOS, Android), a API `window.localStorage` inexiste. A adoção de plugins externos tradicionais (como `shared_preferences`) introduziria:
- Dependência de *platform channels* nativos e vinculação de pods/plugins adicionais no projeto nativo;
- Assincronia desnecessária em leituras críticas de inicialização;
- Risco de regressão entre plataformas e quebra da premissa de zero dependências externas supérfluas.

---

## 2. Decisão Arquitetural: Arquitetura em Duas Camadas (`sync_kv_store.json` + `cloud_cache/`)

Para fornecer uma interface uniforme `webLocalStorageGet`, `webLocalStorageSet` e `webLocalStorageRemove` em todas as plataformas sem qualquer dependência externa, a camada nativa em `platform_io_native.dart` separa estritamente os metadados leves dos snapshots volumosos (`>10MB`):

### 2.1. Localização Canônica por Plataforma

Os arquivos residem no diretório de dados de suporte do aplicativo (`OpenMoneyNew`):

| Sistema Operacional | Diretório Base | Arquivos Gerenciados |
| :--- | :--- | :--- |
| **macOS** | `~/Library/Application Support/OpenMoneyNew/` | `sync_kv_store.json` + `cloud_cache/<key>.json` |
| **Windows** | `%APPDATA%\OpenMoneyNew\` | `sync_kv_store.json` + `cloud_cache\<key>.json` |
| **iOS** | `~/Documents/OpenMoneyNew/` | `sync_kv_store.json` + `cloud_cache/<key>.json` |
| **Linux** | `~/.local/share/OpenMoneyNew/` | `sync_kv_store.json` + `cloud_cache/<key>.json` |

---

### 2.2. Chaves e Dados Armazenados

O arquivo leve `sync_kv_store.json` armazena um mapa JSON compacto `Map<String, String>` apenas para os ponteiros de sequência e fila offline:

```json
{
  "openmoney_sync_seq_v2_<userId>": "482",
  "openmoney_sync_outbox_v2_<userId>": "[{\"coll\":\"txs\",\"id\":\"uuid-1\",\"data\":{...},\"seq\":0}]"
}
```

Já o snapshot de base por usuário (`openmoney_web_cache_<userId>`) é isolado em `cloud_cache/openmoney_web_cache_<userId>.json`.

#### Segregação de Responsabilidades e Migração Automática:

1. **`openmoney_sync_seq_v2_<userId>` (Sequencial de Sync — em `sync_kv_store.json`):**
   - Armazena o valor inteiro monotônico `lastSeq` da conta conectada.
   - **Utilidade:** Permite ao `SyncEngine` solicitar ao Cloudflare Worker apenas deltas gerados após aquele momento (`GET /api/sync?since=<seq>`). Se não houver cache válido, o sequencial é zerado forçando um pull completo do snapshot binário gzip.

2. **`openmoney_sync_outbox_v2_<userId>` (Fila Offline Resiliente — em `sync_kv_store.json`):**
   - Armazena a lista serializada de `SyncChange` (inserções, edições, tombstones de deleção) criadas localmente e pendentes de envio.
   - **Utilidade:** Garante integridade absoluta de dados (*zero data loss*). Se o usuário criar ou editar lançamentos sem rede e fechar o aplicativo, a fila persiste intacta e é despachada automaticamente (`POST /api/sync`) ao reconectar.

3. **`openmoney_web_cache_<userId>` e `openmoney_web_guest_db` (Caches Volumosos `>10MB` — isolados em `cloud_cache/`):**
   - Snapshots de dados do usuário (`payload`) e preferências visuais (`preferences`) **não** são gravados no `sync_kv_store.json`, mas em arquivos dedicados em `cloud_cache/<key>.json`.
   - **Migração Automática:** Durante `_ensureNativeKvLoaded()`, eventuais chaves `openmoney_web_cache_*` legadas ainda presentes no `sync_kv_store.json` são automaticamente migradas para `cloud_cache/` e removidas do índice leve, mantendo o `sync_kv_store.json` abaixo de 1 KB.

4. **Sessão e Contas Salvas (`config.json` / Web `localStorage`):**
   - No Desktop/Mobile, credenciais de autenticação (`cloudAuthToken`, `cloudUserId`, `cloudUserEmail`), catálogo `cloudSavedAccounts` e última base local (`lastLocalDbPath`) residem em `config.json` (verificado sincronamente antes do `runApp()`). Na Web, utilizam `localStorage`.

---

### 2.3. Gravação Estritamente Atômica (Proteção Durante Atualizações)

Para impedir truncamento ou corrupção caso o processo seja encerrado abruptamente durante atualizações (`UpdateService` executando `exit(0)` ou scripts `install.sh` / reinício do app):
1. **Carregamento em Memória (`_ensureNativeKvLoaded`):** Os metadados leves do `sync_kv_store.json` são carregados em mapa `_nativeKvCache` em memória ($O(1)$), enquanto caches volumosos em `cloud_cache/` são lidos diretamente de seu arquivo exclusivo sob demanda.
2. **Escrita Temporária + Rename Atômico (`_atomicWriteStringSync`):** Tanto `_flushNativeKv()` quanto os arquivos individuais em `cloud_cache/` escrevem primeiro em `<caminho>.tmp.<pid>` com `flush: true` e substituem o arquivo final via `renameSync` atômico.
3. **Isolamento de Falhas:** Uma interrupção durante a gravação de um snapshot de `>10MB` jamais corrompe o `sync_kv_store.json` (`seq` e `outbox`) nem os caches de outras contas.

---

## 3. Regras de Validação de Cache e Blindagem Anti-Wipe em 3 Camadas

Para eliminar o risco de abertura zerada (*blank screen*) após atualizações e impedir que uma base vazia substitua a base online:

1. **Inicialização Síncrona (`main.dart`) e Tela de Carregamento Cloud (`app_shell.dart`):**
   - `store.boot()` roda sincronamente antes de `runApp()` em todas as plataformas.
   - Enquanto `store.isCloudMode && CloudSyncService.instance.isAuthenticated && !SyncEngine.instance.hasLoadedRemoteState`, todas as plataformas (Web, Desktop e Mobile) exibem `_buildCloudLoadingScreen`, nunca permitindo interação ou exibição sobre uma base vazia transitória.
2. **Rejeição de Cache Vazio Envenenado (`_isValidCloudCachePayload`):**
   - No `boot()` e em `switchToCloudMode()`, se o cache local carregar `txs.isEmpty` com conta padrão `'a1'` zerada enquanto `revision > 1`, o cache é descartado e removido, forçando o `SyncEngine` a executar `forceFullPull: true` com até **3 retentativas** automáticas em `_pullFullSnapshotAndDeltas()`.
3. **Guarda de Pré-Carga em Deltas (`_applyIncomingDelta`) e Bloqueio `_isSuspiciousEmptyDb`:**
   - `_applyIncomingDelta` nunca aplica deltas nem marca `_hasLoadedRemoteState = true` antes do carregamento completo do snapshot inicial; dispara `syncNow(forceFullPull: true)`.
   - `_persistLocalCache()`, `onLocalSave()` e `_scheduleClientCompaction()` são bloqueados pelo `_isSuspiciousEmptyDb` sempre que `db.txs.isEmpty` com `revision > 1` ou `_baseline` contendo transações (`txs/*`).
   - `disconnectLocalDatabase()` interrompe obrigatoriamente `SyncEngine.instance.stop()` e desativa `isCloudMode` (respeitando `showWelcomeScreen`).
4. **Barreira Anti-Wipe no Cliente REST e Backend Cloudflare D1 (`PUT /api/db`):**
   - `CloudSyncService.pushDatabase()` bloqueia qualquer envio não forçado (`!force`) com `txs` vazio quando `revision > 1`.
   - O endpoint `PUT /api/db` em `functions/api/[[route]].js` rejeita com `HTTP 409` qualquer payload `< 50 KB` (`sizeBytes < 50000`) sobre bases armazenadas em blocos (`chunked:*`) sem `force=true` explícito — e bloqueia também compactações (`compactSeq`) `< 50 KB` sobre bases `chunked:*` (pois um `Database()` vazio com as 66 categorias padrão ocupa ~4,2 KB e antes passava pela barreira legada de `2 KB`).

---

## 4. Equivalência e Paridade com o OpenMoney Swift

Em conformidade com a diretriz inegociável de **Equivalência Funcional Estrita**, a stack nativa em **Swift** (`OpenMoneySwift`) executa exatamente a mesma arquitetura de isolamento atômico e as mesmas travas anti-wipe em `Store.swift` e `SyncEngine.swift`:

| Finalidade do Dado | Flutter Desktop / Mobile (`OpenMoneyNew/`) | Swift macOS / iOS (`~/Library/Application Support/OpenMoney/`) |
| :--- | :--- | :--- |
| **Sequencial (`lastSeq`)** | Chave `openmoney_sync_seq_v2_<userId>` em `sync_kv_store.json` | Arquivo atômico `cloud_sync/seq_<userId>.txt` |
| **Fila Offline (`outbox`)** | Chave `openmoney_sync_outbox_v2_<userId>` em `sync_kv_store.json` | Arquivo atômico `cloud_sync/outbox_<userId>.json` |
| **Cache Local do Banco** | Arquivo isolado `cloud_cache/openmoney_web_cache_<userId>.json` | Arquivo atômico `cloud_sync/cache_<userId>.json` |
| **Sessão / Contas Salvas** | `config.json` (Desktop/Mobile) / `localStorage` (Web) | `config.json` central de configuração |
| **Validação Anti-Wipe** | `_isValidCloudCachePayload` + `_isSuspiciousEmptyDb` + D1 `50 KB` | `isValidCloudCachePayload` + `isSuspiciousEmptyDb` + D1 `50 KB` |

Ambas as abordagens oferecem exatamente os mesmos comportamentos:
- Isolamento total por `userId` (permitindo múltiplos usuários na mesma máquina sem colisão);
- Persistência e reenvio transparente de mutações criadas offline;
- Limpeza segura do cache (`removeLocalCache`) e descarte automático em caso de cache envenenado.

---

## 5. Conclusão e Benefícios

1. **Portabilidade Universal:** O código do `SyncEngine` e do `CloudSyncService` do Flutter opera com a mesmíssima interface chave-valor na Web, macOS, Windows e iOS.
2. **Escalabilidade para Bases Grandes (`>10MB`):** A segregação em `cloud_cache/` com escrita atômica `.tmp + rename` mantém o I/O rápido e imune a truncamentos durante atualizações.
3. **Blindagem Completa Zero Data Loss:** A combinação de cache isolado, rejeição de cache vazio, guarda em deltas e barreira de `50 KB` no Cloudflare D1 impede abertura zerada e sobrescrita acidental na nuvem.
