<?php
/* ============================================================
 * nat-port-forward.php - aplicado via php -f (ver aplicar-config-pfsense.ps1)
 *
 * Crea el port-forward WAN:80 -> ${MINIKUBE_IP}:30080 (frontend del
 * Inventario ITU, NodePort kubernetes/services/frontend-service.yaml)
 * y la regla de firewall WAN asociada.
 *
 * Equivale a "Firewall > NAT > Port Forward" + la regla automatica de
 * "Firewall > Rules > WAN" descriptas en pfsense/README.md seccion 2.
 *
 * Uso: ver pfsense/scripts/aplicar-config-pfsense.ps1 (sustituye
 * ${MINIKUBE_IP} por el valor real, copia el archivo a pfSense y lo
 * ejecuta con `php -f /tmp/nat-port-forward.php`).
 *
 * Nota: los placeholders ${VAR} van entre comillas simples (PHP no
 * interpola variables en strings con comillas simples), para que el
 * texto quede literal hasta que aplicar-config-pfsense.ps1 lo
 * sustituya.
 *
 * Manipula el array $config de pfSense y llama a
 * write_config()/filter_configure(). Revisar/ajustar contra la
 * instancia real antes de usar en produccion (los nombres exactos de
 * claves de 'nat'/'filter' pueden variar levemente segun la version de
 * pfSense).
 * ============================================================ */

require_once('config.inc');
require_once('filter.inc');
require_once('util.inc');

if (!is_array($config['nat']['rule'])) {
    $config['nat']['rule'] = array();
}

$descr = 'Inventario ITU - frontend (NAT 80 -> 30080)';

// Evitar duplicados si se vuelve a correr el playback.
foreach ($config['nat']['rule'] as $rule) {
    if (isset($rule['descr']) && $rule['descr'] === $descr) {
        echo "Ya existe el port-forward '$descr', no se duplica.\n";
        return;
    }
}

$nat_rule = array(
    'interface'   => 'wan',
    'protocol'    => 'tcp',
    'target'      => '${MINIKUBE_IP}',
    'local-port'  => '30080',
    'source'      => array('any' => ''),
    'destination' => array('any' => '', 'port' => '80'),
    'descr'       => $descr,
);
$config['nat']['rule'][] = $nat_rule;

if (!is_array($config['filter']['rule'])) {
    $config['filter']['rule'] = array();
}

$filter_rule = array(
    'type'        => 'pass',
    'interface'   => 'wan',
    'protocol'    => 'tcp',
    'source'      => array('any' => ''),
    'destination' => array('address' => '${MINIKUBE_IP}', 'port' => '30080'),
    'descr'       => $descr,
);
$config['filter']['rule'][] = $filter_rule;

write_config('Inventario ITU: NAT port-forward 80 -> ${MINIKUBE_IP}:30080');
filter_configure();

echo "OK: port-forward WAN:80 -> ${MINIKUBE_IP}:30080 aplicado.\n";
