<#
============================================================
aplicar-config-pfsense.ps1

Aplica uno de los scripts de pfsense/scripts/*.php a la instancia de
pfSense via SSH + `php -f`, sustituyendo los placeholders
${VAR} por los valores de infra/red.local.env (o infra/red.example.env
como fallback).

Nota: se probo `pfSsh.php playback <ruta>` primero, pero esa subcomando
solo acepta nombres de sesiones predefinidas (no rutas arbitrarias) y
el directorio /usr/local/share/pfSense/pfSsh.php/playback/ no existe en
pfSense 2.8. Como la sesion SSH del usuario admin corre como root, basta
con ejecutar el .php directo con `php -f`, que ya tiene config.inc/util.inc
en el include_path.

Requisitos:
  - pfSense con SSH habilitado (System > Advanced > Admin Access),
    ver pfsense/README.md seccion "Habilitar SSH".
  - Cliente OpenSSH de Windows (incluido en Windows 10/11: ssh, scp).
  - Acceso por clave publica recomendado (si no, va a pedir la
    password de admin dos veces: una para scp y otra para ssh).

Uso:
  .\aplicar-config-pfsense.ps1 -Script wan-allow-private
  .\aplicar-config-pfsense.ps1 -Script nat-port-forward
  .\aplicar-config-pfsense.ps1 -Script nat-rdp-forward
  .\aplicar-config-pfsense.ps1 -Script nat-iis-forward
  .\aplicar-config-pfsense.ps1 -Script auth-server-ad
  .\aplicar-config-pfsense.ps1 -Script dhcp-relay

ADVERTENCIA: estos scripts modifican la configuracion de pfSense (NAT,
firewall, autenticacion, DHCP). El .php con los valores ya sustituidos
queda en infra/_generated-pfsense/ para poder revisarlo antes de que
se ejecute con `php -f`. Se recomienda tener un backup reciente
de config.xml (Diagnostics > Backup & Restore) antes de aplicar.
============================================================
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('wan-allow-private', 'nat-port-forward', 'nat-rdp-forward', 'nat-iis-forward', 'auth-server-ad', 'dhcp-relay')]
    [string]$Script,

    [string]$SshUser
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PfsenseDir = Split-Path -Parent $ScriptDir
$RootDir = Split-Path -Parent $PfsenseDir
$InfraDir = Join-Path $RootDir 'infra'

function Import-DotEnv {
    param([string]$Path)
    $vars = @{}
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) {
            $vars[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
    return $vars
}

$LocalEnv = Join-Path $InfraDir 'red.local.env'
$ExampleEnv = Join-Path $InfraDir 'red.example.env'

if (Test-Path $LocalEnv) {
    $vars = Import-DotEnv -Path $LocalEnv
} else {
    Write-Warning "infra/red.local.env no existe, usando infra/red.example.env (defaults). PFSENSE_BIND_PASSWORD quedara vacio."
    $vars = Import-DotEnv -Path $ExampleEnv
}

if (-not $SshUser) {
    if ($vars.ContainsKey('PFSENSE_SSH_USER') -and $vars['PFSENSE_SSH_USER']) {
        $SshUser = $vars['PFSENSE_SSH_USER']
    } else {
        $SshUser = 'admin'
    }
}

$srcPhp = Join-Path $ScriptDir "$Script.php"
if (-not (Test-Path $srcPhp)) {
    throw "No existe $srcPhp"
}

$content = Get-Content -Path $srcPhp -Raw
foreach ($key in $vars.Keys) {
    $placeholder = '${' + $key + '}'
    $content = $content.Replace($placeholder, $vars[$key])
}

$leftover = [regex]::Matches($content, '\$\{[A-Z_]+\}')
if ($leftover.Count -gt 0) {
    $names = ($leftover | ForEach-Object { $_.Value } | Select-Object -Unique) -join ', '
    Write-Warning "Quedaron placeholders sin sustituir: $names (definirlos en infra/red.local.env)"
}

$outDir = Join-Path $InfraDir '_generated-pfsense'
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}
$outFile = Join-Path $outDir "$Script.php"
[System.IO.File]::WriteAllText($outFile, $content, (New-Object System.Text.UTF8Encoding $false))

$pfsenseHost = $vars['PFSENSE_LAN_IP']
if (-not $pfsenseHost) { $pfsenseHost = '192.168.56.2' }

$remotePath = "/tmp/$Script.php"

Write-Host "[aplicar-config-pfsense] Generado: $outFile"
Write-Host "[aplicar-config-pfsense] Copiando a ${SshUser}@${pfsenseHost}:${remotePath} ..."
scp $outFile "${SshUser}@${pfsenseHost}:${remotePath}"

Write-Host "[aplicar-config-pfsense] Ejecutando php -f $remotePath ..."
ssh "${SshUser}@${pfsenseHost}" "php -f $remotePath && rm -f $remotePath"

Write-Host "[aplicar-config-pfsense] OK"
