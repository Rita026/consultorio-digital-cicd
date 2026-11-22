#!/usr/bin/env bash
# =============================================================================
# desplegar.sh
# Construye y despliega la aplicación en Vercel usando la CLI oficial.
#
# Uso:
#   bash scripts/desplegar.sh staging      # despliegue de liberación (preview)
#   bash scripts/desplegar.sh production   # despliegue candidato a producción
#
# En "production" el despliegue se crea con --skip-domain: queda listo pero
# SIN recibir el dominio público. Así se le pueden correr pruebas antes de
# liberarlo con scripts/liberar.sh (estrategia de "producción escalonada").
#
# Variables:
#   VERCEL_TOKEN       (obligatoria) token de acceso de Vercel
#   VERCEL_ORG_ID      (obligatoria) id del equipo/cuenta en Vercel
#   VERCEL_PROJECT_ID  (obligatoria) id del proyecto en Vercel
#
# Salida:
#   Imprime la URL del despliegue. Si corre en GitHub Actions también la
#   escribe en $GITHUB_OUTPUT como "url".
# =============================================================================
set -euo pipefail

AMBIENTE="${1:-}"
error() { echo "❌ $*" >&2; exit 1; }

[[ -n "${VERCEL_TOKEN:-}" ]]      || error "Falta la variable VERCEL_TOKEN."
[[ -n "${VERCEL_ORG_ID:-}" ]]     || error "Falta la variable VERCEL_ORG_ID."
[[ -n "${VERCEL_PROJECT_ID:-}" ]] || error "Falta la variable VERCEL_PROJECT_ID."

case "$AMBIENTE" in
  staging)
    ENTORNO_VERCEL="preview"
    BANDERAS_BUILD=()
    BANDERAS_DEPLOY=()
    ;;
  production)
    ENTORNO_VERCEL="production"
    BANDERAS_BUILD=(--prod)
    BANDERAS_DEPLOY=(--prod --skip-domain)
    ;;
  *) error "Uso: bash scripts/desplegar.sh staging|production" ;;
esac

# Usa la CLI instalada globalmente o, si no existe, la descarga con npx.
if command -v vercel >/dev/null 2>&1; then
  VERCEL=(vercel)
else
  VERCEL=(npx --yes "vercel@${VERCEL_CLI_VERSION:-latest}")
fi

COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo local)}"

echo "▶ [1/3] Descargando configuración del proyecto en Vercel (${ENTORNO_VERCEL})..."
"${VERCEL[@]}" pull --yes --environment="$ENTORNO_VERCEL" --token="$VERCEL_TOKEN"

echo "▶ [2/3] Construyendo la aplicación (vercel build)..."
"${VERCEL[@]}" build "${BANDERAS_BUILD[@]}" --token="$VERCEL_TOKEN"

echo "▶ [3/3] Subiendo el build a Vercel..."
SALIDA="$("${VERCEL[@]}" deploy --prebuilt "${BANDERAS_DEPLOY[@]}" \
        --meta commit="$COMMIT" --meta ambiente="$AMBIENTE" \
        --token="$VERCEL_TOKEN")"

# La CLI imprime la URL en texto plano o, en modo no interactivo, un JSON.
# Se intenta leer el campo "url" del JSON; si no, se busca la URL en el texto.
URL="$(printf '%s' "$SALIDA" | node -e '
  let t = require("fs").readFileSync(0, "utf8");
  try {
    const j = JSON.parse(t);
    let u = j.url || (j.deployment && j.deployment.url) || "";
    if (u && !u.startsWith("http")) u = "https://" + u;
    process.stdout.write(u);
  } catch { /* no es JSON */ }
')"
if [[ -z "$URL" ]]; then
  URL="$(printf '%s' "$SALIDA" | grep -oE 'https://[A-Za-z0-9.-]+\.vercel\.app' | tail -n 1 || true)"
fi

[[ "$URL" =~ ^https:// ]] || error "No se obtuvo una URL válida del despliegue. Salida de Vercel: $SALIDA"

echo "✅ Despliegue de ${AMBIENTE} listo: ${URL}"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "url=${URL}" >> "$GITHUB_OUTPUT"
fi
