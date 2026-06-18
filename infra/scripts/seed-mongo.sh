#!/usr/bin/env bash
# ============================================================
# Carga los documentos iniciales de componentes en MongoDB.
# Ejecutar desde LinuxEGI después del primer deploy via workflow.
#
# Lee las credenciales de Mongo del Secret de Kubernetes, así
# no hace falta hardcodear nada.
#
# Uso:
#   bash seed-mongo.sh
#   bash seed-mongo.sh --backend-repo /ruta/al/checkout/backend
# ============================================================
set -euo pipefail

BACKEND_REPO="${HOME}/inventario/backend"

for arg in "$@"; do
    case $arg in
        --backend-repo=*) BACKEND_REPO="${arg#*=}" ;;
        --backend-repo) shift; BACKEND_REPO="$1" ;;
    esac
done

SEED_SCRIPT="${BACKEND_REPO}/scripts-dev/componentes_prueba.js"

log() { echo -e "\n\033[1;36m=== $* ===\033[0m"; }
ok()  { echo -e "\033[1;32m[OK]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ---- Verificaciones previas ---------------------------------
[[ -f "$SEED_SCRIPT" ]] || err "No se encontró el seed en $SEED_SCRIPT
  Clonar el repo del backend primero:
  git clone -b backend https://github.com/Agus-tina/Proyecto-Inventario-EGI.git ${HOME}/inventario/backend"

kubectl get pods -n inventario -l app=mongo --no-headers | grep -q Running \
  || err "El pod de mongo no está Running. Verificar: kubectl get pods -n inventario"

# ---- Leer credenciales del Secret de K8s -------------------
log "Leyendo credenciales de backend-secret"
MONGO_USER=$(kubectl get secret backend-secret -n inventario \
    -o jsonpath='{.data.MONGO_USER}' | base64 -d)
MONGO_PASS=$(kubectl get secret backend-secret -n inventario \
    -o jsonpath='{.data.MONGO_PASSWORD}' | base64 -d)
ok "Usuario: $MONGO_USER"

# ---- Verificar si ya hay datos ------------------------------
log "Verificando estado actual de la colección"
POD_MONGO=$(kubectl get pods -n inventario -l app=mongo -o jsonpath='{.items[0].metadata.name}')
COUNT=$(kubectl exec -n inventario "$POD_MONGO" -- \
    mongosh -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase admin \
    --quiet --eval "db.getSiblingDB('inventario_componentes').computadoras.countDocuments()" 2>/dev/null || echo "0")

if [[ "$COUNT" -gt 0 ]]; then
    ok "Ya existen $COUNT documentos en inventario_componentes.computadoras — nada que hacer."
    exit 0
fi

echo "Documentos actuales: $COUNT — ejecutando seed..."

# ---- Copiar y ejecutar el seed ------------------------------
log "Copiando seed al pod $POD_MONGO"
kubectl cp "$SEED_SCRIPT" "inventario/${POD_MONGO}:/tmp/seed.js"

log "Ejecutando seed"
kubectl exec -n inventario "$POD_MONGO" -- \
    mongosh -u "$MONGO_USER" -p "$MONGO_PASS" \
    --authenticationDatabase admin --quiet /tmp/seed.js

# ---- Verificar resultado ------------------------------------
log "Verificando resultado"
COUNT_FINAL=$(kubectl exec -n inventario "$POD_MONGO" -- \
    mongosh -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase admin \
    --quiet --eval "db.getSiblingDB('inventario_componentes').computadoras.countDocuments()")

if [[ "$COUNT_FINAL" -gt 0 ]]; then
    ok "Seed completado: $COUNT_FINAL documentos en inventario_componentes.computadoras"
else
    err "Seed falló: la colección sigue vacía después del seed"
fi
