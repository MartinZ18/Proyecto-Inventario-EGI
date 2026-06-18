# ============================================================
# Configura VirtualBox en la PC de destino (ej. PC de la facultad):
#   1. Crea la red Host-Only 192.168.56.0/24
#   2. Importa las 3 OVAs (pfSense, DC/AD, SQL Server)
#   3. Fija los adaptadores de red a la red Host-Only
#
# Prerequisito: VirtualBox 7.x instalado, OVAs descargadas.
#
# Uso:
#   .\infra\scripts\setup-virtualbox-nueva-pc.ps1
#   .\infra\scripts\setup-virtualbox-nueva-pc.ps1 -OvaDir "D:\VMs-Export"
# ============================================================
param(
    [string]$OvaDir = "$env:USERPROFILE\Downloads\VMs-Export"
)

$vbm = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

if (-not (Test-Path $vbm)) {
    Write-Error "VBoxManage no encontrado. Instalar VirtualBox 7.x desde virtualbox.org"
    exit 1
}

# ---- 1. Red Host-Only ----------------------------------------
Write-Host "`n=== Configurando red Host-Only 192.168.56.0/24 ===" -ForegroundColor Cyan

$ifaces = & $vbm list hostonlyifs
$existe = $ifaces | Select-String "192.168.56"

if ($existe) {
    Write-Host "[OK] Ya existe una interfaz Host-Only con 192.168.56.x" -ForegroundColor Green
    $nombreIface = ($ifaces | Select-String "^Name:" | Select-Object -First 1) -replace "Name:\s+",""
} else {
    Write-Host "Creando interfaz Host-Only..."
    $salida = & $vbm hostonlyif create 2>&1
    # El nombre de la nueva interfaz viene en la salida
    $nombreIface = ($salida | Select-String "Interface '(.+)' was successfully created" |
                   ForEach-Object { $_.Matches[0].Groups[1].Value })
    if (-not $nombreIface) { $nombreIface = "VirtualBox Host-Only Ethernet Adapter" }

    & $vbm hostonlyif ipconfig $nombreIface --ip 192.168.56.1 --netmask 255.255.255.0
    Write-Host "[OK] Interfaz '$nombreIface' creada con IP 192.168.56.1" -ForegroundColor Green
}

# Usar el primer adaptador encontrado si no se detectó el nombre
if (-not $nombreIface) { $nombreIface = "VirtualBox Host-Only Ethernet Adapter" }
Write-Host "Interfaz Host-Only: '$nombreIface'"

# ---- 2. Importar OVAs ----------------------------------------
$vms = @(
    @{ Archivo = "pfsense-gateway.ova"; Nombre = "pfSense-Gateway"   },
    @{ Archivo = "dc01-itu.ova";        Nombre = "DC01-ITU"           },
    @{ Archivo = "sqlserver2022.ova";   Nombre = "SQLServer2022"      }
)

foreach ($vm in $vms) {
    $ova = Join-Path $OvaDir $vm.Archivo
    Write-Host "`n=== Importando $($vm.Nombre) ===" -ForegroundColor Cyan

    if (-not (Test-Path $ova)) {
        Write-Error "No se encontro $ova — verificar que los OVA esten en $OvaDir"
        continue
    }

    # Verificar si ya existe la VM
    $existe = & $vbm list vms | Select-String $vm.Nombre
    if ($existe) {
        Write-Host "[SKIP] '$($vm.Nombre)' ya existe en VirtualBox" -ForegroundColor Yellow
        continue
    }

    Write-Host "Importando $ova (puede tardar varios minutos)..."
    & $vbm import $ova --vsys 0 --vmname $vm.Nombre
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Fallo al importar $($vm.Archivo)"
        continue
    }

    # Fijar adaptador de red a Host-Only
    Write-Host "Configurando red Host-Only..."
    & $vbm modifyvm $vm.Nombre --nic1 hostonly --hostonlyadapter1 $nombreIface
    Write-Host "[OK] $($vm.Nombre) importada y configurada" -ForegroundColor Green
}

# ---- 3. Limitar RAM de las VMs --------------------------------
# Se aplica tanto a VMs recién importadas como a las ya existentes.
# Ejecutar con las VMs apagadas; de lo contrario VBoxManage retorna error.
Write-Host "`n=== Ajustando RAM de las VMs ===" -ForegroundColor Cyan
$ramConfig = @(
    @{ Nombre = "pfSense-Gateway"; MemMB = 512  },
    @{ Nombre = "DC01-ITU";        MemMB = 1024 },
    @{ Nombre = "SQLServer2022";   MemMB = 2048 }
)
foreach ($cfg in $ramConfig) {
    $existe = & $vbm list vms | Select-String $cfg.Nombre
    if ($existe) {
        & $vbm modifyvm $cfg.Nombre --memory $cfg.MemMB
        Write-Host "[OK] $($cfg.Nombre): $($cfg.MemMB) MB" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] $($cfg.Nombre) no encontrada" -ForegroundColor Yellow
    }
}

# ---- 4. Resumen -----------------------------------------------
Write-Host "`n=== VMs configuradas ===" -ForegroundColor Cyan
& $vbm list vms

Write-Host @"

Proximos pasos:
  1. Arrancar las VMs (pfSense primero, luego DC, luego SQL Server)
  2. Verificar conectividad: ping 192.168.56.2 / .10 / .20
  3. Crear la VM LinuxEGI y correr: bash infra/scripts/setup-linuxegi-nueva-pc.sh
  4. Registrar el runner: bash infra/scripts/setup-runner.sh --token TOKEN
  5. Disparar el workflow en GitHub Actions
"@
