
\drs
-- ENTREGA 3 - TurismoUQ

+

-- CONSULTA 2: reservas de una habitacion a partir de una fecha. Filtra por dos
-- columnas, se resuelve con un indice COMPUESTO (id_habitacion, checkin).
-- El orden importa: la columna lider (id_habitacion) va primero.
-- Antes
EXPLAIN PLAN FOR
SELECT *
FROM Reserva_Habitacion
WHERE
    id_habitacion = 150
    AND checkin >= DATE '2025-06-01';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Indice compuesto
CREATE INDEX idx_rh_hab_checkin ON Reserva_Habitacion (id_habitacion, checkin);

-- Despues (usa el indice compuesto por las dos columnas)
EXPLAIN PLAN FOR
SELECT *
FROM Reserva_Habitacion
WHERE
    id_habitacion = 150
    AND checkin >= DATE '2025-06-01';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- CONSULTA 3: reservas de un ano. EXTRACT(YEAR FROM checkin) es una funcion
-- sobre la columna, por eso un indice normal sobre checkin no sirve. Se crea un
-- indice FUNCIONAL sobre la misma expresion del WHERE.
-- Antes
EXPLAIN PLAN FOR
SELECT *
FROM Reserva_Habitacion
WHERE
    EXTRACT(
        YEAR
        FROM checkin
    ) = 2025;

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Indice funcional sobre la expresion
CREATE INDEX fx_rh_anio ON Reserva_Habitacion (
    EXTRACT(
        YEAR
        FROM checkin
    )
);

-- Despues (ahora el filtro por ano puede usar el indice funcional)
EXPLAIN PLAN FOR
SELECT *
FROM Reserva_Habitacion
WHERE
    EXTRACT(
        YEAR
        FROM checkin
    ) = 2025;

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- CASO DONDE EL INDICE NO AYUDA: filtrar Reserva por estado.
-- 'estado' tiene muy pocos valores distintos (4) y 'confirmada' devuelve cerca
-- de un tercio de la tabla. Leer esa fraccion por indice, fila por fila y
-- saltando al ROWID, cuesta mas que leer la tabla de corrido, asi que el
-- optimizador IGNORA el indice y se queda en TABLE ACCESS FULL. Es baja
-- selectividad: un indice solo ayuda cuando devuelve pocas filas por valor.
EXPLAIN PLAN FOR SELECT * FROM Reserva WHERE estado = 'confirmada';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

CREATE INDEX idx_reserva_estado ON Reserva (estado);

-- Aun con el indice creado, el plan sigue en TABLE ACCESS FULL
EXPLAIN PLAN FOR SELECT * FROM Reserva WHERE estado = 'confirmada';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Ver los indices creados
SELECT index_name, uniqueness
FROM user_indexes
WHERE
    table_name IN (
        'RESERVA_HABITACION',
        'RESERVA'
    )
ORDER BY index_name;

-- Limpieza (para volver a ejecutar en limpio):
-- DROP INDEX idx_rh_habitacion;
-- DROP INDEX idx_rh_hab_checkin;
-- DROP INDEX fx_rh_anio;
-- DROP INDEX idx_reserva_estado;