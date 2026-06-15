#!/usr/bin/env bash
# ============================================================
# Resuelve la configuración de red del laboratorio para esta
# ejecución:
#   1. Carga infra/red.local.env (o infra/red.example.env como
#      fallback, con un aviso). MINIKUBE_IP es la IP estática del host
#      Minikube (ver infra/red.local.env) — ya no se recalcula con
#      `minikube ip`, porque con --driver=docker esa IP es la del
#      bridge interno de Docker, no ruteable desde el resto de la red.
#   2. Si SQLSERVER_IP no está fijado, intenta resolverlo por DNS
#      contra el DC (nslookup sqlserver.itu.local ${DC_IP}), usando
#      el valor del archivo de configuración como fallback.
#
# Uso:
#   source infra/scripts/detectar-red.sh
#
# En GitHub Actions (runner self-hosted), además exporta las
# variables resueltas a $GITHUB_ENV para los pasos siguientes del
# workflow.
#
# Variables resueltas: PFSENSE_LAN_IP, DC_IP, SQLSERVER_IP,
# IP_RED_PROF, MINIKUBE_IP
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "${INFRA_DIR}/red.local.env" ]; then
  # shellcheck disable=SC1091
  source "${INFRA_DIR}/red.local.env"
else
  echo "[detectar-red] infra/red.local.env no existe, usando infra/red.example.env (defaults)" >&2
  # shellcheck disable=SC1091
  source "${INFRA_DIR}/red.example.env"
fi

# Si SQLSERVER_IP no está fijado, intentar resolver por DNS contra el DC.
if [ -z "${SQLSERVER_IP:-}" ] && [ -n "${DC_IP:-}" ] && command -v nslookup >/dev/null 2>&1; then
  DNS_IP="$(nslookup sqlserver.itu.local "${DC_IP}" 2>/dev/null | awk '/^Address: / { print $2 }' | tail -n1 || true)"
  if [ -n "${DNS_IP}" ]; then
    SQLSERVER_IP="${DNS_IP}"
  fi
fi

export PFSENSE_LAN_IP DC_IP SQLSERVER_IP IP_RED_PROF MINIKUBE_IP

echo "[detectar-red] PFSENSE_LAN_IP=${PFSENSE_LAN_IP}"
echo "[detectar-red] DC_IP=${DC_IP}"
echo "[detectar-red] SQLSERVER_IP=${SQLSERVER_IP}"
echo "[detectar-red] IP_RED_PROF=${IP_RED_PROF}"
echo "[detectar-red] MINIKUBE_IP=${MINIKUBE_IP}"

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "PFSENSE_LAN_IP=${PFSENSE_LAN_IP}"
    echo "DC_IP=${DC_IP}"
    echo "SQLSERVER_IP=${SQLSERVER_IP}"
    echo "IP_RED_PROF=${IP_RED_PROF}"
    echo "MINIKUBE_IP=${MINIKUBE_IP}"
  } >> "${GITHUB_ENV}"
fi
