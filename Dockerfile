# ============================================================
# Dockerfile del back-end de inventario (FastAPI + pyodbc).
# Empaqueta la app para correr contenerizada (Docker / Kubernetes).
# ============================================================

FROM python:3.12-slim

# Evita que Python genere archivos .pyc y fuerza salida sin buffer (mejores logs).
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# ----- Instalar el ODBC Driver 18 de Microsoft (necesario para pyodbc/SQL Server) -----
# Se instalan utilidades, se agrega el repositorio oficial de Microsoft y el driver.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl gnupg2 apt-transport-https ca-certificates unixodbc-dev gcc g++ \
    && curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
        > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Directorio de trabajo dentro del contenedor.
WORKDIR /app

# Instalar dependencias primero (aprovecha la caché de Docker si no cambian).
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar el código de la aplicación.
COPY ./app ./app

# Puerto que expone la app.
EXPOSE 8000

# Comando de arranque. 0.0.0.0 permite recibir tráfico desde fuera del contenedor.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]