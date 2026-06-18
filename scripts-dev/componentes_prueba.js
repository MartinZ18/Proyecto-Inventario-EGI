// =====================================================================
//  DATOS DE PRUEBA - SOLO DESARROLLO LOCAL
//  Componentes internos de cada equipo (parte NoSQL de MongoDB).
//  id_equipo es el puente con SQL Server.
//
//  NOTA: en mongosh los numeros se guardan como 'double' por defecto.
//  Por eso los campos enteros usan NumberInt(...), para que el validador
//  $jsonSchema no los rechace por bsonType "int".
// =====================================================================

db = db.getSiblingDB('inventario_componentes');
db.computadoras.drop();

// ---------------------------------------------------------------------
//  Coleccion 'computadoras' con validador $jsonSchema
// ---------------------------------------------------------------------
db.createCollection('computadoras', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['id_equipo', 'tipo', 'codigo_inventario', 'fabricante',
                 'modelo', 'sistema_operativo', 'cpu', 'ram', 'almacenamiento'],
      properties: {
        id_equipo:         { bsonType: 'int', description: 'Clave puente -> SQL Server Equipo.id_equipo' },
        tipo:              { enum: ['desktop', 'laptop'] },
        codigo_inventario: { bsonType: 'string' },
        fabricante:        { bsonType: 'string' },
        modelo:            { bsonType: 'string' },
        observacion:       { bsonType: ['string', 'null'] },

        sistema_operativo: {
          bsonType: 'object',
          required: ['nombre'],
          properties: {
            nombre:       { bsonType: 'string' },
            version:      { bsonType: ['string', 'null'] },
            arquitectura: { bsonType: ['string', 'null'] }
          }
        },

        cpu: {
          bsonType: 'object',
          required: ['fabricante', 'modelo', 'nucleos', 'frecuencia_ghz'],
          properties: {
            fabricante:     { bsonType: 'string' },
            modelo:         { bsonType: 'string' },
            nucleos:        { bsonType: 'int' },
            frecuencia_ghz: { bsonType: ['double', 'int'] }
          }
        },

        gpu: {
          bsonType: 'object',
          properties: {
            fabricante: { bsonType: 'string' },
            modelo:     { bsonType: 'string' },
            memoria_gb: { bsonType: ['int', 'null'] }
          }
        },

        ram: {
          bsonType: 'array',
          minItems: 1,
          items: {
            bsonType: 'object',
            required: ['fabricante', 'capacidad_gb', 'tipo', 'frecuencia_mhz'],
            properties: {
              fabricante:     { bsonType: 'string' },
              capacidad_gb:   { bsonType: 'int' },
              tipo:           { bsonType: 'string' },
              frecuencia_mhz: { bsonType: 'int' }
            }
          }
        },

        almacenamiento: {
          bsonType: 'array',
          minItems: 1,
          items: {
            bsonType: 'object',
            required: ['tipo', 'capacidad_gb', 'fabricante', 'modelo'],
            properties: {
              tipo:         { enum: ['SSD', 'HDD'] },
              capacidad_gb: { bsonType: 'int' },
              fabricante:   { bsonType: 'string' },
              modelo:       { bsonType: 'string' }
            }
          }
        },

        perifericos: {
          bsonType: 'object',
          properties: {
            monitor: {
              bsonType: 'object',
              properties: {
                fabricante: { bsonType: 'string' },
                modelo:     { bsonType: 'string' },
                pulgadas:   { bsonType: ['double', 'int'] }
              }
            },
            teclado: {
              bsonType: 'object',
              properties: {
                fabricante: { bsonType: 'string' },
                conexion:   { bsonType: 'string' }
              }
            },
            mouse: {
              bsonType: 'object',
              properties: {
                fabricante: { bsonType: 'string' },
                conexion:   { bsonType: 'string' }
              }
            }
          }
        },

        bateria: {
          bsonType: 'object',
          properties: {
            estado: { bsonType: 'string' },
            ciclos: { bsonType: 'int' }
          }
        },

        pantalla_integrada: {
          bsonType: 'object',
          properties: {
            pulgadas:   { bsonType: ['double', 'int'] },
            resolucion: { bsonType: 'string' }
          }
        }
      },

      oneOf: [
        { properties: { tipo: { enum: ['desktop'] } }, required: ['perifericos'] },
        { properties: { tipo: { enum: ['laptop'] } },  required: ['bateria', 'pantalla_integrada'] }
      ]
    }
  },
  validationLevel: 'strict',
  validationAction: 'error'
});

// ---------------------------------------------------------------------
//  Indices
// ---------------------------------------------------------------------
db.computadoras.createIndex({ id_equipo: 1 }, { unique: true });
db.computadoras.createIndex({ 'sistema_operativo.nombre': 1 });

// ---------------------------------------------------------------------
//  DATOS DE PRUEBA (12 documentos; id_equipo 1..12 = equipos de SQL Server)
//  desktop: 1,2,4,5,7,9,11   |   laptop: 3,6,8,10,12
// ---------------------------------------------------------------------
db.computadoras.insertMany([
  {
    id_equipo: NumberInt(1), tipo: 'desktop', codigo_inventario: 'INV-DSK-0001',
    fabricante: 'Dell', modelo: 'OptiPlex 7090', observacion: 'Lab de software',
    sistema_operativo: { nombre: 'Windows', version: '11 Pro', arquitectura: 'x64' },
    cpu: { fabricante: 'Intel', modelo: 'Core i7-11700', nucleos: NumberInt(8), frecuencia_ghz: 2.5 },
    gpu: { fabricante: 'Intel', modelo: 'UHD Graphics 750', memoria_gb: null },
    ram: [
      { fabricante: 'Kingston', capacidad_gb: NumberInt(8), tipo: 'DDR4', frecuencia_mhz: NumberInt(3200) },
      { fabricante: 'Kingston', capacidad_gb: NumberInt(8), tipo: 'DDR4', frecuencia_mhz: NumberInt(3200) }
    ],
    almacenamiento: [ { tipo: 'SSD', capacidad_gb: NumberInt(512), fabricante: 'Samsung', modelo: '980' } ],
    perifericos: {
      monitor: { fabricante: 'Dell', modelo: 'P2422H', pulgadas: 24 },
      teclado: { fabricante: 'Dell', conexion: 'USB' },
      mouse:   { fabricante: 'Logitech', conexion: 'USB' }
    }
  },
  {
    id_equipo: NumberInt(2), tipo: 'desktop', codigo_inventario: 'INV-DSK-0002',
    fabricante: 'HP', modelo: 'EliteDesk 800 G6', observacion: null,
    sistema_operativo: { nombre: 'Ubuntu', version: '22.04 LTS', arquitectura: 'x64' },
    cpu: { fabricante: 'Intel', modelo: 'Core i5-10500', nucleos: NumberInt(6), frecuencia_ghz: 3.1 },
    gpu: { fabricante: 'Intel', modelo: 'UHD Graphics 630', memoria_gb: null },
    ram: [ { fabricante: 'Crucial', capacidad_gb: NumberInt(16), tipo: 'DDR4', frecuencia_mhz: NumberInt(2666) } ],
    almacenamiento: [
      { tipo: 'SSD', capacidad_gb: NumberInt(256), fabricante: 'Crucial', modelo: 'MX500' },
      { tipo: 'HDD', capacidad_gb: NumberInt(1000), fabricante: 'Seagate', modelo: 'Barracuda' }
    ],
    perifericos: {
      monitor: { fabricante: 'HP', modelo: 'P24h G4', pulgadas: 23.8 },
      teclado: { fabricante: 'HP', conexion: 'USB' },
      mouse:   { fabricante: 'HP', conexion: 'USB' }
    }
  },
  {
    id_equipo: NumberInt(3), tipo: 'laptop', codigo_inventario: 'INV-LAP-0003',
    fabricante: 'Lenovo', modelo: 'ThinkPad E14', observacion: 'Lab de redes',
    sistema_operativo: { nombre: 'Windows', version: '10 Pro', arquitectura: 'x64' },
    cpu: { fabricante: 'AMD', modelo: 'Ryzen 5 5500U', nucleos: NumberInt(6), frecuencia_ghz: 2.1 },
    gpu: { fabricante: 'AMD', modelo: 'Radeon Graphics', memoria_gb: null },
    ram: [ { fabricante: 'Samsung', capacidad_gb: NumberInt(16), tipo: 'DDR4', frecuencia_mhz: NumberInt(3200) } ],
    almacenamiento: [ { tipo: 'SSD', capacidad_gb: NumberInt(512), fabricante: 'WD', modelo: 'SN530' } ],
    bateria: { estado: 'BUENO', ciclos: NumberInt(120) },
    pantalla_integrada: { pulgadas: 14.0, resolucion: '1920x1080' }
  },
  {
    id_equipo: NumberInt(4), tipo: 'desktop', codigo_inventario: 'INV-DSK-0004',
    fabricante: 'Armado', modelo: 'PC Aula 101', observacion: null,
    sistema_operativo: { nombre: 'Windows', version: '10 Pro', arquitectura: 'x64' },
    cpu: { fabricante: 'Intel', modelo: 'Core i3-10100', nucleos: NumberInt(4), frecuencia_ghz: 3.6 },
    ram: [ { fabricante: 'ADATA', capacidad_gb: NumberInt(8), tipo: 'DDR4', frecuencia_mhz: NumberInt(2666) } ],
    almacenamiento: [ { tipo: 'HDD', capacidad_gb: NumberInt(500), fabricante: 'Toshiba', modelo: 'P300' } ],
    perifericos: {
      monitor: { fabricante: 'Samsung', modelo: 'S24R350', pulgadas: 24 },
      teclado: { fabricante: 'Genius', conexion: 'USB' },
      mouse:   { fabricante: 'Genius', conexion: 'USB' }
    }
  },
  {
    id_equipo: NumberInt(5), tipo: 'desktop', codigo_inventario: 'INV-DSK-0005',
    fabricante: 'Armado', modelo: 'Workstation Hardware', observacion: 'En reparacion',
    sistema_operativo: { nombre: 'Debian', version: '12', arquitectura: 'x64' },
    cpu: { fabricante: 'AMD', modelo: 'Ryzen 7 5800X', nucleos: NumberInt(8), frecuencia_ghz: 3.8 },
    gpu: { fabricante: 'NVIDIA', modelo: 'GeForce RTX 3060', memoria_gb: NumberInt(12) },
    ram: [
      { fabricante: 'Corsair', capacidad_gb: NumberInt(16), tipo: 'DDR4', frecuencia_mhz: NumberInt(3600) },
      { fabricante: 'Corsair', capacidad_gb: NumberInt(16), tipo: 'DDR4', frecuencia_mhz: NumberInt(3600) }
    ],
    almacenamiento: [ { tipo: 'SSD', capacidad_gb: NumberInt(1000), fabricante: 'Samsung', modelo: '970 EVO' } ],
    perifericos: {
      monitor: { fabricante: 'LG', modelo: '24GN600', pulgadas: 24 },
      teclado: { fabricante: 'Redragon', conexion: 'USB' },
      mouse:   { fabricante: 'Redragon', conexion: 'USB' }
    }
  },
  {
    id_equipo: NumberInt(6), tipo: 'laptop', codigo_inventario: 'INV-LAP-0006',
    fabricante: 'Dell', modelo: 'Latitude 5420', observacion: 'Oficina de sistemas',
    sistema_operativo: { nombre: 'Windows', version: '11 Pro', arquitectura: 'x64' },
    cpu: { fabricante: 'Intel', modelo: 'Core i7-1185G7', nucleos: NumberInt(4), frecuencia_ghz: 3.0 },
    gpu: { fabricante: 'Intel', modelo: 'Iris Xe', memoria_gb: null },
    ram: [ { fabricante: 'Micron', capacidad_gb: NumberInt(16), tipo: 'DDR4', frecuencia_mhz: NumberInt(3200) } ],
    almacenamiento: [ { tipo: 'SSD', capacidad_gb: NumberInt(512), fabricante: 'Micron', modelo: '2300' } ],
    bateria: { estado: 'BUENO', ciclos: NumberInt(85) },
    pantalla_integrada: { pulgadas: 14.0, resolucion: '1920x1080' }
  },
  {
    id_equipo: NumberInt(7), tipo: 'desktop', codigo_inventario: 'INV-DSK-0007',
    fabricante: 'Lenovo', modelo: 'ThinkCentre M70t', observacion: 'Biblioteca',
    sistema_operativo: { nombre: 'Windows', version: '11 Pro', arquitectura: 'x64' },
    cpu: { fabricante: 'Intel', modelo: 'Core i5-12400', nucleos: NumberInt(6), frecuencia_ghz: 2.5 },
    ram: [ { fabricante: 'Kingston', capacidad_gb: NumberInt(8), tipo: 'DDR4', frecuencia_mhz: NumberInt(3200) } ],
    almacenamiento: [ { tipo: 'SSD', capacidad_gb: NumberInt(256), fabricante: 'Kingston', modelo: 'NV2' } ],
    perifericos: {
      monitor: { fabricante: 'Lenovo', modelo: 'D24-20', pulgadas: 23.8 },
      teclado: { fabricante: 'Lenovo', conexion: 'USB' },
      mouse:   { fabricante: 'Lenovo', conexion: 'inalambrico' }
    }
  },
  {
    id_equipo: NumberInt(8), tipo: 'laptop', codigo_inventario: 'INV-LAP-0008',
    fabricante: 'HP', modelo: 'ProBook 450 G8', observacion: null,
    sistema_operativo: { nombre: 'Windows', version: '10 Pro', arquitectura: 'x64' },
    cpu: { fabricante: 'Intel', modelo: 'Core i5-1135G7', nucleos: NumberInt(4), frecuencia_ghz: 2.4 },
    gpu: { fabricante: 'Intel', modelo: 'Iris Xe', memoria_gb: null },
    ram: [ { fabricante: 'SK Hynix', capacidad_gb: NumberInt(8), tipo: 'DDR4', frecuencia_mhz: NumberInt(3200) } ],
    almacenamiento: [ { tipo: 'SSD', capacidad_gb: NumberInt(256), fabricante: 'SK Hynix', modelo: 'BC711' } ],
    bateria: { estado: 'REGULAR', ciclos: NumberInt(310) },
    pantalla_integrada: { pulgadas: 15.6, resolucion: '1920x1080' }
  },
  {
    id_equipo: NumberInt(9), tipo: 'desktop', codigo_inventario: 'INV-DSK-0009',
    fabricante: 'Armado', modelo: 'PC Aula 201', observacion: null,
    sistema_operativo: { nombre: 'Windows', version: '10 Pro', arquitectura: 'x64' },
    cpu: { fabricante: 'AMD', modelo: 'Ryzen 3 3200G', nucleos: NumberInt(4), frecuencia_ghz: 3.6 },
    gpu: { fabricante: 'AMD', modelo: 'Radeon Vega 8', memoria_gb: null },
    ram: [ { fabricante: 'HyperX', capacidad_gb: NumberInt(8), tipo: 'DDR4', frecuencia_mhz: NumberInt(3000) } ],
    almacenamiento: [ { tipo: 'SSD', capacidad_gb: NumberInt(240), fabricante: 'Kingston', modelo: 'A400' } ],
    perifericos: {
      monitor: { fabricante: 'AOC', modelo: '24B2H', pulgadas: 24 },
      teclado: { fabricante: 'Logitech', conexion: 'USB' },
      mouse:   { fabricante: 'Logitech', conexion: 'USB' }
    }
  },
  {
    id_equipo: NumberInt(10), tipo: 'laptop', codigo_inventario: 'INV-LAP-0010',
    fabricante: 'Asus', modelo: 'ExpertBook B1', observacion: 'Oficina de direccion',
    sistema_operativo: { nombre: 'Windows', version: '11 Pro', arquitectura: 'x64' },
    cpu: { fabricante: 'Intel', modelo: 'Core i5-1235U', nucleos: NumberInt(10), frecuencia_ghz: 1.3 },
    gpu: { fabricante: 'Intel', modelo: 'Iris Xe', memoria_gb: null },
    ram: [ { fabricante: 'Samsung', capacidad_gb: NumberInt(16), tipo: 'DDR4', frecuencia_mhz: NumberInt(3200) } ],
    almacenamiento: [ { tipo: 'SSD', capacidad_gb: NumberInt(512), fabricante: 'WD', modelo: 'SN560' } ],
    bateria: { estado: 'BUENO', ciclos: NumberInt(40) },
    pantalla_integrada: { pulgadas: 14.0, resolucion: '1920x1080' }
  },
  {
    id_equipo: NumberInt(11), tipo: 'desktop', codigo_inventario: 'INV-DSK-0011',
    fabricante: 'Dell', modelo: 'PowerEdge T40', observacion: 'Servidor de laboratorio',
    sistema_operativo: { nombre: 'Ubuntu Server', version: '24.04 LTS', arquitectura: 'x64' },
    cpu: { fabricante: 'Intel', modelo: 'Xeon E-2224G', nucleos: NumberInt(4), frecuencia_ghz: 3.5 },
    ram: [
      { fabricante: 'Kingston', capacidad_gb: NumberInt(16), tipo: 'DDR4', frecuencia_mhz: NumberInt(2666) },
      { fabricante: 'Kingston', capacidad_gb: NumberInt(16), tipo: 'DDR4', frecuencia_mhz: NumberInt(2666) }
    ],
    almacenamiento: [
      { tipo: 'SSD', capacidad_gb: NumberInt(480), fabricante: 'Intel', modelo: 'D3-S4510' },
      { tipo: 'HDD', capacidad_gb: NumberInt(2000), fabricante: 'Seagate', modelo: 'IronWolf' }
    ],
    perifericos: {
      monitor: { fabricante: 'Dell', modelo: 'E1916HV', pulgadas: 18.5 },
      teclado: { fabricante: 'Dell', conexion: 'USB' },
      mouse:   { fabricante: 'Dell', conexion: 'USB' }
    }
  },
  {
    id_equipo: NumberInt(12), tipo: 'laptop', codigo_inventario: 'INV-LAP-0012',
    fabricante: 'Acer', modelo: 'Aspire 5', observacion: 'Dada de baja',
    sistema_operativo: { nombre: 'Windows', version: null, arquitectura: 'x64' },
    cpu: { fabricante: 'Intel', modelo: 'Core i3-1115G4', nucleos: NumberInt(2), frecuencia_ghz: 3.0 },
    gpu: { fabricante: 'Intel', modelo: 'UHD Graphics', memoria_gb: null },
    ram: [ { fabricante: 'Generica', capacidad_gb: NumberInt(8), tipo: 'DDR4', frecuencia_mhz: NumberInt(2666) } ],
    almacenamiento: [ { tipo: 'HDD', capacidad_gb: NumberInt(1000), fabricante: 'Toshiba', modelo: 'MQ04' } ],
    bateria: { estado: 'MALO', ciclos: NumberInt(820) },
    pantalla_integrada: { pulgadas: 15.6, resolucion: '1366x768' }
  }
]);

print('Documentos insertados: ' + db.computadoras.countDocuments());