# Active Directory — Dominio `itu.local`

## Rol en la arquitectura

El Domain Controller (`DC01-ITU`) provee **AD DS + DNS + DHCP** para todo
el laboratorio: identidad de los usuarios del Inventario (autenticación
LDAP del backend), administradores de pfSense (`pfAdmins`) y resolución
de nombres/IP para las demás VMs. Ver `docs/topologia-red.md` para el
diagrama general.

| Dato | Valor |
|---|---|
| Dominio (FQDN) | `itu.local` |
| NetBIOS | `ITU` |
| Nombre del DC | `DC01-ITU` |
| IP del DC | `192.168.56.10` (default `DC_IP`, ver `infra/red.example.env`) |
| Base DN | `DC=itu,DC=local` |
| OU del proyecto | `OU=ITU,DC=itu,DC=local` |

---

## 1. Instalación de AD DS + DNS (si la VM aún no lo tiene)

> Si la VM del DC ya fue provista por la cátedra con AD DS instalado y
> el dominio `itu.local` creado, saltar a la sección 2.

En `DC01-ITU` (Windows Server), con PowerShell como Administrador:

```powershell
# 1. Instalar el rol AD DS (incluye DNS como dependencia recomendada)
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools

# 2. Promover el servidor a Controlador de Dominio (crea un bosque nuevo)
Install-ADDSForest `
    -DomainName "itu.local" `
    -DomainNetbiosName "ITU" `
    -InstallDns:$true `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "RecoveryAdm1n!" -AsPlainText -Force)

# El servidor reinicia automáticamente para completar la promoción.
```

Tras el reinicio, verificar:
```powershell
Get-ADDomain
Get-Service ADWS, DNS, NTDS, KDC
```

---

## 2. Estructura de OUs, grupos y usuarios

Estructura objetivo (creada por el script `scripts/04-crear-usuarios-grupos.ps1`):

```
itu.local
└── OU=ITU
    ├── OU=User       (cuentas de usuario del proyecto)
    ├── OU=Computer   (equipos de laboratorio - inventario)
    ├── OU=Server     (VMs: SQL Server, Minikube, etc.)
    ├── OU=Printer    (impresoras de laboratorio)
    └── OU=Grupos     (grupos de seguridad del proyecto)
```

### Grupos de seguridad (`OU=Grupos,OU=ITU,DC=itu,DC=local`)

| Grupo | Propósito |
|---|---|
| `pfAdmins` | Login de administradores en la WebGUI de pfSense (ver `pfsense/README.md`) |
| `InventarioAdmins` | Administradores generales del proyecto (técnicos + cuenta de servicio) |
| `InventarioUsers` | Todos los usuarios habilitados a usar el sistema |
| `Tecnicos` | Rol "Técnico" leído por `app/services/ldap_service.py::obtener_rol()` — habilita `requiere_tecnico` (alta/edición/baja de equipos) |
| `Docentes` | Rol "Docente" |
| `Alumnos` | Rol "Alumno" |

### Usuarios de prueba (`OU=User,OU=ITU,DC=itu,DC=local`)

| Usuario (sAMAccountName / UPN) | Contraseña | Grupos | Propósito |
|---|---|---|---|
| `svc-inventario@itu.local` | `Inventario!2025` | `InventarioAdmins` | Cuenta de servicio para el bind administrativo del backend (ver "Acción requerida en el backend" abajo) |
| `pfsense_bind@itu.local` | `LdapAuth!2025` | — | Bind LDAP de pfSense (`AD-ITU-Laboratorio`, ver `pfsense/README.md`). **Nota**: en el DC actual esta cuenta quedó en `OU=pfsense,DC=itu,DC=local` (OU propia bajo la raíz del dominio), no en `OU=User,OU=ITU,...` como el resto de la tabla — verificado con `ldapsearch` el 2026-06-14. El `ldap_binddn` del Authentication Server debe usar esa ruta. **Nota 2**: la password original `Pfsense!2025` nunca fue válida — viola la política de complejidad de AD por contener 7 caracteres consecutivos del `sAMAccountName` (`pfsense_bind`). Se reseteó a `LdapAuth!2025` el 2026-06-14 con `Set-ADAccountPassword -Reset`. |
| `jperez@itu.local` | `Inventario!2025` | `Docentes`, `InventarioUsers` | Usuario de prueba — Docente |
| `mgomez@itu.local` | `Inventario!2025` | `Tecnicos`, `InventarioAdmins`, `InventarioUsers`, `pfAdmins` | Usuario de prueba — Técnico, admin de pfSense |
| `clopez@itu.local` | `Inventario!2025` | `Tecnicos`, `InventarioAdmins`, `InventarioUsers` | Usuario de prueba — Técnico |
| `agarcia@itu.local` | `Inventario!2025` | `Docentes`, `InventarioUsers` | Usuario de prueba — Docente |
| `psanchez@itu.local` | `Inventario!2025` | `Alumnos`, `InventarioUsers` | Usuario de prueba — Alumno |

### Ejecutar el script

En `DC01-ITU` (o una máquina con RSAT y permisos de Domain Admin):

```powershell
cd active-directory\scripts
powershell -ExecutionPolicy Bypass -File .\04-crear-usuarios-grupos.ps1
```

Es idempotente: se puede re-ejecutar sin error si OUs/grupos/usuarios ya existen.

Verificación rápida:
```powershell
Get-ADUser -Filter * -SearchBase "OU=User,OU=ITU,DC=itu,DC=local" | Select Name, SamAccountName
Get-ADGroupMember -Identity Tecnicos
```

---

## 3. Configuración del backend para usar AD (en lugar de OpenLDAP)

El backend (`app/core/config.py` / `.env`) trae por defecto valores de
**OpenLDAP de desarrollo** (`docker-compose.yml`, dominio
`dc=itu,dc=edu,dc=ar`). Para apuntar al AD real, las variables deben
quedar así (ya reflejado en `kubernetes/configmaps/backend-configmap.yaml`):

| Variable | Valor para AD real |
|---|---|
| `LDAP_HOST` | `ldap-service` (Service → Endpoints → `${DC_IP}:389`, default `192.168.56.10:389`, ver `kubernetes/external/ldap-endpoints.yaml`) |
| `LDAP_PORT` | `389` |
| `LDAP_BASE_DN` | `OU=ITU,DC=itu,DC=local` |
| `LDAP_USER_DN_TEMPLATE` | `{username}@itu.local` (formato UPN, válido para bind en AD) |
| `LDAP_USE_SSL` | `false` (LDAP simple en el laboratorio; LDAPS quedaría para una mejora futura) |

Con `LDAP_USER_DN_TEMPLATE={username}@itu.local`, el método
`autenticar()` de `app/services/ldap_service.py` (bind directo del
usuario) funciona sin cambios contra AD: por ejemplo, el login
`mgomez` / `Inventario!2025` hace bind como `mgomez@itu.local`.

---

## 4. ⚠️ Acción requerida en el backend (rama `backend`)

`app/services/ldap_service.py::obtener_rol()` necesita un **segundo
bind administrativo** para poder leer los grupos del usuario y
determinar su rol (Técnico/Docente/Alumno). Hoy ese segundo bind está
**hardcodeado para el OpenLDAP de desarrollo**:

```python
admin_conn = Connection(
    server,
    user=f"cn=admin,{settings.ldap_base_dn}",
    password="admin",  # contraseña del admin del LDAP (de desarrollo)
    auto_bind=True,
)
```

Esto **no funciona contra Active Directory**: AD no tiene una cuenta
`cn=admin`, y la contraseña `"admin"` es solo del contenedor
`osixia/openldap` de desarrollo.

**Cambio necesario** (a coordinar con el integrante de backend):

1. Agregar dos campos a `Settings` (`app/core/config.py`):
   ```python
   ldap_bind_dn: str
   ldap_bind_password: str
   ```
2. En `obtener_rol()`, reemplazar el bind hardcodeado por:
   ```python
   admin_conn = Connection(
       server,
       user=settings.ldap_bind_dn,
       password=settings.ldap_bind_password,
       auto_bind=True,
   )
   ```
3. Configurar (en `backend-secret`, ver
   `kubernetes/secrets/backend-secret.example.yaml`):
   - `LDAP_BIND_DN = svc-inventario@itu.local`
   - `LDAP_BIND_PASSWORD = Inventario!2025` (la del usuario `svc-inventario`
     creado por `04-crear-usuarios-grupos.ps1`)

Hasta que este cambio se incorpore al backend, el login contra AD
**validará credenciales correctamente** (el primer bind con
`LDAP_USER_DN_TEMPLATE` sí funciona), pero `obtener_rol()` devolverá
`None` y el RBAC (`requiere_tecnico`) no podrá distinguir roles.

---

## 5. Checklist de verificación

- [ ] `Get-ADDomain` confirma el dominio `itu.local` activo.
- [ ] OUs `OU=ITU` → `User/Computer/Server/Printer/Grupos` creadas.
- [ ] 6 grupos de seguridad creados (`pfAdmins`, `InventarioAdmins`,
      `InventarioUsers`, `Tecnicos`, `Docentes`, `Alumnos`).
- [ ] 7 usuarios de prueba creados, con membresías correctas.
- [ ] Bind de prueba `mgomez@itu.local` / `Inventario!2025` exitoso
      (puede probarse con `ldapsearch` o `Test-LdapConnection` desde
      otra máquina apuntando a `192.168.56.10:389`, default `DC_IP`).
- [ ] Cambio de `obtener_rol()` (sección 4) coordinado con backend —
      o documentado como pendiente para la defensa oral.
