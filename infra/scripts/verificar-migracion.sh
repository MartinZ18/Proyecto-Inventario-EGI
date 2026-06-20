#!/usr/bin/env bash
# ============================================================
# Verificación end-to-end post-migración.
# Ejecutar desde LinuxEGI después de completar todos los pasos.
#
# Chequea:
#   - Pods en Running
#   - NetworkPolicies aplicadas
#   - Login contra AD y obtención de JWT
#   - /inventario/ devuelve 12 equipos con componentes
#   - NetworkPolicy bloqueando frontend -> mongo directo
#
# Uso:
#   bash verificar-migracion.sh
#
# Variables de entorno opcionales (si no se pasan, se usan los defaults de lab):
#   VERIFY_USER      usuario AD para el test de login (default: mgomez)
#   VERIFY_PASSWORD  contraseña del usuario          (no tiene default — debe setearse)
#
# Ejemplo:
#   VERIFY_USER=mgomez VERIFY_PASSWORD="MiPassword!1" bash verificar-migracion.sh
# ============================================================
set -uo pipefail

MINIKUBE_IP=$(grep MINIKUBE_IP "$(dirname "$0")/../red.local.env" 2>/dev/null \
    | cut -d= -f2 || echo "192.168.56.30")
BASE_URL="http://${MINIKUBE_IP}:30080"

VERIFY_USER="${VERIFY_USER:-mgomez}"
if [[ -z "${VERIFY_PASSWORD:-}" ]]; then
    read -rsp "Contraseña para ${VERIFY_USER}: " VERIFY_PASSWORD
    echo
fi

pass=0; fail=0
ok()   { echo -e "\033[1;32m[OK]\033[0m   $*"; ((pass++)); }
fail() { echo -e "\033[1;31m[FAIL]\033[0m $*"; ((fail++)); }
info() { echo -e "\033[1;33m[INFO]\033[0m $*"; }

echo "============================================================"
echo " Verificación post-migración — $(date)"
echo " Base URL: $BASE_URL"
echo "============================================================"

# ---- Pods ---------------------------------------------------
echo ""
info "Verificando pods en namespace inventario..."
kubectl get pods -n inventario -o wide

BACKEND_READY=$(kubectl get deployment backend -n inventario \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
FRONTEND_READY=$(kubectl get deployment frontend -n inventario \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
MONGO_READY=$(kubectl get deployment mongo -n inventario \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

[[ "$BACKEND_READY"  -ge 1 ]] && ok "backend  Running (1/1)" || fail "backend  no está Ready"
[[ "$FRONTEND_READY" -ge 1 ]] && ok "frontend Running (1/1)" || fail "frontend no está Ready"
[[ "$MONGO_READY"    -ge 1 ]] && ok "mongo    Running (1/1)" || fail "mongo    no está Ready"

# ---- NetworkPolicies ----------------------------------------
echo ""
info "Verificando NetworkPolicies..."
NP_COUNT=$(kubectl get networkpolicy -n inventario --no-headers 2>/dev/null | wc -l)
[[ "$NP_COUNT" -ge 7 ]] && ok "$NP_COUNT NetworkPolicies aplicadas" \
                         || fail "Solo $NP_COUNT NetworkPolicies (se esperan 7)"

# ---- Frontend accesible ------------------------------------
echo ""
info "Verificando frontend en $BASE_URL ..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$BASE_URL/" || echo "000")
[[ "$HTTP_CODE" == "200" ]] && ok "Frontend responde HTTP 200" \
                             || fail "Frontend devolvió HTTP $HTTP_CODE"

# ---- Login --------------------------------------------------
echo ""
info "Probando login (${VERIFY_USER})..."
TOKEN=$(curl -s -X POST "${BASE_URL}/auth/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${VERIFY_USER}&password=${VERIFY_PASSWORD}" \
    --max-time 10 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")

if [[ -n "$TOKEN" && "$TOKEN" != "null" ]]; then
    ok "Login OK — JWT obtenido"
else
    fail "Login falló — TOKEN vacío. Verificar AD y LDAP_BIND_PASSWORD en backend-secret"
    TOKEN=""
fi

# ---- /inventario/ ------------------------------------------
if [[ -n "$TOKEN" ]]; then
    echo ""
    info "Verificando GET /inventario/ ..."
    RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" \
        "${BASE_URL}/inventario/" --max-time 15 2>/dev/null || echo "[]")
    COUNT=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")
    CON_COMP=$(echo "$RESPONSE" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(sum(1 for e in d if e.get('componentes') is not None))
" 2>/dev/null || echo "0")

    [[ "$COUNT" -ge 12 ]] && ok "$COUNT equipos en /inventario/" \
                           || fail "Solo $COUNT equipos (se esperan 12)"
    [[ "$CON_COMP" -ge 12 ]] && ok "$CON_COMP/12 equipos con componentes de Mongo" \
                              || fail "$CON_COMP/12 equipos con componentes — correr seed-mongo.sh"
fi

# ---- NetworkPolicy bloqueando frontend -> mongo -------------
echo ""
info "Verificando NetworkPolicy: frontend NO debe llegar a mongo:27017 ..."
NP_TEST=$(kubectl exec -n inventario deploy/frontend -- \
    sh -c "nc -zv mongo-service 27017 2>&1; echo EXIT:$?" 2>/dev/null || echo "EXIT:1")
if echo "$NP_TEST" | grep -q "EXIT:1\|timed out\|refused\|BLOQUEADO"; then
    ok "NetworkPolicy funciona: frontend no puede conectar a mongo:27017"
else
    fail "NetworkPolicy no bloquea: frontend llegó a mongo:27017 (salida: $NP_TEST)"
fi

# ---- Resumen ------------------------------------------------
echo ""
echo "============================================================"
echo " Resultado: $pass OK  /  $fail FAIL"
if [[ $fail -eq 0 ]]; then
    echo -e " \033[1;32mTodo en orden — listo para la defensa.\033[0m"
else
    echo -e " \033[1;31mHay $fail chequeo(s) fallido(s) — revisar arriba.\033[0m"
fi
echo "============================================================"
