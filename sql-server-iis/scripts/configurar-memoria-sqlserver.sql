-- =====================================================================
--  configurar-memoria-sqlserver.sql
--
--  Limita la RAM que SQL Server puede usar (max server memory).
--  Por defecto SQL Server consume toda la RAM disponible de la VM.
--  Correr una sola vez en la instancia, como sysadmin.
--
--  Con la VM en 2048 MB (setup-virtualbox-nueva-pc.ps1) se reservan
--  ~512 MB para Windows Server y se dejan 1536 MB para SQL Server.
--  Ajustar max_server_memory si se cambia la RAM de la VM.
-- =====================================================================

EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
GO

-- 1536 MB = RAM de la VM (2048) menos ~512 MB para el SO
EXEC sys.sp_configure N'max server memory (MB)', 1536;
RECONFIGURE;
GO

-- Verificar
SELECT
    name,
    value_in_use AS valor_actual_MB
FROM sys.configurations
WHERE name = 'max server memory (MB)';
GO
