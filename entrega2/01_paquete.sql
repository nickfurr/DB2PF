-- ENTREGA 2 - TurismoUQ
-- 01. Paquete: funcion, procedimiento y cursor de proceso masivo.
--
-- Codigos de error propios del paquete (RAISE_APPLICATION_ERROR):
--   fn_valor_estadia
--     -20000  Parametros nulos.
--     -20001  La fecha de checkout no es posterior al checkin.
--     -20002  Una noche de la estadia no pertenece a ninguna temporada.
--     -20003  La habitacion no existe.
--     -20005  La habitacion no tiene tarifa para la temporada de una noche.
--     -20006  Una noche cae en dos temporadas (temporadas solapadas).
--   sp_crear_reserva
--     -20010  La habitacion esta ocupada en el rango (reserva no cancelada).
--     -20011  La fecha de checkout no es posterior al checkin.
--     -20012  La cantidad de huespedes excede la capacidad.
--     -20013  La habitacion no existe.
--     -20014  La cantidad de huespedes no es mayor que cero.
--     -20016  El checkin es anterior a la fecha de la reserva.
--     -20017  El cliente es nulo o no existe.
--   sp_liquidacion_mensual
--     -20015  Ano o mes invalidos.

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100

-- Especificacion del paquete
CREATE OR REPLACE PACKAGE pkg_turismo IS

    -- Valor de una estadia: suma, noche por noche, la tarifa de la habitacion
    -- en la temporada a la que pertenece cada noche. La noche del checkout no
    -- se cobra. Una estadia que atraviesa varias temporadas paga cada noche al
    -- precio de su temporada.
    FUNCTION fn_valor_estadia (
        p_id_habitacion IN Habitacion.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER;

    -- Muestra con DBMS_OUTPUT el detalle de fn_valor_estadia: cada noche con
    -- su temporada y tarifa, y el subtotal por temporada. Sirve de evidencia.
    PROCEDURE sp_desglose_estadia (
        p_id_habitacion IN Habitacion.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    );

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

    -- -------------------------------------------------------------------------
    -- Cursor con parametros compartido por fn_valor_estadia y
    -- sp_desglose_estadia: devuelve UNA FILA POR NOCHE de la estadia.
    -- El calendario se genera con CONNECT BY (de checkin a checkout - 1) y se
    -- cruza con TEMPORADA y TARIFA mediante LEFT JOIN, para que una noche sin
    -- temporada o sin tarifa no desaparezca: llega con columnas nulas y la
    -- funcion la detecta y la reporta como error.
    -- n_temporadas cuenta en cuantas temporadas cae cada noche: si son dos o
    -- mas, TEMPORADA tiene periodos solapados y la noche no tiene precio unico.
    -- -------------------------------------------------------------------------
    CURSOR c_noches (p_hab NUMBER, p_in DATE, p_out DATE) IS
        SELECT d.noche,
               t.id_temporada,
               t.nombre AS temporada,
               t.tipo,
               tar.valor_noche,
               COUNT(t.id_temporada) OVER (PARTITION BY d.noche) AS n_temporadas
          FROM (SELECT TRUNC(p_in) + LEVEL - 1 AS noche
                  FROM dual
               CONNECT BY LEVEL <= TRUNC(p_out) - TRUNC(p_in)) d
          LEFT JOIN Temporada t
                 ON d.noche BETWEEN TRUNC(t.fecha_inicio) AND TRUNC(t.fecha_fin)
          LEFT JOIN Tarifa tar
                 ON tar.id_temporada  = t.id_temporada
                AND tar.id_habitacion = p_hab
         ORDER BY d.noche;

    -- Validaciones comunes de los parametros de una estadia.
    PROCEDURE validar_estadia (
        p_id_habitacion IN NUMBER,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) IS
        v_existe NUMBER;
    BEGIN
        IF p_id_habitacion IS NULL OR p_fecha_in IS NULL OR p_fecha_out IS NULL THEN
            RAISE_APPLICATION_ERROR(-20000, 'La habitacion y las fechas de la estadia son obligatorias.');
        END IF;

        IF TRUNC(p_fecha_out) <= TRUNC(p_fecha_in) THEN
            RAISE_APPLICATION_ERROR(-20001, 'La fecha de checkout debe ser posterior al checkin.');
        END IF;

        SELECT COUNT(*) INTO v_existe
          FROM Habitacion
         WHERE id_habitacion = p_id_habitacion;

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'La habitacion ' || p_id_habitacion || ' no existe.');
        END IF;
    END validar_estadia;


    FUNCTION fn_valor_estadia (
        p_id_habitacion IN Habitacion.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER IS
        v_total       NUMBER := 0;
    BEGIN
        validar_estadia(p_id_habitacion, p_fecha_in, p_fecha_out);

        -- Recorrido noche por noche: cada noche suma la tarifa de SU temporada.
        -- Primero se revisa el solape de temporadas, para que una noche en dos
        -- temporadas siempre se reporte como tal y no como falta de tarifa.
        FOR r IN c_noches(p_id_habitacion, p_fecha_in, p_fecha_out) LOOP

            IF r.n_temporadas > 1 THEN
                RAISE_APPLICATION_ERROR(-20006,
                    'La noche ' || TO_CHAR(r.noche, 'YYYY-MM-DD') ||
                    ' pertenece a mas de una temporada; revise TEMPORADA.');
            END IF;

            IF r.id_temporada IS NULL THEN
                RAISE_APPLICATION_ERROR(-20002,
                    'La noche ' || TO_CHAR(r.noche, 'YYYY-MM-DD') ||
                    ' no pertenece a ninguna temporada definida.');
            END IF;

            IF r.valor_noche IS NULL THEN
                RAISE_APPLICATION_ERROR(-20005,
                    'La habitacion ' || p_id_habitacion || ' no tiene tarifa para ' ||
                    r.temporada || ' (noche ' || TO_CHAR(r.noche, 'YYYY-MM-DD') || ').');
            END IF;

            v_total := v_total + r.valor_noche;
        END LOOP;

        RETURN v_total;
    END fn_valor_estadia;


    PROCEDURE sp_desglose_estadia (
        p_id_habitacion IN Habitacion.id_habitacion%TYPE,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) IS
        v_temp_actual  Temporada.nombre%TYPE;
        v_subtotal     NUMBER := 0;
        v_noches_temp  PLS_INTEGER := 0;
        v_total        NUMBER;

        PROCEDURE imprimir_subtotal IS
        BEGIN
            IF v_temp_actual IS NOT NULL THEN
                DBMS_OUTPUT.PUT_LINE('   Subtotal ' || v_temp_actual || ': ' || v_noches_temp ||
                                     ' noche(s) = ' || TO_CHAR(v_subtotal, 'FM999G999G990'));
            END IF;
        END;
    BEGIN
        -- fn_valor_estadia valida todo y lanza el error si algo falta.
        v_total := fn_valor_estadia(p_id_habitacion, p_fecha_in, p_fecha_out);

        DBMS_OUTPUT.PUT_LINE('Habitacion ' || p_id_habitacion || ': ' ||
                             TO_CHAR(p_fecha_in, 'YYYY-MM-DD') || ' -> ' ||
                             TO_CHAR(p_fecha_out, 'YYYY-MM-DD') || ' (' ||
                             (TRUNC(p_fecha_out) - TRUNC(p_fecha_in)) || ' noches)');

        FOR r IN c_noches(p_id_habitacion, p_fecha_in, p_fecha_out) LOOP
            IF v_temp_actual IS NULL OR r.temporada <> v_temp_actual THEN
                imprimir_subtotal;
                v_temp_actual := r.temporada;
                v_subtotal    := 0;
                v_noches_temp := 0;
            END IF;
            DBMS_OUTPUT.PUT_LINE('   ' || TO_CHAR(r.noche, 'YYYY-MM-DD') || '  ' ||
                                 RPAD(r.tipo, 6) || ' ' || RPAD(r.temporada, 45) ||
                                 LPAD(TO_CHAR(r.valor_noche, 'FM999G999G990'), 10));
            v_subtotal    := v_subtotal + r.valor_noche;
            v_noches_temp := v_noches_temp + 1;
        END LOOP;
        imprimir_subtotal;

        DBMS_OUTPUT.PUT_LINE('   TOTAL fn_valor_estadia = ' || TO_CHAR(v_total, 'FM999G999G990'));
    END sp_desglose_estadia;


    PROCEDURE sp_crear_reserva (
        p_id_cliente         IN  Reserva.id_cliente%TYPE,
        p_id_habitacion      IN  Habitacion.id_habitacion%TYPE,
        p_cantidad_huespedes IN  NUMBER,
        p_checkin            IN  Reserva_Habitacion.checkin%TYPE,
        p_checkout           IN  Reserva_Habitacion.checkout%TYPE,
        p_id_reserva         OUT Reserva.id_reserva%TYPE,
        p_fecha_reserva      IN  Reserva.fecha_reserva%TYPE DEFAULT SYSDATE
    ) IS
        -- Las fechas se manejan sin hora: la estadia va de un dia a otro y la
        -- noche del checkout no se cobra. Con horas, una salida a las 11:00
        -- bloquearia ese dia a quien llega despues.
        v_checkin            DATE := TRUNC(p_checkin);
        v_checkout           DATE := TRUNC(p_checkout);
        v_fecha_reserva      DATE := NVL(p_fecha_reserva, SYSDATE);
        v_capacidad          Habitacion.capacidad%TYPE;
        v_cliente_existe     NUMBER;
        v_habitacion_ocupada NUMBER;
        v_precio_noche       Reserva_Habitacion.precio_noche_calculado%TYPE;

        e_checkout_invalido  EXCEPTION;
        e_checkin_pasado     EXCEPTION;
        e_capacidad_excedida EXCEPTION;
        e_cantidad_invalida  EXCEPTION;
        e_cliente_invalido   EXCEPTION;
        e_no_disponible      EXCEPTION;
    BEGIN
        SAVEPOINT sp_crear_reserva_inicio;

        IF v_checkin IS NULL OR v_checkout IS NULL OR v_checkout <= v_checkin THEN
            RAISE e_checkout_invalido;
        END IF;

        -- No se reserva hacia atras: el huesped no puede llegar antes del dia
        -- en que hizo la reserva. p_fecha_reserva permite registrar reservas
        -- historicas (por ejemplo, en las pruebas) con su fecha real.
        IF v_checkin < TRUNC(v_fecha_reserva) THEN
            RAISE e_checkin_pasado;
        END IF;

        IF p_cantidad_huespedes IS NULL OR p_cantidad_huespedes <= 0 THEN
            RAISE e_cantidad_invalida;
        END IF;

        -- Con un cliente nulo o inexistente el INSERT fallaria con ORA-01400 u
        -- ORA-02291; se valida antes para responder con un error propio.
        SELECT COUNT(*)
          INTO v_cliente_existe
          FROM Cliente
         WHERE id_cliente = p_id_cliente;

        IF v_cliente_existe = 0 THEN
            RAISE e_cliente_invalido;
        END IF;

        SELECT capacidad
          INTO v_capacidad
          FROM Habitacion
         WHERE id_habitacion = p_id_habitacion;

        IF p_cantidad_huespedes > v_capacidad THEN
            RAISE e_capacidad_excedida;
        END IF;

        -- Una reserva ocupa la habitacion mientras no este cancelada: la
        -- pendiente ya tiene anticipo, la confirmada esta asegurada y la
        -- completada es una estadia que ya ocurrio. Es la misma regla de
        -- trg_reserva_no_solape.
        SELECT COUNT(*)
          INTO v_habitacion_ocupada
          FROM Reserva_Habitacion rh
          JOIN Reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = p_id_habitacion
           AND r.estado <> 'cancelada'
           AND rh.checkin  < v_checkout
           AND rh.checkout > v_checkin;

        IF v_habitacion_ocupada > 0 THEN
            RAISE e_no_disponible;
        END IF;

        -- Precio promedio por noche, redondeado a centavos como en la carga de
        -- datos. El valor exacto de la estadia sigue siendo fn_valor_estadia.
        v_precio_noche := ROUND(fn_valor_estadia(p_id_habitacion, v_checkin, v_checkout)
                                / (v_checkout - v_checkin), 2);

        INSERT INTO Reserva (id_cliente, fecha_reserva, estado)
        VALUES (p_id_cliente, v_fecha_reserva, 'confirmada')
        RETURNING id_reserva INTO p_id_reserva;

        INSERT INTO Reserva_Habitacion (
            id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado
        ) VALUES (
            p_id_reserva, p_id_habitacion, v_checkin, v_checkout, v_precio_noche
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
        WHEN e_checkin_pasado THEN
            ROLLBACK TO sp_crear_reserva_inicio;
            RAISE_APPLICATION_ERROR(-20016, 'El checkin (' || TO_CHAR(v_checkin, 'YYYY-MM-DD') ||
                ') no puede ser anterior a la fecha de la reserva (' ||
                TO_CHAR(v_fecha_reserva, 'YYYY-MM-DD') || ').');
        WHEN e_cliente_invalido THEN
            ROLLBACK TO sp_crear_reserva_inicio;
            RAISE_APPLICATION_ERROR(-20017, 'El cliente ' || NVL(TO_CHAR(p_id_cliente), '(nulo)') || ' no existe.');
        WHEN NO_DATA_FOUND THEN
            ROLLBACK TO sp_crear_reserva_inicio;
            RAISE_APPLICATION_ERROR(-20013, 'La habitacion indicada no existe.');
        WHEN OTHERS THEN
            ROLLBACK TO sp_crear_reserva_inicio;
            RAISE;
    END sp_crear_reserva;


    -- -------------------------------------------------------------------------
    -- Liquidacion mensual por alojamiento (proceso masivo con cursor explicito
    -- con parametros: OPEN / FETCH / CLOSE).
    --   * Hospedaje: cada estadia confirmada o completada se liquida SOLO por
    --     las noches que caen dentro del mes, con fn_valor_estadia sobre el
    --     tramo [max(checkin, dia 1), min(checkout, dia 1 del mes siguiente)).
    --     Una estadia del 30/07 al 02/08 aporta 2 noches a julio y 1 a agosto,
    --     igual que en la vista materializada de ocupacion.
    --   * Servicios: se liquidan en el mes en que llega el huesped (primer
    --     checkin de la reserva).
    -- -------------------------------------------------------------------------
    PROCEDURE sp_liquidacion_mensual (
        p_anio IN NUMBER,
        p_mes  IN NUMBER
    ) IS
        -- Alojamientos con al menos una noche ocupada en el mes [p_ini, p_fin)
        CURSOR c_aloj (p_ini DATE, p_fin DATE) IS
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
                      AND rh.checkin  < p_fin
                      AND rh.checkout > p_ini)
             ORDER BY m.nombre, a.nombre_comercial;

        r_aloj       c_aloj%ROWTYPE;
        v_ini        DATE;
        v_fin        DATE;
        v_noches     NUMBER;
        v_hospedaje  NUMBER;
        v_servicios  NUMBER;
        v_tot_noches NUMBER := 0;
        v_tot_hosp   NUMBER := 0;
        v_tot_serv   NUMBER := 0;
        v_n          NUMBER := 0;

        FUNCTION dinero (p NUMBER) RETURN VARCHAR2 IS
        BEGIN
            RETURN TO_CHAR(p, 'FM999G999G999G990');
        END;
    BEGIN
        IF p_anio IS NULL OR p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12 THEN
            RAISE_APPLICATION_ERROR(-20015, 'Indique un ano y un mes entre 1 y 12.');
        END IF;

        v_ini := TO_DATE(p_anio || '-' || LPAD(p_mes, 2, '0') || '-01', 'YYYY-MM-DD');
        v_fin := ADD_MONTHS(v_ini, 1);

        DBMS_OUTPUT.PUT_LINE('== LIQUIDACION ' || TO_CHAR(v_ini, 'MM/YYYY') || ' ==');
        DBMS_OUTPUT.PUT_LINE(RPAD('Alojamiento', 30) || RPAD('Municipio', 12) ||
                             LPAD('Noches', 7) || LPAD('Hospedaje', 16) ||
                             LPAD('Servicios', 14) || LPAD('Total', 16));

        OPEN c_aloj(v_ini, v_fin);
        LOOP
            FETCH c_aloj INTO r_aloj;
            EXIT WHEN c_aloj%NOTFOUND;

            -- Noches y valor del hospedaje que caen dentro del mes
            SELECT NVL(SUM(LEAST(rh.checkout, v_fin) - GREATEST(rh.checkin, v_ini)), 0),
                   NVL(SUM(fn_valor_estadia(rh.id_habitacion,
                                            GREATEST(rh.checkin, v_ini),
                                            LEAST(rh.checkout, v_fin))), 0)
              INTO v_noches, v_hospedaje
              FROM Habitacion h
              JOIN Reserva_Habitacion rh ON rh.id_habitacion = h.id_habitacion
              JOIN Reserva r             ON r.id_reserva     = rh.id_reserva
             WHERE h.id_alojamiento = r_aloj.id_alojamiento
               AND r.estado IN ('confirmada', 'completada')
               AND rh.checkin  < v_fin
               AND rh.checkout > v_ini;

            -- Servicios de las reservas que llegan en el mes
            SELECT NVL(SUM(rs.cantidad * rs.precio_cobrado), 0)
              INTO v_servicios
              FROM Servicio s
              JOIN Reserva_Servicio rs ON rs.id_servicio = s.id_servicio
              JOIN Reserva r           ON r.id_reserva   = rs.id_reserva
             WHERE s.id_alojamiento = r_aloj.id_alojamiento
               AND r.estado IN ('confirmada', 'completada')
               AND (SELECT MIN(rh2.checkin)
                      FROM Reserva_Habitacion rh2
                     WHERE rh2.id_reserva = r.id_reserva) >= v_ini
               AND (SELECT MIN(rh2.checkin)
                      FROM Reserva_Habitacion rh2
                     WHERE rh2.id_reserva = r.id_reserva) <  v_fin;

            DBMS_OUTPUT.PUT_LINE(
                RPAD(r_aloj.nombre_comercial, 30) ||
                RPAD(r_aloj.municipio, 12)        ||
                LPAD(v_noches, 7)                 ||
                LPAD(dinero(v_hospedaje), 16)     ||
                LPAD(dinero(v_servicios), 14)     ||
                LPAD(dinero(v_hospedaje + v_servicios), 16));

            v_tot_noches := v_tot_noches + v_noches;
            v_tot_hosp   := v_tot_hosp   + v_hospedaje;
            v_tot_serv   := v_tot_serv   + v_servicios;
            v_n          := v_n + 1;
        END LOOP;
        CLOSE c_aloj;

        DBMS_OUTPUT.PUT_LINE(RPAD('TOTAL DEPARTAMENTO (' || v_n || ' alojamientos)', 42) ||
                             LPAD(v_tot_noches, 7)                    ||
                             LPAD(dinero(v_tot_hosp), 16)             ||
                             LPAD(dinero(v_tot_serv), 14)             ||
                             LPAD(dinero(v_tot_hosp + v_tot_serv), 16));
    END sp_liquidacion_mensual;

END pkg_turismo;
/
