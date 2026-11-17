SET SERVEROUTPUT ON
SET LINESIZE 200

-- Permite crear roles y usuarios sin prefijo C## en el mismo contenedor del proyecto
ALTER SESSION SET "_ORACLE_SCRIPT" = TRUE;

-- 1. Limpieza previa
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

-- 2. Roles
CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_aloj;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

GRANT CREATE SESSION TO rol_recepcion;
GRANT CREATE SESSION TO rol_admin_aloj;
GRANT CREATE SESSION TO rol_gerente;
GRANT CREATE SESSION TO rol_auditor;

-- 3. Perfil con limites de sesion
CREATE PROFILE perfil_recepcion LIMIT
    FAILED_LOGIN_ATTEMPTS 3
    PASSWORD_LOCK_TIME    1/1440
    PASSWORD_LIFE_TIME    90
    SESSIONS_PER_USER     1
    IDLE_TIME             15;

-- 4. Usuarios de prueba
CREATE USER u_recepcion  IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER u_admin_aloj IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER u_gerente    IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER u_auditor    IDENTIFIED BY Turismo2026 DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;

GRANT rol_recepcion  TO u_recepcion;
GRANT rol_admin_aloj TO u_admin_aloj;
GRANT rol_gerente    TO u_gerente;
GRANT rol_auditor    TO u_auditor;

ALTER USER u_recepcion PROFILE perfil_recepcion;

-- 5. Evidencia
SELECT grantee, granted_role
  FROM dba_role_privs
 WHERE grantee IN ('U_RECEPCION','U_ADMIN_ALOJ','U_GERENTE','U_AUDITOR')
 ORDER BY grantee;