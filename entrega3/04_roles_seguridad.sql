-- ENTREGA 3 - TurismoUQ
-- 04. Seguridad: 4 roles con privilegios diferenciados, vistas para recepcion,
--     un perfil con limites de sesion, usuarios y GRANT.
--
-- Roles:
--   rol_recepcion   crea y consulta reservas, SOLO a traves de vistas y del
--                   paquete; nunca toca las tablas directamente.
--   rol_admin_aloj  administra el inventario: habitaciones, tarifas y servicios.
--   rol_gerente     consulta todo, incluida la vista materializada de ocupacion.
--   rol_auditor     solo lectura, incluida la auditoria de tarifas.
--
-- PERMISOS PARA EJECUTARLO:
--   CREATE USER / CREATE ROLE / CREATE PROFILE y GRANT de privilegios de sistema
--   requieren un usuario administrador (SYSTEM o un rol DBA). Los GRANT sobre las
--   tablas y vistas se dan como DUENO del esquema TurismoUQ.
--   En una base multitenant (CDB), conectarse a la PDB; en CDB$ROOT los usuarios
--   locales deben llamarse C##nombre (ORA-65096).

-- 1. Vistas para recepcion (ocultan datos personales del cliente)
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

-- 2. Roles
CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_aloj;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

-- Entrar a la base
GRANT CREATE SESSION TO rol_recepcion;
GRANT CREATE SESSION TO rol_admin_aloj;
GRANT CREATE SESSION TO rol_gerente;
GRANT CREATE SESSION TO rol_auditor;

-- rol_recepcion: SOLO vistas + ejecutar el paquete y el procedimiento de reserva.
-- No recibe ningun privilegio sobre las tablas base.
GRANT SELECT ON v_recepcion_reservas     TO rol_recepcion;
GRANT SELECT ON v_recepcion_habitaciones TO rol_recepcion;
GRANT EXECUTE ON pkg_turismo             TO rol_recepcion;
GRANT EXECUTE ON sp_reservar_y_pagar     TO rol_recepcion;
GRANT EXECUTE ON sp_registrar_pago       TO rol_recepcion;

-- rol_admin_aloj: administra el inventario del alojamiento.
GRANT SELECT, INSERT, UPDATE ON Habitacion TO rol_admin_aloj;
GRANT SELECT, INSERT, UPDATE ON Tarifa     TO rol_admin_aloj;
GRANT SELECT, INSERT, UPDATE ON Servicio   TO rol_admin_aloj;
GRANT SELECT ON Reserva            TO rol_admin_aloj;
GRANT SELECT ON Reserva_Habitacion TO rol_admin_aloj;

-- rol_gerente: consulta todo + la vista materializada de ocupacion.
GRANT SELECT ON Reserva             TO rol_gerente;
GRANT SELECT ON Reserva_Habitacion  TO rol_gerente;
GRANT SELECT ON Pago                TO rol_gerente;
GRANT SELECT ON Alojamiento         TO rol_gerente;
GRANT SELECT ON Habitacion          TO rol_gerente;
GRANT SELECT ON mv_ocupacion_mensual TO rol_gerente;

-- rol_auditor: solo lectura, incluida la auditoria de tarifas.
GRANT SELECT ON Pago            TO rol_auditor;
GRANT SELECT ON Tarifa          TO rol_auditor;
GRANT SELECT ON Auditoria_Tarifa TO rol_auditor;
GRANT SELECT ON Reserva         TO rol_auditor;

-- 3. Perfil con limites de sesion (para la ventanilla de recepcion)
CREATE PROFILE perfil_recepcion LIMIT
    FAILED_LOGIN_ATTEMPTS 3        -- 3 claves malas y se bloquea
    PASSWORD_LOCK_TIME    1/1440   -- bloqueo de 1 minuto (demo; normal: 1 dia)
    PASSWORD_LIFE_TIME    90       -- la clave vence a los 90 dias
    SESSIONS_PER_USER     1        -- una sola sesion a la vez
    IDLE_TIME             15;      -- 15 minutos inactivo y se cierra

-- 4. Usuarios (cambiar las claves). Cada uno recibe su rol.
CREATE USER u_recepcion  IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER u_admin_aloj IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER u_gerente    IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER u_auditor    IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;

GRANT rol_recepcion  TO u_recepcion;
GRANT rol_admin_aloj TO u_admin_aloj;
GRANT rol_gerente    TO u_gerente;
GRANT rol_auditor    TO u_auditor;

-- Recepcion con limites de sesion
ALTER USER u_recepcion PROFILE perfil_recepcion;

-- 5. Comprobaciones
--    (ejecutar conectado como cada usuario para ver que SI y que NO puede)
-- Como u_recepcion:
--   SELECT * FROM turismouq.v_recepcion_reservas;   -- OK (vista)
--   SELECT * FROM turismouq.Reserva;                -- ORA-00942 (no ve la tabla)
-- Como u_auditor:
--   SELECT * FROM turismouq.Auditoria_Tarifa;       -- OK
--   DELETE FROM turismouq.Pago;                     -- ORA-01031 (solo lectura)

-- Quien tiene que rol y con que perfil
SELECT grantee, granted_role FROM dba_role_privs
 WHERE grantee IN ('U_RECEPCION','U_ADMIN_ALOJ','U_GERENTE','U_AUDITOR')
 ORDER BY grantee;
SELECT username, profile FROM dba_users
 WHERE username IN ('U_RECEPCION','U_ADMIN_ALOJ','U_GERENTE','U_AUDITOR');
