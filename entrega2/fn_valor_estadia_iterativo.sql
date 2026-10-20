CREATE OR REPLACE FUNCTION fn_valor_estadia_iterativo (
    p_id_habitacion IN NUMBER,
    p_fecha_in      IN DATE,
    p_fecha_out     IN DATE
) RETURN NUMBER IS
    v_total        NUMBER := 0;
    v_noches       NUMBER;
    v_fecha_actual DATE;
    v_encontrada   BOOLEAN;

    -- Cursor con las tarifas y temporadas de la habitación
    CURSOR c_tarifas IS
        SELECT temp.fecha_inicio, temp.fecha_fin,
               tar.valor_noche * (1 + temp.sobrecostoTemporada) AS valor_noche
        FROM Tarifa tar
        JOIN Temporada temp ON tar.id_temporada = temp.id_temporada
        WHERE tar.id_habitacion = p_id_habitacion;
BEGIN
    -- 1. Validación de fechas
    IF p_fecha_out <= p_fecha_in THEN
        RAISE_APPLICATION_ERROR(-20001, 'La fecha de checkout debe ser posterior al checkin.');
    END IF;

    -- 2. Cantidad de noches a liquidar
    v_noches := TRUNC(p_fecha_out) - TRUNC(p_fecha_in);

    -- 3. Bucle principal: Recorre noche por noche (0 a noches - 1)
    FOR i IN 0 .. (v_noches - 1) LOOP
        v_fecha_actual := TRUNC(p_fecha_in) + i;
        v_encontrada   := FALSE;

        -- 4. Bucle secundario: Revisa en cuál temporada cae esta fecha
        FOR r_tarifa IN c_tarifas LOOP
            IF v_fecha_actual BETWEEN TRUNC(r_tarifa.fecha_inicio) AND TRUNC(r_tarifa.fecha_fin) THEN
                v_total      := v_total + r_tarifa.valor_noche;
                v_encontrada := TRUE;
                EXIT; -- Encontró la tarifa de esta noche, salta a la siguiente fecha
            END IF;
        END LOOP;

        -- Si alguna noche no tiene temporada/tarifa configurada
        IF NOT v_encontrada THEN
            RAISE_APPLICATION_ERROR(-20002, 'No se encontró tarifa para la fecha: ' 
                                            || TO_CHAR(v_fecha_actual, 'YYYY-MM-DD'));
        END IF;
    END LOOP;

    RETURN v_total;
END;
/
