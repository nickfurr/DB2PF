-- =============================================================================
-- amnecia.sql
-- Script de vaciado total (TRUNCATE) de todas las tablas del proyecto TurismoUQ.
-- En Oracle, una tabla referenciada por FOREIGN KEY no permite TRUNCATE directo,
-- por lo cual este bloque deshabilita las FKs, trunca todas las tablas
-- (reiniciando secuencias IDENTITY), y vuelve a habilitar las FKs.
-- =============================================================================

SET SERVEROUTPUT ON;

BEGIN
    -- 1. Deshabilitar todas las Foreign Keys del esquema actual
    FOR c IN (SELECT table_name, constraint_name 
              FROM user_constraints 
              WHERE constraint_type = 'R' AND status = 'ENABLED') 
    LOOP
        EXECUTE IMMEDIATE 'ALTER TABLE "' || c.table_name || '" DISABLE CONSTRAINT "' || c.constraint_name || '"';
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Foreign Keys deshabilitadas.');

    -- 2. Truncar todas las tablas y reiniciar secuencias IDENTITY
    FOR t IN (
        SELECT column_value AS table_name
        FROM TABLE(sys.odcivarchar2list(
            'RESENA',
            'PAGO',
            'RESERVA_SERVICIO',
            'RESERVA_HABITACION',
            'TARIFA',
            'HABITACION',
            'SERVICIO',
            'USUARIO_SISTEMA',
            'RESERVA',
            'ALOJAMIENTO',
            'CLIENTE',
            'TEMPORADA',
            'TIPO_ALOJAMIENTO',
            'MUNICIPIO'
        ))
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'TRUNCATE TABLE "' || t.table_name || '" RESTART IDENTITY';
            DBMS_OUTPUT.PUT_LINE('Truncada: ' || t.table_name);
        EXCEPTION
            WHEN OTHERS THEN
                -- Por si la version de Oracle no soporta RESTART IDENTITY en la sintaxis de TRUNCATE
                EXECUTE IMMEDIATE 'TRUNCATE TABLE "' || t.table_name || '"';
                DBMS_OUTPUT.PUT_LINE('Truncada (estándar): ' || t.table_name);
        END;
    END LOOP;

    -- 3. Volver a habilitar todas las Foreign Keys
    FOR c IN (SELECT table_name, constraint_name 
              FROM user_constraints 
              WHERE constraint_type = 'R' AND status = 'DISABLED') 
    LOOP
        EXECUTE IMMEDIATE 'ALTER TABLE "' || c.table_name || '" ENABLE CONSTRAINT "' || c.constraint_name || '"';
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Foreign Keys habilitadas nuevamente.');
    DBMS_OUTPUT.PUT_LINE('Base de datos reseteada con éxito.');
END;
/
