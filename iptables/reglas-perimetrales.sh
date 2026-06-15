#!/usr/bin/env bash
# ============================================================
# reglas-perimetrales.sh
#
# Endurece el host Linux donde corre Minikube (capa "host/perímetro"
# de la defensa en profundidad, ver README.md de esta carpeta).
#
# Alcance DELIBERADO:
#   - Solo toca la cadena INPUT (tráfico DESTINADO al propio host:
#     SSH, NodePort del frontend, ICMP de diagnóstico).
#   - NO toca FORWARD ni las cadenas creadas por Calico/kube-proxy
#     (CNI-*, KUBE-*, cali-*): Kubernetes gestiona esas reglas
#     dinámicamente y sobrescribir/bloquear FORWARD puede romper el
#     clúster (pod-to-pod, kube-dns, NodePort -> Service -> Pod).
#     El control de tráfico ENTRE pods queda a cargo de las
#     NetworkPolicies de Calico (kubernetes/network-policies/).
#
# La sección "CONFIGURACIÓN" toma los valores de las variables de
# entorno IP_RED_PROF / PFSENSE_LAN_IP (ver infra/red.example.env),
# con defaults para la topología Host-Only recomendada
# (192.168.56.0/24, pfSense LAN = 192.168.56.2). Para usar tu propia
# red, cargá infra/red.local.env y preservá el entorno con `sudo -E`:
#
#   source infra/red.local.env
#   sudo -E ./reglas-perimetrales.sh
#
# Uso (con los defaults):
#   sudo ./reglas-perimetrales.sh
#
# Persistencia (Debian/Ubuntu):
#   sudo apt-get install -y iptables-persistent
#   sudo netfilter-persistent save
# ============================================================
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

# ----- CONFIGURACIÓN -----
RED_LABORATORIO="${IP_RED_PROF:-192.168.56.0/24}"  # red completa del laboratorio (pfSense, AD, SQL Server, mgmt)
PFSENSE_LAN_IP="${PFSENSE_LAN_IP:-192.168.56.2}"    # IP LAN de pfSense (origen del port-forward al frontend)
NODEPORT_FRONTEND="30080"                           # frontend-service (kubernetes/services/frontend-service.yaml)

# ----- Limpieza de la cadena INPUT (no tocar FORWARD/OUTPUT: Calico las usa) -----
iptables -F INPUT

# ----- 1. Loopback: siempre permitido -----
iptables -A INPUT -i lo -j ACCEPT

# ----- 2. Conexiones ya establecidas / relacionadas -----
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ----- 3. SSH de administración, solo desde la red del laboratorio -----
iptables -A INPUT -p tcp --dport 22 -s "$RED_LABORATORIO" -j ACCEPT

# ----- 4. ICMP (ping) para diagnóstico, solo desde la red del laboratorio -----
iptables -A INPUT -p icmp --icmp-type echo-request -s "$RED_LABORATORIO" -j ACCEPT

# ----- 5. NodePort del frontend (30080), accesible desde pfSense (port-forward) -----
#         y desde el resto de la red del laboratorio para pruebas directas.
iptables -A INPUT -p tcp --dport "$NODEPORT_FRONTEND" -s "$PFSENSE_LAN_IP" -j ACCEPT
iptables -A INPUT -p tcp --dport "$NODEPORT_FRONTEND" -s "$RED_LABORATORIO" -j ACCEPT

# ----- 6. Política por defecto: DROP -----
# Cualquier otro tráfico entrante al host (no a los pods) queda
# bloqueado: solo SSH/ICMP de gestión y el NodePort del frontend
# llegan al nodo desde fuera.
iptables -P INPUT DROP

echo "Reglas perimetrales aplicadas. Estado actual de INPUT:"
iptables -L INPUT -v -n --line-numbers
