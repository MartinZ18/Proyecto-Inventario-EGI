# Topología de Red

## Diagrama general

Topología recomendada: **todo en una PC** con VirtualBox, red Host-Only
`192.168.56.0/24` (`IP_RED_PROF`) entre pfSense/AD/SQL Server/Minikube.
El acceso externo (internet) sale por el pod `cloudflared` (Cloudflare
Tunnel), independiente de pfSense. Ver `pfsense/README.md` (sección
"Topología VirtualBox recomendada") para el detalle de adaptadores de
red.

```
                                   Internet
                       ┌───────────────┴────────────────┐
                       │                                 │
              pfSense WAN (NAT VBox)            cloudflared (pod en Minikube)
                       │                         → https://*.trycloudflare.com
                 ┌───────────┐                          │
                 │  pfSense  │  NAT gateway + auth AD   │
                 └───────────┘                          │
                       │ LAN: ${PFSENSE_LAN_IP}          │
                       │ Red Host-Only: ${IP_RED_PROF}   │ (default 192.168.56.0/24)
   ┌───────────────────┼─────────────────────────────────┴──────────────────┐
   │                    │                                                    │
┌──────────────────┐    │    ┌─────────────────────┐    ┌────────────────────────────────┐
│ AD DS+DNS+DHCP    │    │    │ SQL Server 2022      │    │ Host Minikube                    │
│ DC01-ITU          │    │    │ Sin IIS/SSRS         │    │ ${MINIKUBE_IP}                   │
│ ${DC_IP}          │    │    │ ${SQLSERVER_IP}      │    │ namespace: inventario, Calico CNI│
│ :389 LDAP, :53 DNS│    │    │ :1433 SQL            │    │                                  │
└─────────┬─────────┘    │    │ (descartado)         │    │  ┌─────────────────┐ NodePort   │
          │              │    │ (ver README.md)      │    │  │ frontend (nginx) │──► :30080  │
          │ LDAP :389    │    └──────────┬───────────┘    │  └────────┬────────┘  (LAN)     │
          │ (ipBlock     │  SQL :1433    │ (ipBlock       │           │ :8000               │
          │  egress)     │   egress)     │  egress)       │  ┌────────▼────────┐            │
          │              │               │                │  │ backend (FastAPI)│            │
          └──────────────┴── ldap-service / ──────────────┤  └────────┬────────┘            │
                              sqlserver-service             │           │ :27017              │
                              (Service + Endpoints)         │  ┌────────▼────────┐            │
                                                             │  │ mongo (mongo:7)  │            │
                                                             │  └──────────────────┘            │
                                                             │  ┌──────────────────┐            │
                                                             │  │ cloudflared      │── arriba   │
                                                             │  │ → frontend :80   │            │
                                                             │  └──────────────────┘            │
                                                             └──────────────────────────────────┘
```

---

## Configuración de red (dinámica)

Las IPs del laboratorio **no están hardcodeadas** en los manifiestos:
se resuelven al momento del despliegue. El flujo es:

`infra/red.example.env` (plantilla committeada con los defaults de la
red Host-Only) → cada persona la copia una vez a `infra/red.local.env`
(gitignored, ajustable si su red difiere) → `infra/scripts/detectar-red.*`
carga esos valores (`MINIKUBE_IP` es la IP estática del host Minikube,
fijada en `red.local.env`; opcionalmente resuelve `SQLSERVER_IP` por DNS
contra el DC) → `infra/scripts/generar-manifiestos.*` sustituye
los placeholders `${VAR}` y deja el resultado en `kubernetes/_generated/`
(gitignored). Ver `docs/runbook-despliegue.md` (Fase 0).

| Variable | Significado | Default (`infra/red.example.env`) | Usado en |
|---|---|---|---|
| `DC_IP` | IP del Domain Controller (AD DS + DNS + DHCP, `DC01-ITU`) | `192.168.56.10` | `kubernetes/external/ldap-endpoints.yaml`, `pfsense/scripts/`, `active-directory/README.md` |
| `SQLSERVER_IP` | IP de la VM de SQL Server 2022 | `192.168.56.20` | `kubernetes/external/sqlserver-endpoints.yaml`, `sql-server-iis/README.md` |
| `PFSENSE_LAN_IP` | IP de la interfaz LAN de pfSense | `192.168.56.2` | `pfsense/README.md`, `pfsense/scripts/`, `iptables/reglas-perimetrales.sh` |
| `MINIKUBE_IP` | IP estática del host Minikube (LinuxEGI); con `--driver=docker --ports=30080:30080/tcp` el NodePort 30080 queda publicado directo en esta IP | `192.168.56.30` | `pfsense/scripts/nat-port-forward.php`, `sql-server-iis/scripts/configurar-firewall-sql-iis.ps1` |
| `IP_RED_PROF` | Red /24 del laboratorio (Host-Only: pfSense, AD, SQL Server, Minikube) | `192.168.56.0/24` | `kubernetes/network-policies/05-allow-backend-egress.yaml`, `iptables/reglas-perimetrales.sh`, `sql-server-iis/scripts/configurar-firewall-sql-iis.ps1` |

Solo 3 archivos del repo tienen placeholders `${VAR}` y pasan por
`infra/scripts/generar-manifiestos.*`:
- `kubernetes/external/sqlserver-endpoints.yaml` (`${SQLSERVER_IP}`)
- `kubernetes/external/ldap-endpoints.yaml` (`${DC_IP}`)
- `kubernetes/network-policies/05-allow-backend-egress.yaml` (`${IP_RED_PROF}`)

El resto de los manifiestos (configmaps, deployments, services,
namespace, las demás NetworkPolicies) no depende de la red y se aplica
directo desde `kubernetes/`.

---

## Matriz de puertos y protocolos

| Origen | Destino | Puerto/Protocolo | Por qué |
|---|---|---|---|
| Cliente externo (wifi/celular, internet) | `https://*.trycloudflare.com` | 443/TCP (HTTPS) | Acceso externo al frontend vía Cloudflare Tunnel, sin abrir puertos en pfSense |
| `cloudflared` (pod) | Borde de Cloudflare (`0.0.0.0/0`) | 443/TCP + 7844/UDP | Conexión saliente del Quick Tunnel (`07-allow-cloudflared-egress.yaml`) |
| `cloudflared` (pod) | `frontend-service` | 80/TCP | El túnel reenvía al frontend dentro del clúster |
| Cliente (navegador, LAN) | pfSense WAN | 80/TCP | Acceso al frontend vía port-forward de pfSense (opcional, ver `pfsense/README.md` sección 2) |
| pfSense | `frontend-service` (`${MINIKUBE_IP}:30080`) | 80/TCP (NAT port-forward) | Reenvío al NodePort del frontend |
| `frontend` (pod) | `backend-service` | 8000/TCP | Proxy `/api/` de nginx hacia FastAPI |
| `backend` (pod) | `mongo-service` | 27017/TCP | Lectura/escritura de `inventario_componentes.computadoras` |
| `backend` (pod) | `sqlserver-service` → `${SQLSERVER_IP}` | 1433/TCP | SQLAlchemy/pyodbc hacia `inventario_ubicaciones` |
| `backend` (pod) | `ldap-service` → `${DC_IP}` | 389/TCP | Autenticación LDAP/AD (`ldap_service.py`) |
| Todos los pods | kube-dns (`kube-system`) | 53/UDP+TCP | Resolución de nombres de Service |
| Administradores | Host Minikube | 22/TCP (SSH) | Gestión del host (acotado por iptables a `${IP_RED_PROF}`) |
| pfSense | `${DC_IP}` | 389/TCP | Autenticación de `pfAdmins` contra AD |
| pfSense | `${DC_IP}` | 67/68 UDP (DHCP relay) | DHCP Relay hacia el DC |

---

## NetworkPolicies (zero-trust)

Archivos en `kubernetes/network-policies/`, aplicados en orden (00 → 07):

| Archivo | Aplica a (`podSelector`) | Permite | Justificación (menor privilegio) |
|---|---|---|---|
| `00-default-deny.yaml` | todos los pods del namespace | nada (ingress y egress) | Punto de partida zero-trust: nada está permitido salvo que se abra explícitamente |
| `01-allow-dns.yaml` | todos los pods del namespace | egress :53 (UDP/TCP) → `kube-system` | Sin DNS ningún pod puede resolver `*-service`; es la única regla "global" |
| `02-allow-frontend-ingress.yaml` | `app=frontend` | ingress :80 desde cualquier origen | Es el único componente expuesto (NodePort); el resto del clúster sigue cerrado |
| `03-allow-frontend-egress.yaml` | `app=frontend` | egress :8000 → `app=backend` | El frontend solo necesita hablarle a la API (proxy `/api/`) |
| `04-allow-backend-from-frontend.yaml` | `app=backend` | ingress :8000 desde `app=frontend` | Nadie más puede llamar a la API directo, salteando el frontend |
| `05-allow-backend-egress.yaml` | `app=backend` | egress :27017 → `app=mongo`; egress :1433/:389 → `ipBlock ${IP_RED_PROF}` | El backend habla con Mongo (pod) y con SQL Server/AD (VMs externas, acotado a la red del laboratorio) |
| `06-allow-mongodb-from-backend.yaml` | `app=mongo` | ingress :27017 desde `app=backend` | Solo el backend accede a la base documental |
| `07-allow-cloudflared-egress.yaml` | `app=cloudflared` | egress :443/TCP + :7844/UDP → `0.0.0.0/0` | El túnel necesita salir a internet para conectar al borde de Cloudflare; el ingress hacia `frontend` ya está cubierto por `02-allow-frontend-ingress` (acepta cualquier origen) |

**SQL Server y AD usan `ipBlock`** porque son VMs fuera del clúster
(no tienen `podSelector`). **MongoDB usa `podSelector`** porque corre
como pod dentro del namespace `inventario`.
