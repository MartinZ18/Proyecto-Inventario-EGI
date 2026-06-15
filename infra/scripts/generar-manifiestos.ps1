# ============================================================
# Genera la version final de los manifiestos K8s que contienen
# placeholders ${VAR} (IPs/red del laboratorio), sustituyendolos por
# los valores resueltos por infra/scripts/detectar-red.ps1.
#
# Uso:
#   . .\infra\scripts\detectar-red.ps1
#   .\infra\scripts\generar-manifiestos.ps1
#
# Procesa TODOS los .yaml de kubernetes\external\ y
# kubernetes\network-policies\ (la mayoria no tiene placeholders, se
# copian sin cambios) y los copia a:
#   kubernetes\_generated\external\
#   kubernetes\_generated\network-policies\
# (gitignored, ver .gitignore). El resto de los manifiestos
# (configmaps, deployments, services, namespace) no tiene placeholders
# y se aplica directo desde kubernetes\.
# ============================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$OutDir = Join-Path $RootDir 'kubernetes\_generated'

$Vars = @('PFSENSE_LAN_IP', 'DC_IP', 'SQLSERVER_IP', 'IP_RED_PROF', 'MINIKUBE_IP')
$Dirs = @('external', 'network-policies')

if (Test-Path $OutDir) {
    Remove-Item -Recurse -Force $OutDir
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

foreach ($d in $Dirs) {
    $srcDir = Join-Path $RootDir "kubernetes\$d"
    $dstDir = Join-Path $OutDir $d
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

    Get-ChildItem -Path $srcDir -Filter '*.yaml' -File | ForEach-Object {
        $content = Get-Content -Path $_.FullName -Raw

        foreach ($var in $Vars) {
            $value = [Environment]::GetEnvironmentVariable($var)
            if ($null -eq $value) { $value = '' }
            $placeholder = '${' + $var + '}'
            $content = $content.Replace($placeholder, $value)
        }

        $dst = Join-Path $dstDir $_.Name
        [System.IO.File]::WriteAllText($dst, $content, $Utf8NoBom)
    }

    Write-Host "[generar-manifiestos] kubernetes\$d\ -> kubernetes\_generated\$d\"
}

# Verificacion: que no quede ningun ${VAR} sin sustituir.
$leftover = Get-ChildItem -Recurse -Path $OutDir -File | Select-String -Pattern '\$\{[A-Z_]+\}'
if ($leftover) {
    Write-Error "[generar-manifiestos] Quedaron placeholders `${VAR} sin sustituir:"
    $leftover | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "[generar-manifiestos] OK - manifiestos generados en kubernetes\_generated\"
