"""
Servicio de autenticación: orquesta el login completo.

  1. Valida credenciales contra LDAP y obtiene el rol del usuario.
  2. Si son válidas, emite un token JWT que incluye ese rol.
"""

from typing import Optional

from app.services import ldap_service
from app.core.security import crear_token


def login(username: str, password: str) -> Optional[str]:
    """
    Login completo: valida contra LDAP, obtiene el rol y emite un token JWT
    que incluye ese rol. Devuelve el token, o None si las credenciales fallan.
    """
    rol = ldap_service.obtener_rol(username, password)
    if rol is None:
        return None
    return crear_token(username, rol)