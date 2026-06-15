# SQL Server 2022 — VM de Base de Datos

## Rol en la arquitectura

Esta VM aloja la base relacional **SQL Server 2022** que usa el backend
para `Ubicacion`, `Equipo`, `Persona`, `Asignacion` y `Mantenimiento`
(rama `bases-de-datos`, script `Script SQL Server 2022.sql`). El backend
(en Minikube) accede a esta VM vía `sqlserver-service` → `Endpoints` →
`${SQLSERVER_IP}:1433` (default `192.168.56.20:1433`, ver
`kubernetes/external/sqlserver-endpoints.yaml` y `docs/topologia-red.md`).

> **Nota sobre el nombre de la carpeta (`sql-server-iis/`)**: esta VM se
> evaluó originalmente para correr también IIS + SSRS (reportes y un
> sitio de administración). Se decidió no instalarlos — ver la sección 5
> para el detalle y el motivo. El nombre de la carpeta se deja igual para
> no romper las referencias del resto del repo.

| Dato | Valor |
|---|---|
| IP de la VM | `192.168.56.20` (default `SQLSERVER_IP`, ver `infra/red.example.env`) |
| Motor | SQL Server 2022 (Developer/Standard) |
| Puerto | 1433/TCP |
| Base de datos | `inventario_ubicaciones` (ver sección 2 — mismatch con el script) |
| Login de la app | `inventario_app` (SQL Authentication) |

---

## 1. Habilitar TCP/IP y modo de autenticación mixto

Por defecto, SQL Server solo escucha en *Shared Memory* y no acepta
logins SQL (solo Windows). Hay que habilitar ambos:

1. **SQL Server Configuration Manager** → *SQL Server Network
   Configuration* → *Protocols for MSSQLSERVER* → habilitar **TCP/IP**.
2. En las propiedades de TCP/IP → pestaña *IP Addresses* → en `IPAll`,
   limpiar *TCP Dynamic Ports* y fijar **TCP Port = 1433**.
3. Reiniciar el servicio **SQL Server (MSSQLSERVER)**.
4. Habilitar y arrancar el servicio **SQL Server Browser** (útil si en
   el futuro se usa una instancia con nombre).
5. En **SSMS** → click derecho en el servidor → *Properties* →
   *Security* → **SQL Server and Windows Authentication mode** (modo
   mixto). Reiniciar el servicio nuevamente.

Verificación desde otra máquina de la red:
```
sqlcmd -S 192.168.56.20,1433 -U sa -P "<password-sa>" -Q "SELECT @@VERSION"
```

---

## 2. Base de datos: alinear `ubicacion_db` ↔ `inventario_ubicaciones`

⚠️ **Mismatch conocido** (documentado también en el `CLAUDE.md` raíz del
proyecto): el script `Script SQL Server 2022.sql` crea la base con el
nombre **`ubicacion_db`**, pero `app/core/config.py` / `.env.example` y
el ConfigMap (`kubernetes/configmaps/backend-configmap.yaml`) esperan
**`SQLSERVER_DB=inventario_ubicaciones`**.

Para esta VM (despliegue nuevo, sin datos previos), la forma más simple
es **editar el script antes de ejecutarlo**: reemplazar todas las
ocurrencias de `ubicacion_db` por `inventario_ubicaciones` (3
apariciones: `DROP DATABASE`, `CREATE DATABASE`, `USE`).

Alternativa (si el script ya se ejecutó como `ubicacion_db` y tiene
datos que no se quieren perder): renombrar la base existente.
```sql
USE master;
ALTER DATABASE ubicacion_db SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE ubicacion_db MODIFY NAME = inventario_ubicaciones;
ALTER DATABASE inventario_ubicaciones SET MULTI_USER;
```

Ejecutar el script (ya editado) con SSMS, Azure Data Studio o:
```
sqlcmd -S 192.168.56.20,1433 -U sa -P "<password-sa>" -i "Script SQL Server 2022.sql"
```

---

## 3. Crear el login de la aplicación (`inventario_app`)

El backend se conecta con un login SQL dedicado (no `sa`), con permisos
acotados a `inventario_ubicaciones`:

```sql
USE master;
CREATE LOGIN inventario_app WITH PASSWORD = '<password-fuerte>', CHECK_POLICY = ON;
GO

USE inventario_ubicaciones;
CREATE USER inventario_app FOR LOGIN inventario_app;
ALTER ROLE db_datareader ADD MEMBER inventario_app;
ALTER ROLE db_datawriter ADD MEMBER inventario_app;
-- db_ddladmin: necesario porque app/main.py llama a
-- Base.metadata.create_all(bind=engine) al arrancar.
ALTER ROLE db_ddladmin ADD MEMBER inventario_app;
GO
```

Estos valores van al Secret de Kubernetes:
```
SQLSERVER_USER=inventario_app
SQLSERVER_PASSWORD=<password-fuerte>
```
(ver `kubernetes/secrets/backend-secret.example.yaml` y los GitHub
Secrets `SQLSERVER_USER` / `SQLSERVER_PASSWORD` usados por
`.github/workflows/deploy.yml`).

---

## 4. Firewall

Ejecutar `scripts/configurar-firewall-sql-iis.ps1` (como Administrador).
El script lee `IP_RED_PROF` y `MINIKUBE_IP` de variables de entorno
(default `192.168.56.0/24` para `IP_RED_PROF` si no están definidas;
`MINIKUBE_IP` es opcional). Para usar los valores de
`infra/red.local.env`, cargarlos antes de ejecutar (ver el comentario
de cabecera del script). Abre:

- `1433/TCP` (motor SQL Server) y `1434/UDP` (SQL Browser), restringido
  a la red del laboratorio.

---

## 5. IIS + SSRS — evaluado y descartado

El plan original de esta VM incluía instalar IIS (sitio de
administración en `:8081`) y SQL Server Reporting Services (SSRS, para
publicar 1-2 reportes de la base en `/Reports`: equipos por ubicación,
historial de mantenimientos por equipo).

Se decidió **no instalarlos** (2026-06-14):

- La aplicación (frontend + backend) no se sirve desde esta VM ni desde
  IIS: se despliega como Deployments/Services en Minikube (Fase 5 del
  runbook). IIS aquí no tenía ningún rol en ese flujo, solo generaba
  confusión.
- Los reportes SSRS eran un "nice to have" para la defensa oral, no un
  requisito — y agregan un instalador aparte (SSRS no viene con SQL
  Server 2022) más 3 puertos abiertos (`80`, `443`, `8081`) sin ningún
  consumidor real en el resto del runbook.
- Menos servicios/puertos expuestos en la VM de base de datos = menos
  superficie de ataque, en línea con el enfoque zero-trust del resto
  del repo (NetworkPolicies, iptables).

Si en algún momento hace falta mostrar reportes de la base, la
alternativa más simple es un endpoint propio del backend (ya
autenticado vía JWT/LDAP) en lugar de levantar IIS+SSRS en esta VM.

---

## 6. Checklist de verificación

- [x] TCP/IP habilitado, puerto 1433 fijo, modo de autenticación mixto.
- [x] Base `inventario_ubicaciones` creada (alineada con el ConfigMap).
- [x] Login `inventario_app` creado con roles `db_datareader`,
      `db_datawriter`, `db_ddladmin` sobre `inventario_ubicaciones`.
- [x] Firewall: 1433/1434 abiertos a `192.168.56.0/24` (`IP_RED_PROF`).
- [ ] Backend en Minikube puede conectar:
      `kubectl exec -n inventario deploy/backend -- python -c "from app.db.sql_server import engine; print(engine.connect())"`
