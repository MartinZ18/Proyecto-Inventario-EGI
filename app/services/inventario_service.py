"""
Servicio de INVENTARIO: el núcleo del sistema.

Orquesta las dos bases de datos para construir la vista unificada de cada equipo:
  1. Consulta SQL Server por el EQUIPO (con su ubicación, asignaciones y
     mantenimientos) usando el id_equipo.
  2. Con ese mismo id_equipo consulta MongoDB por los COMPONENTES de hardware.
  3. Combina ambas fuentes en una sola respuesta unificada.

SQL Server es la fuente maestra: si el equipo no existe ahí, no existe en el
sistema. Los componentes pueden faltar (equipo recién dado de alta sin hardware
cargado todavía) y en ese caso vienen en null.
"""

from typing import Optional, List
from sqlalchemy.orm import Session
from pymongo.database import Database
from app.repositories import equipo_repo, computadora_repo
from app.schemas.computadora import InventarioCompleto, ComputadoraOut
from app.schemas.inventario import EquipoOut, EquipoCreate, EquipoUpdate

def obtener_inventario_completo(
    sql_db: Session,
    mongo_db: Database,
    id_equipo: int,
) -> Optional[InventarioCompleto]:
    """Vista unificada de un equipo: datos de SQL Server + componentes de Mongo."""
    # Paso 1: buscar el equipo en SQL Server (con ubicación y relaciones).
    equipo = equipo_repo.get_by_id(sql_db, id_equipo)
    if equipo is None:
        return None

    # Paso 2: con el mismo id, buscar los componentes en MongoDB.
    componentes_doc = computadora_repo.get_by_id(mongo_db, id_equipo)

    # Paso 3: combinar ambas fuentes en una sola respuesta.
    return InventarioCompleto(
        equipo=EquipoOut.model_validate(equipo),
        componentes=ComputadoraOut(**componentes_doc) if componentes_doc else None,
    )


def listar_inventario(sql_db: Session, mongo_db: Database) -> List[InventarioCompleto]:
    """Lista todos los equipos con su información de SQL y sus componentes de Mongo."""
    resultado: List[InventarioCompleto] = []
    for equipo in equipo_repo.get_all(sql_db):
        componentes_doc = computadora_repo.get_by_id(mongo_db, equipo.id_equipo)
        resultado.append(
            InventarioCompleto(
                equipo=EquipoOut.model_validate(equipo),
                componentes=ComputadoraOut(**componentes_doc) if componentes_doc else None,
            )
        )
    return resultado


# ===== Operaciones de escritura (CRUD coordinado) =====

def crear_equipo(sql_db: Session, data: EquipoCreate):
    """Crea un equipo en SQL Server (su ubicación ya existe)."""
    return equipo_repo.create(sql_db, data)


def actualizar_equipo(sql_db: Session, id_equipo: int, data: EquipoUpdate):
    """Actualiza los datos de un equipo en SQL Server."""
    return equipo_repo.update(sql_db, id_equipo, data)


def eliminar_equipo(sql_db: Session, mongo_db: Database, id_equipo: int) -> bool:
    """
    Elimina un equipo COMPLETO de las dos bases:
      - De SQL Server: el equipo y, por cascade, sus asignaciones y mantenimientos.
      - De MongoDB: su documento de componentes.
    Así no quedan datos huérfanos en ninguna base.
    """
    # Primero verificamos que exista en SQL (fuente maestra).
    if not equipo_repo.existe(sql_db, id_equipo):
        return False

    # Borrar de SQL Server (cascade incluido).
    equipo_repo.delete(sql_db, id_equipo)

    # Borrar sus componentes de MongoDB (si los tiene).
    computadora_repo.delete(mongo_db, id_equipo)

    return True