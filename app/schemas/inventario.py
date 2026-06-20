"""
Schemas Pydantic del inventario (forma de los datos en la API).

Definen cómo se exponen las entidades del modelo relacional hacia afuera.
Se separan de los modelos SQLAlchemy: el modelo es cómo se guarda, el
schema es cómo se valida y se muestra.
"""

from datetime import date
from typing import Optional, List
from pydantic import BaseModel


class UbicacionOut(BaseModel):
    id_ubicacion: int
    nombre: str
    tipo: str
    edificio: Optional[str] = None
    piso: Optional[int] = None
    model_config = {"from_attributes": True}


class PersonaOut(BaseModel):
    id_persona: int
    nombre: str
    apellido: str
    dni: Optional[str] = None
    email: Optional[str] = None
    rol: str
    model_config = {"from_attributes": True}


class AsignacionOut(BaseModel):
    id_asignacion: int
    persona: PersonaOut
    tipo_asignacion: Optional[str] = None
    fecha_inicio: Optional[date] = None
    fecha_fin: Optional[date] = None
    model_config = {"from_attributes": True}


class MantenimientoOut(BaseModel):
    id_mantenimiento: int
    fecha: Optional[date] = None
    tipo: Optional[str] = None
    descripcion: Optional[str] = None
    tecnico: PersonaOut
    model_config = {"from_attributes": True}


class EquipoOut(BaseModel):
    """Datos del equipo más su ubicación (vienen de SQL Server)."""
    id_equipo: int
    mesa: Optional[str] = None
    estado: Optional[str] = None
    fecha_alta: Optional[date] = None
    ubicacion: UbicacionOut
    asignaciones: List[AsignacionOut] = []
    mantenimientos: List[MantenimientoOut] = []
    model_config = {"from_attributes": True}


# ===== Schemas de entrada (crear / editar equipo) =====

class EquipoCreate(BaseModel):
    """
    Datos para CREAR un equipo. El técnico elige una ubicación existente
    (id_ubicacion) y carga la mesa. La asignación y el mantenimiento NO se
    crean acá: surgen después (la máquina queda libre en el banco).
    """
    id_equipo: int
    id_ubicacion: int
    mesa: Optional[str] = None
    estado: Optional[str] = "operativo"
    fecha_alta: Optional[date] = None


class EquipoUpdate(BaseModel):
    """Datos para EDITAR un equipo. Todos opcionales: se actualiza lo enviado."""
    id_ubicacion: Optional[int] = None
    mesa: Optional[str] = None
    estado: Optional[str] = None
    fecha_alta: Optional[date] = None


class UbicacionCreate(BaseModel):
    """Datos para crear una ubicación (los 4 laboratorios se cargan una vez)."""
    id_ubicacion: int
    nombre: str
    tipo: str
    edificio: Optional[str] = None
    piso: Optional[int] = None