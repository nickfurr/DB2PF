SET SERVEROUTPUT ON;

DECLARE
    v_valor_estadia NUMBER;
BEGIN
    v_valor_estadia := fn_valor_estadia_iterativo(
        p_id_habitacion => 1,
        p_fecha_in       => DATE '2024-01-15',
        p_fecha_out      => DATE '2024-01-20'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Valor total de la estadía: $'
        || TO_CHAR(v_valor_estadia, 'FM999G999G999G990')
    );
END;
/