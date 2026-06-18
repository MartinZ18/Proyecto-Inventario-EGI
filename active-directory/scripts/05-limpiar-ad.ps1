<#
============================================================
05-limpiar-ad.ps1

Limpia el dominio itu.local dejando solo lo necesario para
el proyecto Inventario ITU:

  Usuarios que se CONSERVAN en OU=User,OU=ITU,DC=itu,DC=local
  ----------------------------------------------------------
  svc-inventario  cuenta de servicio para el bind LDAP del backend
  pfsense_bind    cuenta de bind para la autenticacion de pfSense
  mgomez          unico usuario con TODOS los permisos (grupo Tecnicos)
  jperez          unico usuario de SOLO LECTURA        (grupo Docentes)

  Usuarios que se ELIMINAN
  ------------------------
  clopez, agarcia, psanchez y CUALQUIER cuenta que no este en la
  lista de conservacion dentro de OU=ITU o en CN=Users (salvo las
  cuentas built-in de Windows: Administrator, Guest, krbtgt,
  DefaultAccount, WDAGUtilityAccount).

  Grupos que se CONSERVAN (todos son del proyecto)
  ------------------------------------------------
  pfAdmins, InventarioAdmins, InventarioUsers, Tecnicos, Docentes, Alumnos

  OUs que se CONSERVAN (todas son del proyecto)
  ---------------------------------------------
  OU=ITU y sus sub-OUs: User, Computer, Server, Printer, Grupos

Ejecutar en DC01-ITU con PowerShell como Administrador de dominio.
El script es NO DESTRUCTIVO hasta que se confirme cada eliminacion
(modo --Confirm) o se use el parametro -Forzar para saltear la
confirmacion.

Uso:
    # Ver que se va a eliminar sin borrar nada:
    powershell -ExecutionPolicy Bypass -File .\05-limpiar-ad.ps1 -WhatIf

    # Eliminar con confirmacion interactiva:
    powershell -ExecutionPolicy Bypass -File .\05-limpiar-ad.ps1

    # Eliminar sin confirmacion (para automatizar):
    powershell -ExecutionPolicy Bypass -File .\05-limpiar-ad.ps1 -Forzar
============================================================
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Forzar
)

#Requires -Modules ActiveDirectory

$ErrorActionPreference = "Stop"

$DominioDN  = "DC=itu,DC=local"
$OuITU_DN   = "OU=ITU,$DominioDN"
$UserOuDN   = "OU=User,$OuITU_DN"
$CNUsers_DN = "CN=Users,$DominioDN"

# Cuentas del proyecto que deben permanecer (sAMAccountName en minusculas)
$UsuariosPermitidos = @(
    "svc-inventario"   # bind LDAP del backend
    "pfsense_bind"     # bind de autenticacion pfSense
    "mgomez"           # tecnico — acceso total en la app
    "jperez"           # docente — solo lectura en la app
)

# Cuentas built-in de Windows/AD que nunca se tocan
$BuiltIns = @(
    "administrator"
    "guest"
    "krbtgt"
    "defaultaccount"
    "wdagutilityaccount"
)

function Eliminar-Usuario {
    param([Microsoft.ActiveDirectory.Management.ADUser]$Usuario)
    $sam = $Usuario.SamAccountName.ToLower()
    if ($Forzar) {
        Remove-ADUser -Identity $Usuario -Confirm:$false
        Write-Host "  ELIMINADO: $sam"
    } else {
        if ($PSCmdlet.ShouldProcess($sam, "Eliminar usuario de AD")) {
            Remove-ADUser -Identity $Usuario -Confirm:$false
            Write-Host "  ELIMINADO: $sam"
        }
    }
}

Write-Host ""
Write-Host "=== Limpieza del dominio itu.local ==="
Write-Host "Usuarios permitidos: $($UsuariosPermitidos -join ', ')"
Write-Host ""

# ------------------------------------------------------------------
# 1. Eliminar usuarios dentro de OU=User,OU=ITU que no esten en la
#    lista de permitidos.
# ------------------------------------------------------------------
Write-Host "--- 1. Usuarios en $UserOuDN ---"
$usuariosOU = Get-ADUser -Filter * -SearchBase $UserOuDN -ErrorAction SilentlyContinue
if ($null -eq $usuariosOU) {
    Write-Host "  La OU $UserOuDN no existe o esta vacia."
} else {
    foreach ($u in $usuariosOU) {
        $sam = $u.SamAccountName.ToLower()
        if ($UsuariosPermitidos -notcontains $sam) {
            Write-Host "  Eliminando usuario no permitido: $sam ($($u.DistinguishedName))"
            Eliminar-Usuario -Usuario $u
        } else {
            Write-Host "  OK (conservado): $sam"
        }
    }
}

# ------------------------------------------------------------------
# 2. Eliminar usuarios en CN=Users que no sean built-in y no esten
#    en la lista de permitidos. Los usuarios que no son del proyecto
#    suelen crearse aqui por defecto.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- 2. Usuarios en $CNUsers_DN ---"
$usuariosCN = Get-ADUser -Filter * -SearchBase $CNUsers_DN -SearchScope OneLevel -ErrorAction SilentlyContinue
if ($null -eq $usuariosCN) {
    Write-Host "  Sin usuarios en CN=Users."
} else {
    foreach ($u in $usuariosCN) {
        $sam = $u.SamAccountName.ToLower()
        if ($BuiltIns -contains $sam) {
            Write-Host "  OK (built-in, no tocar): $sam"
        } elseif ($UsuariosPermitidos -contains $sam) {
            Write-Host "  OK (usuario del proyecto en CN=Users): $sam — considera moverlo a $UserOuDN"
        } else {
            Write-Host "  Eliminando usuario externo al proyecto: $sam"
            Eliminar-Usuario -Usuario $u
        }
    }
}

# ------------------------------------------------------------------
# 3. Buscar usuarios en cualquier otra OU no esperada del dominio
#    (fuera de OU=ITU y de CN=Users).
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- 3. Usuarios en otras OUs (fuera de OU=ITU y CN=Users) ---"
$todosUsuarios = Get-ADUser -Filter * -SearchBase $DominioDN -Properties DistinguishedName
foreach ($u in $todosUsuarios) {
    $dn  = $u.DistinguishedName
    $sam = $u.SamAccountName.ToLower()
    $enITU    = $dn -like "*$OuITU_DN"
    $enCNUsers= $dn -like "*$CNUsers_DN"
    if (-not $enITU -and -not $enCNUsers) {
        if ($BuiltIns -contains $sam) {
            Write-Host "  OK (built-in): $sam — $dn"
        } else {
            Write-Host "  ATENCION — usuario fuera de OU=ITU y CN=Users: $sam — $dn"
            Write-Host "             Revisar manualmente si este usuario debe eliminarse."
        }
    }
}

# ------------------------------------------------------------------
# 4. Verificar membresías de los usuarios conservados.
#    mgomez debe estar en Tecnicos (acceso total).
#    jperez debe estar en Docentes (solo lectura).
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- 4. Verificacion de membresias de los usuarios conservados ---"

$verificaciones = @(
    @{ Sam = "mgomez"; GrupoEsperado = "Tecnicos";  Rol = "acceso total" }
    @{ Sam = "jperez"; GrupoEsperado = "Docentes";  Rol = "solo lectura" }
)

foreach ($v in $verificaciones) {
    $usuario = Get-ADUser -Filter "SamAccountName -eq '$($v.Sam)'" -ErrorAction SilentlyContinue
    if ($null -eq $usuario) {
        Write-Host "  FALTA el usuario $($v.Sam) — ejecutar 04-crear-usuarios-grupos.ps1"
        continue
    }
    $grupos = (Get-ADUser -Identity $v.Sam -Properties MemberOf).MemberOf | ForEach-Object {
        (Get-ADGroup -Identity $_).Name
    }
    if ($grupos -contains $v.GrupoEsperado) {
        Write-Host "  OK: $($v.Sam) esta en $($v.GrupoEsperado) ($($v.Rol))"
    } else {
        Write-Host "  ADVERTENCIA: $($v.Sam) NO esta en $($v.GrupoEsperado) — agregar con:"
        Write-Host "              Add-ADGroupMember -Identity '$($v.GrupoEsperado)' -Members '$($v.Sam)'"
    }
}

# ------------------------------------------------------------------
# 5. Resumen final
# ------------------------------------------------------------------
Write-Host ""
Write-Host "=== Resumen de usuarios en $UserOuDN ==="
$final = Get-ADUser -Filter * -SearchBase $UserOuDN -Properties MemberOf -ErrorAction SilentlyContinue
if ($null -eq $final) {
    Write-Host "  (vacia o no existe)"
} else {
    foreach ($u in $final) {
        $grupos = $u.MemberOf | ForEach-Object { (Get-ADGroup -Identity $_).Name }
        Write-Host "  $($u.SamAccountName) -> grupos: $($grupos -join ', ')"
    }
}
Write-Host ""
Write-Host "Limpieza completada. Estado final arriba."
Write-Host "Si algun usuario falta, ejecutar: .\04-crear-usuarios-grupos.ps1"
