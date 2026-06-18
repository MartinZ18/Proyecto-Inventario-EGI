# Pendiente — Limpieza de VMs (AD y SQL Server)

Fecha: 2026-06-18. Intentado por automatización vía WinRM/SSH; quedó
pendiente de ejecución manual por falta de acceso admin a las VMs.

---

## ⚠️ URGENTE — Reparar SSH de LubuntuEGI

Durante la sesión se modificó `/etc/ssl/openssl.cnf` en LubuntuEGI para
habilitar el proveedor legacy de OpenSSL (MD4). Eso rompió el demonio
SSH (OpenSSH usa OpenSSL). LubuntuEGI rechaza todas las conexiones SSH.

**Cómo arreglarlo** (abrir la consola de VirtualBox directamente):

1. Abrir VirtualBox → seleccionar `LubuntuEGI` → **Mostrar** (o doble
   click) para abrir la consola gráfica.
2. Iniciar sesión como `martin` / `admin1234`.
3. Revertir el cambio en el archivo:

```bash
sudo cp /etc/ssl/openssl.cnf /etc/ssl/openssl.cnf.bak
sudo python3 - <<'EOF'
import re
with open('/etc/ssl/openssl.cnf') as f:
    content = f.read()
# Eliminar las lineas agregadas por el script automatico
content = re.sub(r'\nlegacy = legacy_sect\n+\[legacy_sect\]\nactivate = 1', '', content)
with open('/etc/ssl/openssl.cnf', 'w') as f:
    f.write(content)
print("Listo")
EOF
sudo systemctl restart ssh
ssh -o StrictHostKeyChecking=no martin@localhost "echo SSH OK"
```

4. Verificar que SSH vuelve a funcionar desde la PC host.

---

## 1. Limpieza del Active Directory (192.168.56.10)

**Cómo acceder**: RDP a `192.168.56.10` con usuario `Administrator`.

### Opción A — Script automático (recomendada)

Abrir PowerShell como Administrador en el DC y ejecutar:

```powershell
# Descargar el script del repo (o copiarlo manualmente)
# Si el repo ya está clonado en el DC:
powershell -ExecutionPolicy Bypass -File "C:\ruta\al\repo\active-directory\scripts\05-limpiar-ad.ps1" -WhatIf
# Revisar que solo va a eliminar lo esperado, luego:
powershell -ExecutionPolicy Bypass -File "C:\ruta\al\repo\active-directory\scripts\05-limpiar-ad.ps1"
```

Si el repo no está clonado en el DC, pegar directamente en PowerShell:

```powershell
# Eliminar usuarios extra (clopez, agarcia, psanchez y cualquier otro
# que no sea svc-inventario, pfsense_bind, mgomez, jperez)
$PermitidosSam = @('svc-inventario','pfsense_bind','mgomez','jperez')
$OuUser = "OU=User,OU=ITU,DC=itu,DC=local"

Get-ADUser -Filter * -SearchBase $OuUser | ForEach-Object {
    if ($PermitidosSam -notcontains $_.SamAccountName) {
        Write-Host "Eliminando: $($_.SamAccountName)"
        Remove-ADUser -Identity $_ -Confirm:$false
    } else {
        Write-Host "Conservado:  $($_.SamAccountName)"
    }
}

# Verificar resultado
Write-Host "`nUsuarios finales en OU=User:"
Get-ADUser -Filter * -SearchBase $OuUser | Select-Object SamAccountName
```

### Estado final esperado en AD

| Usuario | Grupo | Rol |
|---|---|---|
| `mgomez` | Tecnicos | Acceso total en la app |
| `jperez` | Docentes | Solo lectura |
| `svc-inventario` | InventarioAdmins | Bind LDAP del backend |
| `pfsense_bind` | — | Bind pfSense |

---

## 2. Limpieza de SQL Server (192.168.56.20)

**Cómo acceder**: RDP a `192.168.56.20` con usuario `Administrator` →
abrir SSMS o ejecutar `sqlcmd -S localhost -E` (Windows Authentication).

### Paso 1 — Crear los 2 usuarios nuevos (seguro, no toca nada del back)

Ejecutar en SSMS o con sqlcmd:

```
sqlcmd -S localhost -E -i "C:\ruta\al\repo\sql-server-iis\scripts\configurar-usuarios-sql.sql"
```

O solo el Paso 1 del script (hasta la línea "FIN DEL PASO 1").

Esto crea:
- `inventario_admin` / `InvAdmin!2025` — `db_owner` (plenos permisos)
- `inventario_ro` / `InvReadOnly!2025` — `db_datareader` (solo lectura)

### Paso 2 — Actualizar el Secret de Kubernetes en LubuntuEGI

Una vez que SSH de LubuntuEGI esté reparado, ejecutar:

```bash
kubectl create secret generic backend-secret -n inventario \
  --from-literal=JWT_SECRET_KEY="$(python3 -c 'import secrets;print(secrets.token_hex(32))')" \
  --from-literal=SQLSERVER_USER='inventario_admin' \
  --from-literal=SQLSERVER_PASSWORD='InvAdmin!2025' \
  --from-literal=MONGO_USER='inventario_app' \
  --from-literal=MONGO_PASSWORD='inventario_app' \
  --from-literal=LDAP_BIND_PASSWORD='Inventario!2025' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/backend -n inventario
kubectl rollout status deployment/backend -n inventario
```

Verificar que el login desde el frontend sigue funcionando.

### Paso 3 — Eliminar el usuario viejo (solo después de verificar el Paso 2)

Abrir el archivo `configurar-usuarios-sql.sql`, descomentar el bloque
`/* ... */` del Paso 3 y ejecutarlo en SSMS/sqlcmd. Eso elimina
`inventarioapp`.

O directamente en SSMS:

```sql
USE inventario_ubicaciones;
DROP USER inventarioapp;
USE master;
DROP LOGIN inventarioapp;
```

### Estado final esperado en SQL Server

| Login | Password | Permisos | Uso |
|---|---|---|---|
| `inventario_admin` | `InvAdmin!2025` | `db_owner` | Backend + gestión |
| `inventario_ro` | `InvReadOnly!2025` | `db_datareader` | Solo lectura / demos |

---

## 3. Actualizar secretos.local.md

Después de aplicar los cambios, actualizar `infra/secretos.local.md`
(solo en local, nunca commitear) cambiando:

```
SQLSERVER_USER: inventario_app  →  inventario_admin
SQLSERVER_PASSWORD: InventarioApp!2025  →  InvAdmin!2025
```

Y eliminar las filas de `clopez`, `agarcia`, `psanchez` de la tabla
de usuarios AD.

---

## Resumen de orden de ejecución

```
1. Reparar SSH LubuntuEGI (VirtualBox console)
2. RDP a AD  (192.168.56.10) → ejecutar limpieza de usuarios
3. RDP a SQL (192.168.56.20) → ejecutar configurar-usuarios-sql.sql PASO 1
4. SSH a LubuntuEGI → actualizar Secret + rollout restart backend
5. Verificar login en el frontend con mgomez y jperez
6. RDP a SQL → ejecutar PASO 3 (drop inventarioapp)
7. Actualizar infra/secretos.local.md en local
```
