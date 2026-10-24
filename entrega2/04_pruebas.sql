-- ENTREGA 2 - TurismoUQ
-- 04. Pruebas de cada objeto. Ejecutar despues de 01, 02 y 03. Todo con ROLLBACK.

SET SERVEROUTPUT ON
SET LINESIZE 200

-- Prueba 1: fn_valor_estadia (3 noches en temporada alta 2025).
SELECT pkg_turismo.fn_valor_estadia(1, DATE '2025-01-15', DATE '2025-01-18') AS valor_3_noches,
       (SELECT valor_noche FROM Tarifa t JOIN Temporada tp ON tp.id_temporada = t.id_temporada
         WHERE t.id_habitacion = 1 AND DATE '2025-01-15' BETWEEN tp.fecha_inicio AND tp.fecha_fin) AS tarifa_noche
  FROM dual;

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

-- Prueba 5: trg_auditoria_tarifa.
UPDATE Tarifa SET valor_noche = ROUND(valor_noche * 1.05) WHERE id_tarifa = 1;

SELECT id_tarifa, operacion, valor_anterior, valor_nuevo, usuario,
       TO_CHAR(fecha_cambio, 'YYYY-MM-DD HH24:MI') AS cuando
  FROM Auditoria_Tarifa
 ORDER BY id_auditoria;

ROLLBACK;

-- Prueba 6: trg_reserva_no_solape (contra una reserva ya confirmada).
DECLARE
    v_hab Reserva_Habitacion.id_habitacion%TYPE;
    v_in  Reserva_Habitacion.checkin%TYPE;
    v_out Reserva_Habitacion.checkout%TYPE;
    v_res Reserva_Habitacion.id_reserva%TYPE;
BEGIN
    SELECT rh.id_habitacion, rh.checkin, rh.checkout, rh.id_reserva
      INTO v_hab, v_in, v_out, v_res
      FROM Reserva_Habitacion rh
      JOIN Reserva r ON r.id_reserva = rh.id_reserva
     WHERE r.estado = 'confirmada' AND ROWNUM = 1;

    INSERT INTO Reserva_Habitacion (id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado)
    VALUES (v_res, v_hab, v_in, v_out, 100000);

    DBMS_OUTPUT.PUT_LINE('ERROR: el disparador deberia haberlo impedido.');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Disparador OK -> ' || SQLERRM);
END;
/
ROLLBACK;

-- Prueba 7: mv_ocupacion_mensual.
SELECT municipio, nombre_comercial, anio_mes, reservas, noches_ocupadas
  FROM mv_ocupacion_mensual
 WHERE anio_mes = '2025-07'
 ORDER BY noches_ocupadas DESC
 FETCH FIRST 10 ROWS ONLY;
