"""
Repositorio de COMPONENTES (MongoDB).

Aísla todo el acceso a MongoDB, igual que equipo_repo.py aísla SQL Server. A diferencia de aquel, acá NO hay ORM: se trabaja directo con la 
colección y documentos JSON. Implementa las operaciones que pide la consigna sobre Mongo: crear colección, insertar, buscar filtrado, actualizar y eliminar.
El id_equipo es el puente con SQL Server: con él se localizan los componentes del equipo cuyos datos de ubicación viven en la base relacional.
"""

from typing import Optional, List
from pymongo.database import Database
from app.schemas.computadora import ComputadoraCreate, ComputadoraUpdate

# Nombre de la colección donde viven los documentos de componentes.
COLLECTION = "componentes"

def _coll(db: Database):
    """Atajo interno: devuelve la colección de computadoras."""
    return db[COLLECTION]

def get_by_id(db: Database, id_equipo: int) -> Optional[dict]:
    """Trae los componentes de un equipo por su id_equipo (puente con SQL)."""
    return _coll(db).find_one({"id_equipo": id_equipo}, {"_id": 0})

def get_all(db: Database) -> List[dict]:
    """Lista todos los documentos de componentes."""
    return list(_coll(db).find({}, {"_id": 0}))

def search_by_tipo(db: Database, tipo: str) -> List[dict]:
    """Búsqueda filtrada: todas las máquinas de un tipo (desktop/laptop)."""
    return list(_coll(db).find({"tipo": tipo}, {"_id": 0}))

def create(db: Database, data: ComputadoraCreate) -> dict:
    """Inserta un nuevo documento de componentes."""
    doc = data.model_dump()
    _coll(db).insert_one(doc)
    return doc

def update(db: Database, id_equipo: int, data: ComputadoraUpdate) -> Optional[dict]:
    cambios = data.model_dump(exclude_unset=True)
    if not cambios:
        return get_by_id(db, id_equipo)
    _coll(db).update_one({"id_equipo": id_equipo}, {"$set": cambios})
    return get_by_id(db, id_equipo)

def delete(db: Database, id_equipo: int) -> bool:
    resultado = _coll(db).delete_one({"id_equipo": id_equipo})
    return resultado.deleted_count > 0