<?php
/* ============================================================
 * nat-rdp-forward.php - aplicado via php -f (ver aplicar-config-pfsense.ps1)
 *
 * Crea dos port-forwards WAN -> RDP (3389) hacia las VMs del laboratorio,
 * mas las reglas de firewall WAN asociadas:
 *
 *   - WAN:40100 -> ${DC_IP}:3389        (DC01-ITU, puerto alterno)
 *   - WAN:40200 -> ${SQLSERVER_IP}:3389 (SQL Server, puerto alterno)
 *
 * Puertos alternos en vez de WAN:3389 porque el forward a nivel
 * VirtualBox (host:3389 -> guest WAN:3389) no entrega trafico al guest
 * (0 paquetes en em0, causa no determinada; ver pfsense/README.md
 * seccion 2.1). Ademas, antes de aplicar este script hace falta
 * wan-allow-private.php (deshabilita "Block private networks"/"Block
 * bogon networks" en WAN, sin lo cual ningun port-forward WAN funciona
 * en esta topologia).
 *
 * Variables sustituidas por aplicar-config-pfsense.ps1:
 *   ${DC_IP}         IP del DC (DC01-ITU)
 *   ${SQLSERVER_IP}  IP de la VM de SQL Server
 *
 * Nota: el WAN de pfSense es un adaptador NAT de VirtualBox. Estas
 * reglas solo redirigen dentro de esa NAT; para que sean alcanzables
 * desde la PC Windows real (o desde fuera) hace falta ademas un
 * port-forward a nivel VirtualBox (VBoxManage modifyvm ... --natpf1) y,
 * si aplica, en el router de casa.
 *
 * Nota: los placeholders ${VAR} van entre comillas simples (PHP no
 * interpola variables en strings con comillas simples), para que el
 * texto quede literal hasta que aplicar-config-pfsense.ps1 lo
 * sustituya.
 *
 * Manipula el array $config de pfSense y llama a
 * write_config()/filter_configure(), igual que nat-port-forward.php.
 * ============================================================ */

require_once('config.inc');
require_once('filter.inc');
require_once('util.inc');

if (!is_array($config['nat']['rule'])) {
    $config['nat']['rule'] = array();
}
if (!is_array($config['filter']['rule'])) {
    $config['filter']['rule'] = array();
}

function agregar_rdp_forward(&$config, $descr, $target_ip, $wan_port) {
    foreach ($config['nat']['rule'] as $rule) {
        if (isset($rule['descr']) && $rule['descr'] === $descr) {
            echo "Ya existe el port-forward '$descr', no se duplica.\n";
            return;
        }
    }

    $config['nat']['rule'][] = array(
        'interface'   => 'wan',
        'protocol'    => 'tcp',
        'target'      => $target_ip,
        'local-port'  => '3389',
        'source'      => array('any' => ''),
        'destination' => array('any' => '', 'port' => $wan_port),
        'descr'       => $descr,
    );

    $config['filter']['rule'][] = array(
        'type'        => 'pass',
        'interface'   => 'wan',
        'protocol'    => 'tcp',
        'source'      => array('any' => ''),
        'destination' => array('address' => $target_ip, 'port' => '3389'),
        'descr'       => $descr,
    );

    echo "OK: port-forward '$descr' (WAN:$wan_port -> $target_ip:3389) agregado.\n";
}

agregar_rdp_forward($config, 'Inventario ITU - RDP DC01-ITU', '${DC_IP}', '40100');
agregar_rdp_forward($config, 'Inventario ITU - RDP SQL Server (puerto alterno 40200)', '${SQLSERVER_IP}', '40200');

write_config('Inventario ITU: NAT port-forward RDP -> DC01-ITU (3389) y SQL Server (40200)');
filter_configure();

echo "Listo.\n";
