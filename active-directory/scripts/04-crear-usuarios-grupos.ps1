<#
============================================================
04-crear-usuarios-grupos.ps1

Crea la estructura de OUs, los grupos de seguridad y los usuarios de
prueba del proyecto Inventario ITU en el dominio "itu.local".

Ejecutar en el Domain Controller (DC01-ITU) o desde una máquina con
RSAT (modulo ActiveDirectory) y permisos de administrador de dominio.

Es IDEMPOTENTE: se puede volver a ejecutar sin error si las OUs,
grupos o usuarios ya existen (los pasos existentes se saltean).

Uso:
    # Interactivo (solicita contraseñas por consola):
    powershell -ExecutionPolicy Bypass -File .\04-crear-usuarios-grupos.ps1

    # No-interactivo (CI/CD o automatización):
    powershell -ExecutionPolicy Bypass -File .\04-crear-usuarios-grupos.ps1 `
        -PassInventario "MiPasswordSegura!1" `
        -PassLdap "OtraPassword!2"

Ver active-directory/README.md para el detalle de cada usuario/grupo
y el paso a paso completo de instalacion de AD DS/DNS.
============================================================
#>

#Requires -Modules ActiveDirectory

param(
    [string]$PassInventario = "",
    [string]$PassLdap       = ""
)

if (-not $PassInventario) {
    $PassInventario = Read-Host "Contraseña para usuarios de inventario (mgomez, jperez, svc-inventario)"
}
if (-not $PassLdap) {
    $PassLdap = Read-Host "Contraseña para pfsense_bind"
}

$ErrorActionPreference = "Stop"

$DominioDN = "DC=itu,DC=local"
$OuRaizNombre = "ITU"
$OuRaizDN = "OU=$OuRaizNombre,$DominioDN"

# ----- 1. Estructura de OUs -----
# itu.local -> OU=ITU -> User / Computer / Server / Printer / Grupos
# "Grupos" es la OU donde van los grupos de seguridad del proyecto.
# LDAP_BASE_DN del backend (ver kubernetes/configmaps/backend-configmap.yaml)
# debe ser "OU=ITU,DC=itu,DC=local" para que la busqueda de grupos
# "cn={grupo},ou=grupos,{LDAP_BASE_DN}" en app/services/ldap_service.py
# encuentre cn=Tecnicos / cn=Docentes / cn=Alumnos en OU=Grupos,OU=ITU,...

function Asegurar-OU {
    param(
        [string]$Nombre,
        [string]$PathPadre
    )
    $dn = "OU=$Nombre,$PathPadre"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Nombre -Path $PathPadre -ProtectedFromAccidentalDeletion $true
        Write-Host "OU creada: $dn"
    } else {
        Write-Host "OU ya existe: $dn (sin cambios)"
    }
}

Asegurar-OU -Nombre $OuRaizNombre -PathPadre $DominioDN
foreach ($sub in @("User", "Computer", "Server", "Printer", "Grupos")) {
    Asegurar-OU -Nombre $sub -PathPadre $OuRaizDN
}

$UserOuDN   = "OU=User,$OuRaizDN"
$GruposOuDN = "OU=Grupos,$OuRaizDN"

# ----- 2. Grupos de seguridad -----
# - pfAdmins:        login a la WebGUI de pfSense (ver pfsense/README.md)
# - InventarioAdmins / InventarioUsers: grupos generales de administracion
#   del proyecto (no usados directamente por el backend).
# - Tecnicos / Docentes / Alumnos: roles que lee
#   app/services/ldap_service.py -> obtener_rol() para el RBAC del backend
#   (requiere_tecnico, ver app/dependencies.py).
$Grupos = @("pfAdmins", "InventarioAdmins", "InventarioUsers", "Tecnicos", "Docentes", "Alumnos")

foreach ($g in $Grupos) {
    if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $g -SamAccountName $g -GroupScope Global -GroupCategory Security -Path $GruposOuDN
        Write-Host "Grupo creado: $g"
    } else {
        Write-Host "Grupo ya existe: $g (sin cambios)"
    }
}

# ----- 3. Usuarios del proyecto -----
# Solo se crean los 4 necesarios:
#   svc-inventario  cuenta de servicio para el bind LDAP del backend
#   pfsense_bind    cuenta de bind para la autenticacion de pfSense
#   mgomez          UNICO usuario con TODOS los permisos (grupo Tecnicos)
#   jperez          UNICO usuario de SOLO LECTURA        (grupo Docentes)
#
# Las contraseñas se reciben por parametro (ver bloque param() arriba).
# Deben cumplir la politica de complejidad de AD: mayuscula+minuscula+
# numero+simbolo, 8+ caracteres.
# Nota: AD rechaza passwords que contengan 3+ caracteres del sAMAccountName.
$Usuarios = @(
    @{ Sam = "svc-inventario"; Nombre = "Service Account Inventario"; Pass = $PassInventario; Grupos = @("InventarioAdmins") }
    @{ Sam = "pfsense_bind";   Nombre = "pfSense Bind Account";       Pass = $PassLdap;       Grupos = @() }
    @{ Sam = "mgomez";         Nombre = "Maria Gomez";                Pass = $PassInventario; Grupos = @("Tecnicos", "InventarioAdmins", "InventarioUsers", "pfAdmins") }
    @{ Sam = "jperez";         Nombre = "Juan Perez";                 Pass = $PassInventario; Grupos = @("Docentes", "InventarioUsers") }
)

foreach ($u in $Usuarios) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'" -ErrorAction SilentlyContinue)) {
        $securePass = ConvertTo-SecureString $u.Pass -AsPlainText -Force
        New-ADUser `
            -Name $u.Nombre `
            -SamAccountName $u.Sam `
            -UserPrincipalName "$($u.Sam)@itu.local" `
            -Path $UserOuDN `
            -AccountPassword $securePass `
            -Enabled $true `
            -ChangePasswordAtLogon $false `
            -PasswordNeverExpires $true
        Write-Host "Usuario creado: $($u.Sam)"
    } else {
        Write-Host "Usuario ya existe: $($u.Sam) (sin cambios)"
    }

    foreach ($g in $u.Grupos) {
        if (-not (Get-ADGroupMember -Identity $g | Where-Object { $_.SamAccountName -eq $u.Sam })) {
            Add-ADGroupMember -Identity $g -Members $u.Sam
            Write-Host "  -> agregado a grupo $g"
        }
    }
}

Write-Host ""
Write-Host "Listo. Estructura OU=ITU, grupos y 4 usuarios creados/verificados:"
Write-Host "  mgomez      -> Tecnicos (acceso total en la app)"
Write-Host "  jperez      -> Docentes (solo lectura en la app)"
Write-Host "  svc-inventario -> bind LDAP del backend (ver README.md, seccion 4)"
Write-Host "  pfsense_bind   -> bind de autenticacion de pfSense"
Write-Host ""
Write-Host "Para eliminar cuentas extra que puedan existir en la VM, ejecutar:"
Write-Host "  .\05-limpiar-ad.ps1 -WhatIf   (ver que se eliminaria)"
Write-Host "  .\05-limpiar-ad.ps1            (eliminar con confirmacion)"
