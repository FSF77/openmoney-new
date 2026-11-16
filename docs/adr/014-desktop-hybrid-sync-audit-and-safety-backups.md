# ADR 014: Arquitetura Híbrida Desktop (Local ↔ Nuvem), Backups de Segurança Locais e Logs de Auditoria Online

- **Status:** Aceito (Implementado e Homologado no Flutter Desktop macOS, Windows e Web)
- **Data:** 2026-11-08
- **Contexto:** Ecossistema OpenMoney (`OpenMoneyFlutter`, `Cloudflare D1`, `Pages Functions`, `AuditLogManager`, `BackupManager`, `SyncEngine`)

---

## 1. Contexto e Problema

Com a homologação bem-sucedida do motor **Sync v2 (Sincronização em Tempo Real por Registro)** na versão Web ([ADR 013](013-realtime-record-sync.md)), tornou-se necessário estender essa capacidade para os aplicativos instalados no computador (**Flutter Desktop macOS e Windows**). 

Entretanto, a transição para o desktop exigia resolver desafios arquiteturais críticos:

1. **Liberdade de Escolha (Operação Híbrida):** O usuário deve poder escolher manter bases puramente locais (em disco ou pastas de sincronização como iCloud Drive/Dropbox) ou conectar-se à nuvem, podendo alternar entre elas de forma transparente.
2. **Boas-Vindas no Primeiro Acesso:** Se o aplicativo for aberto pela primeira vez sem base configurada, deve apresentar uma interface clara para criar base local, abrir base local existente ou conectar/criar conta na nuvem.
3. **Vulnerabilidade de Backup em Modo Online:** Em modo nuvem, o identificador de base passa a ser `cloud://usuario@dominio.com`. A rotina anterior de backups (`BackupManager`) exigia um arquivo físico local em disco (`File(dbPath).existsSync()`), falhando e retornando erro ao tentar criar backups manuais no desktop para contas online, e deixando o usuário sem cópias locais de segurança em sua máquina.
4. **Logs de Auditoria Invisíveis em Nuvem:** O `AuditLogManager` gravava apenas em arquivos `.log` no sistema de arquivos local. No modo online e na Web, as alterações financeiras deixavam de ser auditadas no banco de dados e o histórico ficava vazio.
5. **Segurança de Identidade e Integridade de Dados:** A criação de contas online, alteração de e-mail e redefinição de senha exigiam validação por código numérico de 6 dígitos enviado por e-mail, e a exclusão da base ou da conta precisava de confirmação de segurança com envio preventivo e irreversível do backup `.zip` para a caixa de entrada do usuário.

---

## 2. Decisões Arquiteturais

### 2.1. Seletor Simples Local ↔ Online no Menu Lateral

No rodapé da barra lateral de navegação (`OpenMoneyAppShell`), foi incorporado um componente de alternância rápida de 2 posições:

```
┌────────────────────────────────────────┐
│  [ 💻 Local ]      [ ☁️ Online ]       │
└────────────────────────────────────────┘
```

- **Pílula "Local":** Ativa o modo de arquivo tradicional do disco (`openmoney.json`). Se não houver base local configurada, abre imediatamente o modal de gerenciamento para abrir ou criar base local.
- **Pílula "Online":** Ativa o modo de nuvem em tempo real com `SyncEngine v2`. Se não estiver autenticado, abre a tela de login/cadastro de conta online.
- **Isolamento de Estado:** A alternância cancela watchers de arquivo em disco, preserva o caminho da última base local (`lastLocalDbPath`) no `config.json` e inicializa o motor de sincronização correto com zero perda de dados.

---

### 2.2. Tela de Primeiro Acesso (`WelcomeDatabaseSelectionScreen`)

Quando o aplicativo é iniciado pela primeira vez ou sem base ativa configurada, é exibida uma tela centralizada que orienta o usuário:

1. **Base Local no Computador:**
   - *Abrir base local existente (.json):* Localiza arquivos no Finder/Explorer, iCloud Drive ou OneDrive.
   - *Criar nova base local vazia:* Escolhe o local e cria um `openmoney.json` limpo já com as categorias padrão sugeridas.
2. **OpenMoney Cloud (Sincronização em Tempo Real):**
   - *Conectar em Conta Online ou Criar Nova Conta:* Abre o modal de autenticação em 2 etapas. Ao criar conta nova limpa, as categorias sugeridas do sistema são geradas automaticamente e enviadas ao servidor.

---

### 2.3. Backups de Segurança Locais Invioláveis para Bases na Nuvem

Mesmo que o usuário utilize exclusivamente uma conta online na nuvem, o aplicativo desktop passa a gerar **cópias de segurança compactadas (.zip) diretamente no disco rígido do computador**:

1. **Compactação a partir de Bytes/Memória (`createZipArchiveFromBytes`):**
   - O `BackupManager` recebeu suporte nativo para gerar arquivos `.zip` tanto de arquivos físicos quanto de buffers em memória (`jsonContent`).
   - No macOS, utiliza `/usr/bin/zip` nativo via diretório temporário para máxima velocidade e integridade. No Windows e Linux, utiliza o pacote multiplataforma `archive` com codificação `ZipEncoder`.

2. **Nomenclatura Canônica dos Backups Cloud no Desktop:**
   - **Backup Diário Automático:**
     `openmoney-cloud-[email]-backup-[YYYY-MM-DD].zip`
   - **Backup Manual Pontual:**
     `openmoney-cloud-[email]-manual-[YYYY-MM-DD_HHmmss].zip`
   - **Local de Armazenamento:**
     - macOS: `~/Library/Application Support/OpenMoney/Backups/`
     - Windows: `%APPDATA%\OpenMoney\Backups\`

3. **Backup Diário Automático ao Acessar o App (`ensureDailyLocalBackup`):**
   - É disparado na inicialização (`boot`), após sincronização do snapshot remoto (`onRemoteChangesApplied` / `syncFromCloud`) e ao alternar para o modo online.
   - **Otimização de Performance:** Verifica se o backup do dia já existe e possui tamanho válido (> 200 bytes), retornando instantaneamente (< 1ms) sem operações desnecessárias de disco.

4. **Restauração Transparente:**
   - Ao selecionar qualquer backup `.zip` da lista no desktop e clicar em "Restaurar", se a aplicação estiver em modo Cloud, a base é extraída e enviada com substituição autorizada para a nuvem via `pushLocalToCloud(force: true)`, sincronizando todos os outros dispositivos automaticamente.

---

### 2.4. Logs de Auditoria e Alterações no Banco Online (Cloudflare D1)

Os logs de auditoria foram equalizados para operar de forma idêntica e centralizada na nuvem:

1. **Tabela `user_audit_logs` no Cloudflare D1:**
   ```sql
   CREATE TABLE IF NOT EXISTS user_audit_logs (
     id TEXT PRIMARY KEY,
     user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
     action TEXT NOT NULL,
     entity TEXT NOT NULL,
     target_id TEXT,
     summary TEXT NOT NULL,
     details TEXT,
     created_at TEXT NOT NULL
   );
   CREATE INDEX IF NOT EXISTS idx_audit_user_created ON user_audit_logs(user_id, created_at DESC);
   ```

2. **Endpoints da API (`functions/api/[[route]].js`):**
   - `POST /api/audit-logs`: Grava registros de auditoria em lote para o usuário autenticado e expurga registros com mais de 30 dias automaticamente (política de retenção de segurança).
   - `GET /api/audit-logs?limit=500`: Retorna os registros cronológicos do usuário mais recentes.

3. **Buffer e Flush Assíncrono com Debounce de 400ms:**
   - Ao criar, editar ou excluir lançamentos, contas ou categorias, o `AuditLogManager` enfileira a entrada em `_pendingCloudLogs` e dispara um timer de 400ms. Múltiplas edições rápidas são combinadas em uma única requisição HTTP atômica, sem bloquear a interface gráfica.

4. **Dual-Write no Desktop e Interface Adaptativa:**
   - No Desktop, o log é gravado no D1 e espelhado no arquivo físico `openmoney-cloud-[email].log` em `~/Library/Application Support/OpenMoney/AuditLogs/`.
   - No modal `_AuditLogsDialog`, a versão Web omite os botões de arquivo local ("Abrir Arquivo .log" e "Revelar no Finder"), exibindo apenas a contagem de registros e o botão "Fechar". A versão Desktop mantém os atalhos para exploração física do arquivo.

---

### 2.5. Protocolo de Confirmação por Código de 6 Dígitos e Exclusão Segura

1. **Tokens Temporários com Resend (`email_verification_tokens`):**
   - **Novo Cadastro:** O registro agora ocorre em 2 etapas (`POST /api/auth/register-request` e `POST /api/auth/register-confirm`). O código de 6 dígitos expira em 15 minutos e é autenticado via hash com o segredo mestre.
   - **Alteração de E-mail:** Requer envio de código de 6 dígitos para o novo endereço pretendido antes da efetivação no banco (`/api/auth/change-email-request` e `/api/auth/change-email-confirm`).
   - **Redefinição de Senha:** Código numérico de uso único de 6 dígitos com expiração estrita.

2. **Exclusão Segura com Envio de Backup Preventivo por E-mail:**
   - A exclusão da base ou da conta exige a digitação da palavra de segurança `"EXCLUIR"`.
   - Antes de realizar a deleção no banco de dados, o servidor extrai o snapshot da base do usuário, gera um arquivo `.zip` em memória com o `openmoney.json` e dispara um e-mail de notificação com o backup anexado para o endereço do usuário cadastrado via API do Resend.

---

### 2.6. Refinamento da Interface e Adaptação na Versão Web

Para garantir conformidade de usabilidade no navegador e eliminar frustrações com chamadas de APIs de sistema operacional incompatíveis no browser:

1. **Rodapé da Barra Lateral:**
   - Na versão Desktop (`!kIsWeb`), mantém o seletor segmentado com as pílulas `"Local"` ↔ `"Online"`.
   - Na versão Web (`kIsWeb`), o botão de alternância para `"Local"` é removido, exibindo apenas o indicador pulsante em tempo real e o e-mail da conta Cloud conectada, com acesso direto ao modal de conta.

2. **Ocultação de Módulos Incompatíveis no Menu Lateral Web:**
   - **Backups de Segurança:** Ocultado no Web (recurso exclusivo do sistema de arquivos local no Desktop).
   - **Importar Carteira (CSV):** Ocultado no Web (fluxo com janelas nativas de arquivos do Desktop).
   - **Importar Comprovantes (OCR):** Ocultado no Web (processamento OCR nativo local do Desktop).
   - **Importar do Celular (.json):** Ocultado no Web (leitura de pasta de inbox local do Desktop).
   - **Buscar Atualizações:** Ocultado no Web (mecanismo de auto-update exclusivo de binários executáveis do Desktop).

---

### 2.7. Gerenciamento de Contas Salvas no Dispositivo (Acesso Rápido)

Na tela de login da versão Web e Desktop:
- As contas salvas anteriormente no dispositivo exibem botões diretos para **Alternar / Conectar**, **Desconectar** (individual) e **Desconectar Todas** (em lote).
- Ao clicar em **Desconectar**, a conta salva é removida do armazenamento seguro do navegador/dispositivo.
- Caso o usuário tente acessar aquela conta novamente no futuro, o sistema exige obrigatoriamente a redigitação da senha.

---

### 2.8. Blindagem de Inicialização, Isolamento de Cache (`cloud_cache/`) e Anti-Wipe em Bases >10MB

- **Separação Atômica de Cache (`platform_io_native.dart`):** Os snapshots locais de contas (`openmoney_web_cache_<userId>`) são armazenados em arquivos individuais dentro de `cloud_cache/`, gravados via `.tmp.<pid>` + `renameSync` atômico (com migração automática de entradas antigas do `sync_kv_store.json`), eliminando corrupções causadas pelo encerramento do app durante atualizações.
- **Inicialização Síncrona & Tela de Carregamento (`main.dart` / `app_shell.dart`):** O `store.boot()` inicia sincronamente antes do `runApp()` e o Desktop exibe `_buildCloudLoadingScreen` enquanto o snapshot inicial de `>10MB` é baixado e validado (`!hasLoadedRemoteState`).
- **Descarte de Cache Envenenado e Travas Anti-Wipe:** Caches vazios em contas com `revision > 1` são automaticamente descartados (`_isValidCloudCachePayload`), deltas pré-carga são rejeitados (`_applyIncomingDelta`), e envios/compactações vazias (`_isSuspiciousEmptyDb`) são bloqueados em 3 camadas (`SyncEngine`, `CloudSyncService` e barreira `< 50 KB` para bases `chunked:*` no Cloudflare D1).

---

## 3. Matriz de Plataformas e Governança Multi-Stack

Conforme diretriz registrada no `AGENTS.md` (e consolidada no [ADR 019](019-swift-cloud-sync-v2-parity.md)):

| Plataforma | Modo Offline Local | Modo Online (Sync v2) | Backups Locais (.zip) | Logs D1 Online |
| :--- | :---: | :---: | :---: | :---: |
| **Flutter Web** | ⚠️ Somente Convidado | ✅ 100% Tempo Real | ⬇️ Download .json | ✅ D1 API |
| **Flutter macOS** | ✅ `openmoney.json` | ✅ 100% Tempo Real | ✅ Diário + Manual | ✅ D1 API + .log |
| **Flutter Windows** | ✅ `openmoney.json` | ✅ 100% Tempo Real | ✅ Diário + Manual | ✅ D1 API + .log |
| **Flutter Mobile** | ✅ Local | ✅ 100% Tempo Real | ✅ Diário + Manual | ✅ D1 API |
| **Swift macOS** | ✅ `openmoney.json` | ✅ 100% Tempo Real | ✅ Diário + Manual | ✅ D1 API + .log |
| **Swift iOS** | ✅ `openmoney.json` | ✅ 100% Tempo Real | ✅ Diário + Manual | ✅ D1 API + .log |

> **Nota de Governança:** Ambas as stacks (**Swift macOS/iOS** e **Flutter Desktop/Web/Mobile**) operam com **100% de paridade funcional**, suportando livremente o modo híbrido (Local ↔ Online com Sync v2), isolamento atômico de cache e travas Anti-Wipe estritamente equivalentes, sem exceções funcionais entre as versões.
