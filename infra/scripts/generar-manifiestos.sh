#!/usr/bin/env bash
# ============================================================
# Genera la versión final de los manifiestos K8s que contienen
# placeholders ${VAR} (IPs/red del laboratorio), sustituyéndolos por
# los valores resueltos por infra/scripts/detectar-red.sh.
#
# Uso:
#   source infra/scripts/detectar-red.sh
#   bash infra/scripts/generar-manifiestos.sh
#
# Procesa TODOS los .yaml de kubernetes/external/ y
# kubernetes/network-policies/ (la mayoría no tienen placeholders;
# envsubst los deja sin cambios) y los copia a:
#   kubernetes/_generated/external/
#   kubernetes/_generated/network-policies/
# (gitignored, ver .gitignore). El resto de los manifiestos
# (configmaps, deployments, services, namespace) no tiene placeholders
# y se aplica directo desde kubernetes/.
#
# Requiere `envsubst` (paquete gettext-base, presente en los runners
# de GitHub Actions basados en Ubuntu).
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT_DIR="${ROOT_DIR}/kubernetes/_generated"

VARS='$PFSENSE_LAN_IP $DC_IP $SQLSERVER_IP $IP_RED_PROF $MINIKUBE_IP'

DIRS=("external" "network-policies")

rm -rf "${OUT_DIR}"

for d in "${DIRS[@]}"; do
  src_dir="${ROOT_DIR}/kubernetes/${d}"
  dst_dir="${OUT_DIR}/${d}"
  mkdir -p "${dst_dir}"
  for src in "${src_dir}"/*.yaml; do
    fname="$(basename "${src}")"
    envsubst "${VARS}" < "${src}" > "${dst_dir}/${fname}"
  done
  echo "[generar-manifiestos] kubernetes/${d}/ -> kubernetes/_generated/${d}/"
done

# Verificación: que no quede ningún ${VAR} sin sustituir.
if grep -rEn '\$\{[A-Z_]+\}' "${OUT_DIR}" >/dev/null 2>&1; then
  echo "[generar-manifiestos] ERROR: quedaron placeholders \${VAR} sin sustituir:" >&2
  grep -rnE '\$\{[A-Z_]+\}' "${OUT_DIR}" >&2
  exit 1
fi

echo "[generar-manifiestos] OK - manifiestos generados en kubernetes/_generated/"
