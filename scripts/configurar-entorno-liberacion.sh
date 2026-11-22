#!/usr/bin/env bash
# =============================================================================
# configurar-entorno-liberacion.sh
# Script de UNA SOLA VEZ que crea y vincula el entorno de liberación:
#
#   1. Crea el proyecto en Vercel y lo vincula a esta carpeta.
#   2. Activa el "Protection Bypass for Automation" para que el pipeline pueda
#      probar los despliegues preview (que Vercel protege por defecto).
#   3. Crea los entornos "staging" y "production" en GitHub.
#   4. Guarda en GitHub los secrets y variables que usa el pipeline.
#
# Requisitos: node, openssl, Vercel CLI (npm i -g vercel) y GitHub CLI (gh).
# Ejecutar desde la raíz del repositorio (Git Bash en Windows):
#   bash scripts/configurar-entorno-liberacion.sh [nombre-proyecto]
# =============================================================================
set -euo pipefail

NOMBRE="${1:-consultorio-digital-cicd}"
error() { echo "❌ $*" >&2; exit 1; }
paso()  { echo; echo "▶ $*"; }

# --- 0. Herramientas y sesiones -------------------------------------------------
for herramienta in node openssl vercel gh git; do
  command -v "$herramienta" >/dev/null 2>&1 || error "No se encontró '$herramienta'. Instálalo antes de continuar."
done
[[ -f package.json && -d .git ]] || error "Ejecuta este script desde la raíz del repositorio."

paso "Verificando sesiones de Vercel y GitHub"
vercel whoami >/dev/null 2>&1 || vercel login
gh auth status >/dev/null 2>&1 || gh auth login
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo "   Repositorio de GitHub: $REPO"

# --- 1. Proyecto en Vercel -------------------------------------------------------
paso "Creando y vinculando el proyecto '$NOMBRE' en Vercel"
vercel project create "$NOMBRE" 2>/dev/null || echo "   (el proyecto ya existía, se reutiliza)"
vercel link --yes --project "$NOMBRE"

VERCEL_ORG_ID="$(node -p "require('./.vercel/project.json').orgId")"
VERCEL_PROJECT_ID="$(node -p "require('./.vercel/project.json').projectId")"
echo "   orgId=$VERCEL_ORG_ID  projectId=$VERCEL_PROJECT_ID"

# --- 2. Bypass de protección para las pruebas automáticas -----------------------
paso "Activando Protection Bypass for Automation"
BYPASS_SECRET="$(openssl rand -hex 16)"
vercel project protection enable "$NOMBRE" --protection-bypass --protection-bypass-secret "$BYPASS_SECRET" --yes

# --- 3. Datos que se piden a la persona -----------------------------------------
paso "Datos de configuración"
echo "   Crea un token en https://vercel.com/account/tokens (alcance: tu cuenta)."
read -r -s -p "   Pega aquí el VERCEL_TOKEN: " VERCEL_TOKEN; echo
[[ -n "$VERCEL_TOKEN" ]] || error "El token no puede estar vacío."

# Valores por defecto tomados de la configuración actual del proyecto.
URL_ACTUAL="$(grep -oE "https://[a-z0-9]+\.supabase\.co" src/environments/environment.ts | head -n 1 || true)"
KEY_ACTUAL="$(grep -oE "key: *'[^']+'" src/environments/environment.ts | head -n 1 | sed -E "s/key: *'([^']+)'/\1/" || true)"

read -r -p "   SUPABASE_URL [${URL_ACTUAL}]: " SUPABASE_URL
SUPABASE_URL="${SUPABASE_URL:-$URL_ACTUAL}"
read -r -p "   SUPABASE_ANON_KEY [usar la del proyecto actual]: " SUPABASE_ANON_KEY
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-$KEY_ACTUAL}"
read -r -p "   URL pública de producción [https://${NOMBRE}.vercel.app]: " PRODUCTION_URL
PRODUCTION_URL="${PRODUCTION_URL:-https://${NOMBRE}.vercel.app}"

[[ -n "$SUPABASE_URL" && -n "$SUPABASE_ANON_KEY" ]] || error "Faltan los datos de Supabase."

# --- 4. Entornos de GitHub --------------------------------------------------------
paso "Creando los entornos 'staging' y 'production' en GitHub"
gh api --silent -X PUT "repos/${REPO}/environments/staging"
gh api --silent -X PUT "repos/${REPO}/environments/production"

# --- 5. Secrets y variables -------------------------------------------------------
paso "Guardando secrets y variables en GitHub"
gh secret set VERCEL_TOKEN                    --repo "$REPO" --body "$VERCEL_TOKEN"
gh secret set VERCEL_ORG_ID                   --repo "$REPO" --body "$VERCEL_ORG_ID"
gh secret set VERCEL_PROJECT_ID               --repo "$REPO" --body "$VERCEL_PROJECT_ID"
gh secret set VERCEL_AUTOMATION_BYPASS_SECRET --repo "$REPO" --body "$BYPASS_SECRET"
gh secret set SUPABASE_URL                    --repo "$REPO" --body "$SUPABASE_URL"
gh secret set SUPABASE_ANON_KEY               --repo "$REPO" --body "$SUPABASE_ANON_KEY"
gh variable set PRODUCTION_URL                --repo "$REPO" --body "$PRODUCTION_URL"

echo
echo "✅ Entorno de liberación configurado."
echo "   Haz un push a 'main' (o ejecuta el workflow manualmente) para el primer despliegue."
