"""
Repositorio de EQUIPOS (SQL Server).
Concentra las consultas al modelo relacional. La clave acá es que, gracias a las relationships de SQLAlchemy, al traer un Equipo podemos
navegar a su ubicación, asignaciones y mantenimientos sin escribir JOINs a mano: SQLAlchemy los resuelve por detrás. Usamos carga 
anticipada (joinedload) para traer todo en una sola consulta eficiente.
"""

from typing import Optional, List
from sqlalchemy.orm import Session, joinedload
from app.models.inventario import Equipo, Ubicacion, Persona
from app.schemas.inventario import EquipoCreate, EquipoUpdate


def _con_relaciones(query):
    """Agrega la carga anticipada de las entidades relacionadas."""
    return query.options(
        joinedload(Equipo.ubicacion),
        joinedload(Equipo.asignaciones),
        joinedload(Equipo.mantenimientos),
    )


def get_by_id(db: Session, id_equipo: int) -> Optional[Equipo]:
    """Trae un equipo con su ubicación, asignaciones y mantenimientos."""
    return _con_relaciones(
        db.query(Equipo).filter(Equipo.id_equipo == id_equipo)
    ).first()


def get_all(db: Session, skip: int = 0, limit: int = 100) -> List[Equipo]:
    """Lista todos los equipos con sus relaciones (ordenado por id)."""
    return (
        _con_relaciones(db.query(Equipo))
        .order_by(Equipo.id_equipo)
        .offset(skip)
        .limit(limit)
        .all()
    )


# ===== Ubicaciones (para el desplegable del front) =====

def get_ubicaciones(db: Session) -> List[Ubicacion]:
    """Lista las ubicaciones existentes (los laboratorios) para elegir al crear."""
    return db.query(Ubicacion).order_by(Ubicacion.nombre).all()


# ===== Personas (para asignar a un equipo) =====

def get_personas(db: Session) -> List[Persona]:
    """Lista las personas disponibles para asignar a un equipo."""
    return db.query(Persona).order_by(Persona.apellido).all()


# ===== CRUD de equipos =====

def create(db: Session, data: EquipoCreate) -> Equipo:
    """Crea un equipo nuevo asociado a una ubicación existente."""
    nuevo = Equipo(**data.model_dump())
    db.add(nuevo)
    db.commit()
    db.refresh(nuevo)
    return nuevo


def update(db: Session, id_equipo: int, data: EquipoUpdate) -> Optional[Equipo]:
    """Actualiza solo los campos enviados de un equipo."""
    equipo = get_by_id(db, id_equipo)
    if equipo is None:
        return None
    for campo, valor in data.model_dump(exclude_unset=True).items():
        setattr(equipo, campo, valor)
    db.commit()
    db.refresh(equipo)
    return equipo


def delete(db: Session, id_equipo: int) -> bool:
    """
    Elimina un equipo. Por el cascade definido en el modelo, también borra
    sus asignaciones y mantenimientos en SQL. (El borrado del documento de
    componentes en Mongo se maneja en el servicio, porque es otra base.)
    """
    equipo = get_by_id(db, id_equipo)
    if equipo is None:
        return False
    db.delete(equipo)
    db.commit()
    return True


def existe(db: Session, id_equipo: int) -> bool:
    """Indica si un equipo existe (útil antes de cargar sus componentes)."""
    return db.query(Equipo.id_equipo).filter(Equipo.id_equipo == id_equipo).first() is not None