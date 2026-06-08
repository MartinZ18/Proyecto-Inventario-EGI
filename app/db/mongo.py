"""
Conexión a MongoDB (base de datos de COMPONENTES).
A diferencia de SQL Server, Mongo no usa ORM ni tablas: se trabaja con colecciones de documentos. Acá creamos un único cliente reutilizable y
exponemos la base de datos para que los repositorios accedan a sus colecciones. La URL se toma de settings.mongo_url, armada desde variables 
de entorno.
"""

from pymongo import MongoClient
from app.core.config import settings

# Cliente único de Mongo. MongoClient ya maneja un pool interno de conexiones,
# por eso se crea una sola vez a nivel de módulo y se reutiliza.
client = MongoClient(settings.mongo_url)

# Referencia a la base de datos de componentes.
mongo_db = client[settings.mongo_db]

def get_mongo_db():
    """
    Dependency de FastAPI: entrega la base de datos de Mongo. Mongo no necesita abrir/cerrar sesión por request como SQL, así que
    simplemente devuelve la referencia ya creada.
    Uso en un endpoint:  db = Depends(get_mongo_db)
    """
    return mongo_db