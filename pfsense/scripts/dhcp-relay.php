<?php
/* ============================================================
 * dhcp-relay.php - aplicado via php -f (ver aplicar-config-pfsense.ps1)
 *
 * Desactiva el servidor DHCP local de pfSense en LAN y configura
 * DHCP Relay hacia el Domain Controller (${DC_IP}), segun
 * pfsense/README.md seccion 4.
 *
 * Variables sustituidas por aplicar-config-pfsense.ps1:
 *   ${DC_IP}  IP del DC (DC01-ITU), destino del relay
 *
 * Nota: el placeholder ${DC_IP} va entre comillas simples (PHP no
 * interpola variables en strings con comillas simples), para que el
 * texto quede literal hasta que aplicar-config-pfsense.ps1 lo
 * sustituya.
 *
 * Manipula el array $config de pfSense y llama a write_config(),
 * ejecutado con php -f (ver pfsense/README.md, seccion "Habilitar SSH").
 * Revisar/ajustar contra la instancia real antes de usar en produccion.
 * ============================================================ */

require_once('config.inc');
require_once('util.inc');

// 1. Desactivar el servidor DHCP local en LAN.
if (isset($config['dhcpd']['lan'])) {
    $config['dhcpd']['lan']['enable'] = false;
}

// 2. Configurar DHCP Relay en LAN -> DC.
if (!is_array($config['dhcrelay'])) {
    $config['dhcrelay'] = array();
}

$config['dhcrelay']['enable']    = true;
$config['dhcrelay']['interface'] = 'lan';
$config['dhcrelay']['server']    = '${DC_IP}';

write_config('Inventario ITU: DHCP Relay LAN -> ${DC_IP} (DHCP local desactivado)');

echo "OK: DHCP local desactivado y DHCP Relay LAN -> ${DC_IP} aplicado.\n";
echo "Verificar en un cliente de la LAN (ipconfig /renew o dhclient -r && dhclient).\n";
