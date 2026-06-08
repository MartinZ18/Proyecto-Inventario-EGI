"""
Conexión a SQL Server (base de datos de UBICACIONES).

Usa SQLAlchemy como capa sobre el driver pyodbc. Acá viven tres cosas:
- engine: el objeto que mantiene el pool de conexiones a SQL Server.
- SessionLocal: fábrica de sesiones (una sesión = una "conversación" con la DB).
- Base: clase de la que heredan los modelos/tablas (en models/ubicacion.py).

La cadena de conexión NO se escribe acá: se toma de settings.sqlserver_url, que se arma sola a partir de las variables de entorno. 
Así el mismo código sirve en local, Docker o Kubernetes.
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from app.core.config import settings

# Motor de conexión. pool_pre_ping verifica que la conexión siga viva
# antes de usarla (evita errores si SQL Server cerró una conexión inactiva).
engine = create_engine(
    settings.sqlserver_url,
    pool_pre_ping=True,
    echo=settings.debug,  # en modo debug imprime el SQL que ejecuta (útil para defender)
)

# Fábrica de sesiones. Cada request abrirá una y la cerrará al terminar.
SessionLocal = sessionmaker(
    bind=engine,
    autocommit=False,
    autoflush=False,
)

# Clase base para los modelos declarativos (tablas).
Base = declarative_base()

def get_sql_session():
    """
    Dependency de FastAPI: entrega una sesión de SQL Server y se asegura de cerrarla al finalizar el request, incluso si hubo error.
    Uso en un endpoint:  db: Session = Depends(get_sql_session)
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()