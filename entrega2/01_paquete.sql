-- ENTREGA 2 - TurismoUQ
-- 01. Paquete: funcion, procedimiento y cursor de proceso masivo.

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100

-- Especificacion del paquete
CREATE OR REPLACE PACKAGE pkg_turismo IS

    FUNCTION fn_valor_estadia (
        p_id_habitacion IN Habitacion.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER;

    PROCEDURE sp_crear_reserva (
        p_id_cliente         IN  Reserva.id_cliente%TYPE,
        p_id_habitacion      IN  Habitacion.id_habitacion%TYPE,
        p_cantidad_huespedes IN  NUMBER,
        p_checkin            IN  Reserva_Habitacion.checkin%TYPE,
        p_checkout           IN  Reserva_Habitacion.checkout%TYPE,
        p_id_reserva         OUT Reserva.id_reserva%TYPE,
        p_fecha_reserva      IN  Reserva.fecha_reserva%TYPE DEFAULT SYSDATE
    );

    PROCEDURE sp_liquidacion_mensual (
        p_anio IN NUMBER,
        p_mes  IN NUMBER
    );

END pkg_turismo;
/

-- Cuerpo del paquete
CREATE OR REPLACE PACKAGE BODY pkg_turismo IS

    FUNCTION fn_valor_estadia (
        p_id_habitacion IN Habitacion.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER IS
        v_total NUMBER := 0;
    BEGIN
        IF p_fecha_out <= p_fecha_in THEN
            RAISE_APPLICATION_ERROR(-20001, 'La fecha de checkout debe ser posterior al checkin.');
        END IF;

        SELECT NVL(SUM(tar.valor_noche), 0)
          INTO v_total
          FROM (
                SELECT TRUNC(p_fecha_in) + LEVEL - 1 AS noche
                  FROM DUAL
                CONNECT BY LEVEL <= (TRUNC(p_fecha_out) - TRUNC(p_fecha_in))
               ) d
          JOIN Temporada temp
            ON d.noche BETWEEN TRUNC(temp.fecha_inicio) AND TRUNC(temp.fecha_fin)
          JOIN Tarifa tar
            ON tar.id_temporada  = temp.id_temporada
           AND tar.id_habitacion = p_id_habitacion;

        RETURN v_total;
    END fn_valor_estadia;


    PROCEDURE sp_crear_reserva (
        p_id_cliente         IN  Reserva.id_cliente%TYPE,
        p_id_habitacion      IN  Habitacion.id_habitacion%TYPE,
        p_cantidad_huespedes IN  NUMBER,
        p_checkin            IN  Reserva_Habitacion.checkin%TYPE,
        p_checkout           IN  Reserva_Habitacion.checkout%TYPE,
        p_id_reserva         OUT Reserva.id_reserva%TYPE,
        p_fecha_reserva      IN  Reserva.fecha_reserva%TYPE DEFAULT SYSDATE
    ) IS
        v_capacidad          Habitacion.capacidad%TYPE;
        v_habitacion_ocupada NUMBER;
        v_precio_noche       Reserva_Habitacion.precio_noche_calculado%TYPE;

        e_checkout_invalido  EXCEPTION;
        e_capacidad_excedida EXCEPTION;
        e_cantidad_invalida  EXCEPTION;
        e_no_disponible      EXCEPTION;
    BEGIN
        SAVEPOINT sp_crear_reserva_inicio;

        IF p_checkin IS NULL OR p_checkout IS NULL OR p_checkout <= p_checkin THEN
            RAISE e_checkout_invalido;
        END IF;

        IF p_cantidad_huespedes IS NULL OR p_cantidad_huespedes <= 0 THEN
            RAISE e_cantidad_invalida;
        END IF;

        SELECT capacidad
          INTO v_capacidad
          FROM Habitacion
         WHERE id_habitacion = p_id_habitacion;

        IF p_cantidad_huespedes > v_capacidad THEN
            RAISE e_capacidad_excedida;
        END IF;

        SELECT COUNT(*)
          INTO v_habitacion_ocupada
          FROM Reserva_Habitacion rh
          JOIN Reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = p_id_habitacion
           AND r.estado = 'confirmada'
           AND rh.checkin  < p_checkout
           AND rh.checkout > p_checkin;

        IF v_habitacion_ocupada > 0 THEN
            RAISE e_no_disponible;
        END IF;

        SELECT fn_valor_estadia(p_id_habitacion, p_checkin, p_checkout)
               / (TRUNC(p_checkout) - TRUNC(p_checkin))
          INTO v_precio_noche
          FROM DUAL;

        INSERT INTO Reserva (id_cliente, fecha_reserva, estado)
        VALUES (p_id_cliente, NVL(p_fecha_reserva, SYSDATE), 'confirmada')
        RETURNING id_reserva INTO p_id_reserva;

        INSERT INTO Reserva_Habitacion (
            id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado
        ) VALUES (
            p_id_reserva, p_id_habitacion, p_checkin, p_checkout, v_precio_noche
        );
    EXCEPTION
        WHEN e_no_disponible THEN
            ROLLBACK TO sp_crear_reserva_inicio;
            RAISE_APPLICATION_ERROR(-20010, 'La habitacion no esta disponible para el rango indicado.');
        WHEN e_checkout_invalido THEN
            ROLLBACK TO sp_crear_reserva_inicio;
            RAISE_APPLICATION_ERROR(-20011, 'La fecha de checkout debe ser posterior al checkin.');
        WHEN e_capacidad_excedida THEN
            ROLLBACK TO sp_crear_reserva_inicio;
            RAISE_APPLICATION_ERROR(-20012, 'La cantidad de huespedes excede la capacidad de la habitacion.');
        WHEN e_cantidad_invalida THEN
            ROLLBACK TO sp_crear_reserva_inicio;
            RAISE_APPLICATION_ERROR(-20014, 'La cantidad de huespedes debe ser mayor que cero.');
        WHEN NO_DATA_FOUND THEN
            ROLLBACK TO sp_crear_reserva_inicio;
            RAISE_APPLICATION_ERROR(-20013, 'La habitacion indicada no existe.');
        WHEN OTHERS THEN
            ROLLBACK TO sp_crear_reserva_inicio;
            RAISE;
    END sp_crear_reserva;


    PROCEDURE sp_liquidacion_mensual (
        p_anio IN NUMBER,
        p_mes  IN NUMBER
    ) IS
        CURSOR c_aloj (p_a NUMBER, p_m NUMBER) IS
            SELECT a.id_alojamiento,
                   a.nombre_comercial,
                   m.nombre AS municipio
              FROM Alojamiento a
              JOIN Municipio   m ON m.id_municipio = a.id_municipio
             WHERE EXISTS (
                   SELECT 1
                     FROM Habitacion h
                     JOIN Reserva_Habitacion rh ON rh.id_habitacion = h.id_habitacion
                     JOIN Reserva r             ON r.id_reserva     = rh.id_reserva
                    WHERE h.id_alojamiento = a.id_alojamiento
                      AND r.estado IN ('confirmada', 'completada')
                      AND EXTRACT(YEAR  FROM rh.checkin) = p_a
                      AND EXTRACT(MONTH FROM rh.checkin) = p_m)
             ORDER BY a.id_alojamiento;

        r_aloj       c_aloj%ROWTYPE;
        v_hospedaje  NUMBER;
        v_servicios  NUMBER;
        v_total_dpto NUMBER := 0;
        v_n          NUMBER := 0;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('== LIQUIDACION ' || LPAD(p_mes, 2, '0') || '/' || p_anio || ' ==');

        OPEN c_aloj(p_anio, p_mes);
        LOOP
            FETCH c_aloj INTO r_aloj;
            EXIT WHEN c_aloj%NOTFOUND;

            SELECT NVL(SUM(fn_valor_estadia(rh.id_habitacion, rh.checkin, rh.checkout)), 0)
              INTO v_hospedaje
              FROM Habitacion h
              JOIN Reserva_Habitacion rh ON rh.id_habitacion = h.id_habitacion
              JOIN Reserva r             ON r.id_reserva     = rh.id_reserva
             WHERE h.id_alojamiento = r_aloj.id_alojamiento
               AND r.estado IN ('confirmada', 'completada')
               AND EXTRACT(YEAR  FROM rh.checkin) = p_anio
               AND EXTRACT(MONTH FROM rh.checkin) = p_mes;

            SELECT NVL(SUM(rs.cantidad * rs.precio_cobrado), 0)
              INTO v_servicios
              FROM Servicio s
              JOIN Reserva_Servicio rs ON rs.id_servicio = s.id_servicio
              JOIN Reserva r           ON r.id_reserva   = rs.id_reserva
             WHERE s.id_alojamiento = r_aloj.id_alojamiento
               AND r.estado IN ('confirmada', 'completada')
               AND EXISTS (SELECT 1 FROM Reserva_Habitacion rh2
                            WHERE rh2.id_reserva = r.id_reserva
                              AND EXTRACT(YEAR  FROM rh2.checkin) = p_anio
                              AND EXTRACT(MONTH FROM rh2.checkin) = p_mes);

            DBMS_OUTPUT.PUT_LINE(
                RPAD(r_aloj.nombre_comercial, 24) || ' ' ||
                RPAD(r_aloj.municipio, 12)        || ' ' ||
                'hospedaje ' || LPAD(TO_CHAR(v_hospedaje, 'FM999G999G990'), 12) || ' ' ||
                'servicios ' || LPAD(TO_CHAR(v_servicios, 'FM999G999G990'), 10) || ' ' ||
                'total '     || LPAD(TO_CHAR(v_hospedaje + v_servicios, 'FM999G999G990'), 12));

            v_total_dpto := v_total_dpto + v_hospedaje + v_servicios;
            v_n          := v_n + 1;
        END LOOP;
        CLOSE c_aloj;

        DBMS_OUTPUT.PUT_LINE('Alojamientos liquidados: ' || v_n ||
            ' . Total departamento: ' || TO_CHAR(v_total_dpto, 'FM999G999G990'));
    END sp_liquidacion_mensual;

END pkg_turismo;
/
