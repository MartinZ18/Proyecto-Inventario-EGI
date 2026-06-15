<?php
/* ============================================================
 * wan-allow-private.php - aplicado via php -f (ver aplicar-config-pfsense.ps1)
 *
 * Deshabilita "Block private networks" y "Block bogon networks" en la
 * interfaz WAN.
 *
 * Motivo: el WAN de pfSense en este laboratorio es un adaptador NAT de
 * VirtualBox. Todo el trafico entrante por WAN llega con source
 * 10.0.2.2 (gateway del NAT de VirtualBox), que cae dentro de
 * 10.0.0.0/8 (RFC1918). Con "Block private networks" activo, pfSense
 * genera una regla "block in quick on $WAN from 10.0.0.0/8 to any" que
 * descarta ese trafico ANTES de llegar a las reglas pass de los
 * port-forwards RDP (nat-rdp-forward.php), rompiendo el acceso desde
 * fuera de la VM de pfSense.
 *
 * Sin placeholders: no requiere sustitucion via aplicar-config-pfsense.ps1
 * (puede aplicarse directo con scp + php -f).
 * ============================================================ */

require_once('config.inc');
require_once('filter.inc');
require_once('util.inc');

unset($config['interfaces']['wan']['blockpriv']);
unset($config['interfaces']['wan']['blockbogons']);

write_config('Inventario ITU: deshabilitar Block private networks / Block bogon networks en WAN (el WAN es NAT de VirtualBox, origen 10.0.2.2 es RFC1918)');
filter_configure();

echo "Listo.\n";
