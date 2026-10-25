-- ENTREGA 2 - TurismoUQ
-- 02. Disparadores: auditoria de TARIFA y control de solape de reservas.

SET SERVEROUTPUT ON

-- -----------------------------------------------------------------------------
-- Disparador de SENTENCIA: auditoria de cambios sobre TARIFA.
-- Registra quien, cuando, la operacion, el valor anterior y el nuevo.
--
-- Por que un disparador compuesto (COMPOUND TRIGGER):
--   Un disparador de sentencia "puro" (sin FOR EACH ROW) se ejecuta una vez
--   por instruccion, pero no puede leer :OLD ni :NEW (ORA-04082), asi que no
--   sabria el valor anterior ni el nuevo. El disparador compuesto reune en un
--   solo objeto varios momentos de la misma sentencia:
--     BEFORE STATEMENT -> se ejecuta una vez: toma el usuario y la hora de la
--                         sentencia y limpia la lista de cambios.
--     AFTER EACH ROW   -> solo ANOTA en memoria cada fila cambiada (:OLD/:NEW).
--     AFTER STATEMENT  -> se ejecuta una vez, al terminar la sentencia, y
--                         escribe la auditoria de todas las filas.
--   Asi la auditoria se graba a nivel de sentencia: un UPDATE que cambia 40
--   tarifas produce 40 filas con el MISMO usuario y la MISMA fecha_cambio, y un
--   UPDATE que no cambia nada no deja rastro.
--   Un UPDATE que asigna el mismo valor (valor_noche = valor_noche) no se
--   registra, porque no es un cambio real de precio.
--
-- La tabla Auditoria_Tarifa se crea en ScriptDDL.sql (Entrega 1).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_auditoria_tarifa
FOR INSERT OR UPDATE OF valor_noche OR DELETE ON Tarifa
COMPOUND TRIGGER

    TYPE t_cambio IS RECORD (
        id_tarifa      Tarifa.id_tarifa%TYPE,
        operacion      VARCHAR2(10),
        valor_anterior NUMBER,
        valor_nuevo    NUMBER
    );
    TYPE t_cambios IS TABLE OF t_cambio INDEX BY PLS_INTEGER;

    g_cambios t_cambios;
    g_usuario Auditoria_Tarifa.usuario%TYPE;
    g_momento TIMESTAMP;

    BEFORE STATEMENT IS
    BEGIN
        g_cambios.DELETE;
        -- Quien: usuario de base de datos y usuario del sistema operativo.
        g_usuario := SUBSTR(SYS_CONTEXT('USERENV', 'SESSION_USER') || ' (' ||
                            SYS_CONTEXT('USERENV', 'OS_USER') || ')', 1, 128);
        -- Cuando: una sola marca de tiempo para toda la sentencia.
        g_momento := SYSTIMESTAMP;
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
        v_i PLS_INTEGER;
    BEGIN
        -- Un UPDATE que deja el mismo precio no es un cambio: no se anota.
        IF NOT (UPDATING AND :OLD.valor_noche = :NEW.valor_noche) THEN
            v_i := g_cambios.COUNT + 1;
            IF INSERTING THEN
                g_cambios(v_i).id_tarifa      := :NEW.id_tarifa;
                g_cambios(v_i).operacion      := 'INSERT';
                g_cambios(v_i).valor_anterior := NULL;
                g_cambios(v_i).valor_nuevo    := :NEW.valor_noche;
            ELSIF UPDATING THEN
                g_cambios(v_i).id_tarifa      := :OLD.id_tarifa;
                g_cambios(v_i).operacion      := 'UPDATE';
                g_cambios(v_i).valor_anterior := :OLD.valor_noche;
                g_cambios(v_i).valor_nuevo    := :NEW.valor_noche;
            ELSE
                g_cambios(v_i).id_tarifa      := :OLD.id_tarifa;
                g_cambios(v_i).operacion      := 'DELETE';
                g_cambios(v_i).valor_anterior := :OLD.valor_noche;
                g_cambios(v_i).valor_nuevo    := NULL;
            END IF;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
    BEGIN
        FOR i IN 1 .. g_cambios.COUNT LOOP
            INSERT INTO Auditoria_Tarifa (
                id_tarifa, usuario, fecha_cambio, operacion, valor_anterior, valor_nuevo
            ) VALUES (
                g_cambios(i).id_tarifa,
                g_usuario,
                g_momento,
                g_cambios(i).operacion,
                g_cambios(i).valor_anterior,
                g_cambios(i).valor_nuevo
            );
        END LOOP;
        g_cambios.DELETE;
    END AFTER STATEMENT;

END trg_auditoria_tarifa;
/

-- -----------------------------------------------------------------------------
-- Disparador de FILA: impide que una habitacion quede reservada dos veces en
-- fechas que se cruzan con una reserva CONFIRMADA.
--
-- Dos rangos [checkin, checkout) se solapan si
--     nuevo.checkin < otro.checkout  AND  nuevo.checkout > otro.checkin
-- (el dia de checkout de uno puede ser el checkin del otro).
--
-- Por que un disparador compuesto y no un FOR EACH ROW simple:
--   Para saber si hay solape hay que consultar RESERVA_HABITACION, que es la
--   misma tabla que se esta modificando. Un disparador de fila que la consulta
--   falla con ORA-04091 (tabla mutante) en un INSERT ... SELECT o en un UPDATE.
--   La version anterior lo esquivaba con PRAGMA AUTONOMOUS_TRANSACTION, pero
--   una transaccion autonoma NO ve las filas aun no confirmadas de la
--   transaccion principal: dos lineas solapadas insertadas antes del COMMIT
--   pasaban sin error.
--   Aqui la seccion AFTER EACH ROW toma cada fila insertada o modificada
--   (:NEW) y la seccion AFTER STATEMENT, cuando la tabla ya no esta mutando,
--   revisa fila por fila contra todas las reservas confirmadas, incluidas las
--   que la misma transaccion acaba de insertar. Si una fila choca, se lanza
--   ORA-20020 y Oracle deshace la sentencia completa.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_reserva_no_solape
FOR INSERT OR UPDATE OF id_habitacion, checkin, checkout ON Reserva_Habitacion
COMPOUND TRIGGER

    TYPE t_linea IS RECORD (
        id_reserva_habitacion Reserva_Habitacion.id_reserva_habitacion%TYPE,
        id_habitacion         Reserva_Habitacion.id_habitacion%TYPE,
        checkin               Reserva_Habitacion.checkin%TYPE,
        checkout              Reserva_Habitacion.checkout%TYPE
    );
    TYPE t_lineas IS TABLE OF t_linea INDEX BY PLS_INTEGER;

    g_lineas t_lineas;

    BEFORE STATEMENT IS
    BEGIN
        g_lineas.DELETE;
    END BEFORE STATEMENT;

    -- Nivel de fila: se anota cada linea nueva o modificada.
    AFTER EACH ROW IS
        v_i PLS_INTEGER := g_lineas.COUNT + 1;
    BEGIN
        g_lineas(v_i).id_reserva_habitacion := :NEW.id_reserva_habitacion;
        g_lineas(v_i).id_habitacion         := :NEW.id_habitacion;
        g_lineas(v_i).checkin               := :NEW.checkin;
        g_lineas(v_i).checkout              := :NEW.checkout;
    END AFTER EACH ROW;

    -- Al terminar la sentencia: cada linea anotada se compara con las demas
    -- lineas de la misma habitacion que pertenecen a reservas confirmadas.
    AFTER STATEMENT IS
        v_conflictos NUMBER;
        v_reserva    NUMBER;
    BEGIN
        FOR i IN 1 .. g_lineas.COUNT LOOP
            SELECT COUNT(*), MIN(rh.id_reserva)
              INTO v_conflictos, v_reserva
              FROM Reserva_Habitacion rh
              JOIN Reserva r ON r.id_reserva = rh.id_reserva
             WHERE rh.id_habitacion          = g_lineas(i).id_habitacion
               AND rh.id_reserva_habitacion <> g_lineas(i).id_reserva_habitacion
               AND r.estado   = 'confirmada'
               AND rh.checkin  < g_lineas(i).checkout
               AND rh.checkout > g_lineas(i).checkin;

            IF v_conflictos > 0 THEN
                RAISE_APPLICATION_ERROR(-20020,
                    'La habitacion ' || g_lineas(i).id_habitacion || ' no esta disponible del ' ||
                    TO_CHAR(g_lineas(i).checkin, 'YYYY-MM-DD') || ' al ' ||
                    TO_CHAR(g_lineas(i).checkout, 'YYYY-MM-DD') ||
                    ': se cruza con la reserva confirmada ' || v_reserva ||
                    CASE WHEN v_conflictos > 1 THEN ' (y ' || (v_conflictos - 1) || ' mas)' END || '.');
            END IF;
        END LOOP;
        g_lineas.DELETE;
    END AFTER STATEMENT;

END trg_reserva_no_solape;
/
