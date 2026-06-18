#!/usr/bin/env bash
# ============================================================
# Configura LinuxEGI desde cero en la PC de destino:
#   - Docker Engine
#   - kubectl
#   - minikube con Calico CNI
#
# Prerequisito: Ubuntu 22.04 LTS con IP 192.168.56.30 ya
# configurada en netplan y SSH operativo.
#
# Uso (desde la PC de destino, SSH a LinuxEGI o directo):
#   bash setup-linuxegi-nueva-pc.sh
# ============================================================
set -euo pipefail

log() { echo -e "\n\033[1;36m=== $* ===\033[0m"; }
ok()  { echo -e "\033[1;32m[OK]\033[0m $*"; }

# ---- Docker Engine ------------------------------------------
log "Instalando Docker Engine"
sudo apt-get update -qq
sudo apt-get install -y ca-certificates curl gnupg apt-transport-https gpg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -qq
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker "$USER"
ok "Docker instalado"

# ---- kubectl ------------------------------------------------
log "Instalando kubectl"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
sudo apt-get update -qq
sudo apt-get install -y kubectl
ok "kubectl $(kubectl version --client=true --output=yaml | grep gitVersion | awk '{print $2}')"

# ---- minikube -----------------------------------------------
log "Instalando minikube"
curl -fsSL -o /tmp/minikube_latest_amd64.deb \
  https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
sudo dpkg -i /tmp/minikube_latest_amd64.deb
ok "minikube $(minikube version --short)"

# ---- Levantar el cluster ------------------------------------
log "Iniciando Minikube con Calico CNI"
# Necesitamos newgrp docker o sg docker para usar docker sin relogin.
# Si el usuario ya está en el grupo (relogin previo), funciona directo.
sg docker -c "minikube start --cni=calico --driver=docker --ports=30080:30080/tcp --memory=2048 --cpus=2"
sg docker -c "kubectl get nodes"
sg docker -c "kubectl get pods -n kube-system | grep calico" || true
ok "Minikube levantado"

# ---- envsubst (requerido por generar-manifiestos.sh) --------
sudo apt-get install -y gettext-base
ok "envsubst disponible"

# ---- Resumen ------------------------------------------------
echo ""
echo "============================================================"
echo " LinuxEGI lista. Proximos pasos:"
echo ""
echo "  1. Cerrar sesion y volver a entrar (o 'newgrp docker')"
echo "     para que el usuario quede en el grupo docker."
echo ""
echo "  2. Registrar el runner de GitHub Actions:"
echo "     bash ~/inventario/infraestructura/infra/scripts/setup-runner.sh --token TOKEN"
echo ""
echo "  3. Disparar el workflow en GitHub Actions."
echo ""
echo "  4. Correr el seed de MongoDB (una vez, Minikube es nuevo):"
echo "     bash ~/inventario/infraestructura/infra/scripts/seed-mongo.sh"
echo "============================================================"
