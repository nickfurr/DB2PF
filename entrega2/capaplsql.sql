--funcion para obtener el valor de la estadia que pasa por fechas especificas

CREATE OR REPLACE FUNCTION fn_valor_estadia (
    p_id_habitacion IN NUMBER,
    p_fecha_in      IN DATE,
    p_fecha_out     IN DATE
) RETURN NUMBER IS
    v_total NUMBER := 0;
BEGIN
    IF p_fecha_out <= p_fecha_in THEN
        RAISE_APPLICATION_ERROR(-20001, 'La fecha de checkout debe ser posterior al checkin.');
    END IF;

    SELECT NVL(SUM(tar.valor_noche * (1 + temp.sobrecostoTemporada)), 0)
    INTO v_total
    FROM (
        SELECT TRUNC(p_fecha_in) + LEVEL - 1 AS noche
        FROM DUAL
        CONNECT BY LEVEL <= (TRUNC(p_fecha_out) - TRUNC(p_fecha_in))
    ) d
    JOIN Temporada temp 
      ON d.noche BETWEEN TRUNC(temp.fecha_inicio) AND TRUNC(temp.fecha_fin)
    JOIN Tarifa tar 
      ON tar.id_temporada = temp.id_temporada 
     AND tar.id_habitacion = p_id_habitacion;

    RETURN v_total;
END;
/