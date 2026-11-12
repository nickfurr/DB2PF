CREATE OR REPLACE PROCEDURE sp_reservar_y_pagar (
    -- Datos para la reserva
    p_id_cliente         IN  Reserva.id_cliente%TYPE,
    p_id_habitacion      IN  Habitacion.id_habitacion%TYPE,
    p_cantidad_huespedes IN  NUMBER,
    p_checkin            IN  Reserva_Habitacion.checkin%TYPE,
    p_checkout           IN  Reserva_Habitacion.checkout%TYPE,
    -- Datos para el pago
    p_monto              IN  Pago.monto%TYPE,
    p_metodo             IN  Pago.metodo%TYPE,
    -- Salidas
    p_id_reserva         OUT Reserva.id_reserva%TYPE,
    p_id_pago            OUT Pago.id_pago%TYPE,
    -- Opcionales (siempre al final)
    p_fecha_reserva      IN  Reserva.fecha_reserva%TYPE DEFAULT SYSDATE,
    p_fecha_pago         IN  Pago.fecha%TYPE DEFAULT SYSDATE
) IS
    -- Variables locales si las necesitas
BEGIN
    -- 1. Punto de guardado inicial (garantiza atomicidad todo o nada)
    SAVEPOINT sp_inicio;

    -- 2. Paso 1: Crear reserva (devuelve p_id_reserva)
    pkg_turismo.sp_crear_reserva(
        -- TODO: pasar parametros de reserva
    );

    -- 3. Paso 2: Registrar pago usando p_id_reserva (devuelve p_id_pago)
    pago(
        -- TODO: pasar parametros de pago
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Si falla la reserva o el pago, deshace ambos
        ROLLBACK TO sp_inicio;
        RAISE;
END sp_reservar_y_pagar;
/
