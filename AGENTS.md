# Memória do Projeto e Arquitetura Unificada (OpenMoney Flutter)

Este documento registra as diretrizes, repositório oficial, versionamento e fluxos de build do ecossistema **OpenMoney**.

## Estrutura de Diretórios e Repositórios

| Plataforma / Stack | Caminho Local | Repositório | Finalidade / Observações |
| :--- | :--- | :--- | :--- |
| **Aplicação Oficial Multiplataforma (Flutter / Dart — macOS, Windows, Web, iOS e Android)** | `/Users/fabiano/Developer/OpenMoneyFlutter` | [FSF77/openmoney-new](https://github.com/FSF77/openmoney-new) *(Público)* | Fonte única da verdade para todas as regras de negócio, modelos, telas, sincronização Cloud Sync v2 (Cloudflare D1 / Durable Objects) e distribuição oficial. |
| **Documentação Oficial do Ecossistema (Arquitetura, ADRs, Manuais)** | `/Users/fabiano/Developer/OpenMoneyFlutter/docs` | [FSF77/openmoney-new/docs](https://github.com/FSF77/openmoney-new/tree/main/docs) | Raiz única oficial de documentação, ADRs, diagramas de arquitetura, dicionário de dados e manuais do usuário. |
| **Legado Arquivado (Swift — Descontinuado na v2.5.0)** | `/Users/fabiano/Developer/OpenMoneySwift` | [FSF77/openmoney-swift](https://github.com/FSF77/openmoney-swift) / [FSF77/openmoney-swift-releases](https://github.com/FSF77/openmoney-swift-releases) | Congelado e descontinuado na `v2.5.0` (ADR 029). Não recebe novas alterações. |

> [!NOTE]
> O nome do repositório oficial no GitHub (`FSF77/openmoney-new`) é mantido intencionalmente para preservar a retrocompatibilidade integral do auto-update Desktop (`raw.githubusercontent.com/FSF77/openmoney-new/...`), dos instaladores rápidos via terminal e da integração contínua com Cloudflare Pages (`openmoney.app.br`).

---

## Diretrizes de Desenvolvimento

1. **Fonte Única da Verdade (Single-Stack Flutter):**
   - Toda evolução funcional, ajuste ou correção é implementada exclusivamente no projeto **Flutter / Dart** (`/Users/fabiano/Developer/OpenMoneyFlutter`), garantindo suporte coeso e comportamento consistente para **Desktop (macOS e Windows)**, **Web PWA (`openmoney.app.br`)** e **Mobile (iOS/iPadOS e Android)**.
   - Toda mudança deve contemplar todas as plataformas atendidas pelo código Flutter (Desktop, Web e Mobile responsivos); se alguma plataforma exigir tratamento específico ou tiver limitação nativa (ex.: OCR local Desktop vs. Web), documentar e tratar explicitamente.
   - **Operação Híbrida Unificada (Modo Local ↔ Online com Cloud Sync v2):** O aplicativo suporta nativamente operação híbrida completa: uso 100% offline local sobre arquivo `openmoney.json` e sincronização em tempo real (Sync v2) via Cloudflare Pages Functions, D1 e Durable Objects com resolução granular por registro, WebSocket, snapshot binário Gzip, autenticação em duas etapas, backups de segurança locais/nuvem e Anti-Wipe Guard.

2. **Compatibilidade da Base de Dados (`openmoney.json`) e Regras de Persistência / Anti-Wipe:**
   - **Schema unificado `v: 7`**: regras estritas de leitura/escrita, campos em centavos inteiros (`amt`, `opening`), debounce de 350ms, migração de chaves de faturas para a competência de vencimento (`dueDay <= closeDay`) e backup atômico diário (até 4 snapshots `.zip` diários e retenção mínima de 7+ dias).
   - **Cache Cloud Isolado e Escrita Atômica (`Sync v2`):** Snapshots em cache offline no Desktop/Mobile são gravados em arquivos individuais por conta (`cloud_cache/<key>.json`), separados do arquivo leve de metadados (`sync_kv_store.json`), sempre via escrita atômica (`.tmp.<pid>` + `rename`) para prevenir corrupção pós-atualizações. Na Web, utilizam `window.localStorage`.
   - **Validação de Cache e Inicialização Segura:** O `boot()` executa sincronamente antes do primeiro frame; enquanto `!hasLoadedRemoteState` no modo Online, a interface exibe a tela de carregamento Cloud (nunca tela zerada). Caches locais vazios (`txs.isEmpty` e conta `'a1'` padrão zerada) para contas com `revision > 1` são descartados automaticamente, forçando `forceFullPull: true` com até 3 retentativas.
   - **Bloqueio Anti-Wipe em 3 Camadas:** Deltas pré-carga (`_applyIncomingDelta`) e gravações/compactações vazias não forçadas (`_isSuspiciousEmptyDb` no `SyncEngine` e `CloudSyncService`) são bloqueados no cliente; `disconnectLocalDatabase()` interrompe obrigatoriamente o `SyncEngine`; e o backend Cloudflare (`PUT /api/db`) bloqueia com `HTTP 409` qualquer payload `< 50 KB` sobre bases `chunked:*` sem `force=true` explícito (incluindo requisições `compactSeq`).
   - **Isolamento Absoluto de Testes Automatizados (Zero-Impact Guard):** O `MoneyStore` e a camada de I/O nativo (`platform_io_native`) detectam automaticamente `Platform.environment['FLUTTER_TEST']` e redirecionam o `Application Support` para diretórios temporários (`OpenMoney_Test_Support`). Testes automatizados (`flutter test`) nunca acessam ou gravam no `config.json` real da máquina de desenvolvimento nem alteram referências de bases ou contas locais/nuvem.
   - **Atualização Compulsória do Dicionário de Dados (`docs/architecture/dicionario-de-dados.md`):** Toda e qualquer adição, alteração ou remoção de campos em modelos locais (`openmoney.json`), tabelas relacionais no Cloudflare D1, estruturas em memória (DTOs) ou chaves de persistência/sincronização DEVE ser documentada e sincronizada imediatamente no Dicionário de Dados oficial, mantendo descrições, tipos, valores padrão, chaves primárias/estrangeiras e regras de validação rigorosamente atualizadas em todo desenvolvimento.

3. **Política de Versionamento (CalVer + Build Sequencial):**
   - **Versão por Data (`CalVer — YYYY.M.D`):** Controlada em `pubspec.yaml` no formato `YYYY.M.D+BUILD` (ex: `2026.11.24+170`), sem zeros à esquerda nos segmentos de mês/dia para compatibilidade estrita com a especificação do `pubspec.yaml` do Dart/Flutter.
   - **Build Number (`+BUILD`):** Incrementado automaticamente (`+1`) a cada compilação de release no `pubspec.yaml` e sincronizado em `lib/services/update_service.dart` e `version.json` (servindo também como critério de desempate para múltiplos builds publicados no mesmo dia).

4. **Diretriz de Documentação e Manuais (User-First Always):**
   - **Atualização Compulsória de ADRs, Guias de Uso e FAQ:** A cada nova funcionalidade, decisão arquitetural ou alteração relevante de comportamento, é obrigatório **criar ou atualizar**:
     - O respectivo **ADR** em `docs/adr/` (registrando contexto, decisão, regras e impacto).
     - O **Guia de Uso** correspondente em `docs/manual/` (seguindo a ordem centrada no usuário abaixo).
     - O **FAQ oficial** em `docs/manual/faq.md` (adicionando ou atualizando perguntas, respostas e links).
     - O índice de documentação no `README.md` da raiz sempre que novos arquivos forem criados.
   - Todo manual e guia de uso (`docs/manual/`) deve seguir estritamente a ordem centrada no usuário:
     1. Passo a passo prático de configuração e uso na perspectiva do usuário final (telas, botões, fluxo de 1 clique, interfaces suportadas).
     2. Exemplos práticos de comandos, prompts e casos reais de uso do dia a dia.
     3. Gestão prática de acessos, segurança na visão do usuário e FAQ de dúvidas comuns.
     4. Detalhamento técnico, arquitetura, fluxos RFCs, APIs e especificações internas apenas nas seções finais, servindo como complemento para desenvolvedores e administradores.

---

## Fluxo Automatizado de Releases (OpenMoney Flutter)

### 1. macOS & Web (Cloudflare Pages)
- **Comando único de compilação e publicação:**
  ```bash
  cd /Users/fabiano/Developer/OpenMoneyFlutter
  ./scripts/publish_release_macos.sh ["Notas da Versão"]
  ```
  *(Exemplo: `./scripts/publish_release_macos.sh "Notas da versão..."` — a versão assume automaticamente a data do dia `YYYY.M.D`, ou pode ser informada opcionalmente como `./scripts/publish_release_macos.sh 2026.11.24 "Notas da versão..."`)*
- **Comportamento automatizado:**
  1. Incrementa o build no `pubspec.yaml` (`+1`), sincroniza `lib/services/update_service.dart`, `version.json` e atualiza a seção de downloads no `README.md` com a nova versão compilada para macOS e Web.
  2. Compila o binário macOS release (`flutter build macos --release`) e a versão Web (`web-dist/`).
  3. No repositório ([`FSF77/openmoney-new`](https://github.com/FSF77/openmoney-new)): commita os arquivos (incluindo `README.md` e `docs/`), gera o pacote `.zip`, atualiza a tag `v${VERSION}` e faz `git push origin main`.

### 2. Windows
- **Fluxo encadeado após o macOS:**
  1. O release deve ser publicado **primeiro no macOS** (que define versão, notas e build).
  2. No Windows, execute:
     ```cmd
     scripts\publish_release_windows.bat
     ```
  3. Ao confirmar com `S`, o script executa `git pull origin main` (puxando a versão, build e notas exatas do Mac), compila o binário Windows, atualiza a chave `"windows"` no `version.json`, atualiza a seção de downloads no `README.md` com os links e hashes do pacote Windows compilado e faz push (incluindo `README.md`) com a tag `v${VERSION}-windows`.
