-- =============================================================================
-- PROYECTO INTEGRADOR TurismoUQ - Bases de Datos II
-- Script 01: DDL (tablas, restricciones y comentarios)
-- Ejecutar sobre un esquema limpio, antes de ScriptDatos.sql.
--
-- Correcciones aplicadas tras la retroalimentacion de la Entrega 1:
--   * COMMENT ON TABLE en todas las tablas.
--   * UNIQUE (id_alojamiento, numero) en HABITACION y UNIQUE (id_habitacion,
--     id_temporada) en TARIFA.
--   * CHECK de calificacion 1-5 en RESENA y de cantidad > 0 en RESERVA_SERVICIO.
--   * CHECK de dominio y de valores positivos en el resto de tablas (tipo de
--     temporada, rango de fechas, estrellas, precios, montos, roles).
--   * Un administrador de la plataforma no pertenece a ningun alojamiento:
--     USUARIO_SISTEMA.id_alojamiento es opcional y un CHECK lo amarra al rol.
--   * El comentario de una resena es opcional (el enunciado lo dice asi) y
--     cada reserva admite como maximo una resena.
--   * Los metodos de pago se guardan sin tildes para que el CHECK no dependa
--     de la codificacion del cliente SQL (SQL*Plus / SQL Developer).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tablas independientes (catalogos)
-- -----------------------------------------------------------------------------
CREATE TABLE Municipio (
    id_municipio NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre       VARCHAR2(100) NOT NULL,
    CONSTRAINT uq_municipio_nombre UNIQUE (nombre)
);
COMMENT ON TABLE Municipio IS 'Catálogo de los 12 municipios del departamento del Quindío';

CREATE TABLE Tipo_Alojamiento (
    id_tipo_alojamiento NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre              VARCHAR2(100) NOT NULL,
    CONSTRAINT uq_tipo_alojamiento_nombre UNIQUE (nombre)
);
COMMENT ON TABLE Tipo_Alojamiento IS 'Clasificación de los tipos de hospedaje (hotel, finca cafetera, glamping, hostal)';

CREATE TABLE Temporada (
    id_temporada NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre       VARCHAR2(100) NOT NULL,
    tipo         VARCHAR2(50)  NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin    DATE NOT NULL,
    CONSTRAINT chk_temporada_tipo   CHECK (tipo IN ('alta', 'media', 'baja')),
    CONSTRAINT chk_temporada_fechas CHECK (fecha_inicio <= fecha_fin),
    CONSTRAINT uq_temporada_inicio  UNIQUE (fecha_inicio)
);
COMMENT ON TABLE Temporada IS 'Periodos turísticos por año (alta, media, baja). Cada día del calendario pertenece a una sola temporada';

CREATE TABLE Cliente (
    id_cliente          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre              VARCHAR2(150) NOT NULL,
    documento_identidad VARCHAR2(20)  NOT NULL,
    correo              VARCHAR2(100) NOT NULL,
    telefono            VARCHAR2(20)  NOT NULL,
    ciudad_origen       VARCHAR2(100) NOT NULL,
    CONSTRAINT uq_cliente_documento UNIQUE (documento_identidad),
    CONSTRAINT uq_cliente_correo    UNIQUE (correo)
);
COMMENT ON TABLE Cliente IS 'Datos personales de los turistas que realizan reservas';

-- -----------------------------------------------------------------------------
-- 2. Nivel intermedio
-- -----------------------------------------------------------------------------
CREATE TABLE Alojamiento (
    id_alojamiento      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_municipio        NUMBER NOT NULL,
    id_tipo_alojamiento NUMBER NOT NULL,
    nombre_comercial    VARCHAR2(150) NOT NULL,
    direccion           VARCHAR2(200) NOT NULL,
    calificacion        NUMBER(1) NOT NULL,
    contacto            VARCHAR2(100) NOT NULL,
    CONSTRAINT chk_alojamiento_estrellas CHECK (calificacion BETWEEN 1 AND 5),
    CONSTRAINT uq_alojamiento_nombre     UNIQUE (nombre_comercial),
    CONSTRAINT fk_alojamiento_municipio  FOREIGN KEY (id_municipio)
        REFERENCES Municipio(id_municipio),
    CONSTRAINT fk_alojamiento_tipo       FOREIGN KEY (id_tipo_alojamiento)
        REFERENCES Tipo_Alojamiento(id_tipo_alojamiento)
);
COMMENT ON TABLE Alojamiento IS 'Establecimientos de hospedaje registrados en la plataforma; la calificación son las estrellas que el alojamiento se autoasigna';

CREATE TABLE Reserva (
    id_reserva    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_cliente    NUMBER NOT NULL,
    fecha_reserva DATE NOT NULL,
    estado        VARCHAR2(50) NOT NULL,
    CONSTRAINT chk_reserva_estado CHECK (estado IN ('pendiente', 'confirmada', 'cancelada', 'completada')),
    CONSTRAINT fk_reserva_cliente FOREIGN KEY (id_cliente) REFERENCES Cliente(id_cliente)
);
COMMENT ON TABLE Reserva IS 'Cabecera de las reservas realizadas por los clientes; las fechas viven en cada línea de RESERVA_HABITACION';

-- -----------------------------------------------------------------------------
-- 3. Nivel de detalle
-- -----------------------------------------------------------------------------
CREATE TABLE Usuario_Sistema (
    id_usuario     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_alojamiento NUMBER,
    nombre         VARCHAR2(150) NOT NULL,
    correo         VARCHAR2(100) NOT NULL,
    rol            VARCHAR2(50)  NOT NULL,
    CONSTRAINT chk_usuario_rol CHECK (rol IN ('administrador', 'encargado')),
    -- El administrador es de toda la plataforma; el encargado, de un alojamiento.
    CONSTRAINT chk_usuario_rol_alojamiento CHECK (
        (rol = 'administrador' AND id_alojamiento IS NULL) OR
        (rol = 'encargado'     AND id_alojamiento IS NOT NULL)),
    CONSTRAINT uq_usuario_correo UNIQUE (correo),
    CONSTRAINT fk_usuario_alojamiento FOREIGN KEY (id_alojamiento)
        REFERENCES Alojamiento(id_alojamiento)
);
COMMENT ON TABLE Usuario_Sistema IS 'Usuarios internos: administradores de la plataforma y encargados de cada alojamiento';

CREATE TABLE Servicio (
    id_servicio    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_alojamiento NUMBER NOT NULL,
    nombre         VARCHAR2(100) NOT NULL,
    descripcion    VARCHAR2(500) NOT NULL,
    precio         NUMBER NOT NULL,
    CONSTRAINT chk_servicio_precio      CHECK (precio > 0),
    CONSTRAINT uq_servicio_alojamiento  UNIQUE (id_alojamiento, nombre),
    CONSTRAINT fk_servicio_alojamiento  FOREIGN KEY (id_alojamiento)
        REFERENCES Alojamiento(id_alojamiento)
);
COMMENT ON TABLE Servicio IS 'Servicios complementarios propios de cada alojamiento (el desayuno del hotel X no es el del hotel Y)';

CREATE TABLE Habitacion (
    id_habitacion  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_alojamiento NUMBER NOT NULL,
    numero         NUMBER NOT NULL,
    capacidad      NUMBER NOT NULL,
    tipo           VARCHAR2(50)  NOT NULL,
    descripcion    VARCHAR2(500) NOT NULL,
    CONSTRAINT chk_habitacion_tipo      CHECK (tipo IN ('sencilla', 'doble', 'suite', 'cabagna')),
    CONSTRAINT chk_habitacion_capacidad CHECK (capacidad > 0),
    CONSTRAINT uq_hab_alojamiento       UNIQUE (id_alojamiento, numero),
    CONSTRAINT fk_habitacion_alojamiento FOREIGN KEY (id_alojamiento)
        REFERENCES Alojamiento(id_alojamiento)
);
COMMENT ON TABLE Habitacion IS 'Inventario de habitaciones; el número se repite entre alojamientos pero no dentro del mismo';

-- -----------------------------------------------------------------------------
-- 4. Tablas transaccionales y de cruce
-- -----------------------------------------------------------------------------
CREATE TABLE Tarifa (
    id_tarifa     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_habitacion NUMBER NOT NULL,
    id_temporada  NUMBER NOT NULL,
    valor_noche   NUMBER NOT NULL,
    CONSTRAINT chk_tarifa_valor  CHECK (valor_noche > 0),
    CONSTRAINT uq_tarifa_unica   UNIQUE (id_habitacion, id_temporada),
    CONSTRAINT fk_tarifa_habitacion FOREIGN KEY (id_habitacion) REFERENCES Habitacion(id_habitacion),
    CONSTRAINT fk_tarifa_temporada  FOREIGN KEY (id_temporada)  REFERENCES Temporada(id_temporada)
);
COMMENT ON TABLE Tarifa IS 'Valor por noche de cada habitación en cada temporada (cruce habitación x temporada)';

CREATE TABLE Auditoria_Tarifa (
    id_auditoria   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tarifa      NUMBER NOT NULL,
    usuario        VARCHAR2(128) NOT NULL,
    fecha_cambio   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    operacion      VARCHAR2(10) NOT NULL,
    valor_anterior NUMBER,
    valor_nuevo    NUMBER,
    CONSTRAINT chk_auditoria_tarifa_operacion
        CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE'))
);
COMMENT ON TABLE Auditoria_Tarifa IS 'Auditoría de cambios sobre TARIFA: quién, cuándo, valor anterior y nuevo (la llena el disparador de la Entrega 2)';

CREATE TABLE Reserva_Habitacion (
    id_reserva_habitacion  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva             NUMBER NOT NULL,
    id_habitacion          NUMBER NOT NULL,
    checkin                DATE NOT NULL,
    checkout               DATE NOT NULL,
    precio_noche_calculado NUMBER NOT NULL,
    CONSTRAINT chk_fechas_reserva       CHECK (checkin < checkout),
    CONSTRAINT chk_precio_noche         CHECK (precio_noche_calculado > 0),
    CONSTRAINT uq_reserva_habitacion    UNIQUE (id_reserva, id_habitacion),
    CONSTRAINT fk_rh_reserva    FOREIGN KEY (id_reserva)    REFERENCES Reserva(id_reserva),
    CONSTRAINT fk_rh_habitacion FOREIGN KEY (id_habitacion) REFERENCES Habitacion(id_habitacion)
);
COMMENT ON TABLE Reserva_Habitacion IS 'Líneas de la reserva: cada habitación con sus propias fechas y el precio promedio por noche calculado desde TARIFA';

CREATE TABLE Reserva_Servicio (
    id_reserva_servicio NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva          NUMBER NOT NULL,
    id_servicio         NUMBER NOT NULL,
    cantidad            NUMBER NOT NULL,
    precio_cobrado      NUMBER NOT NULL,
    CONSTRAINT chk_cantidad              CHECK (cantidad > 0),
    CONSTRAINT chk_precio_cobrado        CHECK (precio_cobrado > 0),
    CONSTRAINT uq_reserva_servicio       UNIQUE (id_reserva, id_servicio),
    CONSTRAINT fk_rs_reserva  FOREIGN KEY (id_reserva)  REFERENCES Reserva(id_reserva),
    CONSTRAINT fk_rs_servicio FOREIGN KEY (id_servicio) REFERENCES Servicio(id_servicio)
);
COMMENT ON TABLE Reserva_Servicio IS 'Servicios contratados en la reserva; precio_cobrado es el valor unitario y el total de la línea es cantidad x precio_cobrado';

CREATE TABLE Pago (
    id_pago    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva NUMBER NOT NULL,
    fecha      DATE NOT NULL,
    monto      NUMBER NOT NULL,
    metodo     VARCHAR2(50) NOT NULL,
    estado     VARCHAR2(50) NOT NULL,
    CONSTRAINT chk_pago_monto  CHECK (monto > 0),
    CONSTRAINT chk_pago_metodo CHECK (metodo IN ('tarjeta de credito', 'tarjeta debito', 'PSE', 'transferencia', 'efectivo')),
    CONSTRAINT chk_pago_estado CHECK (estado IN ('exitoso', 'fallido', 'pendiente', 'reembolsado')),
    CONSTRAINT fk_pago_reserva FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva)
);
COMMENT ON TABLE Pago IS 'Pagos y abonos de cada reserva (anticipo + saldo); un reembolso se registra como una fila en estado reembolsado';

CREATE TABLE Resena (
    id_resena    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva   NUMBER NOT NULL,
    calificacion NUMBER(1) NOT NULL,
    comentario   VARCHAR2(1000),
    CONSTRAINT chk_calificacion   CHECK (calificacion BETWEEN 1 AND 5),
    CONSTRAINT uq_resena_reserva  UNIQUE (id_reserva),
    CONSTRAINT fk_resena_reserva  FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva)
);
COMMENT ON TABLE Resena IS 'Reseña del cliente sobre una reserva completada: calificación de 1 a 5 y comentario opcional';
