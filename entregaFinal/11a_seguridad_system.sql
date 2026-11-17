-- =============================================================================
-- ENTREGA FINAL - TurismoUQ
-- 11a. Seguridad (parte administrativa): perfil con limites de sesion, 4 roles
--      y 4 usuarios de prueba.
--
-- >>> EJECUTAR COMO SYSTEM en el mismo contenedor donde vive el esquema. <<<
-- =============================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200

-- Si se ejecuta desde CDB$ROOT, habilitar _ORACLE_SCRIPT para crear roles y
-- usuarios locales en el mismo contenedor del proyecto. En una PDB no hace falta.
BEGIN
    IF SYS_CONTEXT('USERENV', 'CON_NAME') = 'CDB$ROOT' THEN
        EXECUTE IMMEDIATE 'ALTER SESSION SET "_ORACLE_SCRIPT" = TRUE';
    END IF;
    DBMS_OUTPUT.PUT_LINE('Contenedor actual: ' || SYS_CONTEXT('USERENV', 'CON_NAME'));
END;
/

-- 1. Limpieza previa (permite re-ejecutar el script sobre la misma instancia)
BEGIN
    FOR u IN (SELECT username FROM dba_users
               WHERE username IN ('U_RECEPCION','U_ADMIN_ALOJ','U_GERENTE','U_AUDITOR')) LOOP
        EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
    END LOOP;
    FOR r IN (SELECT role FROM dba_roles
               WHERE role IN ('ROL_RECEPCION','ROL_ADMIN_ALOJ','ROL_GERENTE','ROL_AUDITOR')) LOOP
        EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
    END LOOP;
    FOR p IN (SELECT DISTINCT profile FROM dba_profiles WHERE profile = 'PERFIL_RECEPCION') LOOP
        EXECUTE IMMEDIATE 'DROP PROFILE ' || p.profile || ' CASCADE';
    END LOOP;
END;
/

-- 2. Roles con privilegios diferenciados
CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_aloj;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

GRANT CREATE SESSION TO rol_recepcion;
GRANT CREATE SESSION TO rol_admin_aloj;
GRANT CREATE SESSION TO rol_gerente;
GRANT CREATE SESSION TO rol_auditor;

-- 3. Perfil con limites de sesion (para la ventanilla de recepcion)
CREATE PROFILE perfil_recepcion LIMIT
    FAILED_LOGIN_ATTEMPTS 3        -- 3 claves malas y se bloquea
    PASSWORD_LOCK_TIME    1/1440   -- bloqueo de 1 minuto (demo; produccion: 1 dia)
    PASSWORD_LIFE_TIME    90       -- la clave vence a los 90 dias
    SESSIONS_PER_USER     1        -- una sola sesion a la vez
    IDLE_TIME             15;      -- 15 minutos inactivo y se cierra

-- 4. Usuarios de prueba (cada uno recibe su rol)
CREATE USER u_recepcion  IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER u_admin_aloj IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER u_gerente    IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER u_auditor    IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;

GRANT rol_recepcion  TO u_recepcion;
GRANT rol_admin_aloj TO u_admin_aloj;
GRANT rol_gerente    TO u_gerente;
GRANT rol_auditor    TO u_auditor;

ALTER USER u_recepcion PROFILE perfil_recepcion;

-- 5. Evidencia: roles y perfiles asignados
SELECT grantee, granted_role
  FROM dba_role_privs
 WHERE grantee IN ('U_RECEPCION','U_ADMIN_ALOJ','U_GERENTE','U_AUDITOR')
 ORDER BY grantee;

SELECT username, profile
  FROM dba_users
 WHERE username IN ('U_RECEPCION','U_ADMIN_ALOJ','U_GERENTE','U_AUDITOR')
 ORDER BY username;
