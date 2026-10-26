#!/bin/bash
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 Instalador do OpenMoney para macOS              "
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TMP_DIR="/tmp/openmoney-install-$$"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "📡 Consultando versão mais recente..."
VERSION_JSON=$(curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-new/main/version.json)
DOWNLOAD_URL=$(echo "$VERSION_JSON" | grep -o '"downloadUrl": *"[^"]*"' | head -n 1 | cut -d '"' -f 4)
VERSION=$(echo "$VERSION_JSON" | grep -o '"version": *"[^"]*"' | head -n 1 | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ Erro ao obter URL de download do OpenMoney."
    exit 1
fi

echo "📦 Baixando OpenMoney v${VERSION}..."
curl -# -L "$DOWNLOAD_URL" -o "$TMP_DIR/OpenMoney.zip"

echo "📂 Instalando em /Applications..."
ditto -x -k "$TMP_DIR/OpenMoney.zip" "$TMP_DIR"

rm -rf /Applications/OpenMoney.app
cp -R "$TMP_DIR/OpenMoney.app" /Applications/OpenMoney.app
xattr -cr /Applications/OpenMoney.app 2>/dev/null || true

rm -rf "$TMP_DIR"
echo ""
echo "✅ OpenMoney v${VERSION} instalado com sucesso!"
echo "🚀 Abrindo aplicativo..."
open /Applications/OpenMoney.app
