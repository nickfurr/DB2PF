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