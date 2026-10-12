-- 1. Tablas independientes (No dependen de ninguna otra)
CREATE TABLE Municipio (
    id_municipio NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL
);
CREATE TABLE Tipo_Alojamiento (
    id_tipo_alojamiento NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL
);
CREATE TABLE Temporada (
    id_temporada NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    tipo VARCHAR2(50) NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL
);
CREATE TABLE Cliente (
    id_cliente NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR2(150) NOT NULL,
    documento_identidad VARCHAR2(20) NOT NULL UNIQUE,
    correo VARCHAR2(100) NOT NULL,
    telefono VARCHAR2(20) NOT NULL,
    ciudad_origen VARCHAR2(100) NOT NULL
);
-- 2. Nivel intermedio (Dependen de las tablas independientes)
CREATE TABLE Alojamiento (
    id_alojamiento NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_municipio NUMBER NOT NULL,
    id_tipo_alojamiento NUMBER NOT NULL,
    nombre_comercial VARCHAR2(150) NOT NULL,
    direccion VARCHAR2(200) NOT NULL,
    calificacion NUMBER NOT NULL,
    contacto VARCHAR2(100) NOT NULL,
    FOREIGN KEY (id_municipio) REFERENCES Municipio(id_municipio),
    FOREIGN KEY (id_tipo_alojamiento) REFERENCES Tipo_Alojamiento(id_tipo_alojamiento)
);
CREATE TABLE Reserva (
    id_reserva NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_cliente NUMBER NOT NULL,
    fecha_reserva DATE NOT NULL,
    estado VARCHAR2(50) NOT NULL,
    CONSTRAINT chk_reserva_estado CHECK (
        estado IN (
            'pendiente',
            'confirmada',
            'cancelada',
            'completada'
        )
    ),
    FOREIGN KEY (id_cliente) REFERENCES Cliente(id_cliente)
);
-- 3. Nivel de detalle (Dependen de Alojamiento y Reserva)
CREATE TABLE Usuario_Sistema (
    id_usuario NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_alojamiento NUMBER NOT NULL,
    nombre VARCHAR2(150) NOT NULL,
    correo VARCHAR2(100) NOT NULL,
    rol VARCHAR2(50) NOT NULL,
    FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento)
);
CREATE TABLE Servicio (
    id_servicio NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_alojamiento NUMBER NOT NULL,
    nombre VARCHAR2(100) NOT NULL,
    descripcion VARCHAR2(500) NOT NULL,
    precio NUMBER NOT NULL,
    FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento)
);
CREATE TABLE Habitacion (
    id_habitacion NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_alojamiento NUMBER NOT NULL,
    numero NUMBER NOT NULL,
    capacidad NUMBER NOT NULL,
    tipo VARCHAR2(50) NOT NULL,
    descripcion VARCHAR2(500) NOT NULL,
    CONSTRAINT chk_habitacion_tipo CHECK (tipo IN ('sencilla', 'doble', 'suite', 'cabaña')),
    FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento)
);
-- 4. Tablas transaccionales y de cruce final
CREATE TABLE Tarifa (
    id_tarifa NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_habitacion NUMBER NOT NULL,
    id_temporada NUMBER NOT NULL,
    valor_noche NUMBER NOT NULL,
    FOREIGN KEY (id_habitacion) REFERENCES Habitacion(id_habitacion),
    FOREIGN KEY (id_temporada) REFERENCES Temporada(id_temporada)
);
CREATE TABLE Reserva_Habitacion (
    id_reserva_habitacion NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva NUMBER NOT NULL,
    id_habitacion NUMBER NOT NULL,
    checkin DATE NOT NULL,
    checkout DATE NOT NULL,
    precio_noche_calculado NUMBER NOT NULL,
    CONSTRAINT chk_fechas_reserva CHECK (checkin < checkout),
    FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva),
    FOREIGN KEY (id_habitacion) REFERENCES Habitacion(id_habitacion)
);
CREATE TABLE Reserva_Servicio (
    id_reserva_servicio NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva NUMBER NOT NULL,
    id_servicio NUMBER NOT NULL,
    cantidad NUMBER NOT NULL,
    precio_cobrado NUMBER NOT NULL,
    FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva),
    FOREIGN KEY (id_servicio) REFERENCES Servicio(id_servicio)
);
CREATE TABLE Pago (
    id_pago NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva NUMBER NOT NULL,
    fecha DATE NOT NULL,
    monto NUMBER NOT NULL,
    metodo VARCHAR2(50) NOT NULL,
    estado VARCHAR2(50) NOT NULL,
    CONSTRAINT chk_pago_metodo CHECK (
        metodo IN (
            'tarjeta de crédito',
            'tarjeta débito',
            'PSE',
            'transferencia',
            'efectivo'
        )
    ),
    CONSTRAINT chk_pago_estado CHECK (
        estado IN ('exitoso', 'fallido', 'pendiente', 'reembolsado')
    ),
    FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva)
);
CREATE TABLE Resena (
    id_resena NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva NUMBER NOT NULL,
    calificacion NUMBER NOT NULL,
    comentario VARCHAR2(1000) NOT NULL,
    FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva)
);