"""
Servicio de autenticación contra LDAP / Active Directory.

Encapsula la verificación de credenciales contra el servidor de identidad
institucional. La app NO guarda contraseñas: delega la validación a LDAP.
El método es "bind": se intenta iniciar sesión en el servidor LDAP con el
usuario y contraseña dados. Si el bind tiene éxito, las credenciales son
válidas; si falla, son incorrectas.
"""

from ldap3 import Server, Connection, ALL, SUBTREE
from ldap3.core.exceptions import LDAPException
from app.core.config import settings
from typing import Optional


def obtener_rol(username: str, password: str) -> Optional[str]:
    """
    Valida las credenciales contra LDAP y devuelve el rol del usuario.

    Primero hace un bind con las credenciales del usuario para verificarlas.
    Si el bind tiene éxito, abre una segunda conexión con la cuenta de servicio
    (bind_dn) y lee el atributo memberOf del usuario en Active Directory para
    determinar a qué grupo pertenece.

    Devuelve "Tecnicos", "Docentes" o "Alumnos", o None si las credenciales
    fallan o el usuario no pertenece a ningún grupo conocido.
    """

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