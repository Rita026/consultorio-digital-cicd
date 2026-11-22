#!/usr/bin/env bash
# =============================================================================
# liberar.sh
# Libera (promueve) un despliegue ya probado para que reciba el dominio de
# producción. También sirve para hacer ROLLBACK: basta con pasarle la URL de un
# despliegue anterior que funcionaba.
#
# Uso:
#   bash scripts/liberar.sh https://consultorio-xxxx.vercel.app
#
# Variables:
#   VERCEL_TOKEN, VERCEL_ORG_ID, VERCEL_PROJECT_ID (obligatorias)
# =============================================================================
set -euo pipefail

URL_DESPLIEGUE="${1:-}"
error() { echo "❌ $*" >&2; exit 1; }

[[ "$URL_DESPLIEGUE" =~ ^https:// ]] || error "Uso: bash scripts/liberar.sh <url-del-despliegue>"
[[ -n "${VERCEL_TOKEN:-}" ]]      || error "Falta la variable VERCEL_TOKEN."
[[ -n "${VERCEL_ORG_ID:-}" ]]     || error "Falta la variable VERCEL_ORG_ID."
[[ -n "${VERCEL_PROJECT_ID:-}" ]] || error "Falta la variable VERCEL_PROJECT_ID."

if command -v vercel >/dev/null 2>&1; then
  VERCEL=(vercel)
else
  VERCEL=(npx --yes "vercel@${VERCEL_CLI_VERSION:-latest}")
fi

echo "▶ Liberando ${URL_DESPLIEGUE} al dominio de producción..."
"${VERCEL[@]}" promote "$URL_DESPLIEGUE" --yes --timeout=5m --token="$VERCEL_TOKEN"
echo "✅ Liberación completada."
