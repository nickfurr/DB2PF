-- 1. Tablas independientes (No dependen de ninguna otra)
CREATE TABLE Municipio (
    id_municipio NUMBER PRIMARY KEY,
    nombre VARCHAR2(100)
);

CREATE TABLE Tipo_Alojamiento (
    id_tipo_alojamiento NUMBER PRIMARY KEY,
    nombre VARCHAR2(100)
);

CREATE TABLE Temporada (
    id_temporada NUMBER PRIMARY KEY,
    nombre VARCHAR2(100),
    tipo VARCHAR2(50),
    fecha_inicio DATE,
    fecha_fin DATE
);

CREATE TABLE Cliente (
    id_cliente NUMBER PRIMARY KEY,
    nombre VARCHAR2(150),
    documento_identidad VARCHAR2(20),
    correo VARCHAR2(100),
    telefono VARCHAR2(20),
    ciudad_origen VARCHAR2(100)
);

-- 2. Nivel intermedio (Dependen de las tablas independientes)
CREATE TABLE Alojamiento (
    id_alojamiento NUMBER PRIMARY KEY,
    id_municipio NUMBER,
    id_tipo_alojamiento NUMBER,
    nombre_comercial VARCHAR2(150),
    direccion VARCHAR2(200),
    calificacion NUMBER,
    contacto VARCHAR2(100),
    FOREIGN KEY (id_municipio) REFERENCES Municipio(id_municipio),
    FOREIGN KEY (id_tipo_alojamiento) REFERENCES Tipo_Alojamiento(id_tipo_alojamiento)
);

CREATE TABLE Reserva (
    id_reserva NUMBER PRIMARY KEY,
    id_cliente NUMBER,
    fecha_reserva DATE,
    estado VARCHAR2(50),
    CONSTRAINT chk_reserva_estado CHECK (estado IN ('pendiente', 'confirmada', 'cancelada', 'completada')),
    FOREIGN KEY (id_cliente) REFERENCES Cliente(id_cliente)
);

-- 3. Nivel de detalle (Dependen de Alojamiento y Reserva)
CREATE TABLE Usuario_Sistema (
    id_usuario NUMBER PRIMARY KEY,
    id_alojamiento NUMBER,
    nombre VARCHAR2(150),
    correo VARCHAR2(100),
    rol VARCHAR2(50),
    FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento)
);

CREATE TABLE Servicio (
    id_servicio NUMBER PRIMARY KEY,
    id_alojamiento NUMBER,
    nombre VARCHAR2(100),
    descripcion VARCHAR2(500),
    precio NUMBER,
    FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento)
);

CREATE TABLE Habitacion (
    id_habitacion NUMBER PRIMARY KEY,
    id_alojamiento NUMBER,
    numero NUMBER,
    capacidad NUMBER,
    tipo VARCHAR2(50),
    descripcion VARCHAR2(500),
    CONSTRAINT chk_habitacion_tipo CHECK (tipo IN ('sencilla', 'doble', 'suite', 'cabaña')),
    FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento)
);

-- 4. Tablas transaccionales y de cruce final
CREATE TABLE Tarifa (
    id_tarifa NUMBER PRIMARY KEY,
    id_habitacion NUMBER,
    id_temporada NUMBER,
    valor_noche NUMBER,
    FOREIGN KEY (id_habitacion) REFERENCES Habitacion(id_habitacion),
    FOREIGN KEY (id_temporada) REFERENCES Temporada(id_temporada)
);

CREATE TABLE Reserva_Habitacion (
    id_reserva_habitacion NUMBER PRIMARY KEY,
    id_reserva NUMBER,
    id_habitacion NUMBER,
    checkin DATE,
    checkout DATE,
    precio_noche_calculado NUMBER,
    CONSTRAINT chk_fechas_reserva CHECK (checkin < checkout),
    FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva),
    FOREIGN KEY (id_habitacion) REFERENCES Habitacion(id_habitacion)
);

CREATE TABLE Reserva_Servicio (
    id_reserva_servicio NUMBER PRIMARY KEY,
    id_reserva NUMBER,
    id_servicio NUMBER,
    cantidad NUMBER,
    precio_cobrado NUMBER,
    FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva),
    FOREIGN KEY (id_servicio) REFERENCES Servicio(id_servicio)
);

CREATE TABLE Pago (
    id_pago NUMBER PRIMARY KEY,
    id_reserva NUMBER,
    fecha DATE,
    monto NUMBER,
    metodo VARCHAR2(50),
    estado VARCHAR2(50),
    CONSTRAINT chk_pago_metodo CHECK (metodo IN ('tarjeta de crédito', 'tarjeta débito', 'PSE', 'transferencia', 'efectivo')),
    CONSTRAINT chk_pago_estado CHECK (estado IN ('exitoso', 'fallido', 'pendiente', 'reembolsado')),
    FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva)
);

CREATE TABLE Resena (
    id_resena NUMBER PRIMARY KEY,
    id_reserva NUMBER,
    calificacion NUMBER,
    comentario VARCHAR2(1000),
    FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva)
);