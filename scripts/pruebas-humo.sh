#!/usr/bin/env bash
# =============================================================================
# pruebas-humo.sh  (smoke tests)
# Pruebas que se ejecutan CONTRA UN ENTORNO YA DESPLEGADO (staging o
# producción) para confirmar que la liberación funciona antes de seguir.
#
# Uso:
#   bash scripts/pruebas-humo.sh https://mi-despliegue.vercel.app
#
# Variables opcionales:
#   COMMIT_ESPERADO   commit que debería estar desplegado (lo compara con /version.json)
#   AMBIENTE_ESPERADO staging | production (lo compara con /version.json)
#   SUPABASE_URL      si se define, verifica que el backend responda
#   SUPABASE_ANON_KEY llave pública para la verificación de Supabase
#   VERCEL_AUTOMATION_BYPASS_SECRET  secreto para saltar la protección de los
#                     despliegues preview de Vercel (Deployment Protection)
#   MAX_TIEMPO_RESPUESTA  tiempo máximo aceptado en segundos (default 2.0)
#   REINTENTOS        intentos para la primera petición (default 10)
#   ARCHIVO_METRICAS  si se define, guarda ahí las métricas en formato JSON
# =============================================================================
set -uo pipefail

BASE_URL="${1:-}"
BASE_URL="${BASE_URL%/}"
MAX_TIEMPO_RESPUESTA="${MAX_TIEMPO_RESPUESTA:-2.0}"
REINTENTOS="${REINTENTOS:-10}"

if [[ ! "$BASE_URL" =~ ^https?:// ]]; then
  echo "Uso: bash scripts/pruebas-humo.sh <url-del-entorno>" >&2
  exit 2
fi

APROBADAS=0
FALLIDAS=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CURL_OPTS=(--silent --show-error --location --max-time 15)
if [[ -n "${VERCEL_AUTOMATION_BYPASS_SECRET:-}" ]]; then
  CURL_OPTS+=(-H "x-vercel-protection-bypass: ${VERCEL_AUTOMATION_BYPASS_SECRET}")
fi

ok()    { echo "  ✅ $*"; APROBADAS=$((APROBADAS + 1)); }
falla() { echo "  ❌ $*"; FALLIDAS=$((FALLIDAS + 1)); }

# pedir <ruta> -> guarda cuerpo en $TMP/body y encabezados en $TMP/headers;
# deja en CODIGO y TIEMPO el código HTTP y el tiempo total.
pedir() {
  local salida
  salida="$(curl "${CURL_OPTS[@]}" -D "$TMP/headers" -o "$TMP/body" \
            -w '%{http_code} %{time_total}' "${BASE_URL}$1" 2>/dev/null)" || salida="000 0"
  CODIGO="${salida%% *}"
  TIEMPO="${salida##* }"
}

encabezado() { grep -i "^$1:" "$TMP/headers" | tail -n 1 | cut -d' ' -f2- | tr -d '\r'; }

echo "🔎 Pruebas de humo contra: ${BASE_URL}"
echo

# --- 1. Disponibilidad (con reintentos, el despliegue puede tardar en propagarse)
echo "1) Disponibilidad"
for ((i = 1; i <= REINTENTOS; i++)); do
  pedir "/"
  [[ "$CODIGO" == "200" ]] && break
  echo "  … intento $i/$REINTENTOS: HTTP $CODIGO, reintentando en 6 s"
  sleep 6
done
if [[ "$CODIGO" == "200" ]]; then ok "La página principal responde HTTP 200"; else
  falla "La página principal respondió HTTP $CODIGO"
  [[ "$CODIGO" == "401" ]] && echo "     (401: activa el bypass de Deployment Protection, ver docs/CICD.md)"
fi
grep -q "<app-root" "$TMP/body" && ok "El HTML contiene <app-root>" || falla "El HTML no contiene <app-root>"

# --- 2. Rendimiento
echo "2) Tiempo de respuesta"
pedir "/"
TIEMPO_INICIO="$TIEMPO"
if awk -v t="$TIEMPO" -v m="$MAX_TIEMPO_RESPUESTA" 'BEGIN { exit !(t <= m) }'; then
  ok "Página principal en ${TIEMPO}s (límite ${MAX_TIEMPO_RESPUESTA}s)"
else
  falla "Página principal tardó ${TIEMPO}s (límite ${MAX_TIEMPO_RESPUESTA}s)"
fi

# --- 3. Recursos estáticos (JS y CSS del build)
echo "3) Recursos del build"
MAIN_JS="$(grep -oE 'main-[A-Za-z0-9]+\.js' "$TMP/body" | head -n 1)"
STYLES_CSS="$(grep -oE 'styles-[A-Za-z0-9]+\.css' "$TMP/body" | head -n 1)"
for recurso in "$MAIN_JS" "$STYLES_CSS"; do
  if [[ -z "$recurso" ]]; then falla "No se encontró la referencia a un recurso en index.html"; continue; fi
  pedir "/$recurso"
  if [[ "$CODIGO" == "200" ]]; then ok "/$recurso carga (HTTP 200)"; else falla "/$recurso respondió HTTP $CODIGO"; fi
done
if [[ -n "$MAIN_JS" ]]; then
  pedir "/$MAIN_JS"
  [[ "$(encabezado cache-control)" == *immutable* ]] \
    && ok "Los recursos con hash se cachean como 'immutable'" \
    || falla "Los recursos con hash no tienen Cache-Control immutable"
fi

# --- 4. Rutas de la SPA (deben resolverse a index.html, no dar 404)
echo "4) Rutas de la aplicación"
for ruta in /login/paciente /login/equipo /portal /consultorio /pacientes /ruta-que-no-existe; do
  pedir "$ruta"
  if [[ "$CODIGO" == "200" ]] && grep -q "<app-root" "$TMP/body"; then
    ok "$ruta carga la aplicación"
  else
    falla "$ruta respondió HTTP $CODIGO"
  fi
done

# --- 5. Versión desplegada
echo "5) Versión desplegada"
pedir "/version.json"
if [[ "$CODIGO" == "200" ]]; then
  ok "/version.json disponible"
  COMMIT_DESPLEGADO="$(node -p "JSON.parse(require('fs').readFileSync('$TMP/body','utf8')).commit" 2>/dev/null || echo '?')"
  AMBIENTE_DESPLEGADO="$(node -p "JSON.parse(require('fs').readFileSync('$TMP/body','utf8')).environment" 2>/dev/null || echo '?')"
  if [[ -n "${COMMIT_ESPERADO:-}" ]]; then
    [[ "$COMMIT_DESPLEGADO" == "$COMMIT_ESPERADO" ]] \
      && ok "El commit desplegado es el esperado (${COMMIT_ESPERADO:0:7})" \
      || falla "Commit desplegado ${COMMIT_DESPLEGADO:0:7} ≠ esperado ${COMMIT_ESPERADO:0:7}"
  fi
  if [[ -n "${AMBIENTE_ESPERADO:-}" ]]; then
    [[ "$AMBIENTE_DESPLEGADO" == "$AMBIENTE_ESPERADO" ]] \
      && ok "El entorno desplegado es '${AMBIENTE_ESPERADO}'" \
      || falla "Entorno desplegado '${AMBIENTE_DESPLEGADO}' ≠ esperado '${AMBIENTE_ESPERADO}'"
  fi
else
  falla "/version.json respondió HTTP $CODIGO"
fi

# --- 6. Encabezados de seguridad
echo "6) Encabezados de seguridad"
pedir "/"
for h in x-content-type-options x-frame-options referrer-policy strict-transport-security; do
  valor="$(encabezado "$h")"
  [[ -n "$valor" ]] && ok "$h: $valor" || falla "Falta el encabezado $h"
done

# --- 7. Backend (Supabase)
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "7) Backend (Supabase)"
  CODIGO_SB="$(curl --silent --max-time 15 -o /dev/null -w '%{http_code}' \
               -H "apikey: ${SUPABASE_ANON_KEY}" "${SUPABASE_URL%/}/auth/v1/health" || echo 000)"
  [[ "$CODIGO_SB" == "200" ]] && ok "Supabase Auth responde HTTP 200" \
                              || falla "Supabase Auth respondió HTTP $CODIGO_SB"
fi

# --- Resumen ----------------------------------------------------------------
TOTAL=$((APROBADAS + FALLIDAS))
echo
echo "Resultado: ${APROBADAS}/${TOTAL} pruebas aprobadas"

if [[ -n "${ARCHIVO_METRICAS:-}" ]]; then
  cat > "$ARCHIVO_METRICAS" <<EOF
{"url":"${BASE_URL}","fecha":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","aprobadas":${APROBADAS},"fallidas":${FALLIDAS},"tiempo_respuesta_s":${TIEMPO_INICIO:-0}}
EOF
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Pruebas de humo: ${BASE_URL}"
    echo "| Métrica | Valor |"
    echo "|---|---|"
    echo "| Pruebas aprobadas | ${APROBADAS}/${TOTAL} |"
    echo "| Tiempo de respuesta (página principal) | ${TIEMPO_INICIO:-?} s |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

[[ "$FALLIDAS" -eq 0 ]]
