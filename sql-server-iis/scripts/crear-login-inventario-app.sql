-- =====================================================================
--  crear-login-inventario-app.sql  [REEMPLAZADO]
--
--  ESTE SCRIPT QUEDO OBSOLETO. Usar en su lugar:
--    configurar-usuarios-sql.sql
--
--  Ese script elimina el login "inventarioapp" y crea los 2 logins
--  definitivos del proyecto:
--    inventario_admin  (db_owner — backend + acceso total)
--    inventario_ro     (db_datareader — solo lectura)
--
--  Se conserva este archivo solo como referencia de la configuracion
--  original. No ejecutar en VMs ya migradas.
-- =====================================================================
-- [ARCHIVO OBSOLETO — ver configurar-usuarios-sql.sql]

USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'inventarioapp')
BEGIN
    CREATE LOGIN inventarioapp WITH PASSWORD = 'InventarioApp!2025', CHECK_POLICY = ON;
END
GO

USE inventario_ubicaciones;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'inventarioapp')
BEGIN
    CREATE USER inventarioapp FOR LOGIN inventarioapp;
END
GO

IF (IS_ROLEMEMBER('db_datareader', 'inventarioapp') = 0)
    ALTER ROLE db_datareader ADD MEMBER inventarioapp;
IF (IS_ROLEMEMBER('db_datawriter', 'inventarioapp') = 0)
    ALTER ROLE db_datawriter ADD MEMBER inventarioapp;
IF (IS_ROLEMEMBER('db_ddladmin', 'inventarioapp') = 0)
    ALTER ROLE db_ddladmin ADD MEMBER inventarioapp;
GO
