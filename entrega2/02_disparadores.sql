-- ENTREGA 2 - TurismoUQ
-- 02. Disparadores: auditoria de TARIFA, control de solape de reservas y de
--     temporadas.
--
-- Codigos de error propios:
--   -20020  Una linea de reserva se cruza con otra reserva no cancelada.
--   -20021  Una reserva cancelada no se puede reactivar: sus fechas ya estan ocupadas.
--   -20022  Una temporada se cruza con otra.

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
-- fechas que se cruzan.
--
-- Que reservas ocupan la habitacion: todas las que NO estan canceladas.
--   * confirmada: es la regla del enunciado.
--   * pendiente:  ya tiene anticipo; si no ocupara, otra reserva podria tomar
--                 la habitacion y luego, al confirmar la pendiente, quedarian
--                 dos reservas confirmadas en las mismas fechas.
--   * completada: es una estadia que ya ocurrio.
-- Es la misma regla que aplica sp_crear_reserva y la que sigue la carga de
-- datos (verificacion: 0 solapes entre reservas no canceladas).
-- Una linea de una reserva cancelada no ocupa ni se valida.
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
--   revisa fila por fila contra todas las reservas no canceladas, incluidas
--   las que la misma transaccion acaba de insertar. Si una fila choca, se
--   lanza ORA-20020 y Oracle deshace la sentencia completa.
--   Tambien se dispara si una linea cambia de reserva (id_reserva), porque
--   puede pasar de una reserva cancelada a una activa.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_reserva_no_solape
FOR INSERT OR UPDATE OF id_reserva, id_habitacion, checkin, checkout ON Reserva_Habitacion
COMPOUND TRIGGER

    TYPE t_linea IS RECORD (
        id_reserva_habitacion Reserva_Habitacion.id_reserva_habitacion%TYPE,
        id_reserva            Reserva_Habitacion.id_reserva%TYPE,
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
        g_lineas(v_i).id_reserva            := :NEW.id_reserva;
        g_lineas(v_i).id_habitacion         := :NEW.id_habitacion;
        g_lineas(v_i).checkin               := :NEW.checkin;
        g_lineas(v_i).checkout              := :NEW.checkout;
    END AFTER EACH ROW;

    -- Al terminar la sentencia: cada linea anotada de una reserva activa se
    -- compara con las demas lineas de la misma habitacion que pertenecen a
    -- reservas no canceladas.
    AFTER STATEMENT IS
        v_estado     Reserva.estado%TYPE;
        v_conflictos NUMBER;
        v_reserva    NUMBER;
    BEGIN
        FOR i IN 1 .. g_lineas.COUNT LOOP
            SELECT estado INTO v_estado
              FROM Reserva
             WHERE id_reserva = g_lineas(i).id_reserva;

            IF v_estado <> 'cancelada' THEN
                SELECT COUNT(*), MIN(rh.id_reserva)
                  INTO v_conflictos, v_reserva
                  FROM Reserva_Habitacion rh
                  JOIN Reserva r ON r.id_reserva = rh.id_reserva
                 WHERE rh.id_habitacion          = g_lineas(i).id_habitacion
                   AND rh.id_reserva_habitacion <> g_lineas(i).id_reserva_habitacion
                   AND r.estado  <> 'cancelada'
                   AND rh.checkin  < g_lineas(i).checkout
                   AND rh.checkout > g_lineas(i).checkin;

                IF v_conflictos > 0 THEN
                    RAISE_APPLICATION_ERROR(-20020,
                        'La habitacion ' || g_lineas(i).id_habitacion || ' no esta disponible del ' ||
                        TO_CHAR(g_lineas(i).checkin, 'YYYY-MM-DD') || ' al ' ||
                        TO_CHAR(g_lineas(i).checkout, 'YYYY-MM-DD') ||
                        ': se cruza con la reserva ' || v_reserva ||
                        CASE WHEN v_conflictos > 1 THEN ' (y ' || (v_conflictos - 1) || ' mas)' END || '.');
                END IF;
            END IF;
        END LOOP;
        g_lineas.DELETE;
    END AFTER STATEMENT;

END trg_reserva_no_solape;
/

-- -----------------------------------------------------------------------------
-- Complemento de trg_reserva_no_solape: reactivar una reserva cancelada.
--
-- Una reserva cancelada no ocupa la habitacion, asi que otra reserva puede
-- tomar esas fechas. Si despues la cancelada vuelve a pendiente, confirmada o
-- completada con un UPDATE de RESERVA, el disparador de RESERVA_HABITACION no
-- se entera (sus lineas no cambian) y quedarian dos reservas activas en la
-- misma habitacion y fechas. Este disparador revisa ese caso.
-- El paso de pendiente a confirmada no necesita revision: la pendiente ya
-- ocupaba la habitacion y ninguna otra reserva pudo cruzarse con ella.
-- Es compuesto por la misma razon que el anterior: en AFTER STATEMENT puede
-- consultar RESERVA sin error de tabla mutante.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_reserva_reactivacion
FOR UPDATE OF estado ON Reserva
COMPOUND TRIGGER

    TYPE t_ids IS TABLE OF Reserva.id_reserva%TYPE INDEX BY PLS_INTEGER;
    g_reservas t_ids;

    BEFORE STATEMENT IS
    BEGIN
        g_reservas.DELETE;
    END BEFORE STATEMENT;

    -- Nivel de fila: se anotan solo las reservas que salen de 'cancelada'.
    AFTER EACH ROW IS
    BEGIN
        IF :OLD.estado = 'cancelada' AND :NEW.estado <> 'cancelada' THEN
            g_reservas(g_reservas.COUNT + 1) := :NEW.id_reserva;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_conflictos NUMBER;
        v_reserva    NUMBER;
    BEGIN
        FOR i IN 1 .. g_reservas.COUNT LOOP
            FOR l IN (SELECT id_reserva_habitacion, id_habitacion, checkin, checkout
                        FROM Reserva_Habitacion
                       WHERE id_reserva = g_reservas(i)) LOOP
                SELECT COUNT(*), MIN(rh.id_reserva)
                  INTO v_conflictos, v_reserva
                  FROM Reserva_Habitacion rh
                  JOIN Reserva r ON r.id_reserva = rh.id_reserva
                 WHERE rh.id_habitacion          = l.id_habitacion
                   AND rh.id_reserva_habitacion <> l.id_reserva_habitacion
                   AND r.estado  <> 'cancelada'
                   AND rh.checkin  < l.checkout
                   AND rh.checkout > l.checkin;

                IF v_conflictos > 0 THEN
                    RAISE_APPLICATION_ERROR(-20021,
                        'No se puede reactivar la reserva ' || g_reservas(i) ||
                        ': la habitacion ' || l.id_habitacion || ' ya esta ocupada del ' ||
                        TO_CHAR(l.checkin, 'YYYY-MM-DD') || ' al ' ||
                        TO_CHAR(l.checkout, 'YYYY-MM-DD') || ' por la reserva ' || v_reserva || '.');
                END IF;
            END LOOP;
        END LOOP;
        g_reservas.DELETE;
    END AFTER STATEMENT;

END trg_reserva_reactivacion;
/

-- -----------------------------------------------------------------------------
-- Temporadas sin solape: cada noche debe pertenecer a UNA sola temporada para
-- que fn_valor_estadia sepa que tarifa cobrar. El DDL solo impide dos
-- temporadas con la misma fecha de inicio (UNIQUE); este disparador impide
-- cualquier cruce de rangos [fecha_inicio, fecha_fin] (ambos dias incluidos).
-- fn_valor_estadia conserva su error -20006 como segunda barrera.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_temporada_no_solape
FOR INSERT OR UPDATE OF fecha_inicio, fecha_fin ON Temporada
COMPOUND TRIGGER

    TYPE t_ids IS TABLE OF Temporada.id_temporada%TYPE INDEX BY PLS_INTEGER;
    g_temporadas t_ids;

    BEFORE STATEMENT IS
    BEGIN
        g_temporadas.DELETE;
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
    BEGIN
        g_temporadas(g_temporadas.COUNT + 1) := :NEW.id_temporada;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_nombre Temporada.nombre%TYPE;
        v_otra   Temporada.nombre%TYPE;
    BEGIN
        FOR i IN 1 .. g_temporadas.COUNT LOOP
            SELECT MIN(o.nombre), MIN(t.nombre)
              INTO v_otra, v_nombre
              FROM Temporada t
              JOIN Temporada o ON o.id_temporada <> t.id_temporada
                              AND o.fecha_inicio <= t.fecha_fin
                              AND o.fecha_fin    >= t.fecha_inicio
             WHERE t.id_temporada = g_temporadas(i);

            IF v_otra IS NOT NULL THEN
                RAISE_APPLICATION_ERROR(-20022,
                    'La temporada "' || v_nombre || '" se cruza con "' || v_otra ||
                    '": cada noche debe pertenecer a una sola temporada.');
            END IF;
        END LOOP;
        g_temporadas.DELETE;
    END AFTER STATEMENT;

END trg_temporada_no_solape;
/
