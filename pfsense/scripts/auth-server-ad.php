<?php
/* ============================================================
 * auth-server-ad.php - aplicado via php -f (ver aplicar-config-pfsense.ps1)
 *
 * Da de alta el Authentication Server LDAP "AD-ITU-Laboratorio"
 * contra el Domain Controller (${DC_IP}:389) y el grupo remoto
 * "pfAdmins" con privilegio "WebCfg - All pages", segun
 * pfsense/README.md seccion 3.
 *
 * Variables sustituidas por aplicar-config-pfsense.ps1:
 *   ${DC_IP}                 IP del DC (DC01-ITU)
 *   ${PFSENSE_BIND_PASSWORD} password de la cuenta pfsense_bind en AD
 *                            (definir SOLO en infra/red.local.env,
 *                            nunca commitear)
 *
 * Nota: los placeholders ${VAR} van entre comillas simples (PHP no
 * interpola variables en strings con comillas simples), para que el
 * texto quede literal hasta que aplicar-config-pfsense.ps1 lo
 * sustituya.
 *
 * Manipula el array $config de pfSense y llama a write_config(),
 * ejecutado con php -f (ver pfsense/README.md, seccion "Habilitar SSH").
 * Probado contra la instancia real (2026-06-14): los nombres de
 * 'ldap_attr_*' usados abajo funcionaron en pfSense 2.8.
 * ============================================================ */

require_once('config.inc');
require_once('util.inc');

if (!is_array($config['system']['authserver'])) {
    $config['system']['authserver'] = array();
}

$descr = 'AD-ITU-Laboratorio';

foreach ($config['system']['authserver'] as $srv) {
    if (isset($srv['name']) && $srv['name'] === $descr) {
        echo "Ya existe el Authentication Server '$descr', no se duplica.\n";
        return;
    }
}

$authserver = array(
    'refid'            => uniqid(),
    'type'             => 'ldap',
    'name'             => $descr,
    'host'             => '${DC_IP}',
    'ldap_port'        => '389',
    'transport'        => 'tcp',
    'ldap_protver'     => '3',
    'ldap_scope'       => 'subtree',
    'ldap_basedn'      => 'DC=itu,DC=local',
    'ldap_authcn'      => 'OU=ITU,DC=itu,DC=local',
    'ldap_binddn'      => 'CN=pfsense_bind,OU=pfsense,DC=itu,DC=local',
    'ldap_bindpw'      => '${PFSENSE_BIND_PASSWORD}',
    'ldap_attr_user'   => 'samAccountName',
    'ldap_attr_group'  => 'cn',
    'ldap_attr_member' => 'memberOf',
    'ldap_rfc2307'     => false,
);
$config['system']['authserver'][] = $authserver;

if (!is_array($config['system']['group'])) {
    $config['system']['group'] = array();
}

$group_name = 'pfAdmins';
$group_exists = false;
foreach ($config['system']['group'] as $grp) {
    if (isset($grp['name']) && $grp['name'] === $group_name) {
        $group_exists = true;
        break;
    }
}

if (!$group_exists) {
    $config['system']['group'][] = array(
        'name'  => $group_name,
        'scope' => 'remote',
        'gid'   => '2000',
        'priv'  => array('page-all'),
    );
}

write_config('Inventario ITU: Authentication Server AD-ITU-Laboratorio + grupo pfAdmins');

echo "OK: Authentication Server '$descr' y grupo '$group_name' aplicados.\n";
echo "Recordar: en System > User Manager > Settings, agregar '$descr' como servidor\n";
echo "adicional (sin quitar 'Local Database') para poder usarlo para login.\n";
