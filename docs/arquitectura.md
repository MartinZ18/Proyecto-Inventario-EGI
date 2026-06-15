# Arquitectura — Inventario ITU

## Visión general

El Inventario ITU es un sistema de gestión de equipos de laboratorio
compuesto por:

- **Frontend**: HTML/CSS/JS vanilla (Bootstrap 5), servido como
  contenido estático por nginx.
- **Backend**: API REST en FastAPI (Python 3.12), con autenticación
  JWT respaldada por LDAP/Active Directory.
- **Base relacional**: SQL Server 2022 (`inventario_ubicaciones`) —
  ubicaciones, equipos, personas, asignaciones, mantenimientos.
- **Base documental**: MongoDB 7 (`inventario_componentes`, colección
  `computadoras`) — componentes detallados de cada equipo (CPU, RAM,
  almacenamiento, periféricos), enlazados por `id_equipo`.
- **Identidad**: Active Directory (`itu.local`) vía LDAP.
- **Red/perímetro**: pfSense (NAT gateway + auth AD, configurable por
  SSH desde `pfsense/scripts/`) e iptables (host de Minikube). Las IPs
  de la red del laboratorio se resuelven dinámicamente (`infra/`, ver
  `docs/topologia-red.md`).
- **Acceso externo**: Cloudflare Tunnel (`cloudflared`) expone el
  frontend en `https://*.trycloudflare.com` sin abrir puertos; el
  NodePort `:30080` sigue disponible para la LAN.
- **Orquestación**: Kubernetes (Minikube + Calico CNI), namespace
  `inventario`, con NetworkPolicies zero-trust.
- **CI/CD**: GitHub Actions (`workflow_dispatch`) con runner
  self-hosted en el host de Minikube.

Este repositorio (`Proyecto-Inventario-EGI-infraestructura`) contiene
todo lo necesario para desplegar y asegurar esos componentes: no
contiene el código de la aplicación (que vive en las ramas
`backend`/`frontend`/`bases-de-datos` del repo principal).

---

## Diagrama de componentes (Mermaid)

```mermaid
flowchart TB
    subgraph INET["Internet"]
        Cliente["Cliente externo\n(wifi/celular)"]
        ClienteLAN["Cliente (navegador, LAN)"]
        CFEdge["Borde Cloudflare"]
    end

    subgraph PFS["pfSense (NAT gateway)"]
        WAN["WAN (NAT VirtualBox)"]
        LAN["LAN ${PFSENSE_LAN_IP}\n= ${IP_RED_PROF}"]
    end

    subgraph DC["DC01-ITU ${DC_IP}"]
        AD["Active Directory DS\n+ DNS + DHCP\n:389 / :53"]
    end

    subgraph SQLVM["VM SQL Server ${SQLSERVER_IP}"]
        SQL["SQL Server 2022\ninventario_ubicaciones\n:1433"]
    end

    subgraph MK["Host Minikube ${MINIKUBE_IP} (iptables)"]
        subgraph NS["namespace: inventario (Calico NetworkPolicies)"]
            FE["frontend (nginx)\nNodePort :30080"]
            BE["backend (FastAPI)\nClusterIP :8000"]
            MONGO["mongo:7\ninventario_componentes\nClusterIP :27017"]
            CF["cloudflared\n(Quick Tunnel)"]
            CM["ConfigMap backend-config"]
            SEC["Secret backend-secret"]
            EPS["sqlserver-service\n(Endpoints externos)"]
            EPL["ldap-service\n(Endpoints externos)"]
        end
    end

    subgraph CI["GitHub Actions"]
        GH["Workflow deploy.yml\n(runner self-hosted en MK)"]
    end

    Cliente -->|"HTTPS :443"| CFEdge
    CFEdge -->|"túnel saliente :443/7844"| CF
    CF -->|":80"| FE

    ClienteLAN -->|"HTTP :80"| WAN
    WAN -->|"NAT port-forward 80 -> 30080 (opcional)"| FE
    LAN --- DC
    LAN --- SQLVM
    LAN --- MK

    FE -->|"/api/ proxy_pass :8000"| BE
    BE -->|":27017"| MONGO
    BE --> EPS -->|":1433"| SQL
    BE --> EPL -->|":389"| AD
    BE -.envFrom.-> CM
    BE -.envFrom.-> SEC

    GH -->|"docker build + kubectl apply"| NS
    PFS -->|"auth pfAdmins :389"| AD
```

---

## Componentes y responsabilidades

| Componente | Responsable (rol) | Repositorio/carpeta |
|---|---|---|
| Frontend (HTML/JS) | Integrante Frontend | rama `frontend` |
| Backend (FastAPI) | Integrante Backend | rama `backend` |
| Scripts SQL Server / MongoDB | Integrante Base de Datos | rama `bases-de-datos` |
| Kubernetes, NetworkPolicies, pfSense, AD, firewall SQL Server, iptables, CI/CD | Martin (Seguridad y Redes) | este repo |

---

## Flujo de autenticación (alto nivel)

1. El usuario abre `index.html` (servido por `frontend`/nginx) e
   ingresa usuario/contraseña institucionales.
2. El frontend llama a `POST /auth/login` (vía proxy `/api/` →
   `backend-service:8000`).
3. `app/services/auth_service.py` delega en
   `app/services/ldap_service.py`:
   - `autenticar()` hace **bind** contra AD con
     `LDAP_USER_DN_TEMPLATE = {username}@itu.local`.
   - `obtener_rol()` determina si el usuario pertenece a
     `Tecnicos`, `Docentes` o `Alumnos` (requiere el bind de servicio
     `svc-inventario`, ver `active-directory/README.md` sección 4).
4. Si las credenciales son válidas, el backend emite un JWT
   (`python-jose`, HS256, 60 min) que el frontend guarda en
   `localStorage` y reenvía en cada request (`Authorization: Bearer`).
5. Los endpoints de escritura (`POST/PUT/DELETE /inventario/...`)
   exigen rol `Tecnicos` vía la dependencia `requiere_tecnico`
   (`app/dependencies.py`).

---

## Flujo de datos del inventario

- `GET /inventario/` y `GET /inventario/{id}` combinan datos de
  **SQL Server** (`Equipo`, `Ubicacion`, `Persona`, `Asignacion`,
  `Mantenimiento`) y **MongoDB** (`computadoras`), enlazados por el
  campo puente `id_equipo`.
- Las altas de equipos crean primero el registro en SQL Server
  (`Equipo`) y luego el documento de componentes en MongoDB con el
  mismo `id_equipo`.

---

## Seguridad: defensa en profundidad

Ver el detalle completo en `docs/topologia-red.md` y `iptables/README.md`.
Resumen de las 3 capas:

1. **pfSense** (borde de red): NAT, port-forward opcional (80 →
   NodePort 30080), autenticación de administradores contra AD.
   Configurable como código vía SSH + `pfSsh.php playback`
   (`pfsense/scripts/`, ver `pfsense/README.md`).
2. **Calico NetworkPolicies** (dentro del clúster): modelo
   default-deny, 8 políticas (00-07) que permiten solo los flujos
   estrictamente necesarios entre frontend/backend/mongo/SQL/AD/
   cloudflared.
3. **iptables** (host de Minikube): filtra el tráfico dirigido al
   nodo (SSH, ICMP, NodePort), sin interferir con las cadenas que
   gestiona Calico.

**Acceso externo (Cloudflare Tunnel)**: el pod `cloudflared` abre una
conexión saliente hacia el borde de Cloudflare — no requiere abrir
puertos entrantes en pfSense ni en el router de internet. La
NetworkPolicy `07-allow-cloudflared-egress` acota esa salida a
443/TCP + 7844/UDP, y el tráfico entrante hacia `frontend` sigue
gobernado por `02-allow-frontend-ingress`: el modelo zero-trust dentro
del clúster no cambia, solo se agrega una vía de entrada adicional.

Además: credenciales nunca en el repo (Secrets de Kubernetes +
GitHub Secrets), JWT con expiración corta (60 min), RBAC por rol de
AD (`Tecnicos`/`Docentes`/`Alumnos`).
