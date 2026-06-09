"""
Punto de entrada de la aplicación FastAPI.

Acá se crea la app, se registran los routers y se exponen un par de endpoints
básicos de control. Es el archivo que ejecuta uvicorn para levantar el back.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.routers import auth, inventario

from app.db.sql_server import Base, engine
from app.models import inventario as modelos_inventario  # registra los modelos para crear las tablas

# Creación de la app con metadatos que aparecen en la documentación /docs.
app = FastAPI(
    title=settings.app_name,
    description="API de inventario de computadoras de laboratorios (ITU)",
    version="1.0.0",
)

# Crea las tablas en SQL Server si no existen (al arrancar la app).
Base.metadata.create_all(bind=engine)

# CORS: permite que el frontend (otro origen) consuma esta API.
# En producción conviene restringir allow_origins al dominio real del frontend.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Registro de routers: cada uno aporta su grupo de endpoints.
app.include_router(auth.router)
app.include_router(inventario.router)


@app.get("/", tags=["Estado"])
def raiz():
    """Endpoint raíz: confirma que la API está viva."""
    return {"app": settings.app_name, "estado": "ok"}


@app.get("/health", tags=["Estado"])
def health():
    """
    Health check: lo usan Docker y Kubernetes para saber si el contenedor
    está sano y debe recibir tráfico.
    """
    return {"status": "healthy"}