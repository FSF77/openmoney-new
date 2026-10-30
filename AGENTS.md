# Memória do Projeto e Arquitetura Multi-Stack

Este documento registra as diretrizes, repositórios, versionamento e fluxos de build do ecossistema **OpenMoney**.

## Estrutura de Diretórios e Repositórios

| Plataforma / Stack | Caminho Local | Repositório Principal | Finalidade / Observações |
| :--- | :--- | :--- | :--- |
| **Swift (Principal / Nativo macOS & iOS)** | `/Users/fabiano/Developer/OpenMoneySwift` | [FSF77/openmoney](https://github.com/FSF77/openmoney) *(Privado)* | Versão de referência de todas as regras de negócio, modelos e telas. Repositório auxiliar de releases e downloads: [FSF77/openmoney-releases](https://github.com/FSF77/openmoney-releases). |
| **Flutter / Dart (Multiplataforma macOS, Windows, Web, Mobile)** | `/Users/fabiano/Developer/OpenMoneyFlutter` | [FSF77/openmoney-new](https://github.com/FSF77/openmoney-new) *(Público)* | Versão convertida em Flutter/Dart. Deve replicar fielmente o comportamento da versão Swift. |

---

## Diretrizes de Desenvolvimento Conjunto

1. **Equivalência Funcional Estrita:**
   - O aplicativo em **Swift** é a fonte da verdade para fluxos, modelos, cálculos, regras de negócio e comportamento da interface.
   - Qualquer funcionalidade criada, ajustada ou corrigida no Swift deve ser replicada e rodar com o mesmo comportamento no Flutter/Dart.
   - **Toda mudança deve ser aplicada em todas as plataformas:** Flutter (macOS, Windows, Web, Mobile), Swift macOS e Swift iOS. Nunca entregar uma funcionalidade, ajuste ou correção em apenas uma delas; se alguma plataforma não puder ser feita, avisar explicitamente.

2. **Compatibilidade da Base de Dados (`openmoney.json`):**
   - Ambas as plataformas operam sobre a mesma base de dados.
   - **Schema unificado `v: 7`**: regras idênticas de leitura/escrita, campos em centavos inteiros (`amt`, `opening`), debounce de 350ms, migração de chaves de faturas para a competência de vencimento (`dueDay <= closeDay`) e backup atômico diário.

3. **Política de Versionamento:**
   - **Versão Semântica (`Version`):** Sempre equalizada entre Swift e Flutter (ex: `2.1.1`).
   - **Build Number:** Mantido de forma independente em cada repositório (ex: Swift `70`, Flutter `20`), com incremento automático (`+1`) a cada compilação de release.

---

## Fluxo Automatizado de Releases

### 1. OpenMoney Swift
- **Comando único de compilação e publicação:**
  ```bash
  cd /Users/fabiano/Developer/OpenMoneySwift
  ./build-app.sh [VERSÃO] ["Notas da Versão"] --publish
  ```
  *(Exemplo: `./build-app.sh 2.1.1 "Notas da versão..." --publish`)*
- **Comportamento automatizado:**
  1. Incrementa o `BUILD_NUMBER` automaticamente (`+1`) e atualiza o arquivo `VERSION`.
  2. Compila e assina o app nativo via `codesign`.
  3. No repositório principal ([`FSF77/openmoney`](https://github.com/FSF77/openmoney)): commita o código-fonte, atualiza a tag `v${VERSION}` e faz `git push origin main --tags`.
  4. No repositório de distribuição ([`FSF77/openmoney-releases`](https://github.com/FSF77/openmoney-releases)): publica o `.zip`, atualiza o `version.json`, `install.sh` e faz push com tag.

### 2. OpenMoney Flutter (macOS)
- **Comando único de compilação e publicação:**
  ```bash
  cd /Users/fabiano/Developer/OpenMoneyFlutter
  ./scripts/publish_release_macos.sh [VERSÃO] ["Notas da Versão"]
  ```
  *(Exemplo: `./scripts/publish_release_macos.sh 2.1.1 "Notas da versão..."`)*
- **Comportamento automatizado:**
  1. Incrementa o build no `pubspec.yaml` (`+1`), sincroniza `update_service.dart` e `version.json`.
  2. Compila o binário macOS release (`flutter build macos --release`).
  3. No repositório ([`FSF77/openmoney-new`](https://github.com/FSF77/openmoney-new)): commita os arquivos, gera o pacote `.zip`, atualiza a tag `v${VERSION}` e faz `git push origin main`.

### 3. OpenMoney Flutter (Windows)
- **Fluxo encadeado após o macOS:**
  1. O release deve ser publicado **primeiro no macOS** (que define versão, notas e build).
  2. No Windows, execute:
     ```cmd
     scripts\publish_release_windows.bat
     ```
  3. Ao confirmar com `S`, o script executa `git pull origin main` (puxando a versão, build e notas exatas do Mac), compila o binário Windows, atualiza a chave `"windows"` no `version.json` e faz push da tag `v${VERSION}-windows`.
