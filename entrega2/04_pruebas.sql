-- ENTREGA 2 - TurismoUQ
-- 04. Pruebas de cada objeto. Ejecutar despues de 01, 02, 03a (SYSTEM) y 03b.
--     Todo se deshace con ROLLBACK (la prueba 7f limpia lo que crea).

SET SERVEROUTPUT ON
SET LINESIZE 200

-- =============================================================================
-- Prueba 1: fn_valor_estadia
-- Habitacion de prueba: la 101 del Hotel El Mirador (Armenia), id 1 en una
-- carga limpia. Este hotel casi no sube su precio en temporada alta: compite
-- por volumen, como permite el enunciado.
-- =============================================================================

-- 1a. Cuatro estadias: el valor de la funcion se compara con el valor
--     esperado y con un calculo independiente hecho por tramos de temporada
--     (noches de la estadia dentro de cada temporada x tarifa).
--     Las cuatro filas deben salir con resultado = OK.
WITH hab AS (
    SELECT h.id_habitacion
      FROM Habitacion h
      JOIN Alojamiento a ON a.id_alojamiento = h.id_alojamiento
     WHERE a.nombre_comercial = 'Hotel El Mirador' AND h.numero = 101
),
casos AS (
    SELECT 1 AS caso, 'Una sola temporada (baja)'                AS descripcion,
           DATE '2025-02-10' AS f_in, DATE '2025-02-13' AS f_out,  642000 AS esperado FROM dual UNION ALL
    SELECT 2, 'Cruza alta -> baja (fin de la temporada de enero)',
           DATE '2025-01-10', DATE '2025-01-15', 1127000 FROM dual UNION ALL
    SELECT 3, 'Cruza media -> alta -> media (Semana Santa 2025)',
           DATE '2025-04-10', DATE '2025-04-23', 3167000 FROM dual UNION ALL
    SELECT 4, 'Cruza media -> alta (inicio de diciembre-enero 2024)',
           DATE '2024-12-13', DATE '2024-12-17',  910000 FROM dual
)
SELECT c.caso,
       c.descripcion,
       TO_CHAR(c.f_in, 'YYYY-MM-DD')  AS checkin,
       TO_CHAR(c.f_out, 'YYYY-MM-DD') AS checkout,
       c.f_out - c.f_in               AS noches,
       pkg_turismo.fn_valor_estadia(hab.id_habitacion, c.f_in, c.f_out) AS valor_funcion,
       (SELECT SUM((LEAST(c.f_out, t.fecha_fin + 1) - GREATEST(c.f_in, t.fecha_inicio)) * tar.valor_noche)
          FROM Temporada t
          JOIN Tarifa tar ON tar.id_temporada  = t.id_temporada
                         AND tar.id_habitacion = hab.id_habitacion
         WHERE t.fecha_inicio < c.f_out
           AND t.fecha_fin   >= c.f_in)                               AS valor_por_tramos,
       c.esperado,
       CASE WHEN pkg_turismo.fn_valor_estadia(hab.id_habitacion, c.f_in, c.f_out) = c.esperado
            THEN 'OK' ELSE 'FALLA' END                                AS resultado
  FROM casos c CROSS JOIN hab
 ORDER BY c.caso;

-- 1b. Desglose noche por noche de las estadias que cruzan temporadas.
DECLARE
    v_hab Habitacion.id_habitacion%TYPE;
BEGIN
    SELECT h.id_habitacion INTO v_hab
      FROM Habitacion h
      JOIN Alojamiento a ON a.id_alojamiento = h.id_alojamiento
     WHERE a.nombre_comercial = 'Hotel El Mirador' AND h.numero = 101;

    pkg_turismo.sp_desglose_estadia(v_hab, DATE '2025-01-10', DATE '2025-01-15');
    DBMS_OUTPUT.PUT_LINE('');
    pkg_turismo.sp_desglose_estadia(v_hab, DATE '2025-04-10', DATE '2025-04-23');
END;
/

-- 1c. Casos de error: cada uno debe mostrar su codigo ORA-200xx.
--     Para -20005 y -20006 se altera TARIFA / TEMPORADA dentro de la prueba y
--     se deshace al final con ROLLBACK.
DECLARE
    v_hab  Habitacion.id_habitacion%TYPE;
    v_temp Temporada.id_temporada%TYPE;
    v_val  NUMBER;

    PROCEDURE probar (p_caso VARCHAR2, p_hab NUMBER, p_in DATE, p_out DATE) IS
    BEGIN
        v_val := pkg_turismo.fn_valor_estadia(p_hab, p_in, p_out);
        DBMS_OUTPUT.PUT_LINE(RPAD(p_caso, 38) || ' -> SIN ERROR, valor ' || v_val || ' (no esperado)');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE(RPAD(p_caso, 38) || ' -> ' || SQLERRM);
    END;
BEGIN
    SELECT h.id_habitacion INTO v_hab
      FROM Habitacion h
      JOIN Alojamiento a ON a.id_alojamiento = h.id_alojamiento
     WHERE a.nombre_comercial = 'Hotel El Mirador' AND h.numero = 101;

    probar('Parametro nulo (-20000)',            v_hab, NULL, DATE '2025-02-13');
    probar('Checkout igual al checkin (-20001)', v_hab, DATE '2025-02-10', DATE '2025-02-10');
    probar('Checkout antes del checkin (-20001)', v_hab, DATE '2025-02-13', DATE '2025-02-10');
    probar('Habitacion inexistente (-20003)',    999999, DATE '2025-02-10', DATE '2025-02-13');
    probar('Noches sin temporada (-20002)',      v_hab, DATE '2030-01-01', DATE '2030-01-03');

    -- Sin tarifa: se borra la tarifa de la temporada de febrero 2025.
    SELECT id_temporada INTO v_temp
      FROM Temporada
     WHERE DATE '2025-02-11' BETWEEN fecha_inicio AND fecha_fin;
    DELETE FROM Tarifa WHERE id_habitacion = v_hab AND id_temporada = v_temp;
    probar('Habitacion sin tarifa (-20005)',     v_hab, DATE '2025-02-10', DATE '2025-02-13');
    ROLLBACK;

    -- Temporadas solapadas: una temporada de un dia encima de otra.
    INSERT INTO Temporada (nombre, tipo, fecha_inicio, fecha_fin)
    VALUES ('Temporada de prueba solapada', 'alta', DATE '2025-02-11', DATE '2025-02-11')
    RETURNING id_temporada INTO v_temp;
    INSERT INTO Tarifa (id_habitacion, id_temporada, valor_noche) VALUES (v_hab, v_temp, 999000);
    probar('Temporadas solapadas (-20006)',      v_hab, DATE '2025-02-10', DATE '2025-02-13');
    ROLLBACK;
END;
/

-- Prueba 2: sp_crear_reserva, caso valido (busca una ventana libre).
DECLARE
    v_in  DATE;
    v_res Reserva.id_reserva%TYPE;
BEGIN
    SELECT d INTO v_in FROM (
        SELECT DATE '2025-01-10' + (LEVEL - 1) AS d
          FROM dual CONNECT BY LEVEL <= 300
    ) x
    WHERE NOT EXISTS (
        SELECT 1 FROM Reserva_Habitacion rh JOIN Reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = 1 AND r.estado = 'confirmada'
           AND x.d < rh.checkout AND x.d + 3 > rh.checkin)
      AND ROWNUM = 1;

    pkg_turismo.sp_crear_reserva(
        p_id_cliente => 1, p_id_habitacion => 1, p_cantidad_huespedes => 1,
        p_checkin => v_in, p_checkout => v_in + 3, p_id_reserva => v_res);

    DBMS_OUTPUT.PUT_LINE('OK -> reserva creada id=' || v_res ||
        ' (' || TO_CHAR(v_in, 'YYYY-MM-DD') || ' -> ' || TO_CHAR(v_in + 3, 'YYYY-MM-DD') || ')');
END;
/
ROLLBACK;

-- Prueba 3: sp_crear_reserva, excepciones (20011, 20014, 20013, 20012, 20010).
DECLARE
    v_res Reserva.id_reserva%TYPE;
    v_in  DATE;
    PROCEDURE intentar (p_caso VARCHAR2, p_hab NUMBER, p_hue NUMBER, p_in DATE, p_out DATE) IS
    BEGIN
        pkg_turismo.sp_crear_reserva(1, p_hab, p_hue, p_in, p_out, v_res);
        DBMS_OUTPUT.PUT_LINE(p_caso || ' -> creada id=' || v_res);
    EXCEPTION
        WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE(p_caso || ' -> ' || SQLERRM);
    END;
BEGIN
    intentar('3a fechas ', 1, 1, DATE '2025-05-10', DATE '2025-05-10');
    intentar('3b cantidad', 1, 0, DATE '2025-05-10', DATE '2025-05-13');
    intentar('3c no exist', 999999, 1, DATE '2025-05-10', DATE '2025-05-13');
    intentar('3d capac.  ', 1, 999, DATE '2025-05-10', DATE '2025-05-13');

    SELECT d INTO v_in FROM (
        SELECT DATE '2025-06-01' + (LEVEL - 1) AS d FROM dual CONNECT BY LEVEL <= 200
    ) x
    WHERE NOT EXISTS (
        SELECT 1 FROM Reserva_Habitacion rh JOIN Reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = 1 AND r.estado = 'confirmada'
           AND x.d < rh.checkout AND x.d + 4 > rh.checkin)
      AND ROWNUM = 1;
    pkg_turismo.sp_crear_reserva(1, 1, 1, v_in, v_in + 3, v_res);
    intentar('3e solape ', 1, 1, v_in + 1, v_in + 4);
END;
/
ROLLBACK;

-- Prueba 4: sp_liquidacion_mensual.
BEGIN
    pkg_turismo.sp_liquidacion_mensual(2025, 7);
END;
/

-- =============================================================================
-- Prueba 5: trg_auditoria_tarifa (disparador compuesto, auditoria por sentencia)
-- Se ejecutan cuatro sentencias sobre TARIFA y se muestra lo que quedo
-- auditado. Al final se hace ROLLBACK, asi que no cambia ningun precio.
--   5a. UPDATE de una sola tarifa                -> 1 fila de auditoria
--   5b. UPDATE de las tarifas de Semana Santa 2026 del Hotel El Mirador
--       (40 habitaciones, una sola sentencia)     -> 40 filas, misma fecha_cambio
--   5c. UPDATE que deja el mismo precio          -> 0 filas
--   5d. INSERT y DELETE de una tarifa            -> 1 fila INSERT y 1 fila DELETE
-- =============================================================================
COLUMN usuario FORMAT A30
COLUMN sentencia_ejecutada FORMAT A23
VARIABLE v_desde NUMBER
EXEC SELECT NVL(MAX(id_auditoria), 0) INTO :v_desde FROM Auditoria_Tarifa;

-- 5a. Una tarifa: +5 %
UPDATE Tarifa
   SET valor_noche = ROUND(valor_noche * 1.05, -3)
 WHERE id_tarifa = (SELECT MIN(id_tarifa) FROM Tarifa);

-- 5b. Muchas tarifas en una sola sentencia: +10 % en Semana Santa 2026
UPDATE Tarifa
   SET valor_noche = ROUND(valor_noche * 1.10, -3)
 WHERE id_temporada = (SELECT id_temporada FROM Temporada WHERE nombre = 'Semana Santa 2026')
   AND id_habitacion IN (SELECT h.id_habitacion
                           FROM Habitacion h
                           JOIN Alojamiento a ON a.id_alojamiento = h.id_alojamiento
                          WHERE a.nombre_comercial = 'Hotel El Mirador');

-- 5c. Sin cambio real de precio: no debe auditarse
UPDATE Tarifa
   SET valor_noche = valor_noche
 WHERE id_tarifa = (SELECT MAX(id_tarifa) FROM Tarifa);

-- 5d. INSERT y DELETE (sobre una temporada creada solo para la prueba)
INSERT INTO Temporada (nombre, tipo, fecha_inicio, fecha_fin)
VALUES ('Temporada de prueba auditoria', 'alta', DATE '2030-01-01', DATE '2030-01-31');

INSERT INTO Tarifa (id_habitacion, id_temporada, valor_noche)
VALUES ((SELECT MIN(id_habitacion) FROM Habitacion),
        (SELECT id_temporada FROM Temporada WHERE nombre = 'Temporada de prueba auditoria'),
        500000);

DELETE FROM Tarifa
 WHERE id_temporada = (SELECT id_temporada FROM Temporada WHERE nombre = 'Temporada de prueba auditoria');

-- Resumen por sentencia: cada grupo comparte usuario y fecha_cambio
-- Debe salir: UPDATE 1 fila, UPDATE 40 filas, INSERT 1 fila, DELETE 1 fila.
SELECT TO_CHAR(fecha_cambio, 'YYYY-MM-DD HH24:MI:SS.FF3') AS sentencia_ejecutada,
       operacion,
       usuario,
       COUNT(*) AS filas_auditadas
  FROM Auditoria_Tarifa
 WHERE id_auditoria > :v_desde
 GROUP BY fecha_cambio, operacion, usuario
 ORDER BY MIN(id_auditoria);

-- Detalle: quien, cuando, valor anterior y nuevo (primeras 10 filas)
SELECT id_auditoria, id_tarifa, operacion, valor_anterior, valor_nuevo, usuario,
       TO_CHAR(fecha_cambio, 'YYYY-MM-DD HH24:MI:SS.FF3') AS fecha_cambio
  FROM Auditoria_Tarifa
 WHERE id_auditoria > :v_desde
 ORDER BY id_auditoria
 FETCH FIRST 10 ROWS ONLY;

ROLLBACK;

-- =============================================================================
-- Prueba 6: trg_reserva_no_solape
-- Casos sobre reservas reales y sobre fechas de 2028 (sin reservas, asi el
-- resultado no depende de los datos cargados). Todo se deshace con ROLLBACK.
--   6a. Linea que se cruza con una reserva confirmada existente  -> ORA-20020
--   6b. Dos lineas solapadas en la MISMA transaccion, sin COMMIT  -> la 2a falla
--       (este caso pasaba con la version de transaccion autonoma)
--   6c. INSERT ... SELECT de dos filas que se solapan entre si    -> ORA-20020
--       (un disparador de fila simple daria ORA-04091, tabla mutante)
--   6d. UPDATE que mueve una linea encima de otra reserva         -> ORA-20020
--   6e. Linea que empieza el mismo dia en que termina otra        -> se acepta
-- =============================================================================
DECLARE
    v_cli   Cliente.id_cliente%TYPE;
    v_hab   Habitacion.id_habitacion%TYPE;
    v_hab2  Habitacion.id_habitacion%TYPE;
    v_r1    Reserva.id_reserva%TYPE;
    v_r2    Reserva.id_reserva%TYPE;
    v_r3    Reserva.id_reserva%TYPE;
    v_rh2   Reserva_Habitacion.id_reserva_habitacion%TYPE;
    v_ohab  Reserva_Habitacion.id_habitacion%TYPE;
    v_oin   Reserva_Habitacion.checkin%TYPE;
    v_oout  Reserva_Habitacion.checkout%TYPE;
    v_ores  Reserva_Habitacion.id_reserva%TYPE;

    FUNCTION nueva_reserva RETURN NUMBER IS
        v_id Reserva.id_reserva%TYPE;
    BEGIN
        INSERT INTO Reserva (id_cliente, fecha_reserva, estado)
        VALUES (v_cli, SYSDATE, 'confirmada')
        RETURNING id_reserva INTO v_id;
        RETURN v_id;
    END;

    PROCEDURE resultado (p_caso VARCHAR2, p_esperado VARCHAR2, p_obtenido VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD(p_caso, 44) || ' esperado: ' || RPAD(p_esperado, 9) ||
                             ' -> ' || p_obtenido);
    END;
BEGIN
    SELECT MIN(id_cliente) INTO v_cli FROM Cliente;
    SELECT MIN(h.id_habitacion), MAX(h.id_habitacion) INTO v_hab, v_hab2
      FROM Habitacion h
      JOIN Alojamiento a ON a.id_alojamiento = h.id_alojamiento
     WHERE a.nombre_comercial = 'Hotel El Mirador' AND h.numero IN (101, 102);

    v_r1 := nueva_reserva;
    v_r2 := nueva_reserva;
    v_r3 := nueva_reserva;

    -- 6a. Contra una reserva confirmada que ya existe en los datos
    SELECT rh.id_habitacion, rh.checkin, rh.checkout, rh.id_reserva
      INTO v_ohab, v_oin, v_oout, v_ores
      FROM Reserva_Habitacion rh
      JOIN Reserva r ON r.id_reserva = rh.id_reserva
     WHERE r.estado = 'confirmada'
       AND rh.id_reserva < v_r1
       AND ROWNUM = 1;
    BEGIN
        INSERT INTO Reserva_Habitacion (id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado)
        VALUES (v_r1, v_ohab, v_oin, v_oout, 100000);
        resultado('6a. Cruce con la reserva confirmada ' || v_ores, 'ORA-20020', 'SE ACEPTO (error)');
    EXCEPTION WHEN OTHERS THEN
        resultado('6a. Cruce con la reserva confirmada ' || v_ores, 'ORA-20020', SQLERRM);
    END;

    -- 6b. Misma transaccion: la primera linea entra, la segunda choca con ella
    INSERT INTO Reserva_Habitacion (id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado)
    VALUES (v_r1, v_hab, DATE '2028-03-01', DATE '2028-03-05', 100000);
    resultado('6b. Primera linea 2028-03-01 a 03-05', 'aceptada', 'aceptada (sin COMMIT)');
    BEGIN
        INSERT INTO Reserva_Habitacion (id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado)
        VALUES (v_r2, v_hab, DATE '2028-03-03', DATE '2028-03-06', 100000);
        resultado('6b. Segunda linea 2028-03-03 a 03-06', 'ORA-20020', 'SE ACEPTO (error)');
    EXCEPTION WHEN OTHERS THEN
        resultado('6b. Segunda linea 2028-03-03 a 03-06', 'ORA-20020', SQLERRM);
    END;

    -- 6c. Una sola sentencia con dos filas que se cruzan entre si
    BEGIN
        INSERT INTO Reserva_Habitacion (id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado)
        SELECT v_r2, v_hab2, DATE '2028-05-01', DATE '2028-05-04', 100000 FROM dual
        UNION ALL
        SELECT v_r3, v_hab2, DATE '2028-05-02', DATE '2028-05-06', 100000 FROM dual;
        resultado('6c. INSERT ... SELECT de 2 filas solapadas', 'ORA-20020', 'SE ACEPTO (error)');
    EXCEPTION WHEN OTHERS THEN
        resultado('6c. INSERT ... SELECT de 2 filas solapadas', 'ORA-20020', SQLERRM);
    END;

    -- 6d. UPDATE que mueve una linea libre encima de la de 6b
    INSERT INTO Reserva_Habitacion (id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado)
    VALUES (v_r2, v_hab, DATE '2028-03-10', DATE '2028-03-12', 100000)
    RETURNING id_reserva_habitacion INTO v_rh2;
    BEGIN
        UPDATE Reserva_Habitacion
           SET checkin = DATE '2028-03-04'
         WHERE id_reserva_habitacion = v_rh2;
        resultado('6d. UPDATE de checkin a 2028-03-04', 'ORA-20020', 'SE ACEPTO (error)');
    EXCEPTION WHEN OTHERS THEN
        resultado('6d. UPDATE de checkin a 2028-03-04', 'ORA-20020', SQLERRM);
    END;

    -- 6e. Llega el mismo dia en que sale la reserva de 6b (03-05): no es solape
    BEGIN
        INSERT INTO Reserva_Habitacion (id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado)
        VALUES (v_r3, v_hab, DATE '2028-03-05', DATE '2028-03-07', 100000);
        resultado('6e. Checkin 2028-03-05 = checkout de 6b', 'aceptada', 'aceptada');
    EXCEPTION WHEN OTHERS THEN
        resultado('6e. Checkin 2028-03-05 = checkout de 6b', 'aceptada', SQLERRM);
    END;

    ROLLBACK;
END;
/

-- =============================================================================
-- Prueba 7: tablespace del historico y mv_ocupacion_mensual
-- =============================================================================

-- 7a. Las reservas de 2024 y 2025 estan en TS_RESERVAS_HIST y las actuales no
SELECT s.segment_name AS tabla, s.partition_name AS particion, s.tablespace_name,
       ROUND(s.bytes / 1024 / 1024, 1) AS mb
  FROM user_segments s
 WHERE s.segment_name IN ('RESERVA', 'RESERVA_HABITACION')
 ORDER BY s.segment_name, s.partition_name;

-- 7b. Partition pruning: el plan de una consulta de 2026 solo lee P_ACTUAL
--     (columnas PSTART / PSTOP = 3)
EXPLAIN PLAN FOR
SELECT COUNT(*) FROM Reserva_Habitacion WHERE checkin >= DATE '2026-01-01';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +PARTITION'));

-- 7c. La vista cuadra con las tablas: total de noches ocupadas igual a la
--     suma de noches de las lineas confirmadas y completadas -> resultado OK
SELECT (SELECT SUM(noches_ocupadas) FROM mv_ocupacion_mensual) AS noches_vista,
       (SELECT SUM(rh.checkout - rh.checkin)
          FROM Reserva_Habitacion rh
          JOIN Reserva r ON r.id_reserva = rh.id_reserva
         WHERE r.estado IN ('confirmada', 'completada'))      AS noches_tablas,
       CASE WHEN (SELECT SUM(noches_ocupadas) FROM mv_ocupacion_mensual) =
                 (SELECT SUM(rh.checkout - rh.checkin)
                    FROM Reserva_Habitacion rh
                    JOIN Reserva r ON r.id_reserva = rh.id_reserva
                   WHERE r.estado IN ('confirmada', 'completada'))
            THEN 'OK' ELSE 'FALLA' END                         AS resultado
  FROM dual;

-- 7d. Ocupacion de julio de 2025 (temporada alta) por alojamiento
SELECT municipio, nombre_comercial, habitaciones, noches_ocupadas,
       noches_disponibles, pct_ocupacion
  FROM mv_ocupacion_mensual
 WHERE anio_mes = '2025-07'
 ORDER BY pct_ocupacion DESC
 FETCH FIRST 10 ROWS ONLY;

-- 7e. Ocupacion del departamento mes a mes (estacionalidad)
SELECT anio_mes,
       SUM(noches_ocupadas)    AS noches_ocupadas,
       SUM(noches_disponibles) AS noches_disponibles,
       ROUND(100 * SUM(noches_ocupadas) / SUM(noches_disponibles), 2) AS pct_ocupacion
  FROM mv_ocupacion_mensual
 GROUP BY anio_mes
 ORDER BY anio_mes;

-- 7f. Politica de refresco: la vista queda vieja con una reserva nueva y se
--     pone al dia con DBMS_MVIEW.REFRESH. Como REFRESH hace COMMIT, la reserva
--     de prueba se borra al final y se vuelve a refrescar.
DECLARE
    v_hab   Habitacion.id_habitacion%TYPE;
    v_cli   Cliente.id_cliente%TYPE;
    v_res   Reserva.id_reserva%TYPE;
    v_antes NUMBER;
    v_desp  NUMBER;
    v_aloj  Alojamiento.id_alojamiento%TYPE;

    FUNCTION noches_vista RETURN NUMBER IS
        v NUMBER;
    BEGIN
        SELECT noches_ocupadas INTO v
          FROM mv_ocupacion_mensual
         WHERE id_alojamiento = v_aloj AND anio_mes = '2028-02';
        RETURN v;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;   -- el mes aun no existe en la foto
    END;
BEGIN
    SELECT MIN(id_cliente) INTO v_cli FROM Cliente;
    SELECT h.id_habitacion, h.id_alojamiento INTO v_hab, v_aloj
      FROM Habitacion h
      JOIN Alojamiento a ON a.id_alojamiento = h.id_alojamiento
     WHERE a.nombre_comercial = 'Hotel El Mirador' AND h.numero = 101;

    -- Reserva de 3 noches en febrero de 2028 (sin tarifas: se inserta directo)
    INSERT INTO Reserva (id_cliente, fecha_reserva, estado)
    VALUES (v_cli, SYSDATE, 'confirmada')
    RETURNING id_reserva INTO v_res;
    INSERT INTO Reserva_Habitacion (id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado)
    VALUES (v_res, v_hab, DATE '2028-02-10', DATE '2028-02-13', 100000);
    COMMIT;

    v_antes := noches_vista;
    DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
    v_desp := noches_vista;

    DBMS_OUTPUT.PUT_LINE('Noches de feb-2028 en la vista ANTES del refresco:   ' || NVL(TO_CHAR(v_antes), 'el mes no existe'));
    DBMS_OUTPUT.PUT_LINE('Noches de feb-2028 en la vista DESPUES del refresco: ' || v_desp || ' (esperado 3)');

    -- Limpieza: se borra la reserva de prueba y se deja la vista como estaba
    DELETE FROM Reserva_Habitacion WHERE id_reserva = v_res;
    DELETE FROM Reserva WHERE id_reserva = v_res;
    COMMIT;
    DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
    DBMS_OUTPUT.PUT_LINE('Reserva de prueba eliminada y vista refrescada de nuevo.');
END;
/

SELECT mview_name, refresh_method, TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS ultimo_refresco,
       staleness
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';
