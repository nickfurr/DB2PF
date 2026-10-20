SET SERVEROUTPUT ON;

DECLARE
    TYPE t_id_list IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    TYPE t_date_list IS TABLE OF DATE INDEX BY PLS_INTEGER;
    TYPE t_number_list IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    v_municipio_ids   t_id_list;
    v_tipo_ids        t_id_list;
    v_temporada_ids   t_id_list;
    v_cliente_ids     t_id_list;
    v_alojamiento_ids t_id_list;
    v_servicio_ids    t_id_list;
    v_habitacion_ids  t_id_list;
    
    -- Variables para controlar flujo y evitar sobreposición
    v_hab_to_aloj_idx t_number_list; 
    v_last_checkout   t_date_list;   

    v_res_id NUMBER;
    v_estado VARCHAR2(50);
    v_estado_pago VARCHAR2(50);
    v_fecha_reserva DATE;
    v_checkin DATE;
    v_checkout DATE;
    v_monto NUMBER;
    
    v_room_idx NUMBER;
    v_aloj_idx NUMBER;
    v_serv_idx NUMBER;
BEGIN
    -- 1. MUNICIPIOS
    FOR i IN 1..12 LOOP
        INSERT INTO Municipio (nombre)
        VALUES (
            CASE i WHEN 1 THEN 'Armenia' WHEN 2 THEN 'Buenavista' WHEN 3 THEN 'Calarca' WHEN 4 THEN 'Circasia'
                   WHEN 5 THEN 'Cordoba' WHEN 6 THEN 'Filandia' WHEN 7 THEN 'Genova' WHEN 8 THEN 'La Tebaida'
                   WHEN 9 THEN 'Montenegro' WHEN 10 THEN 'Pijao' WHEN 11 THEN 'Quimbaya' ELSE 'Salento' END
        ) RETURNING id_municipio INTO v_municipio_ids(i);
    END LOOP;

    -- 2. TIPOS DE ALOJAMIENTO
    FOR i IN 1..4 LOOP
        INSERT INTO Tipo_Alojamiento (nombre)
        VALUES (CASE i WHEN 1 THEN 'Finca cafetera' WHEN 2 THEN 'Hotel' WHEN 3 THEN 'Glamping' ELSE 'Hostal' END) 
        RETURNING id_tipo_alojamiento INTO v_tipo_ids(i);
    END LOOP;

    -- 3. TEMPORADAS (Incluye 2024, 2025 y 2026)
    FOR i IN 1..9 LOOP
        INSERT INTO Temporada (
            nombre, tipo, fecha_inicio, fecha_fin, sobrecostoTemporada
        )
        VALUES (
            CASE MOD(i - 1, 3) WHEN 0 THEN 'Alta '||(2024+TRUNC((i-1)/3)) WHEN 1 THEN 'Media '||(2024+TRUNC((i-1)/3)) ELSE 'Baja '||(2024+TRUNC((i-1)/3)) END,
            CASE MOD(i - 1, 3) WHEN 0 THEN 'alta' WHEN 1 THEN 'media' ELSE 'baja' END,
            CASE MOD(i - 1, 3) WHEN 0 THEN ADD_MONTHS(DATE '2024-01-01', 12 * TRUNC((i - 1) / 3))
                               WHEN 1 THEN ADD_MONTHS(DATE '2024-04-01', 12 * TRUNC((i - 1) / 3))
                               ELSE ADD_MONTHS(DATE '2024-09-01', 12 * TRUNC((i - 1) / 3)) END,
            CASE MOD(i - 1, 3) WHEN 0 THEN ADD_MONTHS(DATE '2024-01-01', 12 * TRUNC((i - 1) / 3)) + 89
                               WHEN 1 THEN ADD_MONTHS(DATE '2024-04-01', 12 * TRUNC((i - 1) / 3)) + 152
                               ELSE ADD_MONTHS(DATE '2024-09-01', 12 * TRUNC((i - 1) / 3)) + 121 END,
            CASE MOD(i - 1, 3) WHEN 0 THEN 0.30 WHEN 1 THEN 0.15 ELSE 0.05 END
        ) RETURNING id_temporada INTO v_temporada_ids(i);
    END LOOP;

    -- 4. CLIENTES
    FOR i IN 1..3000 LOOP
        INSERT INTO Cliente (nombre, documento_identidad, correo, telefono, ciudad_origen) 
        VALUES (
            'Turista ' || i, 'DOC' || LPAD(i, 9, '0'), 'cliente' || i || '@turismouq.com',
            '3' || LPAD(MOD(i * 7919, 100000000), 9, '0'),
            CASE MOD(i * 13, 8) WHEN 0 THEN 'Armenia' WHEN 1 THEN 'Pereira' WHEN 2 THEN 'Manizales' WHEN 3 THEN 'Bogota'
                                WHEN 4 THEN 'Medellin' WHEN 5 THEN 'Cali' WHEN 6 THEN 'Ibague' ELSE 'Cartago' END
        ) RETURNING id_cliente INTO v_cliente_ids(i);
    END LOOP;

    -- 5. ALOJAMIENTOS
    FOR i IN 1..60 LOOP
        INSERT INTO Alojamiento (id_municipio, id_tipo_alojamiento, nombre_comercial, direccion, calificacion, contacto) 
        VALUES (
            v_municipio_ids(1 + MOD(i, 12)),
            v_tipo_ids(1 + MOD(i, 4)),
            'Alojamiento Quindio ' || i,
            'Via turistica km ' || (1 + MOD(i * 7, 48)),
            ROUND(3 + DBMS_RANDOM.VALUE(0, 2), 1),
            'contacto' || i || '@turismouq.com'
        ) RETURNING id_alojamiento INTO v_alojamiento_ids(i);
    END LOOP;

    -- 6. HABITACIONES (Vinculadas a un alojamiento lógico)
    FOR i IN 1..400 LOOP
        v_aloj_idx := 1 + MOD(i, 60); 
        v_hab_to_aloj_idx(i) := v_aloj_idx; 
        v_last_checkout(i) := DATE '2024-01-01'; 

        INSERT INTO Habitacion (id_alojamiento, numero, capacidad, tipo, descripcion) 
        VALUES (
            v_alojamiento_ids(v_aloj_idx),
            100 + i,
            2 + MOD(i, 4),
            -- CAMBIO APLICADO AQUÍ: 'cabagna' en lugar de 'cabana'
            CASE MOD(i, 4) WHEN 0 THEN 'sencilla' WHEN 1 THEN 'doble' WHEN 2 THEN 'suite' ELSE 'cabagna' END,
            'Habitacion estandar ' || i
        ) RETURNING id_habitacion INTO v_habitacion_ids(i);
    END LOOP;

    -- 7. TARIFAS
    FOR h_idx IN 1..400 LOOP
        FOR t_idx IN 1..9 LOOP
            INSERT INTO Tarifa (id_habitacion, id_temporada, valor_noche)
            VALUES (v_habitacion_ids(h_idx), v_temporada_ids(t_idx), 90000 + MOD(h_idx * 137 + t_idx * 23000, 260000));
        END LOOP;
    END LOOP;

    -- 8. SERVICIOS (Exactamente 3 servicios por alojamiento)
    FOR a_idx IN 1..60 LOOP
        FOR s_idx IN 1..3 LOOP
            INSERT INTO Servicio (id_alojamiento, nombre, descripcion, precio) 
            VALUES (
                v_alojamiento_ids(a_idx),
                CASE s_idx WHEN 1 THEN 'Desayuno' WHEN 2 THEN 'Tour' ELSE 'Transporte' END || ' ' || a_idx,
                'Servicio exclusivo',
                25000 + MOD(a_idx * 4300, 150000)
            ) RETURNING id_servicio INTO v_servicio_ids((a_idx - 1) * 3 + s_idx);
        END LOOP;
    END LOOP;

    -- 9. RESERVAS, PAGOS Y SERVICIOS
    FOR i IN 1..25000 LOOP
        -- Seleccionamos una habitación al azar
        v_room_idx := 1 + MOD(i * 29 + i * i, 400);
        v_aloj_idx := v_hab_to_aloj_idx(v_room_idx);
        
        -- Calculamos el espacio de tiempo para evitar overlaps en la MISMA habitacion
        v_checkin := v_last_checkout(v_room_idx) + (1 + MOD(i * 13, 20));
        v_checkout := v_checkin + (1 + MOD(i * 7, 5)); -- Estadía de 1 a 6 días
        
        -- Actualizamos el registro de disponibilidad
        v_last_checkout(v_room_idx) := v_checkout;

        -- La reserva se hace unos días antes del checkin
        v_fecha_reserva := v_checkin - (5 + MOD(i * 11, 25));

        -- Estado de la reserva
        v_estado := CASE MOD(i, 10) WHEN 0 THEN 'completada' WHEN 1 THEN 'completada' WHEN 2 THEN 'completada'
                                    WHEN 3 THEN 'completada' WHEN 4 THEN 'confirmada' WHEN 5 THEN 'confirmada'
                                    WHEN 6 THEN 'confirmada' WHEN 7 THEN 'pendiente' ELSE 'cancelada' END;

        -- Cabecera
        INSERT INTO Reserva (id_cliente, fecha_reserva, estado)
        VALUES (v_cliente_ids(1 + MOD(i * 19, 3000)), v_fecha_reserva, v_estado) 
        RETURNING id_reserva INTO v_res_id;

        -- Detalle Habitación
        INSERT INTO Reserva_Habitacion (id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado) 
        VALUES (v_res_id, v_habitacion_ids(v_room_idx), v_checkin, v_checkout, 95000 + MOD(i * 191, 240000));

        -- Detalle Servicios
        v_serv_idx := (v_aloj_idx - 1) * 3 + (1 + MOD(i, 3));
        INSERT INTO Reserva_Servicio (id_reserva, id_servicio, cantidad, precio_cobrado) 
        VALUES (v_res_id, v_servicio_ids(v_serv_idx), 1 + MOD(i * 3, 4), 25000 + MOD(i * 271, 150000));

        -- Pago
        v_estado_pago := CASE v_estado WHEN 'cancelada' THEN 'reembolsado' WHEN 'pendiente' THEN 'pendiente' ELSE 'exitoso' END;
        INSERT INTO Pago (id_reserva, fecha, monto, metodo, estado) 
        VALUES (
            v_res_id, v_fecha_reserva + 1, 120000 + MOD(i * 313, 850000),
            CASE MOD(i, 4) WHEN 0 THEN 'PSE' WHEN 1 THEN 'transferencia' WHEN 2 THEN 'efectivo' ELSE 'tarjeta de crédito' END,
            v_estado_pago
        );

        -- Reseñas
        IF v_estado = 'completada' AND MOD(i, 2) = 0 THEN
            INSERT INTO Resena (id_reserva, calificacion, comentario)
            VALUES (v_res_id, 3 + MOD(i * 7, 3), 'Buena estadia, todo correcto.');
        END IF;

    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Datos generados sin overlaps y con integridad logica.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/