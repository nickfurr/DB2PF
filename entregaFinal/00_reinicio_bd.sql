-- =============================================================================
-- ENTREGA FINAL - TurismoUQ
-- 00. Reinicio seguro del esquema (opcional si se ejecuta sobre una base ya
--     poblada). Ignora los errores si los objetos aun no existen.
-- Ejecutar con el usuario dueno del esquema del proyecto.
-- =============================================================================
SET SERVEROUTPUT ON

DECLARE
    PROCEDURE ejecutar_drop (p_sql VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;
BEGIN
    ejecutar_drop('DROP PROCEDURE sp_reservar_y_pagar');
    ejecutar_drop('DROP PROCEDURE sp_registrar_pago');
    ejecutar_drop('DROP VIEW v_recepcion_reservas');
    ejecutar_drop('DROP VIEW v_recepcion_habitaciones');
    ejecutar_drop('DROP MATERIALIZED VIEW mv_ocupacion_mensual');
    ejecutar_drop('DROP PACKAGE pkg_turismo');

    FOR t IN (
        SELECT table_name FROM user_tables
         WHERE table_name IN (
             'AUDITORIA_TARIFA','RESENA','PAGO','RESERVA_SERVICIO',
             'RESERVA_HABITACION','TARIFA','RESERVA','HABITACION',
             'SERVICIO','USUARIO_SISTEMA','ALOJAMIENTO','TEMPORADA',
             'TIPO_ALOJAMIENTO','CLIENTE','MUNICIPIO'
         )
    ) LOOP
        ejecutar_drop('DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE');
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Esquema limpio y listo para ejecutar desde 02_DDL.sql.');
END;
/
