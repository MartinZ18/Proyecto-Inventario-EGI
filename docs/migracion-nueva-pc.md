# Plan de migración a una PC nueva (ej. PC de la facultad)

Guía completa para reproducir el ecosistema del Inventario ITU en
otra PC, usando las VMs exportadas como OVA desde la PC original y
el pipeline de GitHub Actions para el deploy de la capa Kubernetes.

## Topología objetivo

```
PC nueva (Windows, 16 GB+ RAM, SSD)
├── VirtualBox
│   ├── pfsense        192.168.56.2   (importada como OVA)
│   ├── DC01-ITU       192.168.56.10  (importada como OVA)
│   ├── SQLServer2022  192.168.56.20  (importada como OVA)
│   └── LinuxEGI       192.168.56.30  (VM nueva — el workflow
│                                      hace el deploy automático)
└── Red Host-Only      192.168.56.0/24
```

> **LinuxEGI no se exporta**: es mucho más limpio crearla de cero
> y dejar que el pipeline de GitHub Actions haga el deploy completo.
> Las tres VMs de Windows son las que cuestan reconfigurar, por eso
> sí se exportan.

---

## Estimación de tiempo y tamaño

| Tarea | Tiempo estimado |
|---|---|
| Exportar 3 VMs a OVA | 30–60 min (depende del disco) |
| Subir OVAs a Google Drive | 2–8 h (depende del upload) |
| Descargar OVAs en PC facultad | 30 min–2 h (red interna) |
| Importar OVAs + fix red | 30–45 min |
| Setup LinuxEGI + Minikube | 30–45 min |
| Deploy via workflow | 10–15 min |
| Seed Mongo + verificación | 10 min |
| **Total activo** | **~3–4 h** |

Tamaño aproximado de las OVAs (comprimidas):

| VM | Tamaño OVA estimado |
|---|---|
| pfSense | ~500 MB |
| DC01-ITU (Windows Server + AD) | ~8–15 GB |
| SQLServer2022 (Windows Server + SQL) | ~15–25 GB |
| **Total** | **~25–40 GB** |

Conviene iniciar la subida a Google Drive antes de dormir y dejarla
correr de noche.

---

## Paso 0 — Prerrequisitos en la PC de la facultad

Verificar antes de ir:

- [ ] VirtualBox 7.x instalado (descargar de virtualbox.org si no está)
- [ ] SSD con al menos 80 GB libres
- [ ] 16 GB RAM (funciona; ver nota al final sobre optimización)
- [ ] Google Drive instalado o acceso web para descargar las OVAs
- [ ] Acceso a internet para que el runner de GitHub Actions se conecte

---

## Paso 1 — Exportar VMs desde la PC actual (Windows)

Nombres exactos de las VMs en la instalación de VirtualBox actual:

| VM | Nombre en VirtualBox | OVA de salida |
|---|---|---|
| pfSense | `pfSense-Gateway` | `pfsense-gateway.ova` |
| DC / AD | `Window Server AD-DC- Comision B` | `dc01-itu.ova` |
| SQL Server | `Window Server SQL - IIS - Comision B` | `sqlserver2022.ova` |

Usar el script preparado (guarda los OVA en `C:\VMs-Export\`):

```powershell
# Desde la raíz del repo de infraestructura
.\infra\scripts\exportar-vms.ps1

# O con destino personalizado (ej. disco externo):
.\infra\scripts\exportar-vms.ps1 -Destino "D:\VMs-Export"
```

Cada export tarda 10–30 minutos. Total: ~1–3 horas para las 3 VMs.

### Subir a Google Drive

Subir los tres `.ova` a una carpeta compartida en Google Drive. Con
la carpeta compartida (link de solo lectura), se puede abrir en la
PC de la facultad sin necesitar login.

---

## Paso 2 — Importar VMs en la PC de la facultad

### 2.1 Crear la red Host-Only

Abrir PowerShell como administrador en la PC de la facultad:

```powershell
$vbm = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

# Crear la interfaz Host-Only (puede llamarse "VirtualBox Host-Only Ethernet Adapter #2"
# si ya existe una; anotá el nombre que devuelve)
& $vbm hostonlyif create

# Asignarle la IP del gateway (la PC host queda en .1)
& $vbm hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" `
    --ip 192.168.56.1 --netmask 255.255.255.0

# Verificar
& $vbm list hostonlyifs
```

> Si el nombre de la interfaz es distinto (ej. "...Adapter #2"), usá
> ese nombre en todos los comandos siguientes.

### 2.2 Importar las OVAs

Usar el script preparado (detecta la interfaz Host-Only y fija los
adaptadores automáticamente):

```powershell
# OVAs en la carpeta por defecto ($env:USERPROFILE\Downloads\VMs-Export)
.\infra\scripts\setup-virtualbox-nueva-pc.ps1

# O indicando la carpeta donde están los OVA:
.\infra\scripts\setup-virtualbox-nueva-pc.ps1 -OvaDir "C:\VMs-Export"
```

### 2.3 Verificar conectividad entre VMs

Arrancar las tres VMs y desde SQL Server (o el DC):

```cmd
ping 192.168.56.2    :: pfSense
ping 192.168.56.10   :: DC
ping 192.168.56.20   :: SQL Server
```

Si todo responde, la red está bien. Continuar.

---

## Paso 3 — Crear LinuxEGI en la PC de la facultad

### 3.1 Crear la VM en VirtualBox

- Nombre: `LinuxEGI`
- Tipo: Linux / Ubuntu (64-bit)
- RAM: 4096 MB
- Disco: 40 GB (VDI, dinámico)
- Red: Host-Only Ethernet Adapter (`192.168.56.0/24`)
- Instalar Ubuntu Server 22.04 LTS desde ISO

Durante la instalación de Ubuntu:
- Usuario: `itu`, contraseña a elección
- Hostname: `linuxegi`
- Instalar OpenSSH Server (marcar en el instalador)

### 3.2 Configurar IP estática en LinuxEGI

Editar el netplan:

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp0s3:          # ajustar si el adaptador se llama distinto (ip link show)
      dhcp4: false
      addresses: [192.168.56.30/24]
      nameservers:
        addresses: [192.168.56.10, 8.8.8.8]
```

```bash
sudo netplan apply
ip addr show enp0s3   # verificar que tiene 192.168.56.30
```

---

## Paso 4 — Instalar Docker + Minikube + Calico en LinuxEGI

SSH desde la PC de la facultad (o hacerlo directo en la VM):

```bash
ssh itu@192.168.56.30
```

Clonar el repo de infraestructura (si no está ya):

```bash
mkdir -p ~/inventario
git clone https://github.com/MartinZ18/Proyecto-Inventario-EGI-infraestructura.git \
    ~/inventario/infraestructura
```

Correr el script de setup (instala Docker, kubectl, minikube, levanta
el cluster con Calico). Con `--with-claude` también instala Claude Code:

```bash
bash ~/inventario/infraestructura/infra/scripts/setup-linuxegi-nueva-pc.sh

# O con Claude Code incluido:
bash ~/inventario/infraestructura/infra/scripts/setup-linuxegi-nueva-pc.sh --with-claude
```

Después del script, cerrar sesión y volver a entrar (o ejecutar
`newgrp docker`) para que el grupo docker quede activo.

---

## Paso 5 — Registrar el runner de GitHub Actions

Ir a GitHub: `MartinZ18/Proyecto-Inventario-EGI-infraestructura` →
Settings → Actions → Runners → New self-hosted runner (Linux x64) →
copiar el token de registro de un solo uso.

```bash
# El script descarga el runner, lo configura e instala como servicio
bash ~/inventario/infraestructura/infra/scripts/setup-runner.sh --token TOKEN
```

El runner del entorno anterior (PC de escritorio) quedará offline en
GitHub automáticamente cuando no esté corriendo — no hace falta
eliminarlo.

---

## Paso 6 — Verificar GitHub Secrets

Los secrets ya deberían estar cargados del setup anterior. Confirmar en:
`MartinZ18/Proyecto-Inventario-EGI-infraestructura` → Settings →
Secrets and variables → Actions.

Deben existir los 7 secrets:

- `REPO_ACCESS_TOKEN`
- `JWT_SECRET`
- `SQLSERVER_USER`
- `SQLSERVER_PASSWORD`
- `MONGO_ROOT_USER`
- `MONGO_ROOT_PASSWORD`
- `LDAP_BIND_PASSWORD`

---

## Paso 7 — Disparar el workflow

GitHub → `MartinZ18/Proyecto-Inventario-EGI-infraestructura` →
Actions → "Deploy Inventario ITU a Minikube" → Run workflow.

El workflow hace automáticamente:
1. Checkout de infraestructura + backend + frontend
2. Resolución de red (`detectar-red.sh` → `red.example.env` si no hay `red.local.env`)
3. Generación de manifiestos con las IPs reales
4. Build de imágenes Docker dentro de Minikube
5. Apply de namespace, configmaps, endpoints externos, secrets, deployments, services, NetworkPolicies
6. Espera de rollout (180s timeout por deployment)

Verificar en la pestaña Actions que el workflow termina en verde (~10 min).

---

## Paso 8 — Seed de MongoDB (una sola vez)

El PVC de Mongo persiste entre restarts del pod, pero en un Minikube
nuevo el volumen está vacío. El script lee las credenciales
directamente del Secret de Kubernetes (no hay que hardcodear nada):

```bash
bash ~/inventario/infraestructura/infra/scripts/seed-mongo.sh
```

Si el backend está en otra ruta:

```bash
bash ~/inventario/infraestructura/infra/scripts/seed-mongo.sh \
    --backend-repo /ruta/al/backend
```

El script detecta automáticamente si ya hay datos y no repite el
seed si encuentra 12 documentos.

---

## Paso 9 — Optimización de RAM (16 GB)

En la PC de la facultad, limitar el consumo de memoria de SQL Server
para que no compita con las demás VMs:

```sql
-- Conectarse a SQL Server y ejecutar:
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 1536; RECONFIGURE;
```

Asignación recomendada de RAM en VirtualBox:

| VM | RAM asignada |
|---|---|
| pfSense | 512 MB |
| DC01-ITU | 2048 MB |
| SQLServer2022 | 3072 MB |
| LinuxEGI | 4096 MB |
| **Total VMs** | **9728 MB** |
| Windows host + browser | ~4–5 GB |

Durante la defensa cerrar todo lo que no sea VirtualBox y el browser.

---

## Paso 10 — SSH key para LinuxEGI en la nueva PC

Para conectarse a LinuxEGI desde la nueva PC sin contraseña:

```powershell
# PowerShell en la PC de la facultad (Windows)
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519_linuxegi" -N '""'
type "$env:USERPROFILE\.ssh\id_ed25519_linuxegi.pub" | ssh itu@192.168.56.30 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Verificar
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_linuxegi" itu@192.168.56.30 "hostname"
```

---

## Checklist de verificación final

Correr el script de verificación end-to-end (hace todos los chequeos
automáticamente y muestra un resumen OK/FAIL):

```bash
bash ~/inventario/infraestructura/infra/scripts/verificar-migracion.sh
```

Chequeos que realiza:
- 3 pods Running (backend, frontend, mongo)
- 7 NetworkPolicies aplicadas
- Frontend responde HTTP 200
- Login con `mgomez` devuelve JWT
- `GET /inventario/` devuelve 12 equipos con componentes
- NetworkPolicy bloquea frontend → mongo:27017 (demo de seguridad)

---

## Notas para la defensa oral

Ver `docs/runbook-despliegue.md` sección "Orden resumido para la
defensa oral" (6 pasos).

Tener abierto antes de entrar a defender:
1. VirtualBox con las 4 VMs en `Running`
2. Browser en `http://192.168.56.30:30080` (o pfSense NAT si hay acceso externo)
3. Terminal SSH a LinuxEGI para comandos `kubectl` en vivo
4. GitHub Actions en el repo de infraestructura (para mostrar el workflow)
