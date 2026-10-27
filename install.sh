#!/bin/bash
set -e

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
