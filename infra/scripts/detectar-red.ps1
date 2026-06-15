# ============================================================
# Resuelve la configuracion de red del laboratorio para esta
# ejecucion:
#   1. Carga infra/red.local.env (o infra/red.example.env como
#      fallback, con una advertencia). MINIKUBE_IP es la IP estatica
#      del host Minikube (ver infra/red.local.env) - ya no se recalcula
#      con `minikube ip`, porque con --driver=docker esa IP es la del
#      bridge interno de Docker, no ruteable desde el resto de la red.
#   2. Si SQLSERVER_IP no esta fijado, intenta resolverlo por DNS
#      contra el DC (Resolve-DnsName sqlserver.itu.local -Server
#      $DC_IP), usando el valor del archivo de configuracion como
#      fallback.
#
# Uso (dot-sourcing, para que las variables queden en la sesion):
#   . .\infra\scripts\detectar-red.ps1
#
# Variables resueltas (como variables de script y de entorno del
# proceso, para infra/scripts/generar-manifiestos.ps1):
#   PFSENSE_LAN_IP, DC_IP, SQLSERVER_IP, IP_RED_PROF, MINIKUBE_IP
# ============================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InfraDir = Split-Path -Parent $ScriptDir

function Import-DotEnv {
    param([string]$Path)
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) {
            $name = $parts[0].Trim()
            $value = $parts[1].Trim()
            Set-Variable -Name $name -Value $value -Scope Script
        }
    }
}

$LocalEnv = Join-Path $InfraDir 'red.local.env'
$ExampleEnv = Join-Path $InfraDir 'red.example.env'

if (Test-Path $LocalEnv) {
    Import-DotEnv -Path $LocalEnv
} else {
    Write-Warning "infra/red.local.env no existe, usando infra/red.example.env (defaults)"
    Import-DotEnv -Path $ExampleEnv
}

# Si SQLSERVER_IP no esta fijado, intentar resolver por DNS contra el DC.
if ([string]::IsNullOrWhiteSpace($SQLSERVER_IP) -and -not [string]::IsNullOrWhiteSpace($DC_IP)) {
    try {
        $dnsResult = Resolve-DnsName -Name 'sqlserver.itu.local' -Server $DC_IP -Type A -ErrorAction Stop
        $resolved = $dnsResult | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1 -ExpandProperty IPAddress
        if ($resolved) { $SQLSERVER_IP = $resolved }
    } catch {}
}

Write-Host "[detectar-red] PFSENSE_LAN_IP=$PFSENSE_LAN_IP"
Write-Host "[detectar-red] DC_IP=$DC_IP"
Write-Host "[detectar-red] SQLSERVER_IP=$SQLSERVER_IP"
Write-Host "[detectar-red] IP_RED_PROF=$IP_RED_PROF"
Write-Host "[detectar-red] MINIKUBE_IP=$MINIKUBE_IP"

# Tambien quedan como variables de entorno del proceso, para que
# infra/scripts/generar-manifiestos.ps1 las pueda leer.
$env:PFSENSE_LAN_IP = $PFSENSE_LAN_IP
$env:DC_IP = $DC_IP
$env:SQLSERVER_IP = $SQLSERVER_IP
$env:IP_RED_PROF = $IP_RED_PROF
$env:MINIKUBE_IP = $MINIKUBE_IP
