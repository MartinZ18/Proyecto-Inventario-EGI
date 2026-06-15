<#
============================================================
configurar-firewall-sql-iis.ps1

Crea las reglas de Windows Firewall necesarias en la VM de
SQL Server 2022 para que el backend (en Minikube) y el
resto del laboratorio puedan conectarse, sin dejar los puertos
abiertos a cualquier origen.

Ejecutar como Administrador en la VM de SQL Server.

Las variables $RedLaboratorio y $IpMinikube se toman de las
variables de entorno IP_RED_PROF / MINIKUBE_IP (ver
infra/red.example.env), con defaults para la topología Host-Only
recomendada (192.168.56.0/24). Para usar tu propia red, cargá
infra/red.local.env antes de ejecutar, por ejemplo:

  Get-Content ..\..\infra\red.local.env | Where-Object { $_ -match '=' } |
    ForEach-Object {
      $k, $v = $_ -split '=', 2
      [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim())
    }

MINIKUBE_IP es opcional: si no está definida, las reglas solo
permiten la red del laboratorio (que ya incluye al host de Minikube).
============================================================
#>

#Requires -RunAsAdministrator

# ----- Configuración (env vars con defaults Host-Only) -----
$RedLaboratorio = if ($env:IP_RED_PROF) { $env:IP_RED_PROF } else { "192.168.56.0/24" }
$IpMinikube     = $env:MINIKUBE_IP

$RemoteAddressesSql = @($RedLaboratorio)
if ($IpMinikube) { $RemoteAddressesSql += $IpMinikube }

# ----- 1. SQL Server (motor de base de datos) -----
# Puerto TCP 1433: acceso desde toda la red del laboratorio (incluye
# Minikube, AD, pfSense) y explícitamente desde el host de Minikube.
New-NetFirewallRule `
    -DisplayName "Inventario - SQL Server (TCP 1433)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 1433 `
    -RemoteAddress $RemoteAddressesSql `
    -Action Allow `
    -Profile Domain,Private

# UDP 1434: SQL Server Browser (resolución de instancias con nombre).
# Solo necesario si se usa una instancia nombrada en lugar de la
# default; se deja habilitado por si se reconfigura más adelante.
New-NetFirewallRule `
    -DisplayName "Inventario - SQL Server Browser (UDP 1434)" `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort 1434 `
    -RemoteAddress $RedLaboratorio `
    -Action Allow `
    -Profile Domain,Private

Write-Host "Reglas de firewall creadas/actualizadas."
Write-Host "Verificar con: Get-NetFirewallRule -DisplayName 'Inventario*' | Format-Table DisplayName,Enabled,Direction"
