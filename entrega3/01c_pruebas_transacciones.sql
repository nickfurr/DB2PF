-- =============================================================================
-- ENTREGA 3 - TurismoUQ
-- Pruebas de transacciones:
--   1. Exito atomico (sp_reservar_y_pagar -> COMMIT).
--   2. Fallo atomico (sp_reservar_y_pagar falla en pago -> ROLLBACK TO sp_inicio).
--   3. Demostracion de rollback parcial con SAVEPOINT (la reserva sobrevive y
--      el pago fallido se revierte).
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

DECLARE
    v_cli      Cliente.id_cliente%TYPE;
    v_hab      Habitacion.id_habitacion%TYPE;
    v_in       DATE := DATE '2026-12-10';
    v_out      DATE := DATE '2026-12-12';
    v_valor    NUMBER;
    v_res      Reserva.id_reserva%TYPE;
    v_pago     Pago.id_pago%TYPE;
    v_cnt_res  NUMBER;
    v_cnt_pago NUMBER;
BEGIN
    SELECT MIN(id_cliente) INTO v_cli FROM Cliente;

    SELECT MIN(h.id_habitacion)
      INTO v_hab
      FROM Habitacion h
     WHERE h.id_habitacion NOT IN (
           SELECT rh.id_habitacion
             FROM Reserva_Habitacion rh
             JOIN Reserva r ON r.id_reserva = rh.id_reserva
            WHERE r.estado <> 'cancelada'
              AND rh.checkin < v_out
              AND rh.checkout > v_in
     );

    v_valor := pkg_turismo.fn_valor_estadia(v_hab, v_in, v_out);

    DBMS_OUTPUT.PUT_LINE('=== PRUEBA 1: EXITO ATOMICO (sp_reservar_y_pagar) ===');
    sp_reservar_y_pagar(
        p_id_cliente         => v_cli,
        p_id_habitacion      => v_hab,
        p_cantidad_huespedes => 1,
        p_checkin            => v_in,
        p_checkout           => v_out,
        p_monto              => v_valor,
        p_metodo             => 'PSE',
        p_id_reserva         => v_res,
        p_id_pago            => v_pago,
        p_fecha_reserva      => v_in - 30
    );
    COMMIT;

    SELECT COUNT(*) INTO v_cnt_res  FROM Reserva WHERE id_reserva = v_res;
    SELECT COUNT(*) INTO v_cnt_pago FROM Pago    WHERE id_pago    = v_pago;
    DBMS_OUTPUT.PUT_LINE('OK -> Reserva=' || v_res || ' (filas=' || v_cnt_res ||
                         '), Pago=' || v_pago || ' (filas=' || v_cnt_pago ||
                         '), Valor=' || v_valor);

    -- Limpieza de la prueba 1 para no ensuciar la BD
    DELETE FROM Pago               WHERE id_pago    = v_pago;
    DELETE FROM Reserva_Habitacion WHERE id_reserva = v_res;
    DELETE FROM Reserva            WHERE id_reserva = v_res;
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== PRUEBA 2: FALLO ATOMICO (pago invalido deshace reserva y pago) ===');
    BEGIN
        sp_reservar_y_pagar(
            p_id_cliente         => v_cli,
            p_id_habitacion      => v_hab,
            p_cantidad_huespedes => 1,
            p_checkin            => v_in,
            p_checkout           => v_out,
            p_monto              => v_valor,
            p_metodo             => 'cripto', -- metodo invalido -> ORA-20007
            p_id_reserva         => v_res,
            p_id_pago            => v_pago,
            p_fecha_reserva      => v_in - 30
        );
        DBMS_OUTPUT.PUT_LINE('ERROR: debio fallar.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error esperado: ' || SQLERRM);
    END;

    SELECT COUNT(*)
      INTO v_cnt_res
      FROM Reserva_Habitacion
     WHERE id_habitacion = v_hab
       AND checkin       = v_in
       AND checkout      = v_out;
    DBMS_OUTPUT.PUT_LINE('Filas en Reserva_Habitacion tras fallo atomico: ' || v_cnt_res || ' (esperado 0)');

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== PRUEBA 3: ROLLBACK PARCIAL CON SAVEPOINT ===');
    pkg_turismo.sp_crear_reserva(
        p_id_cliente         => v_cli,
        p_id_habitacion      => v_hab,
        p_cantidad_huespedes => 1,
        p_checkin            => v_in,
        p_checkout           => v_out,
        p_id_reserva         => v_res,
        p_fecha_reserva      => v_in - 30
    );

    SAVEPOINT sp_reserva_ok;

    BEGIN
        sp_registrar_pago(
            p_monto   => -50000, -- monto invalido -> ORA-20001
            p_reserva => v_res,
            p_metodo  => 'PSE',
            p_idpago  => v_pago
        );
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_reserva_ok;
            DBMS_OUTPUT.PUT_LINE('Pago fallido revertido hasta sp_reserva_ok: ' || SQLERRM);
    END;

    SELECT COUNT(*) INTO v_cnt_res  FROM Reserva WHERE id_reserva = v_res;
    SELECT COUNT(*) INTO v_cnt_pago FROM Pago    WHERE id_reserva = v_res;
    DBMS_OUTPUT.PUT_LINE('Tras rollback parcial -> Reserva id=' || v_res ||
                         ' existe (' || v_cnt_res || ' fila), Pagos (' || v_cnt_pago || ' filas)');

    ROLLBACK;
END;
/
