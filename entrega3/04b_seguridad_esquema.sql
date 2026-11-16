-- =============================================================================
-- ENTREGA 3 - TurismoUQ
-- 04b. Seguridad (objetos del esquema): vistas para recepcion y GRANT a roles.
--
-- >>> EJECUTAR CON EL USUARIO DUENO DEL ESQUEMA DEL PROYECTO, despues de haber
--     ejecutado 04a_seguridad_system.sql como SYSTEM. <<<
-- =============================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200

-- 1. Vistas para recepcion (ocultan datos personales del cliente como cedula,
--    correo y telefono; recepcion nunca accede a las tablas directamente).
CREATE OR REPLACE VIEW v_recepcion_reservas AS
SELECT r.id_reserva,
       c.nombre            AS cliente,
       a.nombre_comercial  AS alojamiento,
       h.numero            AS habitacion,
       rh.checkin,
       rh.checkout,
       r.estado
  FROM Reserva r
  JOIN Cliente            c  ON c.id_cliente     = r.id_cliente
  JOIN Reserva_Habitacion rh ON rh.id_reserva    = r.id_reserva
  JOIN Habitacion         h  ON h.id_habitacion  = rh.id_habitacion
  JOIN Alojamiento        a  ON a.id_alojamiento = h.id_alojamiento;

CREATE OR REPLACE VIEW v_recepcion_habitaciones AS
SELECT h.id_habitacion,
       a.nombre_comercial AS alojamiento,
       h.numero,
       h.tipo,
       h.capacidad
  FROM Habitacion  h
  JOIN Alojamiento a ON a.id_alojamiento = h.id_alojamiento;

-- 2. Privilegios diferenciados para los 4 roles

-- rol_recepcion: SOLO vistas + ejecutar el paquete y los procedimientos de
-- reserva y pago. No recibe ningun privilegio sobre las tablas base.
GRANT SELECT  ON v_recepcion_reservas     TO rol_recepcion;
GRANT SELECT  ON v_recepcion_habitaciones TO rol_recepcion;
GRANT EXECUTE ON pkg_turismo              TO rol_recepcion;
GRANT EXECUTE ON sp_reservar_y_pagar      TO rol_recepcion;
GRANT EXECUTE ON sp_registrar_pago        TO rol_recepcion;

-- rol_admin_aloj: administra el inventario del alojamiento.
GRANT SELECT, INSERT, UPDATE ON Habitacion         TO rol_admin_aloj;
GRANT SELECT, INSERT, UPDATE ON Tarifa             TO rol_admin_aloj;
GRANT SELECT, INSERT, UPDATE ON Servicio           TO rol_admin_aloj;
GRANT SELECT                 ON Reserva            TO rol_admin_aloj;
GRANT SELECT                 ON Reserva_Habitacion TO rol_admin_aloj;

-- rol_gerente: consulta todo + la vista materializada de ocupacion.
GRANT SELECT ON Reserva              TO rol_gerente;
GRANT SELECT ON Reserva_Habitacion   TO rol_gerente;
GRANT SELECT ON Pago                 TO rol_gerente;
GRANT SELECT ON Alojamiento          TO rol_gerente;
GRANT SELECT ON Habitacion           TO rol_gerente;
GRANT SELECT ON mv_ocupacion_mensual TO rol_gerente;

-- rol_auditor: solo lectura, incluida la auditoria de tarifas.
GRANT SELECT ON Pago             TO rol_auditor;
GRANT SELECT ON Tarifa           TO rol_auditor;
GRANT SELECT ON Auditoria_Tarifa TO rol_auditor;
GRANT SELECT ON Reserva          TO rol_auditor;

-- 3. Evidencia de privilegios otorgados en este esquema
SELECT grantee, table_name, privilege
  FROM user_tab_privs_made
 WHERE grantee IN ('ROL_RECEPCION','ROL_ADMIN_ALOJ','ROL_GERENTE','ROL_AUDITOR')
 ORDER BY grantee, table_name, privilege;

-- 4. Comprobaciones manuales (ejecutar conectado como cada usuario de prueba,
--    reemplazando <esquema_proyecto> por el nombre del usuario dueno del esquema):
-- Como u_recepcion:
--   SELECT * FROM <esquema_proyecto>.v_recepcion_reservas FETCH FIRST 5 ROWS ONLY; -- OK (vista)
--   SELECT * FROM <esquema_proyecto>.Reserva;                                     -- ORA-00942 (sin acceso a tabla)
--   SELECT * FROM <esquema_proyecto>.Cliente;                                     -- ORA-00942 (sin acceso a tabla)
-- Como u_auditor:
--   SELECT * FROM <esquema_proyecto>.Auditoria_Tarifa;                            -- OK
--   DELETE FROM <esquema_proyecto>.Pago;                                          -- ORA-01031 (solo lectura)
