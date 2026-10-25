-- =============================================================================
-- ENTREGA 2 - TurismoUQ
-- 03a. Tablespace del historico de reservas.
--
-- >>> EJECUTAR COMO SYSTEM, conectado a la misma PDB del esquema del proyecto
--     (en Oracle XE normalmente XEPDB1). <<<
--
-- Crear tablespaces es una tarea del administrador de la base de datos, no del
-- dueno del esquema: por eso este paso va aparte. El script crea el tablespace
-- y le da cuota al esquema del proyecto; despues, el dueno del esquema ejecuta
-- 03b_historico_vista_materializada.sql, que lleva alli el historico.
-- La justificacion de separar el historico esta en el encabezado de 03b.
--
-- El script se puede correr varias veces: si el tablespace existe, solo
-- informa.
-- =============================================================================
SET SERVEROUTPUT ON
SET VERIFY OFF

-- Esquema del proyecto (cambiar si el usuario se llama distinto)
DEFINE esquema = PROJEC

DECLARE
    v_esquema  VARCHAR2(128) := UPPER('&esquema');
    v_existe   NUMBER;
    v_ruta     VARCHAR2(600);
    v_archivo  VARCHAR2(700);
BEGIN
    DBMS_OUTPUT.PUT_LINE('Contenedor actual: ' || SYS_CONTEXT('USERENV', 'CON_NAME'));

    -- El esquema debe existir en este contenedor
    SELECT COUNT(*) INTO v_existe FROM dba_users WHERE username = v_esquema;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20030,
            'El usuario ' || v_esquema || ' no existe en ' || SYS_CONTEXT('USERENV', 'CON_NAME') ||
            '. Conectese como SYSTEM a la PDB del proyecto (por ejemplo XEPDB1).');
    END IF;

    SELECT COUNT(*) INTO v_existe FROM dba_tablespaces WHERE tablespace_name = 'TS_RESERVAS_HIST';
    IF v_existe > 0 THEN
        DBMS_OUTPUT.PUT_LINE('El tablespace TS_RESERVAS_HIST ya existia.');
    ELSE
        -- El datafile se crea en la misma carpeta que el del tablespace USERS
        -- de esta base, para no depender de una ruta escrita a mano.
        SELECT SUBSTR(file_name, 1, INSTR(REPLACE(file_name, '\', '/'), '/', -1))
          INTO v_ruta
          FROM dba_data_files
         WHERE tablespace_name = 'USERS'
           AND ROWNUM = 1;
        v_archivo := v_ruta || 'ts_reservas_hist_01.dbf';

        EXECUTE IMMEDIATE
            'CREATE TABLESPACE ts_reservas_hist ' ||
            'DATAFILE ''' || v_archivo || ''' SIZE 50M AUTOEXTEND ON NEXT 10M MAXSIZE 500M';
        DBMS_OUTPUT.PUT_LINE('Tablespace TS_RESERVAS_HIST creado en ' || v_archivo);
    END IF;

    EXECUTE IMMEDIATE 'ALTER USER ' || v_esquema || ' QUOTA UNLIMITED ON ts_reservas_hist';
    DBMS_OUTPUT.PUT_LINE('Cuota ilimitada sobre TS_RESERVAS_HIST otorgada a ' || v_esquema || '.');
END;
/

-- Evidencia: el tablespace y su datafile
SELECT t.tablespace_name, t.status, t.contents, f.file_name,
       ROUND(f.bytes / 1024 / 1024) AS mb, f.autoextensible
  FROM dba_tablespaces t
  JOIN dba_data_files  f ON f.tablespace_name = t.tablespace_name
 WHERE t.tablespace_name = 'TS_RESERVAS_HIST';

SELECT username, tablespace_name,
       CASE max_bytes WHEN -1 THEN 'ILIMITADA' ELSE TO_CHAR(max_bytes) END AS cuota
  FROM dba_ts_quotas
 WHERE tablespace_name = 'TS_RESERVAS_HIST';
