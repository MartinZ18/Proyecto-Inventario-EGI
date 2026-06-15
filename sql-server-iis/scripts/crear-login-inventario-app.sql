-- =====================================================================
--  crear-login-inventario-app.sql
--
--  Crea el login SQL "inventario_app" (autenticacion SQL, no Windows)
--  que usa el backend para conectarse a inventario_ubicaciones, con
--  permisos db_datareader + db_datawriter + db_ddladmin (ver
--  sql-server-iis/README.md, seccion 3 - db_ddladmin es necesario
--  porque app/main.py llama a Base.metadata.create_all() al arrancar).
--
--  Idempotente: se puede volver a correr sin error si el login/usuario
--  ya existen o ya tienen los roles asignados.
--
--  Contrasena de laboratorio (misma convencion que los usuarios de AD
--  documentados en active-directory/README.md): InventarioApp!2025
--  Cambiarla despues de la defensa si esta VM se reutiliza.
-- =====================================================================

USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'inventario_app')
BEGIN
    CREATE LOGIN inventario_app WITH PASSWORD = 'InventarioApp!2025', CHECK_POLICY = ON;
END
GO

USE inventario_ubicaciones;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'inventario_app')
BEGIN
    CREATE USER inventario_app FOR LOGIN inventario_app;
END
GO

IF (IS_ROLEMEMBER('db_datareader', 'inventario_app') = 0)
    ALTER ROLE db_datareader ADD MEMBER inventario_app;
IF (IS_ROLEMEMBER('db_datawriter', 'inventario_app') = 0)
    ALTER ROLE db_datawriter ADD MEMBER inventario_app;
IF (IS_ROLEMEMBER('db_ddladmin', 'inventario_app') = 0)
    ALTER ROLE db_ddladmin ADD MEMBER inventario_app;
GO
