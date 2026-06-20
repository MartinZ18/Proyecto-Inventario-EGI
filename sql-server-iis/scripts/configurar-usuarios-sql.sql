-- =====================================================================
--  configurar-usuarios-sql.sql
--
--  Crea los 2 logins definitivos del proyecto en inventario_ubicaciones:
--
--    inventario_admin   todos los permisos (db_owner)
--                       usado por el backend (FastAPI) para CRUD + DDL
--    inventario_ro      solo lectura (db_datareader)
--                       para consultas de auditoria o demos
--
--  ORDEN DE EJECUCION SEGURO (no rompe el backend):
--
--    PASO 1 — Ejecutar este script completo hasta "FIN DEL PASO 1".
--             Crea inventario_admin e inventario_ro.
--             El login anterior "inventarioapp" NO se toca en este paso,
--             por lo que el backend sigue funcionando sin cambios.
--
--    PASO 2 — Actualizar el GitHub Secret SQLSERVER_USER a "inventario_admin"
--             y SQLSERVER_PASSWORD a "InvAdmin!2025" en el repo de GitHub.
--             Luego volver a ejecutar el workflow de GitHub Actions para que
--             recree el Secret de Kubernetes con las nuevas credenciales.
--             Verificar que el backend sigue respondiendo correctamente.
--
--    PASO 3 — Una vez confirmado que el backend funciona con inventario_admin,
--             ejecutar la seccion "PASO 3" al final de este archivo para
--             eliminar el login obsoleto "inventarioapp".
--
--  Idempotente: cada paso se puede volver a correr sin error.
--
--  Las contraseñas se pasan como variables sqlcmd (nunca hardcodeadas):
--    sqlcmd -S localhost -E ^
--           -v ADMIN_PASSWORD="TuPasswordSegura!1" RO_PASSWORD="OtraPassword!2" ^
--           -i configurar-usuarios-sql.sql
-- =====================================================================

-- =====================================================================
--  PASO 1 — Crear los 2 logins nuevos (seguro, no toca inventarioapp)
-- =====================================================================

USE master;
GO

-- ---------- inventario_admin (db_owner — acceso total) ----------

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'inventario_admin')
BEGIN
    CREATE LOGIN inventario_admin
        WITH PASSWORD    = '$(ADMIN_PASSWORD)',
             CHECK_POLICY = ON;
    PRINT 'Login inventario_admin creado.';
END
ELSE
    PRINT 'Login inventario_admin ya existe (sin cambios).';
GO

USE inventario_ubicaciones;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'inventario_admin')
BEGIN
    CREATE USER inventario_admin FOR LOGIN inventario_admin;
    PRINT 'Usuario inventario_admin creado en la base.';
END
GO

-- db_owner incluye datareader + datawriter + ddladmin.
-- SQLAlchemy (Base.metadata.create_all) necesita ddladmin al arrancar
-- el pod del backend.
IF (IS_ROLEMEMBER('db_owner', 'inventario_admin') = 0)
BEGIN
    ALTER ROLE db_owner ADD MEMBER inventario_admin;
    PRINT 'Rol db_owner otorgado a inventario_admin.';
END
GO

-- ---------- inventario_ro (db_datareader — solo SELECT) ----------

USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'inventario_ro')
BEGIN
    CREATE LOGIN inventario_ro
        WITH PASSWORD    = '$(RO_PASSWORD)',
             CHECK_POLICY = ON;
    PRINT 'Login inventario_ro creado.';
END
ELSE
    PRINT 'Login inventario_ro ya existe (sin cambios).';
GO

USE inventario_ubicaciones;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'inventario_ro')
BEGIN
    CREATE USER inventario_ro FOR LOGIN inventario_ro;
    PRINT 'Usuario inventario_ro creado en la base.';
END
GO

IF (IS_ROLEMEMBER('db_datareader', 'inventario_ro') = 0)
BEGIN
    ALTER ROLE db_datareader ADD MEMBER inventario_ro;
    PRINT 'Rol db_datareader otorgado a inventario_ro.';
END
GO

-- Verificacion: mostrar logins de aplicacion actuales
USE master;
GO
SELECT
    p.name         AS login,
    p.type_desc    AS tipo,
    dp.name        AS usuario_en_bd,
    STRING_AGG(r.name, ', ') WITHIN GROUP (ORDER BY r.name) AS roles
FROM sys.server_principals p
LEFT JOIN inventario_ubicaciones.sys.database_principals dp
    ON dp.name = p.name
LEFT JOIN inventario_ubicaciones.sys.database_role_members drm
    ON drm.member_principal_id = dp.principal_id
LEFT JOIN inventario_ubicaciones.sys.database_principals r
    ON r.principal_id = drm.role_principal_id
WHERE p.type IN ('S', 'U')
  AND p.name NOT LIKE 'NT %'
  AND p.name NOT LIKE '##%'
  AND p.name <> 'sa'
GROUP BY p.name, p.type_desc, dp.name
ORDER BY p.name;
GO

-- =====================================================================
--  FIN DEL PASO 1
--  Hacer el PASO 2 antes de continuar:
--    1. Actualizar GitHub Secret SQLSERVER_USER = "inventario_admin"
--    2. Actualizar GitHub Secret SQLSERVER_PASSWORD con el valor usado en ADMIN_PASSWORD
--    3. Re-ejecutar el workflow de GitHub Actions
--    4. Verificar que el login desde el frontend sigue funcionando
--  Una vez confirmado, ejecutar el PASO 3 a continuacion.
-- =====================================================================


-- =====================================================================
--  PASO 3 — Eliminar el login obsoleto "inventarioapp"
--           EJECUTAR SOLO DESPUES DE COMPLETAR EL PASO 2 Y VERIFICAR
--           QUE EL BACKEND FUNCIONA CON inventario_admin
-- =====================================================================

/*   <-- descomenta quitando estos comentarios de bloque

USE master;
GO

-- Desconectar sesiones activas de inventarioapp
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'KILL ' + CAST(session_id AS NVARCHAR(10)) + N';'
FROM sys.dm_exec_sessions
WHERE login_name = 'inventarioapp';
IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'inventarioapp')
BEGIN
    USE inventario_ubicaciones;
    IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'inventarioapp')
        DROP USER inventarioapp;
    USE master;
    DROP LOGIN inventarioapp;
    PRINT 'Login inventarioapp eliminado.';
END
ELSE
    PRINT 'Login inventarioapp no existia.';
GO

*/   -- fin del bloque comentado

-- =====================================================================
--  FIN
--  Logins finales esperados en inventario_ubicaciones:
--    inventario_admin  (db_owner — backend + acceso total)
--    inventario_ro     (db_datareader — solo SELECT)
-- =====================================================================
