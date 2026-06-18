# Runbook de despliegue end-to-end

Orden recomendado para levantar todo el entorno desde cero. Cada fase
enlaza al documento con el detalle completo. Marcar cada checklist
antes de pasar a la siguiente fase.

```
0. Topología local y red dinámica
        →  1. Active Directory  →  2. SQL Server 2022  →  3. pfSense
        →  4. Minikube + Calico  →  5. Kubernetes (apps + NetworkPolicies)
        →  6. GitHub Actions (CI/CD)
```

---

## Estado actual

| Fase | Estado |
|---|---|
| 0 — Topología local y red dinámica | ✅ Completa |
| 1 — Active Directory | ✅ Completa |
| 2 — SQL Server 2022 | ✅ Completa |
| 3 — pfSense | ✅ Completa |
| 4 — Minikube + Calico | ✅ Completa |
| 5 — Kubernetes (apps + NetworkPolicies) | ✅ Completa |
| 6 — GitHub Actions (CI/CD) | ✅ Completa |
| 7 — Migración al repo principal | ⏳ Pendiente |

📄 Detalle de lo hecho en cada fase, decisiones tomadas (p. ej. IIS/SSRS
descartado en Fase 2) y pendientes abiertos para retomar: ver
`docs/bitacora-despliegue.md`.

---

## Fase 0 — Topología local y red dinámica

📄 Ver `infra/red.example.env`, `pfsense/README.md` (sección "Topología
VirtualBox recomendada") y `docs/topologia-red.md`.

Esta fase es la base de todas las demás: define las IPs que se usan en
el resto del runbook. Pensada para correr **todo en una sola PC** con
VirtualBox (pfSense + AD + SQL Server + Minikube).

1. Crear una red **Host-Only** en VirtualBox: subred `192.168.56.0/24`
   (la PC Windows queda en `192.168.56.1` automáticamente).
2. Asignar IPs estáticas en esa red a las VMs:
   - pfSense (LAN): `192.168.56.2`
   - Domain Controller (`DC01-ITU`): `192.168.56.10`
   - SQL Server 2022: `192.168.56.20`
3. Copiar `infra/red.example.env` → `infra/red.local.env` (gitignored) y
   ajustar los valores si tu red difiere de los defaults de arriba.
4. Antes de correr scripts de este runbook que usan `IP_RED_PROF` /
   `MINIKUBE_IP` / `DC_IP` / `SQLSERVER_IP` / `PFSENSE_LAN_IP`, cargar
   `infra/red.local.env` en la sesión:
   - Linux/macOS: `source infra/scripts/detectar-red.sh` (carga los
     valores de `infra/red.local.env`; `MINIKUBE_IP` es la IP estática
     del host Minikube, ver Fase 4).
   - Windows (PowerShell): `. .\infra\scripts\detectar-red.ps1`.

✅ Checklist: red Host-Only `192.168.56.0/24` creada, pfSense/AD/SQL con
IPs estáticas asignadas, `infra/red.local.env` creado.

---

## Fase 1 — Active Directory (`itu.local`)

📄 Ver `active-directory/README.md`.

1. Si la VM del DC no tiene AD DS, instalarlo y promoverlo
   (sección 1 del README).
2. Ejecutar `active-directory/scripts/04-crear-usuarios-grupos.ps1`
   para crear OUs, grupos y usuarios de prueba.
3. Confirmar con el equipo de **backend** el cambio descripto en la
   sección 4 del README (`obtener_rol()` necesita el bind de servicio
   `svc-inventario`). Si no llega a estar listo para la defensa,
   documentarlo como limitación conocida.

✅ Checklist: `Get-ADDomain` OK, OUs/grupos/usuarios creados, login de
prueba (`mgomez@itu.local`) válido.

---

## Fase 2 — SQL Server 2022

📄 Ver `sql-server-iis/README.md`.

1. Habilitar TCP/IP (puerto 1433 fijo) y modo de autenticación mixto.
2. Crear la base **`inventario_ubicaciones`** (editando el script de
   `bases-de-datos` antes de ejecutarlo, o renombrando la base
   `ubicacion_db` existente).
3. Crear los logins del proyecto (2 usuarios finales):
   ```
   sqlcmd -S localhost -E -i sql-server-iis\scripts\configurar-usuarios-sql.sql
   ```
   - `inventario_admin` — `db_owner` (acceso total, lo usa el backend)
   - `inventario_ro` — `db_datareader` (solo lectura, para demos)
   El Secret de Kubernetes debe tener `SQLSERVER_USER=inventario_admin`.
   Si venías usando `inventarioapp` (script anterior), ese script lo
   elimina automáticamente.
4. Ejecutar `sql-server-iis/scripts/configurar-firewall-sql-iis.ps1`
   (lee `IP_RED_PROF`/`MINIKUBE_IP` de `infra/red.local.env`, ver
   Fase 0 y la cabecera del script).
5. ~~Instalar IIS (sitio admin en `:8081`) e instalar/configurar SSRS.~~
   Evaluado y descartado (2026-06-14): la app se sirve desde Minikube,
   no desde esta VM, y los reportes SSRS no son necesarios para la
   defensa. Detalle del porqué en `sql-server-iis/README.md` sección 5.

5. Limitar la RAM que SQL Server puede consumir (por defecto usa todo):
   ```sql
   -- Correr como sysadmin en la instancia
   sqlcmd -S localhost -E -i sql-server-iis\scripts\configurar-memoria-sqlserver.sql
   ```
   Ajustar el valor `1536` si la VM tiene más/menos de 2048 MB.

✅ Checklist: `sqlcmd` remoto funciona con `inventario_admin`, base
`inventario_ubicaciones` con las 5 tablas y datos de prueba cargados.
`inventario_ro` puede hacer SELECT pero no INSERT/UPDATE.

---

## Fase 3 — pfSense

📄 Ver `pfsense/README.md`.

1. Configurar WAN (NAT de VirtualBox) y LAN (`192.168.56.2/24`), NAT
   outbound automático.
2. **Interfaces > WAN**: desmarcar "Block private networks and loopback
   addresses" y "Block bogon networks". **Imprescindible** — sin esto,
   *cualquier* port-forward WAN (el de este runbook en el paso 4, y los
   "extra" de `pfsense/README.md` secciones 2.1/2.2) descarta todo el
   tráfico entrante antes de llegar a la regla `pass`/`rdr` (el "ISP" del
   WAN es el NAT de VirtualBox, gateway `10.0.2.2`, RFC1918 — ver
   `pfsense/README.md` sección 1 para el detalle). Automatizable con:
   `.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script wan-allow-private`.
3. Habilitar SSH (sección "Habilitar SSH" del README) para poder
   automatizar los pasos siguientes con `pfsense/scripts/`.
4. (Opcional) Crear el port-forward `WAN:80 → ${MINIKUBE_IP}:30080`
   — recién se podrá probar después de la Fase 5, cuando el frontend
   esté desplegado. Requiere el paso 2 (`wan-allow-private`) ya
   aplicado. Automatizable con:
   `.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script nat-port-forward`.
5. Configurar el Authentication Server `AD-ITU-Laboratorio` contra
   `${DC_IP}:389` y el grupo `pfAdmins`. Automatizable con:
   `.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script auth-server-ad`
   (requiere `PFSENSE_BIND_PASSWORD` en `infra/red.local.env`).
6. Configurar DHCP Relay hacia `${DC_IP}` (y desactivar el DHCP local
   de pfSense antes). Automatizable con:
   `.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script dhcp-relay`.

✅ Checklist: login con usuario de dominio (`mgomez`) en pfSense OK,
`admin` local sigue funcionando, DHCP relay entrega IPs del rango de AD.

> 💡 **Extras opcionales** (no forman parte de este checklist, pero
> quedan documentados y automatizados para reproducir en otra PC): acceso
> RDP a las VMs del laboratorio y acceso externo al sitio IIS
> "almacenes" de la VM de SQL — ver `pfsense/README.md` secciones 2.1 y
> 2.2 (ambos requieren el paso 2, `wan-allow-private`, ya aplicado).

---

## Fase 4 — Minikube + Calico CNI

En el host que actuará como nodo de Kubernetes (dentro de la red
Host-Only del laboratorio, recibirá IP por DHCP relay del DC; esa IP es
la que `infra/scripts/detectar-red.*` resuelve como `MINIKUBE_IP`):

```bash
# Docker Engine (requerido por --driver=docker)
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker

# kubectl (repo de pkgs.k8s.io, ajustar v1.31 a la versión que use minikube)
sudo apt-get install -y apt-transport-https gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl

# minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
sudo dpkg -i minikube_latest_amd64.deb

# Levantar el clúster con Calico (requerido para que las
# NetworkPolicies de kubernetes/network-policies/ funcionen).
# --ports=30080:30080/tcp publica el NodePort del frontend directo en
# la IP de este host (${MINIKUBE_IP} = 192.168.56.30, ver Fase 0):
# `minikube ip` por sí solo devuelve la IP interna del bridge de
# Docker, no ruteable desde el resto de la red ni desde pfSense.
minikube start --cni=calico --driver=docker --ports=30080:30080/tcp --memory=2048 --cpus=2

# Verificar
kubectl get nodes
kubectl get pods -n kube-system | grep -i calico
```

Luego aplicar el endurecimiento del host:
📄 Ver `iptables/README.md` → ejecutar `iptables/reglas-perimetrales.sh`.

✅ Checklist: `minikube status` OK, pods de `calico-system`/`kube-system`
en `Running`, `iptables -L INPUT` muestra la política `DROP` + reglas
permitidas.

---

## Fase 5 — Despliegue de la aplicación en Kubernetes

Puede hacerse manualmente (para la primera prueba) o vía GitHub Actions
(Fase 6). Pasos manuales, desde el host de Minikube:

```bash
# 0. Resolver la red del laboratorio y generar los manifiestos finales
#    (sustituye ${PFSENSE_LAN_IP}/${DC_IP}/${SQLSERVER_IP}/${IP_RED_PROF}/
#    ${MINIKUBE_IP} en kubernetes/external/ y
#    kubernetes/network-policies/05-allow-backend-egress.yaml; deja el
#    resultado en kubernetes/_generated/, gitignored)
source infra/scripts/detectar-red.sh
bash infra/scripts/generar-manifiestos.sh

# 1. Namespace + configuración no sensible + endpoints externos
kubectl apply -f kubernetes/00-namespace.yaml
kubectl apply -f kubernetes/configmaps/
kubectl apply -f kubernetes/_generated/external/

# 2. Secret del backend (NO commitear con valores reales)
kubectl create secret generic backend-secret -n inventario \
  --from-literal=JWT_SECRET_KEY="$(python3 -c 'import secrets;print(secrets.token_hex(32))')" \
  --from-literal=SQLSERVER_USER="inventario_app" \
  --from-literal=SQLSERVER_PASSWORD="<password-real>" \
  --from-literal=MONGO_USER="inventario_app" \
  --from-literal=MONGO_PASSWORD="<password-real>"

# 3. Build de imágenes en el daemon de Minikube
eval $(minikube docker-env)
docker build -t inventario-api:latest <ruta-checkout-backend>
cp docker/frontend/nginx.conf docker/frontend/.dockerignore <ruta-checkout-frontend>/
docker build -f docker/frontend/Dockerfile -t inventario-web:latest <ruta-checkout-frontend>

# 4. Deployments + Services
kubectl apply -f kubernetes/deployments/
kubectl apply -f kubernetes/services/

# 5. NetworkPolicies (al final, cuando los pods/labels ya existen)
kubectl apply -f kubernetes/_generated/network-policies/

# 6. Verificar
kubectl get pods -n inventario -o wide
kubectl rollout status deployment/backend -n inventario
kubectl rollout status deployment/frontend -n inventario
kubectl rollout status deployment/mongo -n inventario
curl http://${MINIKUBE_IP}:30080/

# 7. Acceso externo: aplicar (una sola vez, desde la PC Windows) el NAT
#    port-forward de pfSense y el port-forward a nivel VirtualBox
#    (ver pfsense/README.md seccion 2)
#    .\pfsense\scripts\aplicar-config-pfsense.ps1 -Script nat-port-forward
```

⚠️ Seed de MongoDB: el workflow (Fase 6) lo ejecuta automáticamente
en cada corrida (idempotente). Para hacerlo a mano después de un deploy
manual o un reset de Mongo:

```bash
bash infra/scripts/seed-mongo.sh --backend-repo <ruta-checkout-backend>
```

El script lee credenciales del Secret de Kubernetes, verifica si ya hay
datos (y no toca nada si los hay), y carga los documentos de
`scripts-dev/componentes_prueba.js` del repo del backend. Usar SIEMPRE
ese archivo; NO el de `bases-de-datos` (`inventario_db.componentes`),
que usa la base/colección incorrecta.

✅ Checklist: los 3 Deployments en `Running` (1/1), `curl` al frontend
responde `200`, login desde el navegador funciona, `/inventario/`
devuelve datos combinados de SQL Server + Mongo, y `curl http://127.0.0.1/`
desde la PC Windows (port-forward VirtualBox + NAT pfSense, ver
`pfsense/README.md` sección 2) carga el frontend desde fuera de la red
del laboratorio.

---

## Fase 6 — GitHub Actions (CI/CD)

📄 Ver `.github/workflows/deploy.yml` (comentarios al inicio del archivo
con el detalle de runner y secrets).

1. Registrar un runner self-hosted (etiqueta `minikube`) en el host de
   Minikube: **Settings → Actions → Runners → New self-hosted runner**
   en el repo de infraestructura.
2. En esa misma máquina, crear `infra/red.local.env` (a partir de
   `infra/red.example.env`, ver Fase 0) dentro del checkout del repo de
   infraestructura. El workflow lo lee en el paso "Resolver
   configuración de red" — no hace falta reemplazar ningún placeholder
   a mano ni commitear nada.
3. Cargar los GitHub Secrets: `REPO_ACCESS_TOKEN`, `JWT_SECRET`,
   `SQLSERVER_USER`, `SQLSERVER_PASSWORD`, `MONGO_ROOT_USER`,
   `MONGO_ROOT_PASSWORD`.
4. Ejecutar el workflow manualmente: **Actions → Deploy Inventario ITU
   a Minikube → Run workflow**.

✅ Checklist: el workflow termina en verde, `kubectl get pods -n
inventario` muestra los 3 Deployments actualizados, el frontend sigue
accesible vía NodePort/pfSense, y el último paso del workflow ("Estado
del despliegue") imprime la URL LAN (`http://${MINIKUBE_IP}:30080`) y
recuerda el acceso externo vía el port-forward NAT de pfSense +
VirtualBox (`pfsense/README.md` sección 2).

---

## Fase 7 — Migración al repo principal

📄 Ver `docs/migracion-repo-principal.md` para el paso a paso completo.

El runner self-hosted está registrado en el fork personal
`MartinZ18/Proyecto-Inventario-EGI-infraestructura`. Para que todo el
equipo pueda disparar el workflow desde el repo compartido
(`Agus-tina/Proyecto-Inventario-EGI`) hay que:

1. Pushear el código de infra al repo principal (rama `seguridad` para el
   trabajo de Martin, rama `despliegue` para el material de CI/CD).
2. Dar de baja el runner del fork (`./config.sh remove`).
3. Registrar el runner en el repo principal con un token nuevo.
4. Cargar los 7 GitHub Secrets en el repo principal.
5. Crear `infra/red.local.env` en el workspace nuevo del runner.
6. Disparar el workflow desde el repo principal y verificar que termina
   en verde.

⚠️ El Secret `LDAP_BIND_PASSWORD` es nuevo — no estaba en el fork
original; es necesario para el fix de LDAP del backend.

✅ Checklist: workflow del repo principal termina en verde, `kubectl get
pods -n inventario` muestra los 3 Deployments, login desde el frontend
funciona.

---

## Orden resumido para la defensa oral

1. Mostrar `docs/arquitectura.md` (diagrama general).
2. Mostrar `kubectl get pods,svc,networkpolicy -n inventario`.
3. Disparar el workflow de GitHub Actions en vivo (o mostrar una
   ejecución previa).
4. Probar el login (AD) y un CRUD de equipos desde el frontend.
5. Mostrar una NetworkPolicy bloqueando tráfico no permitido (por
   ejemplo, `kubectl exec` en el pod `frontend` e intentar conectar
   directo a `mongo-service:27017` → debe fallar).
6. Abrir `http://<IP_WAN_PFSENSE_O_PUBLICA>/` (NAT port-forward de
   pfSense + port-forward VirtualBox `host:80 -> WAN:80`, ver
   `pfsense/README.md` sección 2) desde un dispositivo fuera de la red
   del laboratorio para mostrar el acceso externo real.
