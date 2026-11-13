
-- PASO 0: Buscar un cliente y una habitacion libre del 2026-12-20 al 2026-12-22
SELECT MIN(id_cliente) AS id_cliente FROM Cliente;

SELECT MIN(h.id_habitacion) AS id_habitacion_libre
  FROM Habitacion h
 WHERE h.id_habitacion NOT IN (
       SELECT rh.id_habitacion
         FROM Reserva_Habitacion rh
         JOIN Reserva r ON r.id_reserva = rh.id_reserva
        WHERE r.estado <> 'cancelada'
          AND rh.checkin  < DATE '2026-12-22'
          AND rh.checkout > DATE '2026-12-20'
 );


-- EXPERIMENTO: Ejecutar en 2 terminales (antes y despues de agregar FOR UPDATE)

-- [TERMINAL 1 - Sesion A] Ejecutar SIN hacer COMMIT todavia:
SET SERVEROUTPUT ON
DECLARE
    v_res Reserva.id_reserva%TYPE;
BEGIN
    pkg_turismo.sp_crear_reserva(
        p_id_cliente         => 1,
        p_id_habitacion      => 2,
        p_cantidad_huespedes => 1,
        p_checkin            => DATE '2026-12-20',
        p_checkout           => DATE '2026-12-22',
        p_id_reserva         => v_res,
        p_fecha_reserva      => DATE '2026-11-20'
    );
    DBMS_OUTPUT.PUT_LINE('[Sesion A] reserva creada (sin commit): ' || v_res);
END;
/

-- [TERMINAL 2 - Sesion B] Ejecutar mientras Sesion A sigue abierta:
SET SERVEROUTPUT ON
DECLARE
    v_res Reserva.id_reserva%TYPE;
BEGIN
    pkg_turismo.sp_crear_reserva(
        p_id_cliente         => 1,
        p_id_habitacion      => 2,
        p_cantidad_huespedes => 1,
        p_checkin            => DATE '2026-12-20',
        p_checkout           => DATE '2026-12-22',
        p_id_reserva         => v_res,
        p_fecha_reserva      => DATE '2026-11-20'
    );
    DBMS_OUTPUT.PUT_LINE('[Sesion B] reserva creada: ' || v_res);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[Sesion B] error: ' || SQLERRM);
END;
/

-- [TERMINAL 1 y TERMINAL 2] Limpiar ambas sesiones al terminar cada corrida:
ROLLBACK;
