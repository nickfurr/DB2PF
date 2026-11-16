CREATE OR REPLACE PROCEDURE sp_reservar_y_pagar (
    --  reserva
    p_id_cliente         IN  Reserva.id_cliente%TYPE,
    p_id_habitacion      IN  Habitacion.id_habitacion%TYPE,
    p_cantidad_huespedes IN  NUMBER,
    p_checkin            IN  Reserva_Habitacion.checkin%TYPE,
    p_checkout           IN  Reserva_Habitacion.checkout%TYPE,
    --  pago
    p_monto              IN  Pago.monto%TYPE,
    p_metodo             IN  Pago.metodo%TYPE,
    -- Salidas
    p_id_reserva         OUT Reserva.id_reserva%TYPE,
    p_id_pago            OUT Pago.id_pago%TYPE,
    -- Opcionales 
    p_fecha_reserva      IN  Reserva.fecha_reserva%TYPE DEFAULT SYSDATE,
    p_fecha_pago         IN  Pago.fecha%TYPE DEFAULT SYSDATE
) IS
    -- Variables locales si las necesitas
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
