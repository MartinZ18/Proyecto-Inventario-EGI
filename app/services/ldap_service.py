"""
Servicio de autenticación contra LDAP / Active Directory.

Encapsula la verificación de credenciales contra el servidor de identidad
institucional. La app NO guarda contraseñas: delega la validación a LDAP.
El método es "bind": se intenta iniciar sesión en el servidor LDAP con el
usuario y contraseña dados. Si el bind tiene éxito, las credenciales son
válidas; si falla, son incorrectas.
"""

from ldap3 import Server, Connection, ALL
from ldap3.core.exceptions import LDAPException
from app.core.config import settings
from typing import Optional

def autenticar(username: str, password: str) -> bool:
    """
    Valida usuario+contraseña contra LDAP haciendo un bind.

    Devuelve True si las credenciales son válidas, False si no.
    No lanza excepción ante credenciales incorrectas: devuelve False,
    para que el servicio de auth decida qué responder.
    """
    # Arma el DN del usuario a partir de la plantilla configurada.
    # Ej: "uid=jperez,ou=usuarios,dc=itu,dc=edu,dc=ar"
    user_dn = settings.ldap_user_dn_template.format(username=username)

    try:
        server = Server(
            host=settings.ldap_host,
            port=settings.ldap_port,
            use_ssl=settings.ldap_use_ssl,
            get_info=ALL,
        )
        # El bind ES la verificación: si las credenciales son malas, falla.
        conn = Connection(server, user=user_dn, password=password, auto_bind=True)
        conn.unbind()  # cerramos la conexión, ya validamos
        return True
    except LDAPException:
        # Credenciales inválidas o servidor inaccesible -> no autenticado.
        return False
    
def obtener_rol(username: str, password: str) -> Optional[str]:
    """
    Valida las credenciales Y devuelve el rol del usuario según el grupo de
    seguridad al que pertenece.

    En lugar de leer 'memberOf' del usuario (que no todos los LDAP exponen),
    busca en cada grupo si el usuario figura como 'member'. Funciona tanto en
    OpenLDAP como en Active Directory.

    Devuelve "Tecnicos", "Docentes" o "Alumnos", o None si las credenciales
    fallan o no pertenece a ningún grupo conocido.
    """
    from ldap3 import SUBTREE

    user_dn = settings.ldap_user_dn_template.format(username=username)
    try:
        server = Server(
            host=settings.ldap_host,
            port=settings.ldap_port,
            use_ssl=settings.ldap_use_ssl,
            get_info=ALL,
        )
        # Primero validamos las credenciales (bind con el usuario).
        conn = Connection(server, user=user_dn, password=password, auto_bind=True)
        conn.unbind()

        admin_conn = Connection(
            server,
            user=settings.ldap_bind_dn,
            password=settings.ldap_bind_password,
            auto_bind=True,
        )

        admin_conn.search(
            search_base=settings.ldap_base_dn,
            search_filter=f"(userPrincipalName={user_dn})",
            search_scope=SUBTREE,
            attributes=["memberOf"],
        )

        rol = None
        if admin_conn.entries:
            grupos_usuario = admin_conn.entries[0].entry_attributes_as_dict.get("memberOf", [])
            for grupo in ("Tecnicos", "Docentes", "Alumnos"):
                prefijo = f"cn={grupo},".lower()
                if any(dn.lower().startswith(prefijo) for dn in grupos_usuario):
                    rol = grupo
                    break

        admin_conn.unbind()
        return rol
    except LDAPException:
        return None