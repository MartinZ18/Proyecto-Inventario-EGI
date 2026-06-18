# Bitácora de despliegue

Registro de avance del laboratorio: qué se hizo en cada fase, qué
decisiones se tomaron (y por qué) y qué queda abierto. El paso a paso
para ejecutar cada fase está en `docs/runbook-despliegue.md` (incluye
una tabla de "Estado actual" al principio); esta bitácora es el
complemento — el detalle de **qué se hizo y qué falta** — para retomar
el trabajo en otra sesión sin perder el hilo.

---

## Fase 0 — Topología y red ✅

- Red **Host-Only `192.168.56.0/24`** creada en VirtualBox (adaptador
  "VirtualBox Host-Only Ethernet Adapter"; la PC Windows queda en
  `192.168.56.1`).
- Las VMs del laboratorio se recablearon a esta red y se les asignaron
  IPs estáticas:
  - pfSense (LAN): `192.168.56.2`
  - Domain Controller (`DC01-ITU`): `192.168.56.10`
  - SQL Server 2022: `192.168.56.20`
- `infra/red.local.env` creado a partir de `infra/red.example.env`
  (gitignored, valores ajustados a esta topología).

---

## Fase 1 — Active Directory (`itu.local`) ✅

- AD DS + DNS instalado y promovido en `DC01-ITU` (dominio `itu.local`,
  NetBIOS `ITU`).
- Estructura de OUs creada bajo `OU=ITU`: `User`, `Computer`, `Server`,
  `Printer`, `Grupos`.
- 6 grupos de seguridad (`pfAdmins`, `InventarioAdmins`,
  `InventarioUsers`, `Tecnicos`, `Docentes`, `Alumnos`) y 7 usuarios de
  prueba creados con
  `active-directory/scripts/04-crear-usuarios-grupos.ps1` (ver
  `active-directory/README.md` sección 2 para el detalle de cada uno).
- Login de prueba `mgomez@itu.local` validado contra el dominio.

**Abierto**: el cambio en `obtener_rol()` del backend (segundo bind LDAP
con `svc-inventario@itu.local`, en vez del admin hardcodeado del
OpenLDAP de desarrollo) sigue pendiente de coordinar con el integrante
de backend — ver `active-directory/README.md` sección 4. Hasta que se
haga, el login contra AD valida credenciales correctamente, pero el
RBAC (`requiere_tecnico`) no puede distinguir roles.

---

## Fase 2 — SQL Server 2022 ✅ (2026-06-14)

- TCP/IP habilitado (puerto fijo `1433`) y modo de autenticación mixto
  activado en la instancia.
- Base `inventario_ubicaciones` creada/alineada (ver
  `sql-server-iis/README.md` sección 2 para el detalle del mismatch con
  el script `Script SQL Server 2022.sql`, que crea `ubicacion_db`).
- Login `inventario_app` (SQL Authentication) creado, con roles
  `db_datareader`, `db_datawriter` y `db_ddladmin` sobre
  `inventario_ubicaciones`.
- Firewall configurado con
  `sql-server-iis/scripts/configurar-firewall-sql-iis.ps1`: reglas
  `1433/TCP` y `1434/UDP` restringidas a `192.168.56.0/24`.

### Decisión: IIS + SSRS evaluado y descartado (2026-06-14)

El plan original para esta VM incluía instalar IIS (sitio de
administración en `:8081`) y SQL Server Reporting Services — SSRS
(reportes en `/Reports`: equipos por ubicación, historial de
mantenimientos). Se decidió **no instalarlos**:

- La app (frontend + backend) se sirve desde Minikube (Fase 5), no
  desde esta VM — IIS acá no aportaba nada a ese flujo, solo generaba
  confusión.
- SSRS era "nice to have" para la defensa oral, no un requisito, y suma
  un instalador aparte (no viene con SQL Server 2022) más 3 puertos
  abiertos (`80`, `443`, `8081`) sin ningún consumidor en el resto del
  runbook.
- Menos servicios/puertos expuestos en la VM de base de datos = menor
  superficie de ataque, en línea con el enfoque zero-trust del resto del
  repo (NetworkPolicies, iptables).

Detalle completo y alternativa (endpoint propio del backend, ya
autenticado por JWT/LDAP, si más adelante se necesitan reportes) en
`sql-server-iis/README.md` sección 5.

Como consecuencia de esta decisión se actualizaron 8 documentos del repo
(runbook, topología de red, arquitectura, pfSense, READMEs y el script
de firewall) quitando las referencias a IIS/SSRS/8081/80/443. El nombre
de la carpeta `sql-server-iis/` se deja igual para no romper referencias
del resto del repo (aclarado en `sql-server-iis/README.md`).

### Abierto

- ✅ **Limpieza de firewall completada (2026-06-15)**: de las 3 reglas
  viejas (`Inventario - IIS Admin (TCP 8081)`,
  `Inventario - SSRS HTTP (TCP 80)`, `Inventario - SSRS HTTPS (TCP 443)`)
  se borraron las 3. La VM de SQL ya tenía IIS instalado para otro
  propósito (sitio "almacenes", no relacionado con el SSRS evaluado y
  descartado más arriba) que necesita el puerto 80 — se creó una regla
  nueva con nombre correcto, `Inventario - IIS Almacenes (TCP 80)`. Ver
  detalle del port-forward externo en "Extra" más abajo.
- Verificación de conectividad desde Minikube al motor SQL (último ítem
  del checklist de `sql-server-iis/README.md` sección 6) — pendiente
  hasta tener el host de Minikube levantado (Fase 4).

---

## Fase 3 — pfSense ✅ (2026-06-14)

- **WAN/LAN**: WAN en NAT de VirtualBox, LAN estática `192.168.56.2/24`.
  NAT outbound automático.
- **SSH habilitado** (System > Advanced > Admin Access), acceso por clave
  pública (`~/.ssh/id_ed25519_pfsense`, alias `pfsense` en
  `~/.ssh/config`), `SSHd Key Only = Public Key Only`.
- **Automatización vía `php -f`**: se descubrió que `pfSsh.php playback
  <archivo>` no funciona en pfSense 2.8 para scripts propios (solo
  acepta sesiones predefinidas). `pfsense/scripts/aplicar-config-pfsense.ps1`
  y las 3 plantillas `.php` se actualizaron para ejecutar
  `php -f /tmp/<script>.php` por SSH (la sesión `admin` corre como root).
- **Authentication Server `AD-ITU-Laboratorio`** (LDAP contra
  `192.168.56.10:389`, basedn `DC=itu,DC=local`, authcn
  `OU=ITU,DC=itu,DC=local`) + grupo remoto `pfAdmins` (gid 2000,
  `WebCfg - All pages`), creados con `auth-server-ad.php` vía `php -f`.
- **Limpieza**: se borró el Authentication Server `AD-Laboratorio`
  (`192.168.1.10`), leftover de un AD de 2019 que ya no se usa.
- **Fix de credenciales del bind `pfsense_bind`** (dos problemas
  encontrados y corregidos):
  - La cuenta real está en `OU=pfsense,DC=itu,DC=local`, no en
    `OU=User,OU=ITU,...` como decía la documentación original — corregido
    en `auth-server-ad.php` y anotado en `active-directory/README.md`.
  - La password documentada `Pfsense!2025` nunca fue válida: viola la
    política de complejidad de AD por contener 7 caracteres consecutivos
    del `sAMAccountName` (`pfsense_bind`). Se reseteó a `LdapAuth!2025`
    con `Set-ADAccountPassword -Reset` y se actualizó
    `infra/red.local.env`, `active-directory/README.md` y
    `04-crear-usuarios-grupos.ps1`.
- **Verificación de login** (3.4): `mgomez@itu.local` (grupo `pfAdmins`)
  inició sesión con acceso completo vía `LDAP/AD-ITU-Laboratorio`;
  `admin` local sigue entrando por `Local Database Fallback` (Safe Mode
  intacto). Confirmado en `/var/log/system.log`.
- **DHCP Relay**: DHCP server local de LAN ya estaba desactivado. El
  relay tenía config obsoleta (`lan,opt1` → `192.168.1.10`, del AD
  viejo); se corrigió a `lan` → `192.168.56.10`. Verificado el daemon
  corriendo: `/usr/local/sbin/dhcrelay -i em1 192.168.56.10`.

### Diferido a Fase 5

- Port-forward `WAN:80 → ${MINIKUBE_IP}:30080` (`nat-port-forward.php`):
  no se puede probar hasta tener el frontend desplegado en Minikube.

### Extra (post-Fase 3): NAT port-forward RDP a las VMs del laboratorio

- Se agregó `pfsense/scripts/nat-rdp-forward.php` (no estaba en el
  runbook original): `WAN:40100 -> ${DC_IP}:3389` (DC01-ITU) y
  `WAN:40200 -> ${SQLSERVER_IP}:3389` (SQL Server). Ambos puertos
  alternos (no `:3389` directo, ver más abajo). Detalle en
  `pfsense/README.md` sección 2.1.
- **Prerequisito descubierto: "Block private networks" en WAN bloqueaba
  todo el tráfico entrante.** El WAN de pfSense es NAT de VirtualBox
  (gateway `10.0.2.2`, RFC1918). Con "Block private networks"/"Block
  bogon networks" activos (default de pfSense), se genera
  `block in quick on $WAN from 10.0.0.0/8 to any`, que descarta el
  tráfico entrante (origen siempre `10.0.2.2`) **antes** de llegar a las
  reglas `pass` del `rdr` — 0 hits en las reglas de los port-forwards
  aunque el `rdr` esté bien configurado. Se creó
  `pfsense/scripts/wan-allow-private.php` (deshabilita ambas opciones en
  Interfaces > WAN) y se aplicó — **prerequisito para cualquier
  port-forward WAN en esta topología**, incluido el de Fase 5
  (`nat-port-forward.php`).
- **Port-forward a nivel VirtualBox** (necesario porque el WAN de
  pfSense es NAT de VirtualBox, no bridgeado a la red real): se agregó a
  la VM `pfSense-Gateway` con
  `VBoxManage modifyvm pfSense-Gateway --natpf1 "rdp-dc,tcp,,40100,,40100"`
  y `"rdp-sql,tcp,,40200,,40200"` (VM apagada antes, reencendida después).
- **Por qué `40100` y no `:3389` para el DC**: con `WAN:3389 ->
  ${DC_IP}:3389` y el natpf VirtualBox `host:3389 -> guest:3389`, el
  `rdr`/`pass` de pfSense estaban bien (verificado en `pfctl`), pero el
  NAT engine de VirtualBox nunca entregaba ese tráfico al guest (0
  paquetes en `em0` con `tcpdump`, pese a que `showvminfo
  --machinereadable` mostraba el `Forwarding` registrado sin errores en
  `VBox.log`; VRDE descartado, está `off`). Causa exacta no determinada.
  Se aplicó el mismo patrón que ya funcionaba para SQL Server: puerto WAN
  alterno (`40100`) tanto en pfSense como en VirtualBox.
- **Verificado de punta a punta el 2026-06-14**: `tcpdump` en `em0`/`em1`
  de pfSense muestra el handshake TCP + negociación RDP completos para
  ambos puertos, y desde la PC Windows ambos `mstsc` llegan a la pantalla
  de login:
  ```powershell
  mstsc /v:127.0.0.1:40100  # -> DC01-ITU (192.168.56.10:3389)
  mstsc /v:127.0.0.1:40200  # -> SQL Server (192.168.56.20:3389)
  ```
- **Pendiente**: acceso desde *fuera* de la PC (otra red/internet)
  requeriría además un port-forward en el router de esa red hacia
  `40100`/`40200` — no configurado, no bloqueante.

### Extra (post-Fase 3): NAT port-forward externo al sitio IIS "almacenes"

- La VM de SQL Server ya tenía IIS instalado (no es el SSRS de la
  decisión de Fase 2, que sigue descartado) con dos sitios: "Default Web
  Site" (catch-all `*:80:`) y "almacenes" (`Host: almacenes.itu.local`,
  `C:\inetpub\almacenes`). Solo escucha en el puerto 80 (nada en 443 ni
  8081).
- Se agregó `pfsense/scripts/nat-iis-forward.php`:
  `WAN:40080 -> ${SQLSERVER_IP}:80`. Puerto alterno `40080` (no `:80`)
  porque `WAN:80` está reservado para el port-forward del frontend de
  Minikube en Fase 5. Detalle en `pfsense/README.md` sección 2.2.
- Mismo prerequisito que el RDP: `wan-allow-private.php` ya estaba
  aplicado.
- **Port-forward a nivel VirtualBox**: se agregó a la VM
  `pfSense-Gateway` con
  `VBoxManage modifyvm pfSense-Gateway --natpf1 "iis-almacenes,tcp,,40080,,40080"`
  (VM apagada antes, reencendida después).
- **Windows Firewall en la VM de SQL**: se creó
  `Inventario - IIS Almacenes (TCP 80)` (TCP 80 inbound, allow).
- **Verificado de punta a punta el 2026-06-15**: `pfctl -s nat`/`pfctl -s
  rules -i em0 -v` muestran el `rdr`/`pass` con estados activos; desde la
  PC Windows:
  ```powershell
  curl.exe http://127.0.0.1:40080/                                  # -> Default Web Site ("Funciona")
  curl.exe -H "Host: almacenes.itu.local" http://127.0.0.1:40080/   # -> sitio "almacenes"
  ```
  Ambos responden correctamente.
- **Pendiente**: acceso externo al sitio "almacenes" (no al catch-all)
  requiere que el cliente envíe `Host: almacenes.itu.local`; y, como con
  RDP, acceso desde *fuera* de la PC requeriría un port-forward del
  router de esa red hacia `40080` — no configurado, no bloqueante.

### Abierto / no bloqueante

- Se diagnosticó que la WebGUI de pfSense corre lenta por un bug de
  checksum offload del NIC emulado Intel PRO/1000 (82540EM) de
  VirtualBox. Fix recomendado (no confirmado aplicado): System >
  Advanced > Networking → desactivar "Hardware Checksum Offloading",
  "Hardware TSO" y "Hardware Large Receive Offloading".

---

## Fase 4 — Minikube + Calico ✅ (2026-06-15)

- **Red de LinuxEGI reconfigurada** (paso previo de esta fase): se quitó
  `nic1=nat` (`VBoxManage modifyvm LinuxEGI --nic1 none`, queda solo la
  hostonly), se redimensionó el disco `24.5G -> 79G` y se configuró IP
  estática vía netplan: `192.168.56.30/24`, gateway `192.168.56.2`
  (pfSense), DNS `192.168.56.10` (el DC). Verificada conectividad a
  internet a través de pfSense.
- Docker, `kubectl` v1.31 y `minikube` instalados siguiendo
  `docs/runbook-despliegue.md` Fase 4.
- **Limpieza previa**: se bajó un stack docker-compose "escritorio"
  leftover (`docker compose down`) y se eliminó un perfil minikube viejo
  (`minikube delete`) antes de levantar el clúster definitivo.
- Clúster levantado con
  `minikube start --cni=calico --driver=docker --ports=30080:30080/tcp`
  — `calico-node`, `calico-kube-controllers` y `coredns` `Running`, nodo
  `Ready`.

### Decisión: `MINIKUBE_IP` estática en vez de `minikube ip` (2026-06-15)

- Con `--driver=docker`, `minikube ip` devuelve la IP del bridge interno
  de Docker (`192.168.49.x`), **no ruteable** desde el resto de
  `192.168.56.0/24` ni desde pfSense — hubiera roto el port-forward
  `WAN:80 -> ${MINIKUBE_IP}:30080` (Fase 3) y el acceso LAN directo al
  NodePort.
- Se agregó `--ports=30080:30080/tcp` a `minikube start`: Docker publica
  el NodePort `30080` directo en todas las interfaces del host
  (`docker port minikube` -> `30080/tcp -> 0.0.0.0:30080`,
  `[::]:30080`).
- `MINIKUBE_IP` se redefinió como IP **estática** = `192.168.56.30` (la
  de LinuxEGI), en vez de recalcularse con `minikube ip`. Actualizados 9
  archivos: `infra/red.local.env`, `infra/red.example.env`,
  `infra/scripts/detectar-red.sh`/`.ps1`, `docs/topologia-red.md`,
  `docs/runbook-despliegue.md`, `pfsense/README.md`,
  `.github/workflows/deploy.yml`, `README.md` (raíz).

### Endurecimiento del host: `iptables/reglas-perimetrales.sh` ✅

- Aplicado en LinuxEGI con `sudo ./reglas-perimetrales.sh` (el repo de
  infraestructura no está clonado en la VM; el script se copió a
  `~/Escritorio/` vía el portapapeles compartido de VirtualBox).
- Verificado `sudo iptables -L INPUT -v -n --line-numbers`: 6 reglas
  (loopback, `ESTABLISHED,RELATED`, SSH `22` e ICMP `echo-request` desde
  `192.168.56.0/24`, NodePort `30080` desde pfSense y desde
  `192.168.56.0/24`) + policy `DROP`.
- Verificado que el `DROP` no rompe nada:
  - `kubectl get pods -A` sigue con los 9 pods de `kube-system`
    `Running` (0 restarts).
  - `ping 192.168.56.30` desde la PC Windows responde (regla ICMP OK).
  - `curl http://192.168.56.30:30080/` desde la PC Windows devuelve
    `Connection refused` — llega hasta `docker-proxy` (escuchando en
    `0.0.0.0:30080`), el "refused" es solo porque todavía no hay ningún
    Service desplegado (Fase 5). Confirma que **no** es el iptables el
    que bloquea.

### Abierto / no bloqueante

- ✅ **SSH instalado y verificado (2026-06-15)**: se instaló
  `openssh-server` (`sudo apt install -y openssh-server`). Ubuntu 24.04
  usa activación por socket (`ssh.socket` escucha en `:22` y arranca
  `ssh.service` on-demand, por eso el `.service` aparece
  `inactive (dead)` en reposo). Verificado desde la PC Windows:
  `Test-NetConnection 192.168.56.30 -Port 22` -> `TcpTestSucceeded:
  True` — confirma que la regla 3 del iptables (`SSH desde
  192.168.56.0/24`) funciona en la práctica.
- `k9s` (visualización del clúster para la demo) no se pudo instalar vía
  `apt`/`snap` en Ubuntu 24.04 (paquete no disponible / snap no
  instalado) — pendiente, opcional, vía `.deb` de GitHub releases
  (`derailed/k9s`).

---

## Decisión: acceso externo vía NAT port-forward + VirtualBox, se descarta Cloudflare Tunnel (2026-06-15)

- **Qué se quitó**: el Deployment `cloudflared`
  (`kubernetes/deployments/cloudflared-deployment.yaml`) y la
  NetworkPolicy `07-allow-cloudflared-egress.yaml`. Las NetworkPolicies
  pasan de 8 (00-07) a 7 (00-06).
- **Por qué**: el port-forward NAT de pfSense (`WAN:80 ->
  ${MINIKUBE_IP}:30080`, ya scripteado en
  `pfsense/scripts/nat-port-forward.php` desde la Fase 3, "Diferido a
  Fase 5") más el NodePort `:30080` de Minikube ya alcanzan para que el
  frontend sea visible desde fuera del laboratorio, agregando un
  port-forward a nivel VirtualBox en `pfSense-Gateway` (`host:80 ->
  WAN:80`) — exactamente el mismo patrón ya verificado de punta a punta
  para RDP (`40100`/`40200`) e IIS "almacenes" (`40080`) en los extras de
  la Fase 3. No hace falta depender de un servicio externo (Cloudflare)
  ni de su Quick Tunnel.
- **Qué se actualizó** (8 archivos): `kubernetes/services/frontend-service.yaml`
  (comentario), `docs/arquitectura.md`, `docs/topologia-red.md`,
  `pfsense/README.md` (nueva subsección con los comandos `VBoxManage
  natpf1` para `host:80 -> WAN:80`), `docs/runbook-despliegue.md` (Fase
  5: comandos + checklist; Fase 6: checklist; "Orden resumido para la
  defensa oral" paso 6), `README.md` (raíz: estructura del repo +
  sección "Acceso externo") y `.github/workflows/deploy.yml` (se quita
  el rollout de `cloudflared` y el bloque que buscaba la URL
  `*.trycloudflare.com`).
### ✅ Verificado de punta a punta (2026-06-15)

- El port-forward a nivel VirtualBox (`host:80 -> WAN:80` en
  `pfSense-Gateway`, `inventario-frontend,tcp,,80,,80`) ya estaba
  aplicado.
- **Faltaba el `rdr` de pfSense**: `pfctl -s nat` solo mostraba los
  redirects de RDP (`40100`/`40200`) e IIS (`40080`), sin ninguna regla
  para el puerto 80. Por eso `curl http://127.0.0.1/` se quedaba
  **colgado sin responder** (no "connection refused"): el motor NAT de
  VirtualBox completa el handshake TCP con el cliente localmente, pero
  al no existir el `rdr` el paquete llega al WAN de pfSense y se
  descarta en silencio — mismo síntoma de "cuelgue silencioso" que el
  bloqueo de "private networks" documentado en Fase 3, pero esta vez por
  falta de la regla `rdr`, no por el filtro WAN.
- Se aplicó `.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script
  nat-port-forward`, que crea
  `rdr on em0 inet proto tcp from any to any port = http -> 192.168.56.30 port 30080`.
  El warning `"Quedaron placeholders sin sustituir: ${VAR}"` que tira el
  script es un **falso positivo**: es texto literal de un comentario
  dentro de `nat-port-forward.php` (explica el patrón de placeholders),
  no un placeholder real sin reemplazar — confirmado porque el `rdr`
  aplicado usa la IP correcta `192.168.56.30`.
- `curl.exe http://127.0.0.1/` desde la PC Windows devuelve `200 OK`,
  `Server: nginx/1.25.5`, con la página de login del Inventario ITU
  completa. Cadena verificada de punta a punta:
  `PC Windows :80 (VBoxHeadless/natpf) -> pfSense WAN:80 (rdr) ->
  192.168.56.30:30080 (NodePort) -> frontend (nginx)`.
- De paso confirma que **Fase 5 (frontend) está desplegada y corriendo**
  en el clúster.

### Abierto / no bloqueante

- Si en algún momento se aplicó el Deployment `cloudflared` o la
  NetworkPolicy `allow-cloudflared-egress` al clúster vivo (corrida
  previa de Fase 5/6 antes de esta decisión), removerlos:
  ```bash
  kubectl delete -f kubernetes/deployments/cloudflared-deployment.yaml -n inventario
  kubectl delete networkpolicy allow-cloudflared-egress -n inventario
  ```
- Acceso desde *fuera* de esta PC (otra red/internet) requiere además un
  port-forward en el router de esa red hacia el puerto 80 de esta PC —
  no configurado, no bloqueante (mismo caso que RDP/IIS en Fase 3).

---

## Fase 5 — Verificación backend/login tras reinicio de VMs (2026-06-15)

Contexto: al cerrar la sesión anterior, el pod `backend` estaba en
`CrashLoopBackOff` ("Login timeout expired" contra SQL Server
`192.168.56.20`) porque las VMs **SQL Server (.20)** y **AD-DC (.10)**
estaban apagadas en VirtualBox (`VBoxManage list runningvms` solo
mostraba `pfSense-Gateway` y `LinuxEGI`). El usuario encendió ambas VMs.

### ✅ Verificado tras encender ambas VMs

- `VBoxManage list runningvms` -> las 4 VMs corriendo; ping OK a `.10` y
  `.20` desde la PC Windows.
- `kubectl get pods -n inventario`: `backend` `1/1 Running, 0 restarts`
  (pod nuevo, recreado tras el reinicio), logs limpios (`Application
  startup complete`, sin errores de conexión a SQL Server).
- LDAP/AD-DC: puerto `389` responde desde LinuxEGI.
- **Login end-to-end**: `POST /auth/login` (form-encoded,
  `OAuth2PasswordRequestForm` — no es JSON) con el usuario de prueba
  `mgomez` / `Inventario!2025` (grupo `Tecnicos`, ver
  `active-directory/scripts/04-crear-usuarios-grupos.ps1`) -> `200 OK`,
  devuelve JWT con `"rol":"Tecnicos"`. Confirma que el bind
  `svc-inventario@itu.local` + lectura de grupos (`obtener_rol()`)
  funciona contra el AD real — el ítem "Abierto" de Fase 1 sobre
  `obtener_rol()` queda resuelto/funcionando.

### ✅ Resuelto: mismatch de nombres de tabla en `inventario_ubicaciones`

`GET /inventario/` con el JWT de `mgomez` -> `200 OK` pero `[]` (lista
vacía, sin error). Causa: la base `inventario_ubicaciones` tenía **10
tablas**, dos sets:

- `Ubicacion`, `Equipo`, `Persona`, `Asignacion`, `Mantenimiento`
  (PascalCase singular, creadas por
  `database/scripts/Script SQL Server 2022.sql` de la rama
  `bases-de-datos`) -> **tenían los datos del seed** (11/12/12/13/12
  filas).
- `ubicaciones`, `equipos`, `personas`, `asignaciones`,
  `mantenimientos` (minúscula plural, `__tablename__` de
  `app/models/inventario.py`, creadas vacías por
  `Base.metadata.create_all()` al arrancar el backend) -> **0 filas**,
  son las que usa el ORM (`equipo_repo.py`).

Columnas compatibles entre ambos sets (`equipos` solo agrega `mesa`,
nullable, ausente en el seed original -> queda `NULL`). Mismo patrón en
las otras 4 tablas.

**Fix aplicado y verificado**: se copiaron los datos con `INSERT INTO
<tabla_minuscula> (...) SELECT ... FROM <TablaPascalCase>` en orden de
FKs (`ubicaciones` -> `personas` -> `equipos` -> `asignaciones` ->
`mantenimientos`), `mesa = NULL`. Ejecutado como script Python puntual
dentro del pod `backend` (`kubectl exec ... -- python check_db.py`,
usando el `engine` de SQLAlchemy ya configurado) — no se tocó ningún
archivo de migración del repo, fue una migración de datos en runtime,
de una sola vez.

```
Antes:   {'ubicaciones': 0,  'personas': 0,  'equipos': 0,  'asignaciones': 0,  'mantenimientos': 0}
Despues: {'ubicaciones': 11, 'personas': 12, 'equipos': 12, 'asignaciones': 13, 'mantenimientos': 12}
```

Verificación final: `GET /inventario/` con el JWT de `mgomez` -> `200
OK`, devuelve los **12 equipos completos** (cada uno con `ubicacion`,
`asignaciones` con su `persona`, y `mantenimientos` con su `tecnico`).

Las tablas PascalCase quedan como leftover (se podrían borrar después,
no bloqueante). Pendiente para los compañeros de `bases-de-datos`/
`backend`: alinear la convención de nombres de tabla entre el script de
seed y los modelos del ORM para evitar este problema en un re-seed desde
cero.

### ✅ Resuelto: `componentes` de Mongo solo presente en 1 de 12 equipos

De los 12 equipos devueltos por `/inventario/`, solo `id_equipo: 10`
(Dell OptiPlex 7090 desktop) traía `componentes` no nulo. Mismo patrón
que el mismatch de SQL Server, del lado de Mongo:

- `inventario_componentes.computadoras` (nombres correctos según
  `computadora_repo.py` / `MONGO_DB`) tenía **2 documentos**: `id_equipo:
  10` y `id_equipo: 20` — exactamente el seed de
  `Proyecto-Inventario-EGI-backend/scripts-dev/componentes_prueba.js`.
  De esos, `10` matchea un equipo real de SQL Server; `20` no existe en
  `equipos` (1-12) y queda huérfano.
- `inventario_db.componentes` (nombres usados por
  `database/scripts/inventario-db_mongo.js` de la rama
  `bases-de-datos`, con los **12 documentos completos** `id_equipo`
  1-12 alineados 1 a 1 con los 12 equipos de SQL Server) **no existía**
  — ese seed nunca se ejecutó contra este clúster.

**Fix aplicado y verificado**: se cargaron los 12 documentos de
`inventario-db_mongo.js` (con su `$jsonSchema` validator e índices)
directamente en `inventario_componentes.computadoras` — adaptando solo
el nombre de base/colección, mismo patrón que el fix de SQL Server.
Ejecutado con `mongosh` dentro del pod `mongo` (`db.computadoras.drop()`
+ `createCollection` con validator + `insertMany` de los 12 docs),
reemplazando los 2 docs de prueba.

Verificación final: `GET /inventario/` devuelve los 12 equipos, cada uno
con `componentes` no nulo (cpu, ram, almacenamiento, sistema operativo,
y `perifericos` o `bateria`/`pantalla_integrada` según `tipo`).

Pendiente para los compañeros de `bases-de-datos`/`backend`: igual que
con SQL Server, alinear la convención de nombres (`inventario_db` vs
`inventario_componentes`, `componentes` vs `computadoras`) para evitar
este problema en un re-seed desde cero.

### ✅ NetworkPolicies verificadas (2026-06-15)

`kubectl get networkpolicy -n inventario` muestra las **7 políticas**
(`default-deny-all`, `allow-dns`, `allow-frontend-ingress`,
`allow-frontend-egress`, `allow-backend-from-frontend`,
`allow-backend-egress`, `allow-mongodb-from-backend`) — coinciden 1 a 1
con los 7 archivos `00-06` de `kubernetes/network-policies/`.

Se comparó el spec de cada una contra el repo: todas coinciden
exactamente, incluyendo `allow-backend-egress`, cuyo placeholder
`${IP_RED_PROF}` quedó correctamente sustituido por `192.168.56.0/24`
(generado con `infra/scripts/generar-manifiestos.sh`).

Además, el hecho de que **login + `/inventario/` con datos completos**
ya funcionaron de punta a punta (verificaciones de arriba) es evidencia
funcional de que las políticas no están bloqueando ningún tráfico
legítimo: con `default-deny-all` activo, si faltara `allow-dns`,
`allow-backend-egress` (Mongo/SQL/LDAP) o `allow-backend-from-frontend`,
esas llamadas habrían fallado.

### 🔄 Fase 6 — GitHub Actions (CI/CD): preparación iniciada (2026-06-15)

Revisado `.github/workflows/deploy.yml` (comentarios de cabecera) y el
checklist de `docs/runbook-despliegue.md` sección "Fase 6". Avance hecho
desde el lado de LinuxEGI (host de Minikube, futuro runner):

- **Prerrequisitos del runner verificados en LinuxEGI**: `minikube
  status` → `Running` (control-plane/kubelet/apiserver OK), `kubectl
  v1.36.1`, `envsubst` disponible (`gettext-base`). Usuario `itu` en el
  grupo `docker`.
- **Binario del runner descargado y preparado**: `actions-runner-linux-x64-2.335.1.tar.gz`
  descargado y extraído en `~/actions-runner/` en LinuxEGI. `./config.sh
  --help` corre sin problemas (no hace falta `installdependencies.sh`
  para que funcione el runtime .NET del runner en este host).
- **`infra/red.local.env` en `~/inventario/infraestructura`**: ya existe
  y sus valores son **idénticos** a `infra/red.example.env` (que a su vez
  ya coinciden con las IPs reales del lab: `IP_RED_PROF=192.168.56.0/24`,
  `MINIKUBE_IP=192.168.56.30`, `SQLSERVER_IP=192.168.56.20`,
  `DC_IP=192.168.56.10`, `PFSENSE_LAN_IP=192.168.56.2`). Esto importa
  porque `actions/checkout@v4` hace `git clean` del workspace del job, así
  que un `red.local.env` puesto a mano en el checkout del runner no
  sobreviviría entre corridas — pero como `red.example.env` (committeado,
  sobrevive el checkout) ya tiene los valores correctos para este lab, el
  fallback de `infra/scripts/detectar-red.sh` (`source
  infra/red.example.env` con aviso) alcanza igual.

### ✅ Runner self-hosted registrado y corriendo (2026-06-15)

`./config.sh --unattended --url https://github.com/MartinZ18/Proyecto-Inventario-EGI-infraestructura --token <token-registro> --labels minikube --name linuxegi-minikube`
corrió OK ("Runner successfully added", "Settings Saved"). Labels:
`self-hosted, Linux, X64, minikube` — coincide con `runs-on:
[self-hosted, minikube]` de `deploy.yml`.

Arrancado con `nohup ./run.sh > runner.log 2>&1 < /dev/null & disown`
(no se pudo usar `sudo ./svc.sh install` porque el usuario `itu` necesita
password para sudo — pendiente para dejarlo como servicio systemd
persistente entre reboots). Confirmado proceso `Runner.Listener` corriendo
y log mostrando `Listening for Jobs`.

**Pendiente — requiere acciones del usuario en la UI web de GitHub**
(no automatizables desde aquí: no hay `gh` CLI disponible ni acceso a
navegador):

1. Cargar los 7 GitHub Secrets del repo de infraestructura:
   `REPO_ACCESS_TOKEN`, `JWT_SECRET`, `SQLSERVER_USER`,
   `SQLSERVER_PASSWORD`, `MONGO_ROOT_USER`, `MONGO_ROOT_PASSWORD`,
   `LDAP_BIND_PASSWORD` (el workflow los mapea a `backend-secret`, ver
   cabecera de `deploy.yml`).
2. Disparar el workflow manualmente (Actions → "Deploy Inventario ITU a
   Minikube" → Run workflow) y verificar rollout + acceso al frontend.

⚠️ **Observación de seguridad pendiente (sin resolver, a pedido del
usuario se retoma después)**: el remote `origin` del checkout
`~/inventario/infraestructura` en LinuxEGI tiene un Personal Access Token
de GitHub embebido en texto plano en la URL (visible con `git remote -v`
/ `.git/config`). Recomendado rotar ese token y reconfigurar el remote sin
credenciales embebidas (SSH key o credential helper) antes de la defensa.

---

## Fase 6 — GitHub Actions (CI/CD) ✅ (2026-06-18)

### VMs correctas para este entorno

Al levantar las VMs hay que usar las que terminan en `B1` / ` 1` (las
importadas en esta PC). Las equivalencias respecto al entorno original:

| VM en entorno original | VM en esta PC |
|---|---|
| `pfSense-Gateway` | `pfSense-Gateway-B1` |
| `Window Server AD-DC- Comision B` | `Window Server AD-DC- Comision B 1` |
| `Window Server SQL - IIS - Comision B` | `Window Server SQL - IIS - Comision B 1` |
| `LinuxEGI` | `LubuntuEGI` |

### Bugs corregidos durante la primera corrida del workflow

El workflow corrió por primera vez el 2026-06-18 con el runner
`lubuntuegi-minikube` (systemd service en LubuntuEGI). Se encontraron
y corrigieron 4 bugs:

#### Bug 1 — `SQLSERVER_USER` sin guion bajo en GitHub Secret

El Secret tenía `inventarioapp` (sin `_`). El login de SQL Server se
llama `inventario_app`. Error resultante: SQL Server error 18456 ("Login
failed"). Fix permanente: el usuario corrigió el GitHub Secret a
`inventario_app`.

#### Bug 2 — `LDAP_BIND_PASSWORD` sin signo `!` en GitHub Secret

El Secret tenía `Inventario2025` en vez de `Inventario!2025`. Error
resultante: `invalidCredentials` al intentar bind con
`svc-inventario@itu.local`. Fix permanente: el usuario corrigió el
GitHub Secret a `Inventario!2025`.

#### Bug 3 — `ldap_service.py` — admin bind hardcodeado + filtro de grupo incorrecto

`obtener_rol()` tenía dos problemas:

- Admin bind a `cn=admin,OU=ITU,DC=itu,DC=local` con password `"admin"`
  → esa cuenta no existe en AD.
- Búsqueda de grupos con `(member={user_dn})` donde `user_dn` es el
  UPN (`mgomez@itu.local`) → el atributo `member` de AD guarda DNs, no
  UPNs, por lo que siempre devolvía 0 grupos → todos los logins
  retornaban 401 con `rol=None`.

Fix correcto (aplicar en `Agus-tina/Proyecto-Inventario-EGI`, rama `backend`):

```python
# app/core/config.py — agregar en clase Settings, antes de ldap_user_dn_template:
ldap_bind_dn: str
ldap_bind_password: str

# app/services/ldap_service.py — reemplazar el bloque admin_conn + búsqueda de grupos:
admin_conn = Connection(server, user=settings.ldap_bind_dn,
                        password=settings.ldap_bind_password, auto_bind=True)
admin_conn.search(
    search_base=settings.ldap_base_dn,
    search_filter=f"(userPrincipalName={user_dn})",
    search_scope=SUBTREE,
    attributes=["memberOf"],
)
rol = None
if admin_conn.entries:
    grupos_usuario = admin_conn.entries[0].entry_attributes_as_dict.get("memberOf", [])
    for grupo in ("Tecnicos", "Docentes", "Alumnos"):
        prefijo = f"cn={grupo},".lower()
        if any(dn.lower().startswith(prefijo) for dn in grupos_usuario):
            rol = grupo
            break
```

⚠️ **Este fix se aplicó únicamente a la imagen local de Minikube**
(parcheando el fuente en el workspace del runner y reconstruyendo
`inventario-api:latest`). La próxima corrida del workflow hará checkout
del repo y construirá la imagen con el código bugueado nuevamente.

**Pendiente crítico**: commit de los dos archivos al repo del backend
(`Agus-tina/Proyecto-Inventario-EGI`, rama `backend`), luego
re-disparar el workflow.

#### Bug 4 — MongoDB hostPath con datos viejos de deploy anterior

Después de borrar y recrear el PVC `mongo-data`, MongoDB seguía
encontrando datos porque el hostPath provisioner de Minikube guarda en
`/tmp/hostpath-provisioner/inventario/mongo-data` **dentro del
container Docker de Minikube** — ese directorio sobrevive al borrado
del PVC.

MongoDB solo ejecuta `MONGO_INITDB_ROOT_USERNAME/PASSWORD` en el primer
boot con `/data/db` vacío. Con datos viejos presentes, arrancaba con
las credenciales viejas (sin el usuario `inventario_app`), causando
`UserNotFound` en cada llamada del backend.

Fix:
```bash
kubectl scale deployment mongo -n inventario --replicas=0
minikube ssh 'sudo rm -rf /tmp/hostpath-provisioner/inventario/mongo-data'
kubectl scale deployment mongo -n inventario --replicas=1
```

### Seed de MongoDB

El workflow NO seeda MongoDB por defecto en las corridas anteriores.
A partir de esta sesión el workflow incluye un paso 14 (`Seed MongoDB`)
que ejecuta `infra/scripts/seed-mongo.sh` de forma idempotente: si la
colección ya tiene datos, no hace nada; si está vacía (primer deploy o
reset), carga `scripts-dev/componentes_prueba.js` del repo del backend.

Para seed manual (deploy manual o post-reset):
```bash
bash infra/scripts/seed-mongo.sh --backend-repo <ruta-checkout-backend>
```

### ✅ Verificación final (2026-06-18)

- `kubectl get pods -n inventario`: los 3 pods `Running 1/1`.
- Login `POST /auth/login` con `mgomez@itu.local` / `Inventario!2025`
  → `200 OK`, JWT con `"rol":"Tecnicos"`.
- `GET /inventario/` con ese JWT → `200 OK`, 12 equipos con
  `componentes` de Mongo no nulo.
- Frontend accesible en `http://192.168.56.30:30080/` desde la PC
  Windows; login y listado de inventario funcionales.

---

## Cómo seguir

**Fases 0-6 completas** al 2026-06-18.

**Pendiente crítico (bloquea los deploys futuros via workflow)**:
commit de `app/services/ldap_service.py` y `app/core/config.py` al
repo `Agus-tina/Proyecto-Inventario-EGI` rama `backend` con el fix del
LDAP (ver Fase 6 arriba). Hasta que se haga ese commit, cada corrida
del workflow construirá una imagen con el código bugueado de LDAP, y
los logins retornarán 401.

Cada fase tiene su propio detalle paso a paso y checklist en
`docs/runbook-despliegue.md`; esta bitácora registra lo que realmente
ocurrió, las decisiones tomadas y los bugs encontrados.
