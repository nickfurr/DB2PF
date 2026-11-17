-- =============================================================================
-- ENTREGA FINAL - TurismoUQ
-- 09. Transacciones: procedimientos sp_registrar_pago y sp_reservar_y_pagar
--     con SAVEPOINT y control de atomicidad.
-- Ejecutar con el usuario dueno del esquema del proyecto (despues de 06_paquete.sql).
-- =============================================================================
SET SERVEROUTPUT ON

-- -----------------------------------------------------------------------------
-- 1. sp_registrar_pago: valida el monto, el metodo, la fecha, bloquea la
--    reserva con FOR UPDATE y verifica que los pagos exitosos no superen la
--    deuda total (hospedaje + servicios).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_pago (
    p_monto   IN  NUMBER,
    p_reserva IN  Reserva.id_reserva%TYPE,
    p_metodo  IN  Pago.metodo%TYPE,
    p_idpago  OUT Pago.id_pago%TYPE,
    p_fecha   IN  Pago.fecha%TYPE DEFAULT SYSDATE
) IS
    var_estado     Reserva.estado%TYPE;
    var_pagado     Pago.monto%TYPE;
    var_total_hab  NUMBER;
    var_total_serv NUMBER;
    var_apagar     NUMBER;
    var_fecha      DATE := NVL(p_fecha, SYSDATE);

    e_check_violado EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_check_violado, -2290);
BEGIN
    SAVEPOINT sp_pago_inicio;

    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'El monto del pago debe ser mayor que cero.');
    END IF;

    IF p_metodo IS NULL THEN
        RAISE_APPLICATION_ERROR(-20002, 'Se debe establecer un metodo de pago.');
    END IF;

    IF var_fecha > SYSDATE THEN
        RAISE_APPLICATION_ERROR(-20003, 'La fecha del pago no puede ser futura.');
    END IF;

    -- Verificar que la reserva exista y no este cancelada (bloqueo para evitar doble pago concurrente)
    SELECT estado
      INTO var_estado
      FROM Reserva
     WHERE id_reserva = p_reserva
       FOR UPDATE;

    IF var_estado = 'cancelada' THEN
        RAISE_APPLICATION_ERROR(-20006, 'No se puede registrar un pago sobre una reserva cancelada.');
    END IF;

    -- Todo lo que llevamos pagado con exito
    SELECT NVL(SUM(monto), 0)
      INTO var_pagado
      FROM Pago
     WHERE id_reserva = p_reserva
       AND estado = 'exitoso';

    -- Deuda original: hospedaje + servicios
    SELECT NVL(SUM((checkout - checkin) * precio_noche_calculado), 0)
      INTO var_total_hab
      FROM Reserva_Habitacion
     WHERE id_reserva = p_reserva;

    SELECT NVL(SUM(cantidad * precio_cobrado), 0)
      INTO var_total_serv
      FROM Reserva_Servicio
     WHERE id_reserva = p_reserva;

    var_apagar := var_total_hab + var_total_serv;

    IF var_apagar < var_pagado + p_monto THEN
        RAISE_APPLICATION_ERROR(-20004, 'El pago excede la deuda de la reserva.');
    END IF;

    INSERT INTO Pago (id_reserva, fecha, monto, metodo, estado)
    VALUES (p_reserva, var_fecha, p_monto, p_metodo, 'exitoso')
    RETURNING id_pago INTO p_idpago;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK TO sp_pago_inicio;
        RAISE_APPLICATION_ERROR(-20005, 'La reserva ' || NVL(TO_CHAR(p_reserva), '(nula)') || ' no existe.');
    WHEN e_check_violado THEN
        ROLLBACK TO sp_pago_inicio;
        RAISE_APPLICATION_ERROR(-20007, 'Metodo de pago invalido. Valores permitidos: tarjeta de credito, tarjeta debito, PSE, transferencia, efectivo.');
    WHEN OTHERS THEN
        ROLLBACK TO sp_pago_inicio;
        RAISE;
END sp_registrar_pago;
/

-- -----------------------------------------------------------------------------
-- 2. sp_reservar_y_pagar: ejecuta la creacion de la reserva y el registro del
--    pago como una sola unidad atomica usando SAVEPOINT sp_inicio.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_reservar_y_pagar (
    -- Reserva
    p_id_cliente         IN  Reserva.id_cliente%TYPE,
    p_id_habitacion      IN  Habitacion.id_habitacion%TYPE,
    p_cantidad_huespedes IN  NUMBER,
    p_checkin            IN  Reserva_Habitacion.checkin%TYPE,
    p_checkout           IN  Reserva_Habitacion.checkout%TYPE,
    -- Pago
    p_monto              IN  Pago.monto%TYPE,
    p_metodo             IN  Pago.metodo%TYPE,
    -- Salidas
    p_id_reserva         OUT Reserva.id_reserva%TYPE,
    p_id_pago            OUT Pago.id_pago%TYPE,
    -- Opcionales
    p_fecha_reserva      IN  Reserva.fecha_reserva%TYPE DEFAULT SYSDATE,
    p_fecha_pago         IN  Pago.fecha%TYPE DEFAULT SYSDATE
) IS
BEGIN
    -- 1. Punto de guardado inicial (garantiza atomicidad todo o nada)
    SAVEPOINT sp_inicio;

    -- 2. Paso 1: Crear reserva (devuelve p_id_reserva)
    pkg_turismo.sp_crear_reserva(
        p_id_cliente         => p_id_cliente,
        p_id_habitacion      => p_id_habitacion,
        p_cantidad_huespedes => p_cantidad_huespedes,
        p_checkin            => p_checkin,
        p_checkout           => p_checkout,
        p_id_reserva         => p_id_reserva,
        p_fecha_reserva      => p_fecha_reserva
    );

    -- 3. Paso 2: Registrar pago usando p_id_reserva (devuelve p_id_pago)
    sp_registrar_pago(
        p_monto   => p_monto,
        p_reserva => p_id_reserva,
        p_metodo  => p_metodo,
        p_idpago  => p_id_pago,
        p_fecha   => p_fecha_pago
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Si falla la reserva o el pago, deshace ambos
        ROLLBACK TO sp_inicio;
        p_id_reserva := NULL;
        p_id_pago    := NULL;
        RAISE;
END sp_reservar_y_pagar;
/
