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

## Cómo seguir

**Fases 0-4 cerradas del todo**, incluidos los extras post-Fase 3 (RDP a
las VMs del lab en `40100`/`40200` e IIS "almacenes" en `40080`, ambos
verificados de punta a punta el 2026-06-15) y el endurecimiento iptables
de Fase 4.

Próxima fase: **Fase 5 — Kubernetes (apps + NetworkPolicies)**
(`docs/runbook-despliegue.md`, sección "Fase 5"): generar los
manifiestos con `infra/scripts/detectar-red.sh` +
`infra/scripts/generar-manifiestos.sh`, aplicar namespace/configmaps/
secret/deployments/services, y por último las NetworkPolicies. Recordar
el seed correcto de MongoDB
(`Proyecto-Inventario-EGI-backend/scripts-dev/componentes_prueba.js`, no
el de `bases-de-datos`).

Orden de las fases restantes (sin cambios respecto al runbook):

```
5. Kubernetes (apps + NetworkPolicies)  →  6. GitHub Actions (CI/CD)
```

Cada fase tiene su propio detalle paso a paso y checklist en
`docs/runbook-despliegue.md`; esta bitácora se va a ir completando con
una entrada nueva por fase a medida que se avance.
