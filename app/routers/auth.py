"""
Router de AUTENTICACIÓN: expone el endpoint de login.
Recibe usuario y contraseña, los pasa al auth_service (que valida contra LDAP y emite el token) y devuelve el JWT al cliente. 
Es la única puerta de entrada para autenticarse; el resto de los endpoints exigirán el token que sale de acá.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from app.services import auth_service
from app.schemas.auth import Token

router = APIRouter(prefix="/auth", tags=["Autenticación"])


@router.post("/login", response_model=Token)
def login(form: OAuth2PasswordRequestForm = Depends()):
    """
    Inicia sesión.

    Recibe usuario y contraseña como formulario (estándar OAuth2) y devuelve
    un token JWT si las credenciales son válidas contra LDAP. Si no, 401.
    """
    token = auth_service.login(form.username, form.password)
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return Token(access_token=token)