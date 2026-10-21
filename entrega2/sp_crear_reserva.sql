CREATE OR REPLACE PROCEDURE sp_crear_reserva (
    p_id_cliente          IN  Reserva.id_cliente%TYPE,
    p_id_habitacion       IN  Habitacion.id_habitacion%TYPE,
    p_cantidad_huespedes  IN  NUMBER,
    p_checkin             IN  Reserva_Habitacion.checkin%TYPE,
    p_checkout            IN  Reserva_Habitacion.checkout%TYPE,
    p_id_reserva          OUT Reserva.id_reserva%TYPE,
    p_fecha_reserva       IN  Reserva.fecha_reserva%TYPE DEFAULT SYSDATE
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
      AND rh.checkin < p_checkout
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
        id_reserva,
        id_habitacion,
        checkin,
        checkout,
        precio_noche_calculado
    ) VALUES (
        p_id_reserva,
        p_id_habitacion,
        p_checkin,
        p_checkout,
        v_precio_noche
    );
EXCEPTION
    WHEN e_no_disponible THEN
        ROLLBACK TO sp_crear_reserva_inicio;
        RAISE_APPLICATION_ERROR(
            -20010,
            'La habitacion no esta disponible para el rango indicado.'
        );
    WHEN e_checkout_invalido THEN
        ROLLBACK TO sp_crear_reserva_inicio;
        RAISE_APPLICATION_ERROR(
            -20011,
            'La fecha de checkout debe ser posterior al checkin.'
        );
    WHEN e_capacidad_excedida THEN
        ROLLBACK TO sp_crear_reserva_inicio;
        RAISE_APPLICATION_ERROR(
            -20012,
            'La cantidad de huespedes excede la capacidad de la habitacion.'
        );
    WHEN e_cantidad_invalida THEN
        ROLLBACK TO sp_crear_reserva_inicio;
        RAISE_APPLICATION_ERROR(
            -20014,
            'La cantidad de huespedes debe ser mayor que cero.'
        );
    WHEN NO_DATA_FOUND THEN
        ROLLBACK TO sp_crear_reserva_inicio;
        RAISE_APPLICATION_ERROR(
            -20013,
            'La habitacion indicada no existe.'
        );
    WHEN OTHERS THEN
        ROLLBACK TO sp_crear_reserva_inicio;
        RAISE;
END;
/