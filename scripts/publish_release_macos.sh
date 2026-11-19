#!/bin/bash
set -e
export BASH_SILENCE_DEPRECATION_WARNING=1

# ==============================================================================
# OpenMoney Flutter - Script de Compilação e Publicação para macOS
# Repositório Oficial: https://github.com/FSF77/openmoney-new
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# Processamento de argumentos
RELEASE_NOTES=""
CUSTOM_VERSION=""

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Uso: ./scripts/publish_release_macos.sh [VERSÃO] [\"Notas da Versão\"]"
            echo ""
            echo "Exemplos:"
            echo "  ./scripts/publish_release_macos.sh"
            echo "  ./scripts/publish_release_macos.sh 2.1.1"
            echo "  ./scripts/publish_release_macos.sh 2.1.1 \"Correções e melhorias gerais\""
            exit 0
            ;;
        *)
            if [[ "$arg" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
                CUSTOM_VERSION="$arg"
            elif [ -z "$RELEASE_NOTES" ]; then
                RELEASE_NOTES="$arg"
            fi
            ;;
    esac
done

# Extrai versão atual do pubspec.yaml
CURRENT_VERSION=$(grep -E "^version:" "${ROOT_DIR}/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d '+' -f 1)
CURRENT_BUILD=$(grep -E "^version:" "${ROOT_DIR}/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d '+' -f 2)

if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="2.0.0"
fi
if [ -z "$CURRENT_BUILD" ]; then
    CURRENT_BUILD="1"
fi

# Define a versão final
if [ -n "$CUSTOM_VERSION" ]; then
    VERSION="$CUSTOM_VERSION"
else
    VERSION="$CURRENT_VERSION"
fi

# Incrementa automaticamente o Build Number (+1)
BUILD_NUM=$((CURRENT_BUILD + 1))

# Atualiza pubspec.yaml com a nova versão e build number
sed -i '' "s/^version: .*/version: ${VERSION}+${BUILD_NUM}/g" "${ROOT_DIR}/pubspec.yaml"

# Sincroniza fallbackVersion e fallbackBuild em lib/services/update_service.dart
sed -i '' "s/static const String fallbackVersion = '.*';/static const String fallbackVersion = '${VERSION}';/g" "${ROOT_DIR}/lib/services/update_service.dart"
sed -i '' "s/static const int fallbackBuild = [0-9]*;/static const int fallbackBuild = ${BUILD_NUM};/g" "${ROOT_DIR}/lib/services/update_service.dart"

if [ -z "$RELEASE_NOTES" ]; then
    NOTES="OpenMoney Flutter v${VERSION} (Build ${BUILD_NUM}) - Versão oficial multiplataforma com suporte a macOS, Windows, iPhone e iPad."
else
    NOTES="$RELEASE_NOTES"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 OpenMoney Flutter macOS — Build & Publish v${VERSION}+${BUILD_NUM}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Fecha qualquer instância em execução do OpenMoney para evitar concorrência e auto-update durante a publicação
if pgrep -x "OpenMoney" > /dev/null 2>&1 || pgrep -x "openmoney" > /dev/null 2>&1; then
    echo "⚠️  Fechando OpenMoney em execução..."
    pkill -x "OpenMoney" 2>/dev/null || true
    pkill -x "openmoney" 2>/dev/null || true
    sleep 1
fi

# 1. Compilação do macOS Release
echo "🔨 Compilando aplicativo macOS em modo Release..."
flutter build macos --release

# 1b. Compilação da versão Web na MESMA versão e build
echo "🌐 Compilando aplicativo Web (Cloudflare Pages) na versão v${VERSION}+${BUILD_NUM}..."
flutter build web --release --no-tree-shake-icons

# Copia o build Web para web-dist/ para deploy automático via GitHub -> Cloudflare Pages (projeto openmoney-new)
rm -rf "${ROOT_DIR}/web-dist"
mkdir -p "${ROOT_DIR}/web-dist"
cp -R "${ROOT_DIR}/build/web/"* "${ROOT_DIR}/web-dist/"
if [ -f "${ROOT_DIR}/web/_headers" ]; then
    cp "${ROOT_DIR}/web/_headers" "${ROOT_DIR}/web-dist/_headers"
fi
if [ -d "${ROOT_DIR}/coletor" ]; then
    cp -R "${ROOT_DIR}/coletor" "${ROOT_DIR}/web-dist/coletor"
fi

# Cache-busting da fonte MaterialIcons para contornar cache stale de CDN Cloudflare
if [ -f "${ROOT_DIR}/web-dist/assets/fonts/MaterialIcons-Regular.otf" ]; then
    cp "${ROOT_DIR}/web-dist/assets/fonts/MaterialIcons-Regular.otf" "${ROOT_DIR}/web-dist/assets/fonts/MaterialIcons-Regular-v${BUILD_NUM}.otf"
    if [ -f "${ROOT_DIR}/web-dist/assets/FontManifest.json" ]; then
        sed -i '' "s/MaterialIcons-Regular.otf/MaterialIcons-Regular-v${BUILD_NUM}.otf/g" "${ROOT_DIR}/web-dist/assets/FontManifest.json"
    fi
fi

APP_PATH="${ROOT_DIR}/build/macos/Build/Products/Release/openmoney.app"
if [ ! -d "${APP_PATH}" ]; then
    APP_PATH="${ROOT_DIR}/build/macos/Build/Products/Release/OpenMoney.app"
fi

if [ ! -d "${APP_PATH}" ]; then
    echo "❌ Erro: Aplicativo compilado não encontrado em ${APP_PATH}"
    exit 1
fi

# Remove atributos estendidos / quarentena do bundle antes do zip
xattr -cr "${APP_PATH}" 2>/dev/null || true

DOWNLOADS_MAC_DIR="${ROOT_DIR}/downloads/macos"
mkdir -p "${DOWNLOADS_MAC_DIR}"
ZIP_NAME="OpenMoney-macOS-${VERSION}.zip"
ZIP_PATH="${DOWNLOADS_MAC_DIR}/${ZIP_NAME}"

rm -f "${ZIP_PATH}"

echo "📦 Compactando ${ZIP_NAME}..."
TMP_PACKAGE_DIR="/tmp/openmoney_pkg_$$"
rm -rf "${TMP_PACKAGE_DIR}"
mkdir -p "${TMP_PACKAGE_DIR}"
cp -R "${APP_PATH}" "${TMP_PACKAGE_DIR}/OpenMoney.app"
ditto -c -k --keepParent "${TMP_PACKAGE_DIR}/OpenMoney.app" "${ZIP_PATH}"
rm -rf "${TMP_PACKAGE_DIR}"

SHA256=$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')
FILE_SIZE_MB=$(du -m "${ZIP_PATH}" | awk '{print $1}')
RELEASE_DATE=$(date "+%d/%m/%Y")

echo "✅ Pacote gerado com sucesso: ${ZIP_PATH}"
echo "   Tamanho: ~${FILE_SIZE_MB} MB"
echo "   SHA256:  ${SHA256}"

DOWNLOAD_URL="https://github.com/FSF77/openmoney-new/raw/main/downloads/macos/${ZIP_NAME}"

# 2. Atualização do version.json
VERSION_JSON_FILE="${ROOT_DIR}/version.json"

python3 - << EOF
import json, os

version_file = "${VERSION_JSON_FILE}"
data = {}
if os.path.exists(version_file):
    try:
        with open(version_file, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}

data["version"] = "${VERSION}"
data["build"] = int("${BUILD_NUM}")
data["releaseDate"] = "${RELEASE_DATE}"
data["title"] = "OpenMoney Flutter v${VERSION}"
data["notes"] = """${NOTES}"""
data["githubReleaseUrl"] = "https://github.com/FSF77/openmoney-new"

if "macos" not in data:
    data["macos"] = {}

data["macos"]["version"] = "${VERSION}"
data["macos"]["build"] = int("${BUILD_NUM}")
data["macos"]["releaseDate"] = "${RELEASE_DATE}"
data["macos"]["downloadUrl"] = "${DOWNLOAD_URL}"
data["macos"]["sha256"] = "${SHA256}"
data["macos"]["sizeMb"] = int("${FILE_SIZE_MB}")

if "web" not in data:
    data["web"] = {}

data["web"]["version"] = "${VERSION}"
data["web"]["build"] = int("${BUILD_NUM}")
data["web"]["releaseDate"] = "${RELEASE_DATE}"

with open(version_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print("version.json atualizado com sucesso.")

readme_file = "${ROOT_DIR}/README.md"
if os.path.exists(readme_file):
    try:
        with open(readme_file, "r", encoding="utf-8") as f:
            readme_content = f.read()

        mac_info = data.get("macos", {})
        win_info = data.get("windows", {})
        web_info = data.get("web", {})

        mac_ver = mac_info.get("version", data.get("version", ""))
        mac_build = mac_info.get("build", data.get("build", ""))
        mac_url = mac_info.get("downloadUrl", "")
        mac_size = mac_info.get("sizeMb", "")
        mac_date = mac_info.get("releaseDate", data.get("releaseDate", ""))
        mac_zip = mac_url.split("/")[-1] if mac_url else f"OpenMoney-macOS-{mac_ver}.zip"

        win_ver = win_info.get("version", data.get("version", ""))
        win_build = win_info.get("build", "")
        win_url = win_info.get("downloadUrl", "")
        win_size = win_info.get("sizeMb", "")
        win_date = win_info.get("releaseDate", "")
        win_zip = win_url.split("/")[-1] if win_url else f"OpenMoney-Windows-{win_ver}.zip"

        web_ver = web_info.get("version", data.get("version", ""))
        web_date = web_info.get("releaseDate", data.get("releaseDate", ""))

        mac_row = f"| 🍏 **macOS** | **v{mac_ver}** (Build {mac_build}) | [⬇️ Baixar {mac_zip}]({mac_url}) | ~{mac_size} MB | {mac_date} |" if mac_url else "| 🍏 **macOS** | Em breve | Compilação em andamento | — | — |"
        win_row = f"| 🪟 **Windows** | **v{win_ver}** (Build {win_build}) | [⬇️ Baixar {win_zip}]({win_url}) | ~{win_size} MB | {win_date} |" if win_url else "| 🪟 **Windows** | Em breve | Compilação em andamento | — | — |"
        web_row = f"| 🌐 **Web** | **v{web_ver}** | [🚀 Acessar App Web (openmoney.app.br)](https://openmoney.app.br) | — | {web_date} |"

        download_block = f"""<!-- LATEST_DOWNLOADS_START -->
## 📥 Downloads da Versão Oficial

| Plataforma | Versão | Pacote / Instalador | Tamanho | Data |
| :--- | :--- | :--- | :--- | :--- |
{mac_row}
{win_row}
{web_row}

### ⚡ Instalação Rápida via Terminal / PowerShell

- **macOS** (Terminal):
  ```bash
  curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.sh | bash
  ```

- **Windows** (PowerShell):
  ```powershell
  irm https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.ps1 | iex
  ```

- **Windows** (Prompt / CMD):
  ```cmd
  curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.bat -o install.bat && install.bat
  ```

---
<!-- LATEST_DOWNLOADS_END -->"""

        start_marker = "<!-- LATEST_DOWNLOADS_START -->"
        end_marker = "<!-- LATEST_DOWNLOADS_END -->"

        start_idx = readme_content.find(start_marker)
        end_idx = readme_content.find(end_marker)

        if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
            readme_content = readme_content[:start_idx] + download_block + readme_content[end_idx + len(end_marker):]
        else:
            sep = "---\n"
            sep_idx = readme_content.find(sep)
            if sep_idx != -1:
                idx = sep_idx + len(sep)
                readme_content = readme_content[:idx] + "\n" + download_block + "\n\n" + readme_content[idx:].lstrip("\n")
            else:
                readme_content = download_block + "\n\n" + readme_content

        with open(readme_file, "w", encoding="utf-8") as f:
            f.write(readme_content)
        print("README.md atualizado com os links de download com sucesso.")
    except Exception as e:
        print(f"Aviso: Não foi possível atualizar README.md: {e}")
EOF

# 3. Cria/atualiza o script de instalação rápida curl | bash
cat > "${ROOT_DIR}/install.sh" << 'EOF'
#!/bin/bash
set -e
export BASH_SILENCE_DEPRECATION_WARNING=1

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 Instalador do OpenMoney para macOS              "
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Fechar o OpenMoney se estiver em execução para evitar bloqueio de arquivos
if pgrep -x "OpenMoney" > /dev/null 2>&1; then
    echo "⚠️  Fechando OpenMoney em execução..."
    pkill -x "OpenMoney" 2>/dev/null || true
    sleep 1
fi

TMP_DIR="/tmp/openmoney-install-$$"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "📡 Consultando versão mais recente..."
# Cache-busting com timestamp e cabeçalhos no-cache para garantir o feed mais atualizado
TIMESTAMP=$(date +%s)
VERSION_JSON=$(curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" "https://raw.githubusercontent.com/FSF77/openmoney-new/main/version.json?t=${TIMESTAMP}")

# Extração resiliente: tenta osascript JavaScript (100% nativo no macOS), depois python3, depois awk/grep focado no bloco "macos"
DOWNLOAD_URL=""
VERSION=""

if command -v osascript >/dev/null 2>&1; then
    DOWNLOAD_URL=$(osascript -l JavaScript -e 'function run(argv) { try { const d = JSON.parse(argv[0]); return (d.macos && d.macos.downloadUrl) || d.downloadUrl || ""; } catch(e) { return ""; } }' "$VERSION_JSON" 2>/dev/null || true)
    VERSION=$(osascript -l JavaScript -e 'function run(argv) { try { const d = JSON.parse(argv[0]); return (d.macos && d.macos.version) || d.version || ""; } catch(e) { return ""; } }' "$VERSION_JSON" 2>/dev/null || true)
fi

if [ -z "$DOWNLOAD_URL" ] && command -v python3 >/dev/null 2>&1; then
    DOWNLOAD_URL=$(python3 -c "import sys, json; d=json.loads(sys.argv[1]); print(d.get('macos', {}).get('downloadUrl') or d.get('downloadUrl', ''))" "$VERSION_JSON" 2>/dev/null || true)
    VERSION=$(python3 -c "import sys, json; d=json.loads(sys.argv[1]); print(d.get('macos', {}).get('version') or d.get('version', ''))" "$VERSION_JSON" 2>/dev/null || true)
fi

if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(echo "$VERSION_JSON" | awk '/"macos"[[:space:]]*:[[:space:]]*\{/,/\}/' | grep -o '"downloadUrl": *"[^"]*"' | head -n 1 | cut -d '"' -f 4)
    VERSION=$(echo "$VERSION_JSON" | awk '/"macos"[[:space:]]*:[[:space:]]*\{/,/\}/' | grep -o '"version": *"[^"]*"' | head -n 1 | cut -d '"' -f 4)
fi

if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(echo "$VERSION_JSON" | grep -o '"downloadUrl": *"[^"]*"' | grep -i 'macos' | head -n 1 | cut -d '"' -f 4)
fi
if [ -z "$VERSION" ]; then
    VERSION=$(echo "$VERSION_JSON" | grep -o '"version": *"[^"]*"' | head -n 1 | cut -d '"' -f 4)
fi

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ Erro ao obter URL de download do OpenMoney para macOS."
    exit 1
fi

echo "📦 Baixando OpenMoney v${VERSION}..."
curl -# -L -H "Cache-Control: no-cache" "$DOWNLOAD_URL" -o "$TMP_DIR/OpenMoney.zip"

echo "📂 Instalando em /Applications..."
ditto -x -k "$TMP_DIR/OpenMoney.zip" "$TMP_DIR"

APP_SOURCE=""
if [ -d "$TMP_DIR/OpenMoney.app" ]; then
    APP_SOURCE="$TMP_DIR/OpenMoney.app"
else
    APP_SOURCE=$(find "$TMP_DIR" -name "OpenMoney.app" -type d -maxdepth 2 | head -n 1)
fi

if [ -z "$APP_SOURCE" ] || [ ! -d "$APP_SOURCE" ]; then
    echo "❌ Erro: Aplicativo OpenMoney.app não encontrado no pacote descompactado."
    rm -rf "$TMP_DIR"
    exit 1
fi

rm -rf /Applications/OpenMoney.app
cp -R "$APP_SOURCE" /Applications/OpenMoney.app
xattr -cr /Applications/OpenMoney.app 2>/dev/null || true

rm -rf "$TMP_DIR"
echo ""
echo "✅ OpenMoney v${VERSION} instalado com sucesso!"
echo "🚀 Abrindo aplicativo..."
open /Applications/OpenMoney.app
EOF
chmod +x "${ROOT_DIR}/install.sh"

# 4. Commit e Push no próprio repositório openmoney-new (dispara deploy automático no projeto openmoney-new da Cloudflare Pages)
cp -f "${VERSION_JSON_FILE}" "${ROOT_DIR}/web-dist/version.json" 2>/dev/null || true
echo "📤 Comitando e enviando para o repositório openmoney-new..."
git add README.md AGENTS.md .gitignore docs/ scripts/ lib/ macos/ windows/ web/ web-dist/ coletor/ functions/ cloudflare/ wrangler.toml test/ logo/ pubspec.yaml pubspec.lock version.json install.sh install.ps1 install.bat "downloads/macos/${ZIP_NAME}"
if git diff --staged --quiet; then
    echo "ℹ️ Nenhuma alteração a commitar."
else
    git commit -m "Release macOS & Web v${VERSION} (Build ${BUILD_NUM}) - ${RELEASE_DATE}"
    git tag -f "v${VERSION}"
    echo "📤 Enviando release para o GitHub (Cloudflare Pages openmoney-new atualizará automaticamente)..."
    git push origin main "v${VERSION}" --force
fi

echo ""
echo "🎉 Versão macOS & Web v${VERSION} (Build ${BUILD_NUM}) publicada com sucesso!"
echo "☁️ Cloudflare Pages (openmoney-new): deploy acionado automaticamente via GitHub Integration."
echo "🔗 Feed: https://raw.githubusercontent.com/FSF77/openmoney-new/main/version.json"
echo "📥 Download macOS: ${DOWNLOAD_URL}"
