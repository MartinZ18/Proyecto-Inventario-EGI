-- =====================================================================
--  fix-filtered-index.sql
--
--  Crea el indice unico filtrado uq_persona_temporal_vigente sobre
--  Asignacion. Necesario solo si inventario_ubicaciones.sql ya se
--  ejecuto antes de la correccion del SET QUOTED_IDENTIFIER ON y el
--  indice quedo sin crear (error 1934). Es idempotente.
-- =====================================================================

USE inventario_ubicaciones;
GO

SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'uq_persona_temporal_vigente')
BEGIN
    CREATE UNIQUE INDEX uq_persona_temporal_vigente
        ON Asignacion (id_persona)
        WHERE tipo_asignacion = 'TEMPORAL' AND fecha_fin IS NULL;
END
GO
