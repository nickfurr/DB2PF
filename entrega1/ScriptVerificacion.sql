-- =============================================================================
-- PROYECTO INTEGRADOR TurismoUQ - Bases de Datos II
-- Script de verificacion de los datos cargados por ScriptDatos.sql.
-- Cada control de la seccion 2 debe dar 0: son las observaciones de la
-- retroalimentacion de la Entrega 1 convertidas en pruebas.
-- =============================================================================
-- Ejecutar desde la carpeta entrega1 (SQL*Plus: @ScriptVerificacion.sql;
-- SQL Developer: F5). El resultado queda en verificacion_datos.txt, que es la
-- evidencia de la carga que se sube al repositorio.
SET LINESIZE 200
SET PAGESIZE 200
SET TRIMSPOOL ON
SET FEEDBACK ON
COLUMN control FORMAT A55
COLUMN tabla FORMAT A20

SPOOL verificacion_datos.txt

SELECT 'Verificacion generada el ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI') AS fecha FROM dual;

-- -----------------------------------------------------------------------------
-- 1. Volumenes frente al minimo del enunciado
-- -----------------------------------------------------------------------------
SELECT 'MUNICIPIO' AS tabla, (SELECT COUNT(*) FROM Municipio) AS registros, 12 AS minimo FROM DUAL
UNION ALL SELECT 'TIPO_ALOJAMIENTO',   (SELECT COUNT(*) FROM Tipo_Alojamiento), 4 FROM DUAL
UNION ALL SELECT 'ALOJAMIENTO',        (SELECT COUNT(*) FROM Alojamiento), 60 FROM DUAL
UNION ALL SELECT 'HABITACION',         (SELECT COUNT(*) FROM Habitacion), 400 FROM DUAL
UNION ALL SELECT 'TEMPORADA',          (SELECT COUNT(*) FROM Temporada), 6 FROM DUAL
UNION ALL SELECT 'TARIFA',             (SELECT COUNT(*) FROM Tarifa), (SELECT COUNT(*) FROM Habitacion) * (SELECT COUNT(*) FROM Temporada) FROM DUAL
UNION ALL SELECT 'CLIENTE',            (SELECT COUNT(*) FROM Cliente), 3000 FROM DUAL
UNION ALL SELECT 'RESERVA',            (SELECT COUNT(*) FROM Reserva), 25000 FROM DUAL
UNION ALL SELECT 'RESERVA_HABITACION', (SELECT COUNT(*) FROM Reserva_Habitacion), 25000 FROM DUAL
UNION ALL SELECT 'PAGO',               (SELECT COUNT(*) FROM Pago), 25000 FROM DUAL
UNION ALL SELECT 'SERVICIO',           (SELECT COUNT(*) FROM Servicio), 30 FROM DUAL
UNION ALL SELECT 'RESERVA_SERVICIO',   (SELECT COUNT(*) FROM Reserva_Servicio), 40000 FROM DUAL
UNION ALL SELECT 'RESENA',             (SELECT COUNT(*) FROM Resena), CEIL(0.4 * (SELECT COUNT(*) FROM Reserva WHERE estado = 'completada')) FROM DUAL
UNION ALL SELECT 'USUARIO_SISTEMA',    (SELECT COUNT(*) FROM Usuario_Sistema), 10 FROM DUAL;

-- -----------------------------------------------------------------------------
-- 2. Controles de calidad (todos deben dar 0)
-- -----------------------------------------------------------------------------
SELECT 'Solapes entre reservas confirmadas' AS control, COUNT(*) AS total
  FROM Reserva_Habitacion a
  JOIN Reserva ra ON ra.id_reserva = a.id_reserva
  JOIN Reserva_Habitacion b ON b.id_habitacion = a.id_habitacion
                           AND b.id_reserva_habitacion < a.id_reserva_habitacion
  JOIN Reserva rb ON rb.id_reserva = b.id_reserva
 WHERE ra.estado = 'confirmada' AND rb.estado = 'confirmada'
   AND a.checkin < b.checkout AND b.checkin < a.checkout
UNION ALL
SELECT 'Solapes entre reservas no canceladas', COUNT(*)
  FROM Reserva_Habitacion a
  JOIN Reserva ra ON ra.id_reserva = a.id_reserva
  JOIN Reserva_Habitacion b ON b.id_habitacion = a.id_habitacion
                           AND b.id_reserva_habitacion < a.id_reserva_habitacion
  JOIN Reserva rb ON rb.id_reserva = b.id_reserva
 WHERE ra.estado <> 'cancelada' AND rb.estado <> 'cancelada'
   AND a.checkin < b.checkout AND b.checkin < a.checkout
UNION ALL
SELECT 'Habitaciones que nunca se reservan', COUNT(*)
  FROM Habitacion h
 WHERE NOT EXISTS (SELECT 1 FROM Reserva_Habitacion rh WHERE rh.id_habitacion = h.id_habitacion)
UNION ALL
SELECT 'Servicios cobrados en otro alojamiento', COUNT(*)
  FROM Reserva_Servicio rs
  JOIN Servicio s ON s.id_servicio = rs.id_servicio
 WHERE NOT EXISTS (SELECT 1
                     FROM Reserva_Habitacion rh
                     JOIN Habitacion h ON h.id_habitacion = rh.id_habitacion
                    WHERE rh.id_reserva = rs.id_reserva
                      AND h.id_alojamiento = s.id_alojamiento)
UNION ALL
SELECT 'Reservas con habitaciones de varios alojamientos', COUNT(*)
  FROM (SELECT rh.id_reserva
          FROM Reserva_Habitacion rh
          JOIN Habitacion h ON h.id_habitacion = rh.id_habitacion
         GROUP BY rh.id_reserva
        HAVING COUNT(DISTINCT h.id_alojamiento) > 1)
UNION ALL
SELECT 'Precio por noche distinto al calculado con TARIFA', COUNT(*)
  FROM (SELECT rh.id_reserva_habitacion,
               rh.precio_noche_calculado,
               ROUND(SUM(t.valor_noche) / (rh.checkout - rh.checkin), 2) AS precio_tarifa
          FROM Reserva_Habitacion rh
          JOIN (SELECT DATE '2024-01-01' + LEVEL - 1 AS noche
                  FROM dual CONNECT BY LEVEL <= DATE '2027-01-01' - DATE '2024-01-01') c
            ON c.noche >= rh.checkin AND c.noche < rh.checkout
          JOIN Temporada tp ON c.noche BETWEEN tp.fecha_inicio AND tp.fecha_fin
          JOIN Tarifa t ON t.id_habitacion = rh.id_habitacion AND t.id_temporada = tp.id_temporada
         GROUP BY rh.id_reserva_habitacion, rh.precio_noche_calculado, rh.checkout, rh.checkin)
 WHERE ABS(precio_noche_calculado - precio_tarifa) > 0.01
UNION ALL
SELECT 'Precio de servicio distinto al del catalogo', COUNT(*)
  FROM Reserva_Servicio rs
  JOIN Servicio s ON s.id_servicio = rs.id_servicio
 WHERE rs.precio_cobrado <> s.precio
UNION ALL
SELECT 'Dias 2024-2026 sin temporada', COUNT(*)
  FROM (SELECT DATE '2024-01-01' + LEVEL - 1 AS dia
          FROM dual CONNECT BY LEVEL <= DATE '2027-01-01' - DATE '2024-01-01') c
 WHERE NOT EXISTS (SELECT 1 FROM Temporada t WHERE c.dia BETWEEN t.fecha_inicio AND t.fecha_fin)
UNION ALL
SELECT 'Temporadas que se solapan', COUNT(*)
  FROM Temporada a
  JOIN Temporada b ON b.id_temporada < a.id_temporada
                  AND a.fecha_inicio <= b.fecha_fin AND b.fecha_inicio <= a.fecha_fin
UNION ALL
SELECT 'Resenas de reservas no completadas', COUNT(*)
  FROM Resena re
  JOIN Reserva r ON r.id_reserva = re.id_reserva
 WHERE r.estado <> 'completada'
UNION ALL
SELECT 'Reservas sin ningun pago', COUNT(*)
  FROM Reserva r
 WHERE NOT EXISTS (SELECT 1 FROM Pago p WHERE p.id_reserva = r.id_reserva)
UNION ALL
SELECT 'Completadas cuyos pagos exitosos no cubren el total', COUNT(*)
  FROM (SELECT r.id_reserva,
               (SELECT SUM((rh.checkout - rh.checkin) * rh.precio_noche_calculado)
                  FROM Reserva_Habitacion rh WHERE rh.id_reserva = r.id_reserva)
             + NVL((SELECT SUM(rs.cantidad * rs.precio_cobrado)
                      FROM Reserva_Servicio rs WHERE rs.id_reserva = r.id_reserva), 0) AS total,
               (SELECT NVL(SUM(p.monto), 0)
                  FROM Pago p WHERE p.id_reserva = r.id_reserva AND p.estado = 'exitoso') AS pagado
          FROM Reserva r
         WHERE r.estado = 'completada')
 WHERE pagado < total - 1
UNION ALL
SELECT 'Reembolsos con 5 dias o menos de anticipacion', COUNT(*)
  FROM Pago p
 WHERE p.estado = 'reembolsado'
   AND (SELECT MIN(rh.checkin) FROM Reserva_Habitacion rh WHERE rh.id_reserva = p.id_reserva) - p.fecha <= 5
UNION ALL
SELECT 'Check-in anterior a la fecha de reserva', COUNT(*)
  FROM Reserva r
  JOIN Reserva_Habitacion rh ON rh.id_reserva = r.id_reserva
 WHERE rh.checkin < r.fecha_reserva;

-- -----------------------------------------------------------------------------
-- 3. Asimetria y variedad (para mostrar que ROLLUP, PIVOT y RANK tienen
--    diferencias reales que mostrar)
-- -----------------------------------------------------------------------------
SELECT estado, COUNT(*) AS reservas FROM Reserva GROUP BY estado ORDER BY 2 DESC;

SELECT estado, COUNT(*) AS pagos FROM Pago GROUP BY estado ORDER BY 2 DESC;

SELECT 'Reservas con varias habitaciones' AS indicador, COUNT(*) AS total
  FROM (SELECT id_reserva FROM Reserva_Habitacion GROUP BY id_reserva HAVING COUNT(*) > 1)
UNION ALL
SELECT 'Reservas con mas de un pago', COUNT(*)
  FROM (SELECT id_reserva FROM Pago GROUP BY id_reserva HAVING COUNT(*) > 1)
UNION ALL
SELECT 'Reservas con linea que llega un dia despues', COUNT(DISTINCT rh.id_reserva)
  FROM Reserva_Habitacion rh
 WHERE rh.checkin > (SELECT MIN(x.checkin) FROM Reserva_Habitacion x WHERE x.id_reserva = rh.id_reserva);

SELECT tipo, COUNT(*) AS temporadas FROM Temporada GROUP BY tipo;

SELECT m.nombre AS municipio,
       COUNT(DISTINCT a.id_alojamiento) AS alojamientos,
       COUNT(DISTINCT h.id_habitacion)  AS habitaciones,
       COUNT(DISTINCT rh.id_reserva)    AS reservas
  FROM Municipio m
  JOIN Alojamiento a ON a.id_municipio = m.id_municipio
  JOIN Habitacion  h ON h.id_alojamiento = a.id_alojamiento
  LEFT JOIN Reserva_Habitacion rh ON rh.id_habitacion = h.id_habitacion
 GROUP BY m.nombre
 ORDER BY reservas DESC;

SPOOL OFF
