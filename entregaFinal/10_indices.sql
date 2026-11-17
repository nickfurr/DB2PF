-- =============================================================================
-- ENTREGA 3 - TurismoUQ
-- 03. Indices y planes de ejecucion (3 consultas lentas + caso donde no ayuda).
-- Ejecutar con F5 en SQL Developer conectado con el usuario del proyecto.
-- =============================================================================
SET LINESIZE 250
SET PAGESIZE 100
COLUMN plan_table_output FORMAT A150

-- Limpieza previa (por si los indices ya existian de una corrida anterior)
BEGIN
    FOR i IN (SELECT index_name
                FROM user_indexes
               WHERE index_name IN ('IDX_RH_HABITACION', 'IDX_RH_HAB_CHECKIN',
                                    'FX_RH_MES_DIA', 'FX_RH_ANIO',
                                    'FX_CLIENTE_CORREO_UPPER', 'IDX_RESERVA_ESTADO')) LOOP
        EXECUTE IMMEDIATE 'DROP INDEX ' || i.index_name;
    END LOOP;
END;
/

-- -----------------------------------------------------------------------------
-- CONSULTA 1: historial de reservas de una habitacion especifica (llave
-- foranea sin indice automatico en Oracle). Sin indice obliga a recorrer toda
-- la tabla Reserva_Habitacion; con idx_rh_habitacion pasa a INDEX RANGE SCAN.
-- -----------------------------------------------------------------------------
PROMPT === CONSULTA 1 (ANTES): Busqueda por id_habitacion sin indice ===
EXPLAIN PLAN FOR
SELECT id_reserva, checkin, checkout, precio_noche_calculado
  FROM Reserva_Habitacion
 WHERE id_habitacion = 150;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- Indice sobre llave foranea
CREATE INDEX idx_rh_habitacion ON Reserva_Habitacion (id_habitacion);

PROMPT === CONSULTA 1 (DESPUES): Con indice B-Tree idx_rh_habitacion ===
EXPLAIN PLAN FOR
SELECT id_reserva, checkin, checkout, precio_noche_calculado
  FROM Reserva_Habitacion
 WHERE id_habitacion = 150;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- -----------------------------------------------------------------------------
-- CONSULTA 2: reservas de una habitacion a partir de una fecha. Filtra por dos
-- columnas, se resuelve con un indice COMPUESTO (id_habitacion, checkin).
-- El orden importa: la columna lider (id_habitacion) va primero.
-- -----------------------------------------------------------------------------
-- Se borra el indice simple anterior para medir el efecto limpio del compuesto
DROP INDEX idx_rh_habitacion;

PROMPT === CONSULTA 2 (ANTES): Filtro por habitacion y fecha sin indice ===
EXPLAIN PLAN FOR
SELECT *
  FROM Reserva_Habitacion
 WHERE id_habitacion = 150
   AND checkin >= DATE '2025-06-01';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- Indice compuesto
CREATE INDEX idx_rh_hab_checkin ON Reserva_Habitacion (id_habitacion, checkin);

PROMPT === CONSULTA 2 (DESPUES): Con indice compuesto idx_rh_hab_checkin ===
EXPLAIN PLAN FOR
SELECT *
  FROM Reserva_Habitacion
 WHERE id_habitacion = 150
   AND checkin >= DATE '2025-06-01';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- -----------------------------------------------------------------------------
-- CONSULTA 3: busqueda de un cliente por correo sin importar mayusculas o
-- minusculas. Aunque Cliente.correo tiene un indice UNIQUE normal, al aplicarle
-- la funcion UPPER(correo) en el WHERE el indice normal queda inservible y
-- Oracle hace TABLE ACCESS FULL sobre los 3.000 clientes. Se resuelve creando
-- un indice BASADO EN FUNCION sobre UPPER(correo).
-- -----------------------------------------------------------------------------
PROMPT === CONSULTA 3 (ANTES): Busqueda con UPPER(correo) sin indice basado en funcion ===
EXPLAIN PLAN FOR
SELECT id_cliente, nombre, documento_identidad, correo, telefono
  FROM Cliente
 WHERE UPPER(correo) = 'CARLOS.RAMIREZ1@CORREO.COM';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- Indice basado en funcion sobre UPPER(correo)
CREATE INDEX fx_cliente_correo_upper ON Cliente (UPPER(correo));

PROMPT === CONSULTA 3 (DESPUES): Con indice basado en funcion fx_cliente_correo_upper ===
EXPLAIN PLAN FOR
SELECT id_cliente, nombre, documento_identidad, correo, telefono
  FROM Cliente
 WHERE UPPER(correo) = 'CARLOS.RAMIREZ1@CORREO.COM';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- -----------------------------------------------------------------------------
-- CASO DONDE EL INDICE NO AYUDA: filtrar Reserva por estado = 'completada'.
-- 'estado' tiene solo 4 valores distintos y 'completada' devuelve mas del 70 %
-- de las 25.000 reservas. Leer esa cantidad de filas por indice saltando al
-- ROWID bloque por bloque cuesta mucho mas que leer la tabla de corrido, asi
-- que el optimizador IGNORA el indice y mantiene TABLE ACCESS FULL.
-- -----------------------------------------------------------------------------
PROMPT === CASO DONDE NO AYUDA (ANTES): Filtro por estado = completada sin indice ===
EXPLAIN PLAN FOR
SELECT *
  FROM Reserva
 WHERE estado = 'completada';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

CREATE INDEX idx_reserva_estado ON Reserva (estado);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA', cascade => TRUE);

PROMPT === CASO DONDE NO AYUDA (DESPUES): Con idx_reserva_estado (sigue en TABLE ACCESS FULL) ===
EXPLAIN PLAN FOR
SELECT *
  FROM Reserva
 WHERE estado = 'completada';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- Ver los indices creados
SELECT table_name, index_name, index_type, uniqueness
  FROM user_indexes
 WHERE table_name IN ('RESERVA_HABITACION', 'CLIENTE', 'RESERVA')
 ORDER BY table_name, index_name;

-- Limpieza (para volver a ejecutar en limpio):
-- DROP INDEX idx_rh_hab_checkin;
-- DROP INDEX fx_cliente_correo_upper;
-- DROP INDEX idx_reserva_estado;