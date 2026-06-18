"""
Router de INVENTARIO: endpoints para consultar y gestionar el inventario.

- Lectura (listar, consultar, ubicaciones): cualquier usuario autenticado.
- Escritura (crear, editar, borrar): solo técnicos (RBAC con requiere_tecnico).
"""

from typing import List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pymongo.database import Database

from app.dependencies import get_sql, get_mongo, get_current_user, requiere_tecnico
from app.repositories import computadora_repo
from app.services import inventario_service
from app.schemas.inventario import EquipoCreate, EquipoUpdate, EquipoOut, UbicacionOut, PersonaOut
from app.schemas.computadora import (
    ComputadoraCreate, ComputadoraUpdate, ComputadoraOut, InventarioCompleto,
)

router = APIRouter(
    prefix="/inventario",
    tags=["Inventario"],
    dependencies=[Depends(get_current_user)],  # todo el router exige autenticación
)


# ===== UBICACIONES (desplegable del front) =====

@router.get("/ubicaciones", response_model=List[UbicacionOut])
def listar_ubicaciones(sql: Session = Depends(get_sql)):
    """Lista los laboratorios/ubicaciones disponibles para crear un equipo."""
    return inventario_service.equipo_repo.get_ubicaciones(sql)


# ===== PERSONAS (para asignar a un equipo) =====

@router.get("/personas", response_model=List[PersonaOut])
def listar_personas(sql: Session = Depends(get_sql)):
    """Lista las personas disponibles para asignar a un equipo."""
    return inventario_service.equipo_repo.get_personas(sql)


# ===== VISTA UNIFICADA (SQL + Mongo combinados) =====

@router.get("/", response_model=List[InventarioCompleto])
def listar_todo(sql: Session = Depends(get_sql), mongo: Database = Depends(get_mongo)):
    """Lista todos los equipos con su info de SQL y sus componentes de Mongo."""
    return inventario_service.listar_inventario(sql, mongo)


@router.get("/{id_equipo}", response_model=InventarioCompleto)
def obtener(id_equipo: int,
            sql: Session = Depends(get_sql),
            mongo: Database = Depends(get_mongo)):
    """Vista completa de un equipo: dónde está, quién lo mantiene y qué tiene adentro."""
    resultado = inventario_service.obtener_inventario_completo(sql, mongo, id_equipo)
    if resultado is None:
        raise HTTPException(status_code=404, detail="Equipo no encontrado")
    return resultado


# ===== EQUIPOS (escritura - solo técnicos) =====

@router.post("/equipos", response_model=EquipoOut, status_code=201)
def crear_equipo(data: EquipoCreate,
                 sql: Session = Depends(get_sql),
                 _: dict = Depends(requiere_tecnico)):
    """Crea un equipo nuevo en una ubicación existente (solo técnicos)."""
    return inventario_service.crear_equipo(sql, data)


@router.put("/equipos/{id_equipo}", response_model=EquipoOut)
def actualizar_equipo(id_equipo: int, data: EquipoUpdate,
                      sql: Session = Depends(get_sql),
                      _: dict = Depends(requiere_tecnico)):
    """Actualiza un equipo (solo técnicos)."""
    actualizado = inventario_service.actualizar_equipo(sql, id_equipo, data)
    if actualizado is None:
        raise HTTPException(status_code=404, detail="Equipo no encontrado")
    return actualizado


@router.delete("/equipos/{id_equipo}", status_code=204)
def eliminar_equipo(id_equipo: int,
                    sql: Session = Depends(get_sql),
                    mongo: Database = Depends(get_mongo),
                    _: dict = Depends(requiere_tecnico)):
    """Elimina un equipo de ambas bases (solo técnicos)."""
    if not inventario_service.eliminar_equipo(sql, mongo, id_equipo):
        raise HTTPException(status_code=404, detail="Equipo no encontrado")


# ===== COMPONENTES (escritura - solo técnicos) =====

@router.post("/componentes", response_model=ComputadoraOut, status_code=201)
def crear_componentes(data: ComputadoraCreate,
                      mongo: Database = Depends(get_mongo),
                      _: dict = Depends(requiere_tecnico)):
    """Carga los componentes de un equipo (solo técnicos)."""
    return computadora_repo.create(mongo, data)


@router.put("/componentes/{id_equipo}", response_model=ComputadoraOut)
def actualizar_componentes(id_equipo: int, data: ComputadoraUpdate,
                           mongo: Database = Depends(get_mongo),
                           _: dict = Depends(requiere_tecnico)):
    """Actualiza los componentes de un equipo (solo técnicos)."""
    actualizado = computadora_repo.update(mongo, id_equipo, data)
    if actualizado is None:
        raise HTTPException(status_code=404, detail="Componentes no encontrados")
    return actualizado


@router.delete("/componentes/{id_equipo}", status_code=204)
def eliminar_componentes(id_equipo: int,
                         mongo: Database = Depends(get_mongo),
                         _: dict = Depends(requiere_tecnico)):
    """Elimina los componentes de un equipo (solo técnicos)."""
    if not computadora_repo.delete(mongo, id_equipo):
        raise HTTPException(status_code=404, detail="Componentes no encontrados")