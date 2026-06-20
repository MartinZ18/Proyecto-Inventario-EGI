"""
Configuración central de la aplicación.
Lee todas las variables de entorno una sola vez y las expone como un objeto 'settings' que el resto del código importa. Gracias a esto, el
mismo código corre en local, Docker o Kubernetes: lo único que cambia son los valores del entorno (.env / ConfigMap / Secret), nunca el código.
"""

from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict
from urllib.parse import quote_plus


class Settings(BaseSettings):
    # ----- App -----
    app_name: str = "Inventario ITU"
    app_env: str = "local"
    debug: bool = False

    # ----- Seguridad / JWT -----
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60

    # ----- SQL Server (ubicaciones) -----
    sqlserver_host: str
    sqlserver_port: int = 1433
    sqlserver_db: str
    sqlserver_user: str
    sqlserver_password: str
    sqlserver_driver: str = "ODBC Driver 18 for SQL Server"

    # ----- MongoDB (componentes) -----
    mongo_host: str
    mongo_port: int = 27017
    mongo_db: str
    mongo_user: str
    mongo_password: str

    # ----- LDAP / Active Directory -----
    ldap_host: str
    ldap_port: int = 389
    ldap_base_dn: str
    ldap_bind_dn: str
    ldap_bind_password: str
    ldap_user_dn_template: str
    ldap_use_ssl: bool = False

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # ---- Cadenas de conexión derivadas (se arman solas) ----

    @property
    def sqlserver_url(self) -> str:
        """
        Cadena de conexión SQLAlchemy para SQL Server vía pyodbc.
        TrustServerCertificate=yes evita problemas con el cert
        autofirmado de la imagen oficial de SQL Server en contenedor.
        """
        usuario = quote_plus(self.sqlserver_user)
        clave = quote_plus(self.sqlserver_password)
        driver = self.sqlserver_driver.replace(" ", "+")
        return (
            f"mssql+pyodbc://{usuario}:{clave}"
            f"@{self.sqlserver_host}:{self.sqlserver_port}/{self.sqlserver_db}"
            f"?driver={driver}&TrustServerCertificate=yes"
        )

    @property
    def mongo_url(self) -> str:
        """Cadena de conexión para MongoDB."""
        usuario = quote_plus(self.mongo_user)
        clave = quote_plus(self.mongo_password)
        return (
            f"mongodb://{usuario}:{clave}"
            f"@{self.mongo_host}:{self.mongo_port}/"
            f"?authSource=admin&authMechanism=SCRAM-SHA-256"
        )


@lru_cache
def get_settings() -> Settings:
    """
    Devuelve la configuración como singleton (cacheada).
    Se usa con Depends(get_settings) o importando `settings` directo.
    """
    return Settings()

# Instancia lista para importar: `from app.core.config import settings`
settings = get_settings()