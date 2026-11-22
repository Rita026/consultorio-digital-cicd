#!/usr/bin/env bash
# =============================================================================
# generar-entorno.sh
# Genera la configuración de la aplicación para el entorno de liberación
# (staging) o de producción, a partir de variables de entorno / secrets.
#
# Produce dos archivos:
#   1. src/environments/environment.ts  -> configuración que Angular compila
#   2. public/version.json              -> datos de la versión desplegada, que
#                                          luego verifican las pruebas de humo
#
# Uso:
#   APP_ENV=staging SUPABASE_URL=... SUPABASE_ANON_KEY=... bash scripts/generar-entorno.sh
#
# Variables:
#   APP_ENV            (obligatoria) staging | production
#   SUPABASE_URL       (obligatoria) URL del proyecto de Supabase (https://...)
#   SUPABASE_ANON_KEY  (obligatoria) llave pública "anon" de Supabase
#   APP_VERSION        (opcional)    versión; por defecto la de package.json
#   GIT_COMMIT         (opcional)    commit; por defecto GITHUB_SHA o git rev-parse
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVO_ENV="$RAIZ/src/environments/environment.ts"
ARCHIVO_VERSION="$RAIZ/public/version.json"

error() { echo "❌ $*" >&2; exit 1; }

# --- 1. Validar variables obligatorias -----------------------------------------
APP_ENV="${APP_ENV:-}"
case "$APP_ENV" in
  staging|production) ;;
  *) error "APP_ENV debe ser 'staging' o 'production' (recibido: '${APP_ENV}')." ;;
esac

[[ -n "${SUPABASE_URL:-}" ]]      || error "Falta la variable SUPABASE_URL."
[[ -n "${SUPABASE_ANON_KEY:-}" ]] || error "Falta la variable SUPABASE_ANON_KEY."
[[ "$SUPABASE_URL" =~ ^https://[A-Za-z0-9.-]+$ ]] \
  || error "SUPABASE_URL debe tener la forma https://<proyecto>.supabase.co (sin '/' al final)."

# --- 2. Datos de la versión ----------------------------------------------------
APP_VERSION="${APP_VERSION:-$(node -p "require('$RAIZ/package.json').version")}"
GIT_COMMIT="${GIT_COMMIT:-${GITHUB_SHA:-$(git -C "$RAIZ" rev-parse HEAD 2>/dev/null || echo 'local')}}"
FECHA_BUILD="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- 3. Escribir environment.ts ------------------------------------------------
# El modo OTP-bypass (solo para desarrollo) queda SIEMPRE desactivado en los
# entornos que genera el pipeline.
cat > "$ARCHIVO_ENV" <<EOF
// ARCHIVO GENERADO por scripts/generar-entorno.sh — no editar a mano en CI.
export const environment = {
  production: true,
  appEnv: '${APP_ENV}',
  appVersion: '${APP_VERSION}',
  gitCommit: '${GIT_COMMIT}',
  supabase: {
    url: '${SUPABASE_URL}',
    key: '${SUPABASE_ANON_KEY}'
  },
  otpBypass: false,
  otpBypassPhone: '',
  otpBypassCode: ''
};
EOF

# --- 4. Escribir version.json --------------------------------------------------
cat > "$ARCHIVO_VERSION" <<EOF
{
  "app": "consultorio-digital",
  "environment": "${APP_ENV}",
  "version": "${APP_VERSION}",
  "commit": "${GIT_COMMIT}",
  "builtAt": "${FECHA_BUILD}"
}
EOF

echo "✅ Entorno '${APP_ENV}' generado"
echo "   - versión: ${APP_VERSION}"
echo "   - commit:  ${GIT_COMMIT}"
echo "   - supabase: ${SUPABASE_URL}"
