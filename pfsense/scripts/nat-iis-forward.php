<?php
/* ============================================================
 * nat-iis-forward.php - aplicado via php -f (ver aplicar-config-pfsense.ps1)
 *
 * Crea un port-forward WAN -> IIS (sitio "almacenes", VM de SQL Server),
 * mas la regla de firewall WAN asociada:
 *
 *   - WAN:40080 -> ${SQLSERVER_IP}:80
 *
 * Puerto alterno (40080, no 80) porque WAN:80 esta reservado para el
 * port-forward del frontend de Minikube en Fase 5
 * (WAN:80 -> ${MINIKUBE_IP}:30080, ver nat-port-forward.php).
 *
 * Prerequisito: wan-allow-private.php (deshabilita "Block private
 * networks"/"Block bogon networks" en WAN), sin el cual ningun
 * port-forward WAN funciona en esta topologia (ver pfsense/README.md
 * secciones 1 y 2.1).
 *
 * Nota sobre el sitio "almacenes": IIS lo expone con binding por Host
 * header (almacenes.itu.local), no en el binding "catch-all" (*:80:) que
 * usa "Default Web Site". Un request sin ese Host header (ej. desde un
 * navegador apuntando a la IP/puerto directo) cae en "Default Web Site".
 * Para llegar a "almacenes" desde afuera hace falta enviar
 * "Host: almacenes.itu.local" (curl -H, o una entrada en el archivo hosts
 * del cliente que resuelva ese nombre a la IP/puerto externos).
 *
 * Variables sustituidas por aplicar-config-pfsense.ps1:
 *   ${SQLSERVER_IP}  IP de la VM de SQL Server (sitio IIS "almacenes")
 *
 * Nota: el WAN de pfSense es un adaptador NAT de VirtualBox. Esta regla
 * solo redirige dentro de esa NAT; para que sea alcanzable desde la PC
 * Windows real (o desde fuera) hace falta ademas un port-forward a nivel
 * VirtualBox (VBoxManage modifyvm ... --natpf1) y, si aplica, en el
 * router de casa.
 *
 * Nota: los placeholders ${VAR} van entre comillas simples (PHP no
 * interpola variables en strings con comillas simples), para que el
 * texto quede literal hasta que aplicar-config-pfsense.ps1 lo sustituya.
 *
 * Manipula el array $config de pfSense y llama a
 * write_config()/filter_configure(), igual que nat-rdp-forward.php.
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

function agregar_http_forward(&$config, $descr, $target_ip, $wan_port, $target_port) {
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
        'local-port'  => $target_port,
        'source'      => array('any' => ''),
        'destination' => array('any' => '', 'port' => $wan_port),
        'descr'       => $descr,
    );

    $config['filter']['rule'][] = array(
        'type'        => 'pass',
        'interface'   => 'wan',
        'protocol'    => 'tcp',
        'source'      => array('any' => ''),
        'destination' => array('address' => $target_ip, 'port' => $target_port),
        'descr'       => $descr,
    );

    echo "OK: port-forward '$descr' (WAN:$wan_port -> $target_ip:$target_port) agregado.\n";
}

agregar_http_forward($config, 'Inventario ITU - IIS almacenes (puerto alterno 40080)', '${SQLSERVER_IP}', '40080', '80');

write_config('Inventario ITU: NAT port-forward IIS almacenes (40080 -> 80)');
filter_configure();

echo "Listo.\n";
