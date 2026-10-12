-- Generador de datos para el proyecto TurismoUQ.
-- Ejecutar despues de ScriptDDL.sql en Oracle 12c o superior.
-- El script esta pensado para ejecutarse una sola vez sobre tablas vacias.

SET SERVEROUTPUT ON;

DECLARE
    TYPE t_id_list IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    v_municipio_ids   t_id_list;
    v_tipo_ids        t_id_list;
    v_temporada_ids   t_id_list;
    v_cliente_ids     t_id_list;
    v_alojamiento_ids t_id_list;
    v_servicio_ids    t_id_list;
    v_habitacion_ids  t_id_list;
    v_reserva_ids     t_id_list;

    v_id NUMBER;
    v_estado Reserva.estado%TYPE;
    v_fecha_reserva DATE;
    v_checkin DATE;
    v_checkout DATE;
    v_monto NUMBER;
BEGIN
    -- Municipios reales del Quindio, con nombres unicos.
    FOR i IN 1..12 LOOP
        INSERT INTO Municipio (nombre)
        VALUES (
            CASE i
                WHEN 1 THEN 'Armenia'
                WHEN 2 THEN 'Buenavista'
                WHEN 3 THEN 'Calarca'
                WHEN 4 THEN 'Circasia'
                WHEN 5 THEN 'Cordoba'
                WHEN 6 THEN 'Filandia'
                WHEN 7 THEN 'Genova'
                WHEN 8 THEN 'La Tebaida'
                WHEN 9 THEN 'Montenegro'
                WHEN 10 THEN 'Pijao'
                WHEN 11 THEN 'Quimbaya'
                ELSE 'Salento'
            END
        ) RETURNING id_municipio INTO v_municipio_ids(i);
    END LOOP;

    FOR i IN 1..4 LOOP
        INSERT INTO Tipo_Alojamiento (nombre)
        VALUES (
            CASE i
                WHEN 1 THEN 'Finca cafetera'
                WHEN 2 THEN 'Hotel'
                WHEN 3 THEN 'Glamping'
                ELSE 'Hostal'
            END
        ) RETURNING id_tipo_alojamiento INTO v_tipo_ids(i);
    END LOOP;

    -- Tres temporadas por ano durante 2025 y 2026.
    FOR i IN 1..6 LOOP
        INSERT INTO Temporada (nombre, tipo, fecha_inicio, fecha_fin)
        VALUES (
            CASE MOD(i - 1, 3)
                WHEN 0 THEN 'Temporada alta ' || (2025 + TRUNC((i - 1) / 3))
                WHEN 1 THEN 'Temporada media ' || (2025 + TRUNC((i - 1) / 3))
                ELSE 'Temporada baja ' || (2025 + TRUNC((i - 1) / 3))
            END,
            CASE MOD(i - 1, 3)
                WHEN 0 THEN 'alta'
                WHEN 1 THEN 'media'
                ELSE 'baja'
            END,
            CASE MOD(i - 1, 3)
                WHEN 0 THEN ADD_MONTHS(DATE '2025-01-01', 12 * TRUNC((i - 1) / 3))
                WHEN 1 THEN ADD_MONTHS(DATE '2025-04-01', 12 * TRUNC((i - 1) / 3))
                ELSE ADD_MONTHS(DATE '2025-09-01', 12 * TRUNC((i - 1) / 3))
            END,
            CASE MOD(i - 1, 3)
                WHEN 0 THEN ADD_MONTHS(DATE '2025-01-01', 12 * TRUNC((i - 1) / 3)) + 89
                WHEN 1 THEN ADD_MONTHS(DATE '2025-04-01', 12 * TRUNC((i - 1) / 3)) + 152
                ELSE ADD_MONTHS(DATE '2025-09-01', 12 * TRUNC((i - 1) / 3)) + 121
            END
        ) RETURNING id_temporada INTO v_temporada_ids(i);
    END LOOP;

    -- 3.000 clientes y documentos unicos.
    FOR i IN 1..3000 LOOP
        INSERT INTO Cliente (
            nombre,
            documento_identidad,
            correo,
            telefono,
            ciudad_origen
        ) VALUES (
            CASE MOD(i, 8)
                WHEN 0 THEN 'Laura Martinez'
                WHEN 1 THEN 'Carlos Rodriguez'
                WHEN 2 THEN 'Sofia Gomez'
                WHEN 3 THEN 'Andres Ramirez'
                WHEN 4 THEN 'Valentina Torres'
                WHEN 5 THEN 'Juan Hernandez'
                WHEN 6 THEN 'Mariana Castro'
                ELSE 'Diego Morales'
            END || ' ' || i,
            'DOC' || LPAD(i, 9, '0'),
            'cliente' || i || '@turismouq.com',
            '3' || LPAD(MOD(i * 7919, 100000000), 9, '0'),
            CASE MOD(i * 13, 8)
                WHEN 0 THEN 'Armenia'
                WHEN 1 THEN 'Pereira'
                WHEN 2 THEN 'Manizales'
                WHEN 3 THEN 'Bogota'
                WHEN 4 THEN 'Medellin'
                WHEN 5 THEN 'Cali'
                WHEN 6 THEN 'Ibague'
                ELSE 'Cartago'
            END
        ) RETURNING id_cliente INTO v_cliente_ids(i);
    END LOOP;

    -- 60 alojamientos distribuidos de forma desigual entre municipios y tipos.
    FOR i IN 1..60 LOOP
        INSERT INTO Alojamiento (
            id_municipio,
            id_tipo_alojamiento,
            nombre_comercial,
            direccion,
            calificacion,
            contacto
        ) VALUES (
            v_municipio_ids(
                1 + MOD(
                    i * 7 + CASE
                        WHEN i <= 20 THEN 0
                        WHEN i <= 40 THEN 2
                        ELSE 5
                    END,
                    12
                )
            ),
            CASE
                WHEN i <= 3 THEN v_tipo_ids(2)
                WHEN i <= 8 THEN v_tipo_ids(1)
                ELSE v_tipo_ids(1 + MOD(i * 3 + TRUNC((i - 1) / 15), 4))
            END,
            'Alojamiento Quindio ' || i,
            'Via turistica km ' || (1 + MOD(i * 7, 48)) || ', vereda ' || (1 + MOD(i, 20)),
            ROUND(3 + DBMS_RANDOM.VALUE(0, 2), 1),
            'contacto' || i || '@turismouq.com'
        ) RETURNING id_alojamiento INTO v_alojamiento_ids(i);
    END LOOP;

    -- 400 habitaciones, con cantidades diferentes por alojamiento.
    FOR i IN 1..400 LOOP
        INSERT INTO Habitacion (
            id_alojamiento,
            numero,
            capacidad,
            tipo,
            descripcion
        ) VALUES (
            v_alojamiento_ids(
                CASE
                    WHEN i <= 35 THEN 1
                    WHEN i <= 65 THEN 2
                    WHEN i <= 95 THEN 3
                    WHEN i <= 110 THEN 4 + MOD(i - 96, 5)
                    ELSE 9 + MOD(i - 111, 52)
                END
            ),
            100 + i,
            CASE MOD(i * 5, 9)
                WHEN 0 THEN 1
                WHEN 1 THEN 2
                WHEN 2 THEN 2
                WHEN 3 THEN 3
                WHEN 4 THEN 4
                WHEN 5 THEN 5
                WHEN 6 THEN 6
                WHEN 7 THEN 2
                ELSE 8
            END,
            CASE MOD(i * 11, 4)
                WHEN 0 THEN 'sencilla'
                WHEN 1 THEN 'doble'
                WHEN 2 THEN 'suite'
                ELSE 'cabaña'
            END,
            'Habitacion con distribucion y capacidad variable'
        ) RETURNING id_habitacion INTO v_habitacion_ids(i);
    END LOOP;

    -- 2.400 tarifas: una por cada combinacion habitacion-temporada.
    FOR habitacion_idx IN 1..400 LOOP
        FOR temporada_idx IN 1..6 LOOP
            INSERT INTO Tarifa (id_habitacion, id_temporada, valor_noche)
            VALUES (
                v_habitacion_ids(habitacion_idx),
                v_temporada_ids(temporada_idx),
                90000 + MOD(habitacion_idx * 137 + temporada_idx * 23000, 260000)
            );
        END LOOP;
    END LOOP;

    -- 30 servicios distribuidos entre los alojamientos.
    FOR i IN 1..30 LOOP
        INSERT INTO Servicio (
            id_alojamiento,
            nombre,
            descripcion,
            precio
        ) VALUES (
            v_alojamiento_ids(1 + MOD(i * i + 5 * i, 60)),
            CASE MOD(i, 6)
                WHEN 0 THEN 'Desayuno campesino'
                WHEN 1 THEN 'Tour de cafe'
                WHEN 2 THEN 'Transporte local'
                WHEN 3 THEN 'Wifi premium'
                WHEN 4 THEN 'Senderismo guiado'
                ELSE 'Cena regional'
            END || ' ' || i,
            'Servicio disponible para los huespedes del alojamiento',
            25000 + MOD(i * 4300, 150000)
        ) RETURNING id_servicio INTO v_servicio_ids(i);
    END LOOP;

    -- 10 usuarios del sistema, asociados a alojamientos diferentes.
    FOR i IN 1..10 LOOP
        INSERT INTO Usuario_Sistema (
            id_alojamiento,
            nombre,
            correo,
            rol
        ) VALUES (
            v_alojamiento_ids(1 + MOD(i * 7, 60)),
            CASE WHEN MOD(i, 2) = 0 THEN 'Encargado ' ELSE 'Administrador ' END || i,
            'usuario' || i || '@turismouq.com',
            CASE WHEN MOD(i, 2) = 0 THEN 'encargado' ELSE 'administrador' END
        );
    END LOOP;

    -- 25.000 reservas entre 2024 y 2026, con estados desiguales.
    FOR i IN 1..25000 LOOP
        v_estado := CASE MOD(i, 10)
            WHEN 0 THEN 'completada'
            WHEN 1 THEN 'completada'
            WHEN 2 THEN 'completada'
            WHEN 3 THEN 'completada'
            WHEN 4 THEN 'confirmada'
            WHEN 5 THEN 'confirmada'
            WHEN 6 THEN 'confirmada'
            WHEN 7 THEN 'pendiente'
            ELSE 'cancelada'
        END;

        v_fecha_reserva := DATE '2024-01-01' + MOD(i * 17 + i * i, 1095);

        INSERT INTO Reserva (id_cliente, fecha_reserva, estado)
        VALUES (
            v_cliente_ids(1 + MOD(MOD(i * i, 3000) * 19, 3000)),
            v_fecha_reserva,
            v_estado
        ) RETURNING id_reserva INTO v_reserva_ids(i);
    END LOOP;

    -- Al menos 25.000 relaciones reserva-habitacion; algunas reservas tienen dos.
    FOR i IN 1..25000 LOOP
        v_checkin := DATE '2024-01-02' + MOD(i * 23 + i * i, 1090);
        v_checkout := v_checkin + 1 + MOD(i * 7, 6);

        INSERT INTO Reserva_Habitacion (
            id_reserva,
            id_habitacion,
            checkin,
            checkout,
            precio_noche_calculado
        ) VALUES (
            v_reserva_ids(i),
            v_habitacion_ids(1 + MOD(i * 29 + i * i, 400)),
            v_checkin,
            v_checkout,
            95000 + MOD(i * 191, 240000)
        );

        IF MOD(i, 5) = 0 THEN
            INSERT INTO Reserva_Habitacion (
                id_reserva,
                id_habitacion,
                checkin,
                checkout,
                precio_noche_calculado
            ) VALUES (
                v_reserva_ids(i),
                v_habitacion_ids(1 + MOD(i * 31 + i * i, 400)),
                v_checkin,
                v_checkout,
                110000 + MOD(i * 173, 220000)
            );
        END IF;
    END LOOP;

    -- 40.000 lineas de servicios contratados.
    FOR i IN 1..25000 LOOP
        INSERT INTO Reserva_Servicio (
            id_reserva,
            id_servicio,
            cantidad,
            precio_cobrado
        ) VALUES (
            v_reserva_ids(i),
            v_servicio_ids(1 + MOD(i * 17 + i * i, 30)),
            1 + MOD(i * 3, 4),
            25000 + MOD(i * 271, 150000)
        );

        IF i <= 15000 THEN
            INSERT INTO Reserva_Servicio (
                id_reserva,
                id_servicio,
                cantidad,
                precio_cobrado
            ) VALUES (
                v_reserva_ids(i),
                v_servicio_ids(1 + MOD(i * 23 + 7, 30)),
                1 + MOD(i * 5, 3),
                30000 + MOD(i * 193, 130000)
            );
        END IF;
    END LOOP;

    -- Un pago por reserva, con estados coherentes con la reserva.
    FOR i IN 1..25000 LOOP
        v_estado := CASE MOD(i, 10)
            WHEN 7 THEN 'pendiente'
            WHEN 8 THEN 'reembolsado'
            WHEN 9 THEN 'reembolsado'
            ELSE 'exitoso'
        END;

        v_monto := 120000 + MOD(i * 313, 850000);

        INSERT INTO Pago (
            id_reserva,
            fecha,
            monto,
            metodo,
            estado
        ) VALUES (
            v_reserva_ids(i),
            DATE '2024-01-02' + MOD(i * 17 + i, 1095),
            v_monto,
            CASE MOD(i * 7, 3)
                WHEN 0 THEN 'PSE'
                WHEN 1 THEN 'transferencia'
                ELSE 'efectivo'
            END,
            v_estado
        );
    END LOOP;

    -- Las 10.000 reservas completadas reciben resena: 40% del total de reservas.
    FOR i IN 1..25000 LOOP
        IF MOD(i, 10) BETWEEN 0 AND 3 THEN
            INSERT INTO Resena (id_reserva, calificacion, comentario)
            VALUES (
                v_reserva_ids(i),
                3 + MOD(i * 7, 3),
                CASE MOD(i, 4)
                    WHEN 0 THEN 'Excelente experiencia y buena atencion.'
                    WHEN 1 THEN 'Lugar agradable y servicio cumplido.'
                    WHEN 2 THEN 'Buena ubicacion, volveria nuevamente.'
                    ELSE 'Estadia comoda y experiencia satisfactoria.'
                END
            );
        END IF;
    END LOOP;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Datos generados correctamente.');
    DBMS_OUTPUT.PUT_LINE('Municipios: 12 | Alojamientos: 60 | Habitaciones: 400');
    DBMS_OUTPUT.PUT_LINE('Clientes: 3000 | Reservas: 25000 | Reserva_Habitacion: 30000');
    DBMS_OUTPUT.PUT_LINE('Reserva_Servicio: 40000 | Pagos: 25000 | Resenas: 10000');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/
