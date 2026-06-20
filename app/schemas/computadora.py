"""
Schemas Pydantic de COMPONENTES (MongoDB).

Reflejan el diseño documental de inventario-db: objetos anidados (CPU, SO, GPU),
arrays (RAM, almacenamiento) y estructuras condicionales según el tipo de equipo
(laptop lleva batería y pantalla; desktop lleva periféricos).

Validación flexible: solo id_equipo y tipo son obligatorios (el puente con SQL
y el discriminador). El resto es opcional, porque MongoDB es schemaless y el
back no debe imponer rigidez donde la base no la tiene.

id_equipo es el puente con SQL Server.
"""

from typing import Optional, List, Literal
from pydantic import BaseModel, Field
from app.schemas.inventario import EquipoOut


# ----- Sub-documentos -----

class SistemaOperativo(BaseModel):
    nombre: Optional[str] = None
    version: Optional[str] = None
    arquitectura: Optional[str] = None


class CPU(BaseModel):
    fabricante: Optional[str] = None
    modelo: Optional[str] = None
    nucleos: Optional[int] = None
    frecuencia_ghz: Optional[float] = None


class GPU(BaseModel):
    fabricante: Optional[str] = None
    modelo: Optional[str] = None
    memoria_gb: Optional[int] = None


class ModuloRAM(BaseModel):
    fabricante: Optional[str] = None
    capacidad_gb: Optional[int] = None
    tipo: Optional[str] = None
    frecuencia_mhz: Optional[int] = None


class Disco(BaseModel):
    tipo: Optional[str] = None              # SSD | HDD
    capacidad_gb: Optional[int] = None
    fabricante: Optional[str] = None
    modelo: Optional[str] = None


# Periféricos (solo desktop)
class Monitor(BaseModel):
    fabricante: Optional[str] = None
    modelo: Optional[str] = None
    pulgadas: Optional[float] = None


class Periferico(BaseModel):
    fabricante: Optional[str] = None
    conexion: Optional[str] = None


class Perifericos(BaseModel):
    monitor: Optional[Monitor] = None
    teclado: Optional[Periferico] = None
    mouse: Optional[Periferico] = None


# Solo laptop
class Bateria(BaseModel):
    estado: Optional[str] = None
    ciclos: Optional[int] = None


class PantallaIntegrada(BaseModel):
    pulgadas: Optional[float] = None
    resolucion: Optional[str] = None


# ----- Documento principal -----

class ComputadoraBase(BaseModel):
    """Estructura completa de los componentes de un equipo."""
    tipo: Literal["desktop", "laptop"]
    codigo_inventario: Optional[str] = None
    fabricante: Optional[str] = None
    modelo: Optional[str] = None
    observacion: Optional[str] = None
    sistema_operativo: Optional[SistemaOperativo] = None
    cpu: Optional[CPU] = None
    gpu: Optional[GPU] = None
    ram: List[ModuloRAM] = []
    almacenamiento: List[Disco] = []
    # Condicionales según tipo:
    perifericos: Optional[Perifericos] = None        # desktop
    bateria: Optional[Bateria] = None                # laptop
    pantalla_integrada: Optional[PantallaIntegrada] = None  # laptop


class ComputadoraCreate(ComputadoraBase):
    """Datos para crear el documento de componentes. Incluye el id_equipo (puente)."""
    id_equipo: int = Field(..., description="ID que conecta con SQL Server (Equipo)")


class ComputadoraUpdate(BaseModel):
    """Actualización parcial: todos los campos opcionales."""
    tipo: Optional[Literal["desktop", "laptop"]] = None
    codigo_inventario: Optional[str] = None
    fabricante: Optional[str] = None
    modelo: Optional[str] = None
    observacion: Optional[str] = None
    sistema_operativo: Optional[SistemaOperativo] = None
    cpu: Optional[CPU] = None
    gpu: Optional[GPU] = None
    ram: Optional[List[ModuloRAM]] = None
    almacenamiento: Optional[List[Disco]] = None
    perifericos: Optional[Perifericos] = None
    bateria: Optional[Bateria] = None
    pantalla_integrada: Optional[PantallaIntegrada] = None


class ComputadoraOut(ComputadoraBase):
    """Lo que la API devuelve, con el id_equipo incluido."""
    id_equipo: int


# ----- Vista unificada (SQL + Mongo) -----

class InventarioCompleto(BaseModel):
    """
    Vista unificada: datos del equipo + ubicación + asignaciones +
    mantenimientos (SQL Server) combinados con los componentes (MongoDB).
    """
    equipo: EquipoOut
    componentes: Optional[ComputadoraOut] = None