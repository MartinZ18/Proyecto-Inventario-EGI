"""
Seguridad: creación y verificación de tokens JWT.

Una vez que LDAP validó al usuario, la app le entrega un token JWT firmado
que incluye su rol. Ese token viaja en cada request y prueba identidad y
permisos sin volver a consultar LDAP.
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import jwt, JWTError

from app.core.config import settings


def crear_token(username: str, rol: Optional[str] = None) -> str:
    """Genera un JWT para un usuario ya autenticado, incluyendo su rol."""
    expira = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {
        "sub": username,
        "rol": rol,          # Tecnicos / Docentes / Alumnos
        "exp": expira,
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def verificar_token(token: str) -> Optional[dict]:
    """
    Verifica firma y expiración del token.
    Devuelve un dict con username y rol, o None si es inválido.
    """
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
        )
        username = payload.get("sub")
        if username is None:
            return None
        return {"username": username, "rol": payload.get("rol")}
    except JWTError:
        return None