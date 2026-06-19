# Proyecto Inventario EGI — Repo Principal

**Repositorio central del Proyecto Integrador EGI (ITU)** — sistema de inventario
de equipos de laboratorio. Acá vive todo: infra, seguridad, CI/CD y el código de
cada capa subido por el equipo.

## Ramas por capa

| Rama | Responsable | Contenido |
|---|---|---|
| `main` | Martin (Seguridad y Redes) | Infra, Kubernetes, CI/CD, pfSense, AD, iptables |
| `backend` | (Backend) | FastAPI + Python — código de la API |
| `frontend` | (Frontend) | HTML/JS/Bootstrap — interfaz web |
| `bases-de-datos` | (Bases de datos) | Scripts SQL Server + MongoDB |

El pipeline de CI/CD (`.github/workflows/deploy.yml`) toma el código de las ramas
`backend` y `frontend` de este mismo repo, lo buildea y lo despliega en Minikube
en la VM **LinuxEGI** de la facultad.

---

## Empezar acá

- 📐 **`docs/arquitectura.md`** — visión general del sistema, diagrama
  de componentes (Mermaid), flujo de autenticación y modelo de
  seguridad en capas.
- 🌐 **`docs/topologia-red.md`** — diagrama de red, esquema de
  configuración de red dinámica, matriz de puertos/protocolos y
  detalle de las 7 NetworkPolicies zero-trust (00-06).
- 🚀 **`docs/runbook-despliegue.md`** — orden de despliegue end-to-end
  (Fase 0: red local → AD → SQL Server → pfSense → Minikube/Calico
  → Kubernetes → GitHub Actions), con comandos y checklists por fase.
- 🔧 **`infra/red.example.env`** — plantilla de configuración de red
  del laboratorio (copiar a `infra/red.local.env`, gitignored, antes de
  desplegar).

---

## Estructura del repositorio

```
.
├── docs/                    Documentación (arquitectura, topología, runbook)
├── infra/                   Configuración de red dinámica
│   ├── red.example.env      Plantilla (commiteada) -> copiar a red.local.env
│   └── scripts/              detectar-red.*, generar-manifiestos.*
├── docker/frontend/         Dockerfile + nginx.conf del frontend
├── kubernetes/              Manifiestos del namespace "inventario"
│   ├── 00-namespace.yaml
│   ├── configmaps/          Configuración no sensible del backend
│   ├── secrets/             Plantilla de Secret (no se commitean valores reales)
│   ├── deployments/         backend, frontend, mongo
│   ├── services/            ClusterIP/NodePort
│   ├── external/            Endpoints hacia SQL Server y AD (placeholders ${VAR})
│   ├── network-policies/    7 políticas zero-trust (00-06)
│   └── _generated/          (gitignored) manifiestos con ${VAR} ya resueltos
├── .github/workflows/       Pipeline de despliegue (deploy.yml)
├── pfsense/                 Runbook + automatización (SSH/pfSsh.php)
│   └── scripts/              nat-port-forward.php, auth-server-ad.php,
│                              dhcp-relay.php, aplicar-config-pfsense.ps1
├── active-directory/        Runbook + script de creación de OUs/grupos/usuarios
├── sql-server-iis/          Runbook + script de firewall para SQL Server 2022
└── iptables/                Reglas de firewall del host de Minikube
```

---

## Configuración de red (dinámica)

Las IPs del laboratorio (pfSense, AD, SQL Server, Minikube) **no están
hardcodeadas**: se resuelven al desplegar a partir de
`infra/red.example.env` (plantilla commiteada, defaults de la red
Host-Only `192.168.56.0/24` recomendada en `pfsense/README.md`) →
`infra/red.local.env` (copia local, gitignored, una por máquina) →
`infra/scripts/detectar-red.*` (carga esos valores — `MINIKUBE_IP` es
la IP estática del host Minikube — y opcionalmente resuelve
`SQLSERVER_IP` por DNS) →
`infra/scripts/generar-manifiestos.*` (sustituye los placeholders
`${VAR}` y genera `kubernetes/_generated/`, gitignored). Tabla completa
de variables en `docs/topologia-red.md`; pasos en
`docs/runbook-despliegue.md` (Fase 0).

---

## Acceso externo

El frontend queda disponible por dos vías que conviven sin
reemplazarse:

- **LAN (NodePort `:30080`)**: cualquier equipo en la red del
  laboratorio puede abrir `http://${MINIKUBE_IP}:30080` directamente, o
  vía el port-forward de pfSense (`pfsense/README.md`, sección 2).
- **Fuera de la red del laboratorio (NAT port-forward)**: pfSense
  reenvía `WAN:80 -> ${MINIKUBE_IP}:30080`
  (`pfsense/scripts/nat-port-forward.php`, requiere
  `wan-allow-private.php` aplicado primero) y, para llegar desde fuera
  de la red Host-Only, un port-forward a nivel VirtualBox en la VM
  `pfSense-Gateway` (`host:80 -> WAN:80`, mismo patrón que los de
  RDP/IIS). No depende de ningún servicio externo. Ver
  `pfsense/README.md` sección 2 para los comandos.

---

## Mismatches conocidos (resueltos en este repo)

Documentados también en el `CLAUDE.md` raíz del proyecto:

| Mismatch | Resolución aplicada |
|---|---|
| SQL Server: script crea `ubicacion_db`, backend espera `inventario_ubicaciones` | `sql-server-iis/README.md` — renombrar/crear la base como `inventario_ubicaciones` |
| MongoDB: el seed de `bases-de-datos` crea `inventario_db.componentes`, backend espera `inventario_componentes.computadoras` | `kubernetes/deployments/mongo-deployment.yaml` — usar en su lugar el seed correcto `Proyecto-Inventario-EGI-backend/scripts-dev/componentes_prueba.js` (ya usa `inventario_componentes`/`computadoras`) |
| Mongo puerto 27018 (docker-compose local) vs 27017 | `kubernetes/configmaps/backend-configmap.yaml` usa `MONGO_PORT=27017` (puerto del Service en K8s) |
| LDAP del backend (OpenLDAP, `dc=itu,dc=edu,dc=ar`) vs AD real (`itu.local`) | `active-directory/README.md` — `LDAP_BASE_DN`/`LDAP_USER_DN_TEMPLATE` actualizados para AD |
| `obtener_rol()` usa un bind admin hardcodeado (`cn=admin`/`admin`, solo dev) | `active-directory/README.md` sección 4 — requiere cambio coordinado en el backend (cuenta `svc-inventario`) |
