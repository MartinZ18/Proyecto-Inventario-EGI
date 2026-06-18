-- =====================================================================
--  configurar-usuarios-sql.sql
--
--  Deja exactamente 2 logins de aplicacion en inventario_ubicaciones:
--
--    inventario_admin   todos los permisos (db_owner)
--                       usado por el backend (FastAPI) para CRUD + DDL
--    inventario_ro      solo lectura (db_datareader)
--                       para consultas de auditoria o demos
--
--  Tambien elimina el login anterior "inventarioapp" si existe.
--  Los logins de sistema (sa, NT AUTHORITY\SYSTEM, NT SERVICE\*,
--  ##MS_*##) NO se tocan.
--
--  Idempotente: se puede volver a correr sin error.
--
--  IMPORTANTE: si el backend usaba "inventarioapp", actualizar el
--  Secret de Kubernetes en LubuntuEGI y re-ejecutar el workflow:
--
--    kubectl create secret generic backend-secret -n inventario \
--      --from-literal=SQLSERVER_USER="inventario_admin" \
--      --from-literal=SQLSERVER_PASSWORD="<password>" \
--      ... (resto de los campos igual) \
--      --dry-run=client -o yaml | kubectl apply -f -
--
--    kubectl rollout restart deployment/backend -n inventario
--
--  Contrasenas de laboratorio (cambiar despues de la defensa si la VM
--  se reutiliza):
--    inventario_admin  InvAdmin!2025
--    inventario_ro     InvReadOnly!2025
-- =====================================================================

USE master;
GO

-- =====================================================================
--  1. Eliminar el login anterior si existe
-- =====================================================================

-- Desconectar sesiones activas de inventarioapp antes de eliminar
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'inventarioapp')
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'';
    SELECT @sql += N'KILL ' + CAST(session_id AS NVARCHAR(10)) + N';'
    FROM sys.dm_exec_sessions
    WHERE login_name = 'inventarioapp';
    IF LEN(@sql) > 0 EXEC sp_executesql @sql;
END
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
    PRINT 'Login inventarioapp no existia (sin cambios).';
GO

-- =====================================================================
--  2. Crear login inventario_admin  (todos los permisos — db_owner)
-- =====================================================================

USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'inventario_admin')
BEGIN
    CREATE LOGIN inventario_admin
        WITH PASSWORD   = 'InvAdmin!2025',
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

-- db_owner incluye datareader + datawriter + ddladmin + mas.
-- SQLAlchemy (Base.metadata.create_all) necesita ddladmin al arrancar
-- el backend, por eso se otorga db_owner en lugar de permisos granulares.
IF (IS_ROLEMEMBER('db_owner', 'inventario_admin') = 0)
BEGIN
    ALTER ROLE db_owner ADD MEMBER inventario_admin;
    PRINT 'Rol db_owner otorgado a inventario_admin.';
END
GO

-- =====================================================================
--  3. Crear login inventario_ro  (solo lectura — db_datareader)
-- =====================================================================

USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'inventario_ro')
BEGIN
    CREATE LOGIN inventario_ro
        WITH PASSWORD   = 'InvReadOnly!2025',
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

-- =====================================================================
--  4. Verificacion — mostrar logins de aplicacion activos
--     (excluye SA, NT AUTHORITY, NT SERVICE y los certificados internos)
-- =====================================================================

USE master;
GO
SELECT
    p.name         AS login,
    p.type_desc    AS tipo,
    p.is_disabled  AS deshabilitado,
    dp.name        AS usuario_en_bd,
    STRING_AGG(r.name, ', ') WITHIN GROUP (ORDER BY r.name) AS roles
FROM sys.server_principals p
LEFT JOIN inventario_ubicaciones.sys.database_principals dp
    ON dp.name = p.name
LEFT JOIN inventario_ubicaciones.sys.database_role_members drm
    ON drm.member_principal_id = dp.principal_id
LEFT JOIN inventario_ubicaciones.sys.database_principals r
    ON r.principal_id = drm.role_principal_id
WHERE p.type IN ('S', 'U')   -- SQL login o Windows login
  AND p.name NOT LIKE 'NT %'
  AND p.name NOT LIKE '##%'
  AND p.name <> 'sa'
GROUP BY p.name, p.type_desc, p.is_disabled, dp.name
ORDER BY p.name;
GO

-- =====================================================================
--  FIN
--  Credenciales de aplicacion resultantes:
--    inventario_admin  InvAdmin!2025    (acceso total — usar en el backend)
--    inventario_ro     InvReadOnly!2025 (solo SELECT — demos/auditoria)
-- =====================================================================
