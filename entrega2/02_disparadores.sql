-- ENTREGA 2 - TurismoUQ
-- 02. Disparadores: auditoria de TARIFA y control de solape de reservas.

SET SERVEROUTPUT ON

-- Tabla de auditoria de cambios en TARIFA.
DROP TABLE Auditoria_Tarifa PURGE;
CREATE TABLE Auditoria_Tarifa (
    id_auditoria   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tarifa      NUMBER,
    usuario        VARCHAR2(40),
    fecha_cambio   TIMESTAMP,
    operacion      VARCHAR2(10),
    valor_anterior NUMBER,
    valor_nuevo    NUMBER
);

-- Auditoria de TARIFA: quien, cuando, valor anterior y nuevo.
CREATE OR REPLACE TRIGGER trg_auditoria_tarifa
AFTER INSERT OR UPDATE OF valor_noche OR DELETE ON Tarifa
FOR EACH ROW
BEGIN
    INSERT INTO Auditoria_Tarifa (
        id_tarifa,
        usuario,
        fecha_cambio,
        operacion,
        valor_anterior,
        valor_nuevo
    ) VALUES (
        CASE
            WHEN INSERTING THEN :NEW.id_tarifa
            ELSE :OLD.id_tarifa
        END,
        SYS_CONTEXT('USERENV', 'SESSION_USER'),
        SYSTIMESTAMP,
        CASE
            WHEN INSERTING THEN 'INSERT'
            WHEN UPDATING THEN 'UPDATE'
            ELSE 'DELETE'
        END,
        CASE WHEN INSERTING THEN NULL ELSE :OLD.valor_noche END,
        CASE WHEN DELETING THEN NULL ELSE :NEW.valor_noche END
    );
END;
/

-- Impide reservas que se solapen en la misma habitacion.
CREATE OR REPLACE TRIGGER trg_reserva_no_solape
BEFORE INSERT OR UPDATE ON Reserva_Habitacion
FOR EACH ROW
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_conflictos NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO v_conflictos
      FROM Reserva_Habitacion rh
      JOIN Reserva r ON r.id_reserva = rh.id_reserva
     WHERE rh.id_habitacion        = :NEW.id_habitacion
       AND rh.id_reserva_habitacion <> NVL(:NEW.id_reserva_habitacion, -1)
       AND r.estado = 'confirmada'
       AND :NEW.checkin  < rh.checkout
       AND :NEW.checkout > rh.checkin;
    COMMIT;

    IF v_conflictos > 0 THEN
        RAISE_APPLICATION_ERROR(-20020,
            'La habitacion ' || :NEW.id_habitacion ||
            ' ya esta ocupada por una reserva confirmada en ese rango de fechas.');
    END IF;
END;
/
