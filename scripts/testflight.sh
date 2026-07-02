#!/usr/bin/env bash
#
# Automatiza: regenerar projeto -> arquivar (Release) -> exportar e enviar ao
# App Store Connect (TestFlight) usando uma chave da App Store Connect API.
#
# Uso:  ./scripts/testflight.sh
#
# Pré-requisitos (feito uma vez):
#   1. Gerar uma chave da App Store Connect API (role App Manager) e baixar o .p8.
#   2. Colocar o .p8 em ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
#   3. Copiar scripts/asc.env.example para scripts/asc.env e preencher.
#
# IMPORTANTE: lembre de subir o build (CURRENT_PROJECT_VERSION no project.yml)
# antes de cada envio — o App Store Connect rejeita builds com número repetido.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f scripts/asc.env ]]; then
  echo "ERRO: scripts/asc.env não encontrado." >&2
  echo "      Copie scripts/asc.env.example para scripts/asc.env e preencha." >&2
  exit 1
fi
# shellcheck disable=SC1091
source scripts/asc.env

: "${ASC_KEY_ID:?defina ASC_KEY_ID em scripts/asc.env}"
: "${ASC_ISSUER_ID:?defina ASC_ISSUER_ID em scripts/asc.env}"
: "${ASC_KEY_PATH:?defina ASC_KEY_PATH em scripts/asc.env}"

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "ERRO: chave .p8 não encontrada em: $ASC_KEY_PATH" >&2
  exit 1
fi

SCHEME="HermesVoice"
PROJECT="HermesVoice.xcodeproj"

echo "==> xcodegen generate"
xcodegen generate >/dev/null

# Lê das build settings resolvidas (o Sources/Info.plist tem placeholders $(...) não resolvidos).
SETTINGS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null)"
VERSION="$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
BUILD="$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')"
GIT_COMMIT="$(git rev-parse --short=8 HEAD 2>/dev/null || echo dev)"
echo "==> Enviando ${SCHEME} ${VERSION} (${BUILD}) — commit ${GIT_COMMIT}"

ARCH_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
mkdir -p "$ARCH_DIR"
ARCH_PATH="${ARCH_DIR}/${SCHEME} ${VERSION} (${BUILD}).xcarchive"
EXPORT_DIR="$(mktemp -d)"

echo "==> Arquivando (Release)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCH_PATH" \
  -allowProvisioningUpdates \
  GIT_COMMIT="$GIT_COMMIT" \
  archive

echo "==> Exportando e enviando ao App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$ARCH_PATH" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo ""
echo "==> OK: ${VERSION} (${BUILD}) enviado."
echo "    Acompanhe em App Store Connect > TestFlight (processa em ~5-15 min)."
