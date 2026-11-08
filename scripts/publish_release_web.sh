#!/bin/bash
set -e

# ==============================================================================
# OpenMoney Flutter - Script de Compilação e Publicação da Versão Web
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

CURRENT_VERSION=$(grep -E "^version:" "${ROOT_DIR}/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d '+' -f 1)
CURRENT_BUILD=$(grep -E "^version:" "${ROOT_DIR}/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d '+' -f 2)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🌐 OpenMoney Web (Cloudflare Pages) — Build v${CURRENT_VERSION}+${CURRENT_BUILD}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

flutter build web --release --no-tree-shake-icons

# Atualiza a pasta web-dist/ para integração direta do Cloudflare Pages via GitHub
rm -rf "${ROOT_DIR}/web-dist"
mkdir -p "${ROOT_DIR}/web-dist"
cp -R "${ROOT_DIR}/build/web/"* "${ROOT_DIR}/web-dist/"

if [ -d "${ROOT_DIR}/coletor" ]; then
    mkdir -p "${ROOT_DIR}/web-dist/coletor"
    cp -R "${ROOT_DIR}/coletor/"* "${ROOT_DIR}/web-dist/coletor/"
fi

echo "✅ Build Web atualizado em: ${ROOT_DIR}/web-dist"

if command -v npx >/dev/null 2>&1 && ! grep -q "SUBSTITUIR_PELO_ID_DO_SEU_D1_NA_CLOUDFLARE" "${ROOT_DIR}/wrangler.toml" 2>/dev/null; then
    echo "☁️ Enviando para Cloudflare Pages via Wrangler..."
    npx wrangler pages deploy "${ROOT_DIR}/web-dist" --project-name=openmoney
else
    echo "📤 Enviando web-dist/ para o GitHub (deploy automático na Cloudflare Pages)..."
    git add lib/ web/ web-dist/ functions/ cloudflare/ scripts/ wrangler.toml
    if ! git diff --staged --quiet; then
        git commit -m "Update OpenMoney Web v${CURRENT_VERSION}+${CURRENT_BUILD}"
        git push origin main
        echo "🎉 Enviado ao GitHub! A Cloudflare Pages atualizará o site automaticamente."
    else
        echo "ℹ️ Nenhuma alteração pendente para enviar."
    fi
fi
