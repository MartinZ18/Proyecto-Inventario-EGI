# pfSense — Gateway NAT y Autenticación del Laboratorio

## Rol en la arquitectura

pfSense actúa como **gateway NAT** del laboratorio: separa la red
externa (WAN) de la red interna del proyecto (LAN), donde viven el
Domain Controller (AD), la VM de SQL Server y el host de Minikube.
Además centraliza la **autenticación de administradores de pfSense**
contra Active Directory y resuelve el acceso DHCP de los clientes hacia
el DC.

En este proyecto **todo corre en la misma PC** (Windows + VirtualBox):
pfSense, las VMs de AD y SQL Server, y Minikube. Las IPs de abajo son
los **valores por defecto** de `infra/red.example.env` para esa
topología (red Host-Only `192.168.56.0/24`); si tu red difiere,
ajustalos en `infra/red.local.env` (gitignored) — ver
`docs/topologia-red.md`.

```
            WAN (acceso a internet de pfSense, NAT de VirtualBox)
                       │
                  ┌───────────┐
                  │  pfSense  │  modo NAT gateway
                  └───────────┘
                       │ LAN: 192.168.56.2/24 (Host-Only)
       ┌───────────────┼───────────────────┐
       │               │                    │
  ┌─────────┐   ┌──────────────┐   ┌──────────────────┐
  │  AD DS  │   │ SQL Server    │   │  Minikube host    │
  │ DC01-ITU│   │ 2022          │   │  (namespace        │
  │.10      │   │ .20           │   │   inventario)      │
  └─────────┘   └──────────────┘   └──────────────────┘
```

---

## Topología VirtualBox recomendada

1. **Crear una red Host-Only** en VirtualBox (File/Archivo > Host
   Network Manager / Tools > Network): subred `192.168.56.0/24`. La PC
   Windows queda automáticamente en `192.168.56.1` en esa red. Si
   VirtualBox trae habilitado un servidor DHCP para esa red, se puede
   dejar (no interfiere: las VMs de abajo usan IP estática) o
   desactivarlo, a gusto.

2. **VM de pfSense** — dos interfaces de red:
   - **LAN**: adaptador "Red solo-anfitrión" (Host-Only), IP estática
     `192.168.56.2/24`. Es la interfaz por la que pfSense habla con AD,
     SQL Server y Minikube.
   - **WAN**: adaptador "NAT" (el NAT por defecto de VirtualBox). Le da
     a pfSense salida a internet por su cuenta (actualizaciones,
     sincronización horaria NTP) sin depender de ninguna red externa
     real. No es la vía de acceso externo al frontend — para eso ver
     `docs/topologia-red.md` (Cloudflare Tunnel / NodePort LAN).

3. **VM del Domain Controller (DC01-ITU)**: adaptador Host-Only, IP
   estática `192.168.56.10/24`, gateway `192.168.56.2` (pfSense).

4. **VM de SQL Server**: adaptador Host-Only, IP estática
   `192.168.56.20/24`, gateway `192.168.56.2`.

5. **Host de Minikube (LinuxEGI)**: VM Ubuntu con **una sola NIC
   Host-Only**, IP estática `192.168.56.30/24`, gateway `192.168.56.2`
   (pfSense) — todo su tráfico, incluido internet, sale por pfSense.
   Minikube corre con `--driver=docker`: el daemon de Docker vive en
   esta misma VM, así que los pods llegan a `192.168.56.10`/`.20` a
   través de la interfaz `192.168.56.30` del host — esto es lo que
   permite que las NetworkPolicies con `ipBlock`
   (`05-allow-backend-egress`) funcionen.

   `minikube ip` por sí solo devuelve la IP interna del bridge de
   Docker (`192.168.49.x`), **no ruteable** desde el resto de
   `192.168.56.0/24` ni desde pfSense. Por eso el cluster se levanta
   con `--ports=30080:30080/tcp` (ver Fase 4 del runbook), que publica
   el NodePort del frontend directo en `192.168.56.30:30080`. Esa IP
   fija es la que se configura como `MINIKUBE_IP` en
   `infra/red.local.env` (ya no se recalcula con `minikube ip`).

---

## Habilitar SSH (para automatización con `pfsense/scripts/`)

Los scripts de `pfsense/scripts/` (ver más abajo) aplican configuración
vía SSH + `php -f` (ejecutan el `.php` directo como root, que es lo que
la sesión SSH de `admin` da en pfSense). Para habilitarlo:

1. **System > Advanced > Admin Access**:
   - "Secure Shell" → marcar **Enable Secure Shell**.
   - Recomendado: **Disable password login for Secure Shell (RSA/ECDSA/EdDSA only)**
     una vez que el acceso por clave funcione (ver paso 2).
2. **Acceso por clave pública (recomendado)**:
   - Generar un par de claves en la PC Windows si no existe:
     `ssh-keygen -t ed25519 -f $HOME\.ssh\id_ed25519_pfsense`
   - Copiar la pública a pfSense: **System > User Manager > Users >
     admin (editar) > Authorized SSH Keys**, pegar el contenido de
     `id_ed25519_pfsense.pub`.
   - Probar: `ssh -i $HOME\.ssh\id_ed25519_pfsense admin@192.168.56.2`
3. Si se usa autenticación por password en vez de clave, los scripts de
   `aplicar-config-pfsense.ps1` van a pedir la contraseña de `admin` dos
   veces (una para `scp`, otra para `ssh`).

> ⚠️ **Safe Mode**: nunca borrar ni deshabilitar el usuario `admin`
> local de pfSense, ni siquiera después de integrar la autenticación
> con AD (sección 3). Si el DC se cae, `admin` local es la única forma
> de recuperar acceso a la WebGUI/SSH.

---

## Scripts de configuración (`pfsense/scripts/`)

Plantillas de **infraestructura como código** para pfSense: manipulan
directamente el array `$config` de pfSense y llaman a
`write_config()`/`filter_configure()`, igual que un `pfSsh.php playback`
pero ejecutadas con `php -f` (ver "Habilitar SSH" arriba):

| Script | Qué hace | Equivale a (sección de este doc) |
|---|---|---|
| `wan-allow-private.php` | Deshabilita "Block private networks" y "Block bogon networks" en WAN | Sección 1 |
| `nat-port-forward.php` | Port-forward `WAN:80 -> ${MINIKUBE_IP}:30080` + regla de firewall WAN asociada | Sección 2 |
| `nat-rdp-forward.php` | Port-forward RDP `WAN:40100 -> ${DC_IP}:3389` y `WAN:40200 -> ${SQLSERVER_IP}:3389` + reglas de firewall WAN asociadas | Sección 2.1 (extra, fuera del runbook obligatorio) |
| `nat-iis-forward.php` | Port-forward `WAN:40080 -> ${SQLSERVER_IP}:80` (sitio IIS "almacenes") + regla de firewall WAN asociada | Sección 2.2 (extra, fuera del runbook obligatorio) |
| `auth-server-ad.php` | Authentication Server LDAP `AD-ITU-Laboratorio` (`${DC_IP}:389`) + grupo remoto `pfAdmins` | Sección 3 |
| `dhcp-relay.php` | Desactiva el DHCP local de LAN y configura DHCP Relay hacia `${DC_IP}` | Sección 4 |

Uso, desde la PC Windows (donde se ejecuta Claude Code y tiene acceso a
la red Host-Only):

```powershell
.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script wan-allow-private
.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script nat-port-forward
.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script auth-server-ad
.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script dhcp-relay
```

El script:
1. Carga `infra/red.local.env` (o `infra/red.example.env` con los
   defaults `192.168.56.x` si no existe).
2. Sustituye los placeholders `${VAR}` del `.php` correspondiente y
   guarda el resultado en `infra/_generated-pfsense/` (gitignored) para
   poder revisarlo antes de aplicarlo.
3. Lo copia a pfSense por `scp` y ejecuta `php -f /tmp/<script>.php` por
   `ssh` (la sesión de `admin` corre como root, así que tiene acceso
   directo a `config.inc`/`util.inc`); al terminar borra el `.php`
   temporal de `/tmp`.

`auth-server-ad.php` necesita además `PFSENSE_BIND_PASSWORD` (password
de la cuenta `pfsense_bind` en AD, ver
`active-directory/scripts/04-crear-usuarios-grupos.ps1`) — definirla
**solo** en `infra/red.local.env` (gitignored), nunca commitearla.

> `wan-allow-private.php`, `auth-server-ad.php`, `dhcp-relay.php`,
> `nat-rdp-forward.php` y `nat-iis-forward.php` ya se probaron contra la
> instancia real (2026-06-14) y funcionaron con `php -f` vía
> `aplicar-config-pfsense.ps1`. `nat-port-forward.php`
> (el de `WAN:80 -> ${MINIKUBE_IP}:30080`) sigue el mismo mecanismo pero
> todavía no se ejecutó — recién se puede probar en Fase 5, cuando
> `MINIKUBE_IP` exista. Recomendado: probar primero contra un
> snapshot/backup de `config.xml` (Diagnostics > Backup & Restore) antes
> de aplicar.

---

## 1. Interfaces WAN/LAN (modo NAT gateway)

1. **WAN**: adaptador NAT de VirtualBox (ver "Topología VirtualBox
   recomendada" arriba) — IP asignada automáticamente por VirtualBox.
2. **LAN**: asignar `192.168.56.2/24` (red Host-Only del laboratorio,
   `IP_RED_PROF` en `infra/red.example.env`).
3. En **System > Routing**, dejar el **Default Gateway** apuntando a la
   WAN (pfSense ya lo hace por defecto al crear la interfaz WAN).
4. Verificar que **NAT > Outbound** esté en modo *Automatic outbound NAT*
   (o *Hybrid* si ya hay reglas manuales) para que los hosts de la LAN
   salgan a través de pfSense.
5. **Interfaces > WAN**: desmarcar **"Block private networks and loopback
   addresses"** y **"Block bogon networks"**.

   > ⚠️ **Imprescindible para que cualquier port-forward WAN funcione**
   > (sección 2, 2.1 y el de Fase 5). El "ISP" del WAN de pfSense es el
   > NAT de VirtualBox, cuyo gateway es `10.0.2.2` (RFC1918, dentro de
   > `10.0.0.0/8`). Con "Block private networks" activo, pfSense genera
   > una regla `block in quick on $WAN from 10.0.0.0/8 to any` que
   > descarta TODO el tráfico entrante por WAN (el origen siempre es
   > `10.0.2.2`) **antes** de llegar a las reglas `pass` de los
   > port-forwards — el `rdr` nunca llega a aplicarse. Sin esto, los
   > paquetes llegan a `em0` (se ven con `tcpdump`) pero terminan en la
   > "Default deny" / regla de bloqueo de redes privadas, con 0 hits en
   > las reglas `pass` asociadas al `rdr`.

   Alternativa automatizada: `pfsense/scripts/wan-allow-private.php` (ver
   "Scripts de configuración" arriba).

---

## 2. Port-forward hacia el frontend (Minikube)

> ℹ️ Esta es **una de varias formas** de exponer el frontend; el acceso
> "real" desde fuera de la red para la defensa se resuelve con
> **Cloudflare Tunnel** (`kubernetes/deployments/cloudflared-deployment.yaml`)
> y/o el **NodePort `:30080`** directo (ver `docs/topologia-red.md`,
> sección "Acceso externo"). Configurar este port-forward sigue siendo
> útil para mostrar pfSense como NAT gateway funcional en la defensa
> oral.

El frontend del Inventario está expuesto como `frontend-service`
(NodePort `30080`) en `${MINIKUBE_IP}` (IP estática del host de
Minikube — `192.168.56.30`, fijada en `infra/red.local.env`, ver
sección "Topología VirtualBox recomendada" más arriba).

**Firewall > NAT > Port Forward** → nueva regla:

| Campo | Valor |
|---|---|
| Interface | WAN |
| Protocol | TCP |
| Destination | WAN address |
| Destination port range | 80 (HTTP) |
| Redirect target IP | `${MINIKUBE_IP}` (ver `infra/red.local.env`, `192.168.56.30`) |
| Redirect target port | 30080 |
| Description | Inventario ITU - frontend (NodePort) |

pfSense crea automáticamente la regla de **Firewall > Rules > WAN**
asociada. Revisar que quede habilitada y, si se quiere acotar el
acceso, restringir el *Source* a `192.168.56.0/24` (`IP_RED_PROF`) en
vez de `any`.

Alternativa automatizada: `pfsense/scripts/nat-port-forward.php` (ver
sección "Scripts de configuración" arriba).

Verificación:
```
curl -I http://<IP_WAN_PFSENSE>/
```
Debe responder `200 OK` (servido por nginx desde el pod `frontend`).

---

## 2.1 Acceso RDP a las VMs del laboratorio (extra, opcional)

> ℹ️ No forma parte del checklist obligatorio del runbook (Fase 3). Se
> agregó porque el equipo necesita entrar por escritorio remoto a las
> VMs del DC y de SQL Server.

Dos port-forwards adicionales en **Firewall > NAT > Port Forward**:

| Regla | Destino |
|---|---|
| `WAN:40100 -> ${DC_IP}:3389` | DC01-ITU (puerto alterno — ver nota abajo) |
| `WAN:40200 -> ${SQLSERVER_IP}:3389` | SQL Server (puerto alterno) |

Cada una crea su regla de firewall WAN asociada automáticamente.

> ℹ️ **Por qué puertos alternos (40100/40200) y no `:3389` directo**:
> el `rdr` `WAN:3389 -> ${DC_IP}:3389` se probó primero, y a nivel
> pfSense funciona igual que los demás (`pfctl -s nat`/`pfctl -s rules`
> correctos). El problema está en el **forward a nivel VirtualBox**
> (`host:3389 -> guest WAN:3389`): el NAT engine de VirtualBox nunca
> entrega ese tráfico al guest (0 paquetes en `em0`, verificado con
> `tcpdump`), aunque `showvminfo --machinereadable` muestre la regla
> `Forwarding` registrada y sin errores en `VBox.log` (VRDE
> descartado: está `off`). No se encontró la causa exacta; se optó por
> el mismo patrón que ya funciona para SQL Server: usar un puerto WAN
> alterno (`40100`) tanto en pfSense como en VirtualBox, dejando el
> guest siempre en `:3389`.

Alternativa automatizada:
```powershell
.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script wan-allow-private  # prerequisito, ver sección 1
.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script nat-rdp-forward
```

> ⚠️ El WAN de pfSense es un adaptador **NAT de VirtualBox**, no está
> bridgeado a la red real. Estas reglas redirigen dentro de esa NAT; para
> que el RDP sea alcanzable desde la PC Windows real (o desde fuera) hace
> falta además un port-forward a nivel VirtualBox.

**Port-forward a nivel VirtualBox** (host Windows, VM `pfSense-Gateway`
apagada antes de correrlo):

```powershell
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $VBoxManage controlvm pfSense-Gateway acpipowerbutton   # esperar a que apague
& $VBoxManage modifyvm pfSense-Gateway --natpf1 "rdp-dc,tcp,,40100,,40100"
& $VBoxManage modifyvm pfSense-Gateway --natpf1 "rdp-sql,tcp,,40200,,40200"
& $VBoxManage startvm pfSense-Gateway --type headless
```

**Configurado y verificado de punta a punta el 2026-06-14**:
`showvminfo pfSense-Gateway --machinereadable` muestra
`Forwarding(0)="rdp-dc,tcp,,40100,,40100"` y
`Forwarding(1)="rdp-sql,tcp,,40200,,40200"`; `tcpdump` en `em0`/`em1` de
pfSense muestra el handshake TCP + negociación RDP completos en ambos
casos, y desde la PC Windows ambos `mstsc` llegan a la pantalla de login:

```powershell
mstsc /v:127.0.0.1:40100  # -> DC01-ITU (192.168.56.10:3389)
mstsc /v:127.0.0.1:40200  # -> SQL Server (192.168.56.20:3389)
```

Si además se necesita acceso desde fuera de la PC (otra red/internet),
falta un port-forward equivalente en el router de esa red hacia los
puertos `40100`/`40200` de la PC — no configurado.

---

## 2.2 Acceso externo al sitio IIS "almacenes" (extra, opcional)

> ℹ️ No forma parte del checklist obligatorio del runbook. La VM de SQL
> Server ya tenía IIS instalado para otro propósito (no el SSRS evaluado
> y descartado en Fase 2 — ver `docs/bitacora-despliegue.md`): dos
> sitios, "Default Web Site" (binding catch-all `*:80:`) y "almacenes"
> (binding por Host header `almacenes.itu.local`, `C:\inetpub\almacenes`).
> Se necesita que "almacenes" sea alcanzable desde fuera de la red del
> laboratorio, igual que el RDP de la sección 2.1.

Port-forward adicional en **Firewall > NAT > Port Forward**:

| Regla | Destino |
|---|---|
| `WAN:40080 -> ${SQLSERVER_IP}:80` | IIS - sitio "almacenes" (puerto alterno, ver nota abajo) |

Crea su regla de firewall WAN asociada automáticamente.

> ℹ️ **Por qué puerto alterno (40080) y no `:80` directo**: `WAN:80` está
> reservado para el port-forward del frontend de Minikube (sección 2,
> Fase 5 — `WAN:80 -> ${MINIKUBE_IP}:30080`). Usar `40080` evita el
> choque entre ambas reglas.

Alternativa automatizada:
```powershell
.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script wan-allow-private  # prerequisito, ver sección 1
.\pfsense\scripts\aplicar-config-pfsense.ps1 -Script nat-iis-forward
```

> ⚠️ Igual que en 2.1: el WAN de pfSense es NAT de VirtualBox, así que
> además del `rdr` de pfSense hace falta un port-forward a nivel
> VirtualBox para que sea alcanzable desde la PC Windows real (o desde
> fuera).

**Port-forward a nivel VirtualBox** (host Windows, VM `pfSense-Gateway`
apagada antes de correrlo):

```powershell
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $VBoxManage controlvm pfSense-Gateway acpipowerbutton   # esperar a que apague
& $VBoxManage modifyvm pfSense-Gateway --natpf1 "iis-almacenes,tcp,,40080,,40080"
& $VBoxManage startvm pfSense-Gateway --type headless
```

**En la VM de SQL Server** hace falta además habilitar el puerto 80 en
el Windows Firewall (no se usaba hasta ahora):

```powershell
New-NetFirewallRule -DisplayName "Inventario - IIS Almacenes (TCP 80)" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
```

**Configurado y verificado de punta a punta el 2026-06-14**:
`pfctl -s nat`/`pfctl -s rules -i em0 -v` muestran el `rdr`/`pass` con
estados activos (2 packets capturados en la prueba); desde la PC Windows:

```powershell
curl.exe http://127.0.0.1:40080/                                  # -> Default Web Site
curl.exe -H "Host: almacenes.itu.local" http://127.0.0.1:40080/   # -> sitio "almacenes"
```

Ambos responden correctamente. Para acceder a "almacenes" desde un
cliente externo hace falta enviar el header `Host: almacenes.itu.local`
(p. ej. `curl -H`, o una entrada en el archivo `hosts` del cliente que
resuelva ese nombre a la IP/puerto externos) — sin ese header, IIS
enruta al binding catch-all de "Default Web Site".

Si además se necesita acceso desde fuera de la PC (otra red/internet),
falta un port-forward equivalente en el router de esa red hacia el
puerto `40080` de la PC — no configurado.

---

## 3. Autenticación de pfSense contra Active Directory

Permite que los integrantes del grupo (grupo `pfAdmins` en AD, ver
`active-directory/README.md`) inicien sesión en la WebGUI de pfSense
con sus credenciales de dominio, sin crear usuarios locales por persona.

### 3.1 Crear el Authentication Server

**System > User Manager > Authentication Servers > Add**:

| Campo | Valor |
|---|---|
| Descriptive name | `AD-ITU-Laboratorio` |
| Type | LDAP |
| Hostname or IP | `192.168.56.10` (`DC_IP`, ver `infra/red.example.env`) |
| Port | 389 (o 636 si se habilita LDAPS) |
| Transport | TCP - Standard (o SSL/TLS si hay certificado) |
| Search scope / Base DN | `DC=itu,DC=local` |
| Authentication containers | `OU=ITU,DC=itu,DC=local` |
| Bind anonymous | NO |
| Bind credentials (DN) | `CN=pfsense_bind,OU=User,OU=ITU,DC=itu,DC=local` |
| Bind credentials (password) | la de `pfsense_bind` (ver `active-directory/scripts/04-crear-usuarios-grupos.ps1`) |
| User naming attribute | `samAccountName` |
| Group naming attribute | `cn` |
| Group member attribute | `memberOf` |

Probar con el botón **Test connection** antes de guardar.

Alternativa automatizada: `pfsense/scripts/auth-server-ad.php` (ver
sección "Scripts de configuración" arriba).

### 3.2 Crear el grupo espejo `pfAdmins`

**System > User Manager > Groups > Add**:

| Campo | Valor |
|---|---|
| Group name | `pfAdmins` |
| Scope | Remote |
| Assigned Privileges | `WebCfg - All pages` |

Este nombre debe coincidir EXACTO con el grupo `pfAdmins` creado en AD
(ver `active-directory/README.md`). pfSense resuelve la pertenencia al
grupo vía `memberOf` durante el login LDAP — no hace falta volver a
agregar usuarios locales.

### 3.3 Activar el servidor LDAP como método de login

**System > User Manager > Settings**: agregar `AD-ITU-Laboratorio` como
servidor de autenticación adicional (dejar `Local Database` también
habilitado, para no perder acceso con `admin`).

### 3.4 Verificación

1. Cerrar sesión de `admin`.
2. Iniciar sesión con un usuario miembro de `pfAdmins` en AD (p. ej.
   `mgomez`, ver tabla de usuarios en `active-directory/README.md`),
   usando `mgomez@itu.local` o `ITU\mgomez` según el formato que pida
   pfSense.
3. Confirmar que tiene acceso completo a la WebGUI.
4. Volver a iniciar sesión como `admin` local para confirmar que sigue
   funcionando (Safe Mode).

---

## 4. DHCP Relay hacia el Domain Controller

El DC (`192.168.56.10`, `DC_IP`) actúa como servidor DHCP real (junto
con AD DS y DNS). pfSense solo **reenvía** las solicitudes DHCP de la
LAN hacia el DC.

> ⚠️ Antes de configurar el relay, **desactivar el servidor DHCP local**
> de pfSense en la interfaz LAN (**Services > DHCP Server > LAN** →
> "Enable DHCP server on LAN interface" desmarcado). Tener ambos
> activos al mismo tiempo genera asignaciones de IP duplicadas/conflicto.

**Services > DHCP Relay**:

| Campo | Valor |
|---|---|
| Enable | sí |
| Interfaces | LAN (y CLIENTES si existe una VLAN/segmento separado) |
| Destination server | `192.168.56.10` (`DC_IP`) |

Alternativa automatizada: `pfsense/scripts/dhcp-relay.php` (ver sección
"Scripts de configuración" arriba) — desactiva el DHCP local y configura
el relay en un solo paso.

Verificación: desde un cliente en la LAN, `ipconfig /renew` (Windows) o
`dhclient -r && dhclient` (Linux) y confirmar que la IP/DNS asignados
provienen del rango configurado en AD DS.

---

## 5. Checklist de verificación final

- [x] Red Host-Only `192.168.56.0/24` creada en VirtualBox; pfSense LAN
      = `192.168.56.2`, DC = `192.168.56.10`, SQL Server = `192.168.56.20`.
- [x] WAN (NAT de VirtualBox) y LAN configuradas, NAT outbound automático.
- [x] SSH habilitado (System > Advanced > Admin Access), acceso por
      clave pública desde la PC Windows funciona.
- [ ] Port-forward `WAN:80 → ${MINIKUBE_IP}:30080` responde `200 OK`
      (opcional — diferido a Fase 5, cuando el frontend esté desplegado
      en Minikube).
- [x] Authentication Server `AD-ITU-Laboratorio` configurado. pfSense 2.8
      no tiene botón *Test connection*; se verificó el bind LDAP por SSH
      (`ldapwhoami` como `pfsense_bind`) y con un login real exitoso.
- [x] Grupo `pfAdmins` (Remote, `WebCfg - All pages`) creado.
- [x] Login con usuario de dominio (miembro de `pfAdmins`) funciona
      (`mgomez@itu.local`, 2026-06-14).
- [x] Login con `admin` local sigue funcionando (Safe Mode).
- [x] DHCP Relay activo hacia `192.168.56.10` (interfaz LAN), DHCP local
      de pfSense apagado.
