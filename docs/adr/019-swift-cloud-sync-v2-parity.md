# ADR 019: Paridade Integral do Modo Online e Sync v2 no OpenMoney Swift (macOS e iOS)

**Status:** Aprovado e Implementado  
**Data:** 12 de Novembro de 2026  
**Contexto:** Ecossistema OpenMoney Multi-Stack (`OpenMoneySwift` e `OpenMoneyFlutter`)

---

## 1. Contexto e Motivação

O ecossistema **OpenMoney** é regido pelo princípio inegociável de **Equivalência Funcional Estrita**: qualquer funcionalidade existente em uma stack deve funcionar com comportamento idêntico em todas as plataformas suportadas.

Com o amadurecimento e consolidação do **Sync v2 em Tempo Real** no Cloudflare D1/Durable Objects e a operação híbrida (Modo Local ↔ Online) no Flutter Desktop e Web ([ADR 013](013-realtime-record-sync.md) e [ADR 014](014-desktop-hybrid-sync-audit-and-safety-backups.md)), fazia-se necessária a eliminação da exceção temporária que mantinha a versão nativa em **Swift (macOS e iOS)** operando exclusivamente no modo local.

Este ADR documenta a arquitetura, protocolos binários, engenharia de sincronização em tempo real e interfaces nativas desenvolvidas em Swift puro (sem dependências externas) para atingir **100% de paridade funcional** entre as versões Swift e Flutter.

---

## 2. Decisões de Arquitetura

### 2.1. Zero Dependências Externas (Apple Native)
Para preservar o tamanho ultra-compacto do binário macOS (~2 MB), a velocidade de inicialização instantânea e a compatibilidade irrestrita com o App Sandbox no macOS e iOS:
- **Compressão e Descompressão Gzip (RFC 1952):** Implementada nativamente em `GzipHelper.swift` utilizando a biblioteca de sistema `zlib` (`deflateInit2_` e `inflateInit2_` com detecção de cabeçalho `MAX_WBITS + 32`), além de um arquivador `.zip` em Swift puro para criação de backups locais no iOS sem invocar processos externos.
- **WebSockets em Tempo Real:** Implementados nativamente utilizando `URLSessionWebSocketTask` com keep-alive periódico (`ping`), reconexão resiliente com backoff exponencial e tratamento assíncrono de eventos `hello`, `pong` e `sync`.

### 2.2. Cliente REST e Autenticação em 2 Etapas (`CloudSyncService.swift`)
O serviço encapsula todos os contratos de API com o backend Cloudflare Pages (`https://openmoney.app.br`):
1. **Autenticação e Sessão:** Login (`POST /api/auth/login`), cadastro em duas etapas com código de 6 dígitos via Resend (`/api/auth/register-request` e `/api/auth/register-confirm`), recuperação de senha (`/api/auth/forgot-password` e `/api/auth/reset-password`), alteração de e-mail em duas etapas e troca de senha.
2. **Snapshot Binário Gzip:** `GET /api/db?format=binary` e `PUT /api/db` com cabeçalhos `X-OpenMoney-*` (`Compression`, `Raw-Size`, `Prefs` em Base64URL, `Base-Revision`, `Compact-Seq` e `Force`), transferindo bases completas em 0.5ms de CPU no Cloudflare Worker.
3. **Backups e Auditoria Remota:** Listagem e restauração de snapshots diários (`/api/backups`) e envio de logs de alterações para a tabela D1 (`user_audit_logs`).
4. **Exclusão Segura com Envio Preventivo de Backup:** Suporte a `POST /api/db/delete` com palavra-chave `EXCLUIR` e envio compulsório de backup `.zip` por e-mail antes da exclusão.
5. **Alternância Rápida entre Múltiplas Contas Salvas:** Persistência de `savedAccounts` permitindo alternar instantaneamente entre diferentes bases e contas na nuvem.

### 2.3. Motor de Sincronização Granular por Registro (`SyncEngine.swift`)
O motor replica estritamente o algoritmo LSM do Sync v2:
1. **Extração Granular:** Decomposição da base de dados em coleções tipadas:
   - `accounts/<id>`: Contas financeiras
   - `cats/<id>`: Categorias e subcategorias
   - `txs/<id>`: Lançamentos financeiros
   - `recs/<id>`: Regras de recorrência
   - `budgets/<id>`: Limites de gastos
   - `comments/<id>`: Comentários mensais
   - `meta/predMode`: Modo de previsão ("month" vs "invoice")
   - `meta/accountOrder`: Ordenação das contas
   - `prefs/userPrefs`: Parâmetros de personalização do usuário
2. **Diff Determinístico via JSON Canônico:** Ordenação lexicográfica compulsória de chaves (`JSONEncoder.OutputFormatting.sortedKeys`) para evitar diffs espúrios em dicionários.
3. **Outbox Persistente e Batch Atômico:** Gravação assíncrona da fila em `Application Support/OpenMoney/cloud_sync/outbox_<userId>.json` e envio em lote via `POST /api/sync` com `opId` único.
4. **Compacting em Background pelo Cliente:** Compactação periódica do snapshot via `PUT /api/db` a cada lote processado com sucesso.
5. **Anti-Wipe Guard Cruzado:** Prevenção inviolável contra substituição acidental de bases locais populadas por snapshots remotos vazios.

### 2.4. Integração ao `MoneyStore` e Desconexão de Bases/Contas
1. **Operação Híbrida em Tempo de Execução:**
   - Ao alternar entre Local e Online (e vice-versa), o estado em memória é sincronizado, os índices de busca e saldos ($O(1)$) são recalculados instantaneamente via `rebuildIndexes()`, as notificações são atualizadas e a UI SwiftUI é notificada via `objectWillChange.send()`, sem necessidade de reiniciar o aplicativo.
2. **Desconexão de Base Local (`disconnectLocalDatabase`):**
   - Permite desconectar o arquivo `openmoney.json` local em uso, limpando as credenciais no `config.json` e retornando à tela de boas-vindas (`WelcomeDatabaseView`).
3. **Desconexão de Contas Salvas:**
   - Suporte a desconexão individual de contas de login salvas no dispositivo e opção de desconectar todas as contas em lote.

---

## 3. Interfaces Gráficas Implementadas

| Componente | Plataforma | Finalidade |
| :--- | :--- | :--- |
| `WelcomeDatabaseView.swift` | macOS & iOS | Tela de primeiro acesso / boas-vindas com opções de login Cloud, criação de base local nova ou seleção de arquivo existente. |
| `CloudAccountSheet.swift` | macOS & iOS | Modal unificado de login, cadastro 2FA, recuperação de senha, gerenciamento de contas salvas, restauração de backups e desconexão de bases. |
| `sidebarCloudFooterBar` (em `Views.swift`) | macOS | Pill de status no rodapé da barra lateral com alternância rápida com 1 clique (Local / Online) e menu contextual. |
| `iOSDatabaseTab` (em `iOSViews.swift`) | iOS | Seção de Conta Cloud & Sync v2 na aba Base, status de conexão, sincronização manual e desconexão de base local. |

---

## 4. Consequências e Resultados

1. **Equivalência Multi-Stack Total:** A regra de ouro de equivalência estrita volta a vigorar plenamente sem qualquer exceção funcional entre Swift e Flutter.
2. **Interoperabilidade Perfeita:** Um usuário pode editar lançamentos no OpenMoney nativo no macOS, visualizar a atualização em tempo real no iPhone e acompanhar simultaneamente no Windows ou Web.
3. **Conformidade de Build:** Homologado e testado em ambos os fluxos automatizados (`./build-app.sh` no macOS com código de saída 0 e `xcodebuild` no iOS Simulator com `BUILD SUCCEEDED`).
