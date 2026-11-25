# Guia do Usuário: Atualizações do Sistema, Versionamento por Data (CalVer) e Releases

Este guia explica de forma simples como identificar a versão do seu **OpenMoney**, como funciona o padrão de **Versionamento por Data (`AAAA.M.D`)** e como atualizar o aplicativo com 1 clique no **macOS**, **Windows**, **Web** e **Mobile**. Nas seções finais, também apresenta o fluxo técnico para compilação e publicação de releases.

---

## 1. 📅 Como ler a versão do OpenMoney (Padrão por Data)

O OpenMoney utiliza o padrão de **Versionamento por Data (CalVer)** no formato **`AAAA.M.D (Build N)`** — por exemplo: **`v2026.11.24 (Build 170)`**.

| Parte da Versão | Exemplo | O que significa |
| :--- | :--- | :--- |
| **Ano (`AAAA`)** | `2026` | Ano em que a versão foi lançada |
| **Mês (`M`)** | `11` | Mês do lançamento (`1` para janeiro até `12` para dezembro, sem zero à esquerda) |
| **Dia (`D`)** | `24` | Dia do mês em que a versão foi publicada (`1` a `31`, sem zero à esquerda) |
| **Build (`+170`)** | `Build 170` | Contador sequencial único de compilação (desempata atualizações lançadas no mesmo dia) |

> 💡 **Por que isso é ótimo para você?**
> Ao olhar o número da versão no aplicativo, você sabe **instantaneamente a data exata** da sua versão instalada, sem precisar consultar listas de mudanças para descobrir quando a versão saiu.

---

## 2. 🔍 Onde ver a versão instalada e como atualizar

### No Computador (macOS e Windows)
1. **Na Barra Lateral:** No rodapé da barra lateral esquerda (ou passando o mouse sobre o ícone no modo compacto *Mini Rail*), a versão e o build atuais são exibidos permanentemente.
2. **Em Ajustes & Personalização:** Abra **Módulos › Ajustes & Personalização** (ou pressione `Cmd + ,` no Mac / `Ctrl + ,` no Windows) e role até o card **Sobre & Integridade da Base**.
3. **Como buscar e instalar atualizações com 1 clique:**
   - No menu superior (ou dentro de **Ajustes & Personalização**), clique em **Verificar Atualizações...**.
   - Se houver uma versão mais nova (ou um novo Build publicado no mesmo dia), o OpenMoney exibirá uma janela com as novidades da versão.
   - Clique em **Atualizar Agora**: o aplicativo baixa o pacote oficial com verificação criptográfica de integridade (`SHA-256`), instala automaticamente e reinicia pronto para uso, preservando todas as suas contas e configurações.

### Na Web (`https://openmoney.app.br`)
- A versão Web é atualizada **automaticamente** nos servidores da Cloudflare Pages a cada nova publicação.
- Basta abrir ou recarregar a página no navegador para usar a versão e o build mais recentes.

### Instalação ou Atualização Rápida via Terminal / PowerShell
Se preferir atualizar ou instalar diretamente em um novo computador com um único comando:

- **macOS (Terminal):**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.sh | bash
  ```
- **Windows (PowerShell):**
  ```powershell
  irm https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.ps1 | iex
  ```
- **Windows (Prompt de Comando / CMD):**
  ```cmd
  curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.bat -o install.bat && install.bat
  ```

---

## 3. ❓ Perguntas Frequentes (FAQ)

### 1. Estou em uma versão antiga como `v2.5.8`. A atualização automática para `v2026.11.24` funciona normalmente?
**Sim!** O verificador de atualização compara cada número da versão. Como `2026` é maior que `2`, o aplicativo reconhece imediatamente a nova versão por data e faz a atualização normalmente com 1 clique.

### 2. E se saírem duas atualizações no mesmo dia?
Cada compilação incrementa o número sequencial de **Build** (por exemplo, de `2026.11.24+170` para `2026.11.24+171`). O sistema detecta que o Build `171` é maior que o `170` e disponibiliza a atualização normalmente.

### 3. Por que meses e dias menores que 10 não usam zero à esquerda (ex.: `2027.1.5` em vez de `2027.01.05`)?
Porque o gerenciador de pacotes oficial do Flutter/Dart segue a norma técnica internacional *SemVer 2.0*, onde cada bloco numérico entre pontos é tratado como um número inteiro puro (sem zero à esquerda). Isso garante compatibilidade total com todas as plataformas e lojas de aplicativos.

### 4. Atualizar o aplicativo altera ou apaga meus lançamentos?
**Nunca.** A atualização substitui apenas o programa executável. Sua base local (`openmoney.json`), seus backups automáticos em `.zip` e sua sincronização em nuvem (**OpenMoney Cloud — Sync v2**) permanecem 100% intactos.

---

## 4. 🛠️ Especificação Técnica e Guia de Publicação (Para Desenvolvedores)

Esta seção documenta o funcionamento interno dos scripts de compilação e publicação automatizada (ver [ADR 038](../adr/038-calver-date-versioning-and-release-automation.md)).

### 4.1. Arquivos Sincronizados na Release
1. **`pubspec.yaml`**: Armazena `version: YYYY.M.D+BUILD` (fonte primária lida durante a compilação Flutter).
2. **`lib/services/update_service.dart`**: Sincroniza `OpenMoneyVersion.fallbackVersion` e `OpenMoneyVersion.fallbackBuild`.
3. **`version.json`**: Feed público JSON consultado pelos clientes Desktop e instaladores de terminal, contendo versão, build, notas, data (`DD/MM/AAAA`), URLs de download e hashes `SHA-256` por plataforma (`macos`, `windows`, `web`).
4. **`README.md`**: Bloco `<!-- LATEST_DOWNLOADS_START --> ... <!-- LATEST_DOWNLOADS_END -->` atualizado automaticamente com links, tamanhos e builds de cada plataforma.

### 4.2. Passo 1 — Publicação macOS & Web (Cloudflare Pages)
A publicação sempre se inicia no **macOS**, que define a versão CalVer do dia, incrementa o `+BUILD` e publica simultaneamente o binário macOS e o bundle Web (`web-dist/`):

```bash
cd /Users/fabiano/Developer/OpenMoneyFlutter

# Publicação padrão (usa automaticamente a data de hoje YYYY.M.D e incrementa +1 no build):
./scripts/publish_release_macos.sh "Descrição das novidades e melhorias da versão"
```

- Caso deseje especificar manualmente uma versão (se informar `2027.01.05`, o script normaliza automaticamente para `2027.1.5`):
  ```bash
  ./scripts/publish_release_macos.sh 2026.11.24 "Descrição das novidades..."
  ```

### 4.3. Passo 2 — Publicação Windows (Encadeada após o macOS)
Após concluir o push no macOS, execute na máquina Windows:

```cmd
scripts\publish_release_windows.bat
```

1. Confirme com `S` quando perguntado se a release já foi publicada no Mac.
2. O script executa `git pull origin main`, lê a versão `YYYY.M.D+BUILD` e as notas geradas no Mac, compila o executável Windows (`flutter build windows --release`), gera `downloads/windows/OpenMoney-Windows-YYYY.M.D.zip`, calcula o hash `SHA-256`, atualiza a chave `"windows"` no `version.json` e a tabela do `README.md`, e faz push com a tag `vYYYY.M.D-windows`.
