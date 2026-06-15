-- =====================================================================
--  inventario_ubicaciones.sql
--
--  Copia de bases-de-datos/database/scripts/Script SQL Server 2022.sql
--  con el nombre de la base alineado a SQLSERVER_DB=inventario_ubicaciones
--  (ver sql-server-iis/README.md, seccion 2 - mismatch conocido con
--  ubicacion_db). Estructura y datos de prueba sin cambios, solo se
--  renombraron las 6 referencias a la base.
--
--  Ejecutar en la VM de SQL Server con sqlcmd, SSMS o Azure Data Studio.
--  Los 'GO' son separadores de lote (no son SQL, los interpreta la herramienta).
-- =====================================================================

-- Nos paramos en master para poder dropear inventario_ubicaciones aunque la ventana
-- estuviera conectada a ella. Sin esto, el DROP falla con "currently in use".
USE master;
GO

IF DB_ID('inventario_ubicaciones') IS NOT NULL
BEGIN
    ALTER DATABASE inventario_ubicaciones SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE inventario_ubicaciones;
END
GO
CREATE DATABASE inventario_ubicaciones;
GO
USE inventario_ubicaciones;
GO

-- =====================================================================
--  ESTRUCTURA
--  En SQL Server los ENUM del diagrama se modelan con CHECK (col IN (...)).
-- =====================================================================

-- ---------- Ubicacion ----------
CREATE TABLE Ubicacion (
    id_ubicacion INT IDENTITY(1,1) PRIMARY KEY,
    nombre       NVARCHAR(100) NOT NULL,
    tipo         VARCHAR(20)   NOT NULL
        CONSTRAINT chk_ubicacion_tipo CHECK (tipo IN ('AULA','LABORATORIO','BIBLIOTECA','OFICINA')),
    edificio     NVARCHAR(100) NOT NULL,
    piso         INT           NOT NULL
);
GO

-- ---------- Persona ----------
CREATE TABLE Persona (
    id_persona INT IDENTITY(1,1) PRIMARY KEY,
    nombre     NVARCHAR(80)  NOT NULL,
    apellido   NVARCHAR(80)  NOT NULL,
    dni        VARCHAR(20)   NOT NULL CONSTRAINT uq_persona_dni   UNIQUE,
    email      VARCHAR(150)  NOT NULL CONSTRAINT uq_persona_email UNIQUE,
    rol        VARCHAR(20)   NOT NULL
        CONSTRAINT chk_persona_rol CHECK (rol IN ('TECNICO','DOCENTE','ALUMNO','ADMINISTRADOR'))
);
GO

-- ---------- Equipo ----------
-- Un equipo pertenece a una sola ubicacion (1:N Ubicacion->Equipo).
CREATE TABLE Equipo (
    id_equipo    INT IDENTITY(1,1) PRIMARY KEY,
    id_ubicacion INT NOT NULL,
    estado       VARCHAR(40) NOT NULL,   -- ej: OPERATIVO, EN_REPARACION, BAJA
    fecha_alta   DATE NOT NULL,
    CONSTRAINT fk_equipo_ubicacion FOREIGN KEY (id_ubicacion)
        REFERENCES Ubicacion(id_ubicacion)
);
GO

-- ---------- Asignacion ----------
CREATE TABLE Asignacion (
    id_asignacion   INT IDENTITY(1,1) PRIMARY KEY,
    id_equipo       INT NOT NULL,
    id_persona      INT NOT NULL,
    tipo_asignacion VARCHAR(20) NOT NULL
        CONSTRAINT chk_asig_tipo CHECK (tipo_asignacion IN ('RESPONSABLE_TECNICO','TEMPORAL')),
    fecha_inicio    DATE NOT NULL,
    fecha_fin       DATE NULL,           -- NULL = asignacion abierta / vigente
    CONSTRAINT fk_asig_equipo  FOREIGN KEY (id_equipo)  REFERENCES Equipo(id_equipo) ON DELETE CASCADE,
    CONSTRAINT fk_asig_persona FOREIGN KEY (id_persona) REFERENCES Persona(id_persona),
    CONSTRAINT chk_asig_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);
GO

-- Regla de negocio: "Una Persona puede estar asignada a solo un equipo
-- TEMPORAL vigente". En SQL Server esto se resuelve LIMPIO con un INDICE
-- UNICO FILTRADO (algo que MySQL no soporta y por eso alla hubo que hacer
-- el truco de la columna generada). Aca es nativo:
-- Los indices filtrados requieren QUOTED_IDENTIFIER ON; el sqlcmd basado
-- en ODBC lo trae en OFF por defecto, asi que se fija explicitamente
-- en el mismo batch antes del CREATE INDEX.
SET QUOTED_IDENTIFIER ON;
CREATE UNIQUE INDEX uq_persona_temporal_vigente
    ON Asignacion (id_persona)
    WHERE tipo_asignacion = 'TEMPORAL' AND fecha_fin IS NULL;
GO

-- ---------- Mantenimiento ----------
-- id_tecnico referencia a Persona; "debe ser rol TECNICO" es regla de
-- aplicacion (un CHECK no puede consultar otra tabla).
CREATE TABLE Mantenimiento (
    id_mantenimiento INT IDENTITY(1,1) PRIMARY KEY,
    id_equipo        INT NOT NULL,
    fecha            DATE NOT NULL,
    tipo             VARCHAR(20) NOT NULL
        CONSTRAINT chk_mant_tipo CHECK (tipo IN ('PREVENTIVO','CORRECTIVO')),
    descripcion      NVARCHAR(500) NOT NULL,
    id_tecnico       INT NOT NULL,
    CONSTRAINT fk_mant_equipo  FOREIGN KEY (id_equipo)  REFERENCES Equipo(id_equipo) ON DELETE CASCADE,
    CONSTRAINT fk_mant_tecnico FOREIGN KEY (id_tecnico) REFERENCES Persona(id_persona)
);
GO

-- Indices de apoyo
CREATE INDEX idx_equipo_ubicacion ON Equipo(id_ubicacion);
CREATE INDEX idx_asig_equipo      ON Asignacion(id_equipo);
CREATE INDEX idx_asig_persona     ON Asignacion(id_persona);
CREATE INDEX idx_mant_equipo      ON Mantenimiento(id_equipo);
CREATE INDEX idx_mant_tecnico     ON Mantenimiento(id_tecnico);
GO

-- =====================================================================
--  DATOS DE PRUEBA
--  Las columnas IDENTITY se autogeneran 1..N en el orden de insercion,
--  por eso NO se insertan los id y las FK calzan (ubicacion 1..11,
--  persona 1..12, equipo 1..12). Correr una sola vez tras crear la BD.
-- =====================================================================

-- ---------- Ubicacion (11) ----------
INSERT INTO Ubicacion (nombre, tipo, edificio, piso) VALUES
  (N'Aula 101',                'AULA',        N'Edificio A',  1),
  (N'Aula 102',                'AULA',        N'Edificio A',  1),
  (N'Laboratorio de Redes',    'LABORATORIO', N'Edificio B',  2),
  (N'Laboratorio de Software', 'LABORATORIO', N'Edificio B',  2),
  (N'Biblioteca Central',      'BIBLIOTECA',  N'Edificio C',  0),
  (N'Oficina de Sistemas',     'OFICINA',     N'Edificio A',  3),
  (N'Aula 201',                'AULA',        N'Edificio A',  2),
  (N'Laboratorio de Hardware', 'LABORATORIO', N'Edificio B',  1),
  (N'Oficina de Direccion',    'OFICINA',     N'Edificio C',  3),
  (N'Aula Magna',              'AULA',        N'Edificio D',  0),
  (N'Sala de Servidores',      'OFICINA',     N'Edificio B', -1);
GO

-- ---------- Persona (12) ----------
INSERT INTO Persona (nombre, apellido, dni, email, rol) VALUES
  (N'Carlos',  N'Funes',   '30111222', 'carlos.funes@itu.edu.ar',          'TECNICO'),
  (N'Marina',  N'Lopez',   '28999444', 'marina.lopez@itu.edu.ar',          'TECNICO'),
  (N'Diego',   N'Perez',   '31222333', 'diego.perez@itu.edu.ar',           'TECNICO'),
  (N'Ana',     N'Gomez',   '27888111', 'ana.gomez@itu.edu.ar',             'DOCENTE'),
  (N'Roberto', N'Diaz',    '26555000', 'roberto.diaz@itu.edu.ar',          'DOCENTE'),
  (N'Lucia',   N'Romero',  '33444555', 'lucia.romero@itu.edu.ar',          'DOCENTE'),
  (N'Tomas',   N'Aguirre', '42111000', 'tomas.aguirre@alumno.itu.edu.ar',  'ALUMNO'),
  (N'Julieta', N'Sosa',    '43222111', 'julieta.sosa@alumno.itu.edu.ar',   'ALUMNO'),
  (N'Martin',  N'Vega',    '41333222', 'martin.vega@alumno.itu.edu.ar',    'ALUMNO'),
  (N'Sofia',   N'Herrera', '29666777', 'sofia.herrera@itu.edu.ar',         'ADMINISTRADOR'),
  (N'Pablo',   N'Nunez',   '32777888', 'pablo.nunez@itu.edu.ar',           'TECNICO'),
  (N'Camila',  N'Ortiz',   '44555666', 'camila.ortiz@alumno.itu.edu.ar',   'ALUMNO');
GO

-- ---------- Equipo (12) ----------
-- id_equipo 1..12: clave puente hacia MongoDB.
INSERT INTO Equipo (id_ubicacion, estado, fecha_alta) VALUES
  ( 4, 'OPERATIVO',     '2023-03-15'),  -- 1  desktop
  ( 4, 'OPERATIVO',     '2023-03-15'),  -- 2  desktop
  ( 3, 'OPERATIVO',     '2023-04-01'),  -- 3  laptop
  ( 1, 'OPERATIVO',     '2023-05-10'),  -- 4  desktop
  ( 8, 'EN_REPARACION', '2022-08-20'),  -- 5  desktop
  ( 6, 'OPERATIVO',     '2024-01-12'),  -- 6  laptop
  ( 5, 'OPERATIVO',     '2023-09-05'),  -- 7  desktop
  ( 3, 'OPERATIVO',     '2024-02-28'),  -- 8  laptop
  ( 7, 'OPERATIVO',     '2023-11-11'),  -- 9  desktop
  ( 9, 'OPERATIVO',     '2024-03-01'),  -- 10 laptop
  (11, 'OPERATIVO',     '2022-06-30'),  -- 11 desktop
  (10, 'BAJA',          '2021-04-18');  -- 12 laptop
GO

-- ---------- Asignacion (13) ----------
-- RESPONSABLE_TECNICO -> Personas TECNICO (ids 1,2,3,11).
-- TEMPORAL -> docentes/alumnos; un solo TEMPORAL vigente (fecha_fin NULL) por persona.
INSERT INTO Asignacion (id_equipo, id_persona, tipo_asignacion, fecha_inicio, fecha_fin) VALUES
  ( 1,  1, 'RESPONSABLE_TECNICO', '2023-03-20', NULL),
  ( 2,  1, 'RESPONSABLE_TECNICO', '2023-03-20', NULL),
  ( 3,  2, 'RESPONSABLE_TECNICO', '2023-04-05', NULL),
  ( 4,  3, 'RESPONSABLE_TECNICO', '2023-05-15', NULL),
  ( 5, 11, 'RESPONSABLE_TECNICO', '2022-08-25', NULL),
  ( 6,  2, 'RESPONSABLE_TECNICO', '2024-01-15', NULL),
  ( 7,  4, 'TEMPORAL',            '2025-03-01', NULL),  -- Ana, vigente
  ( 8,  5, 'TEMPORAL',            '2025-03-01', NULL),  -- Roberto, vigente
  ( 9,  7, 'TEMPORAL',            '2024-08-01', '2024-12-15'),  -- Tomas, cerrada
  (10,  7, 'TEMPORAL',            '2025-03-10', NULL),  -- Tomas, nueva vigente
  (11,  8, 'TEMPORAL',            '2025-04-01', '2025-05-30'),  -- Julieta, cerrada
  ( 1,  6, 'TEMPORAL',            '2025-05-05', NULL),  -- Lucia, vigente
  (12,  9, 'TEMPORAL',            '2024-02-01', '2024-06-30');  -- Martin, cerrada
GO

-- ---------- Mantenimiento (12) ----------
INSERT INTO Mantenimiento (id_equipo, fecha, tipo, descripcion, id_tecnico) VALUES
  ( 1, '2024-06-10', 'PREVENTIVO', N'Limpieza interna y revision general',   1),
  ( 1, '2025-01-15', 'CORRECTIVO', N'Reemplazo de fuente de poder',          1),
  ( 2, '2024-07-20', 'PREVENTIVO', N'Actualizacion de SO y limpieza',        1),
  ( 3, '2024-09-05', 'PREVENTIVO', N'Revision de bateria y ventiladores',    2),
  ( 5, '2022-09-01', 'CORRECTIVO', N'Diagnostico de falla de arranque',     11),
  ( 5, '2025-02-10', 'CORRECTIVO', N'Cambio de disco SSD danado',           11),
  ( 6, '2024-04-22', 'PREVENTIVO', N'Mantenimiento preventivo trimestral',   2),
  ( 8, '2024-12-01', 'PREVENTIVO', N'Limpieza y reemplazo de pasta termica', 3),
  ( 9, '2024-10-18', 'CORRECTIVO', N'Reparacion de puerto de red',           2),
  (11, '2023-01-30', 'PREVENTIVO', N'Revision de servidores y arreglo RAID', 1),
  ( 4, '2025-03-12', 'PREVENTIVO', N'Inspeccion de hardware de aula',        3),
  ( 7, '2024-08-08', 'CORRECTIVO', N'Sustitucion de teclado danado',         3);
GO

-- =====================================================================
--  FIN
-- =====================================================================

USE inventario_ubicaciones;
SELECT name FROM sys.tables ORDER BY name;
SELECT COUNT(*) FROM Persona;

SELECT * FROM Equipo;
SELECT * FROM Asignacion;
SELECT * FROM Mantenimiento;
SELECT * FROM Persona;
SELECT * FROM Ubicacion;
