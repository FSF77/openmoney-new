#!/bin/bash
set -e

# ==============================================================================
# OpenMoney Flutter - Script de Compilação e Publicação para macOS
# Repositório de Releases: https://github.com/FSF77/openmoney-releases
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# Extrai versão do pubspec.yaml
VERSION=$(grep -E "^version:" "${ROOT_DIR}/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d '+' -f 1)
BUILD_NUM=$(grep -E "^version:" "${ROOT_DIR}/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d '+' -f 2)

if [ -z "$VERSION" ]; then
    VERSION="2.0.0"
fi
if [ -z "$BUILD_NUM" ]; then
    BUILD_NUM="1"
fi

NOTES="${1:-OpenMoney Flutter v${VERSION} - Versão multiplataforma oficial com suporte a macOS, Windows, iPhone e iPad.}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 OpenMoney Flutter macOS — Build & Publish v${VERSION}+${BUILD_NUM}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Compilação do macOS Release
echo "🔨 Compilando aplicativo macOS em modo Release..."
flutter build macos --release

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

DIST_DIR="${ROOT_DIR}/dist/flutter/macos"
mkdir -p "${DIST_DIR}"
ZIP_NAME="OpenMoney-macOS-${VERSION}.zip"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"

rm -f "${ZIP_PATH}"

echo "📦 Compactando ${ZIP_NAME}..."
# Empacota renomeando para OpenMoney.app na raiz do zip se necessário
TMP_PACKAGE_DIR="/tmp/openmoney_pkg_$$"
rm -rf "${TMP_PACKAGE_DIR}"
mkdir -p "${TMP_PACKAGE_DIR}"
cp -R "${APP_PATH}" "${TMP_PACKAGE_DIR}/OpenMoney.app"
ditto -c -k --keepParent "${TMP_PACKAGE_DIR}/OpenMoney.app" "${ZIP_PATH}"
rm -rf "${TMP_PACKAGE_DIR}"

SHA256=$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')
FILE_SIZE_MB=$(du -m "${ZIP_PATH}" | awk '{print $1}')
RELEASE_DATE=$(date "+%d/%m/%Y")
RELEASE_TIME=$(date "+%H:%M")

echo "✅ Pacote gerado com sucesso: ${ZIP_PATH}"
echo "   Tamanho: ~${FILE_SIZE_MB} MB"
echo "   SHA256:  ${SHA256}"

# 2. Publicação no repositório openmoney-releases
RELEASES_REPO="https://github.com/FSF77/openmoney-releases.git"
STAGING_DIR="/tmp/openmoney-releases-staging-$$"
rm -rf "${STAGING_DIR}"

echo "📡 Clonando repositório de distribuição: ${RELEASES_REPO}..."
git clone "${RELEASES_REPO}" "${STAGING_DIR}"

DOWNLOAD_FLUTTER_MAC_DIR="${STAGING_DIR}/downloads/flutter/macos"
mkdir -p "${DOWNLOAD_FLUTTER_MAC_DIR}"
cp -f "${ZIP_PATH}" "${DOWNLOAD_FLUTTER_MAC_DIR}/${ZIP_NAME}"

DOWNLOAD_URL="https://github.com/FSF77/openmoney-releases/raw/main/downloads/flutter/macos/${ZIP_NAME}"

# 3. Atualização do version-flutter.json
VERSION_JSON_FILE="${STAGING_DIR}/version-flutter.json"

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
data["githubReleaseUrl"] = "https://github.com/FSF77/openmoney-releases"

if "macos" not in data:
    data["macos"] = {}

data["macos"]["version"] = "${VERSION}"
data["macos"]["build"] = int("${BUILD_NUM}")
data["macos"]["releaseDate"] = "${RELEASE_DATE}"
data["macos"]["downloadUrl"] = "${DOWNLOAD_URL}"
data["macos"]["sha256"] = "${SHA256}"
data["macos"]["sizeMb"] = int("${FILE_SIZE_MB}")

with open(version_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print("version-flutter.json atualizado com sucesso.")
EOF

# 4. Cria script de instalação rápida curl | bash para o Flutter macOS
cat > "${STAGING_DIR}/install-flutter.sh" << 'EOF'
#!/bin/bash
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 Instalador do OpenMoney Flutter para macOS      "
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TMP_DIR="/tmp/openmoney-flutter-install-$$"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "📡 Consultando versão mais recente..."
VERSION_JSON=$(curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-releases/main/version-flutter.json)
DOWNLOAD_URL=$(echo "$VERSION_JSON" | grep -o '"downloadUrl": *"[^"]*"' | head -n 1 | cut -d '"' -f 4)
VERSION=$(echo "$VERSION_JSON" | grep -o '"version": *"[^"]*"' | head -n 1 | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ Erro ao obter URL de download do OpenMoney Flutter."
    exit 1
fi

echo "📦 Baixando OpenMoney Flutter v${VERSION}..."
curl -# -L "$DOWNLOAD_URL" -o "$TMP_DIR/OpenMoney.zip"

echo "📂 Instalando em /Applications..."
ditto -x -k "$TMP_DIR/OpenMoney.zip" "$TMP_DIR"

rm -rf /Applications/OpenMoney.app
cp -R "$TMP_DIR/OpenMoney.app" /Applications/OpenMoney.app
xattr -cr /Applications/OpenMoney.app 2>/dev/null || true

rm -rf "$TMP_DIR"
echo ""
echo "✅ OpenMoney Flutter v${VERSION} instalado com sucesso!"
echo "🚀 Abrindo aplicativo..."
open /Applications/OpenMoney.app
EOF
chmod +x "${STAGING_DIR}/install-flutter.sh"

# 5. Commit e Push no openmoney-releases
cd "${STAGING_DIR}"
git config user.name "FSF77"
git config user.email "FSF77@users.noreply.github.com"

git add version-flutter.json install-flutter.sh "downloads/flutter/macos/${ZIP_NAME}"
if git diff --staged --quiet; then
    echo "ℹ️ Nenhuma alteração a commitar no repositório de releases."
else
    git commit -m "Release OpenMoney Flutter macOS v${VERSION} (Build ${BUILD_NUM}) - ${RELEASE_DATE}"
    git tag -f "v${VERSION}-flutter"
    echo "📤 Enviando pacote para o GitHub (openmoney-releases)..."
    git push origin main --tags --force
fi

cd "${ROOT_DIR}"
rm -rf "${STAGING_DIR}"

echo ""
echo "🎉 Versão macOS v${VERSION} publicada com sucesso no openmoney-releases!"
echo "🔗 Feed: https://raw.githubusercontent.com/FSF77/openmoney-releases/main/version-flutter.json"
echo "📥 Download: ${DOWNLOAD_URL}"
