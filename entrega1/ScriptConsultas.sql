-- PROYECTO INTEGRADOR: TurismoUQ
-- Plataforma de Reservas Turísticas del Quindío
-- SCRIPT COMPLETO DE CONSULTAS (1 A 7)

-- =============================================================================
-- CONSULTA 1: Ocupación por municipio y mes con PIVOT
-- =============================================================================
SELECT municipio, 
       NVL(Ene,0) AS ene, NVL(Feb,0) AS feb, NVL(Mar,0) AS mar, NVL(Abr,0) AS abr, 
       NVL(May,0) AS may, NVL(Jun,0) AS jun, NVL(Jul,0) AS jul, NVL(Ago,0) AS ago, 
       NVL(Sep,0) AS sep, NVL(Oct,0) AS oct, NVL(Nov,0) AS nov, NVL(Dic,0) AS dic,
       (NVL(Ene,0)+NVL(Feb,0)+NVL(Mar,0)+NVL(Abr,0)+NVL(May,0)+NVL(Jun,0)+NVL(Jul,0)+NVL(Ago,0)+NVL(Sep,0)+NVL(Oct,0)+NVL(Nov,0)+NVL(Dic,0)) AS total_anual_noches
FROM (
    SELECT m.nombre AS municipio, 
           EXTRACT(MONTH FROM rh.checkin) AS mes_num, 
           (TRUNC(rh.checkout) - TRUNC(rh.checkin)) AS noches_estadia
    FROM Municipio m
    JOIN Alojamiento a ON m.id_municipio = a.id_municipio
    JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
    JOIN Reserva_Habitacion rh ON h.id_habitacion = rh.id_habitacion
    JOIN Reserva r ON rh.id_reserva = r.id_reserva
    WHERE r.estado IN ('confirmada', 'completada') 
      AND EXTRACT(YEAR FROM rh.checkin) = 2025
) PIVOT (
    SUM(noches_estadia) FOR mes_num IN (
        1 AS Ene, 2 AS Feb, 3 AS Mar, 4 AS Abr, 5 AS May, 6 AS Jun, 
        7 AS Jul, 8 AS Ago, 9 AS Sep, 10 AS Oct, 11 AS Nov, 12 AS Dic
    )
)
ORDER BY total_anual_noches DESC;


-- =============================================================================
-- CONSULTA 2 CORREGIDA: Ingresos por municipio, tipo y temporada con ROLLUP
-- (Cálculo Noche por Noche y Filtro Año 2024)
-- =============================================================================
WITH NochesDesglosadas AS (
    SELECT rh.id_reserva, 
           h.id_alojamiento, 
           rh.id_habitacion, 
           rh.checkin + LEVEL - 1 AS fecha_noche
    FROM Reserva_Habitacion rh
    JOIN Habitacion h ON rh.id_habitacion = h.id_habitacion
    WHERE EXTRACT(YEAR FROM rh.checkin) = 2024 OR EXTRACT(YEAR FROM rh.checkout) = 2024
    CONNECT BY LEVEL <= (rh.checkout - rh.checkin)
           AND PRIOR rh.id_reserva = rh.id_reserva
           AND PRIOR SYS_GUID() IS NOT NULL
)
SELECT 
    CASE WHEN GROUPING(m.nombre) = 1 THEN '>>> TOTAL DEPARTAMENTAL <<<' ELSE m.nombre END AS municipio,
    CASE WHEN GROUPING(m.nombre) = 0 AND GROUPING(ta.nombre) = 1 THEN '--- Subtotal Municipio ---' 
         WHEN GROUPING(m.nombre) = 1 THEN '--- Todos los Tipos ---' 
         ELSE ta.nombre END AS tipo_alojamiento,
    CASE WHEN GROUPING(ta.nombre) = 0 AND GROUPING(t.tipo) = 1 THEN '--- Subtotal Tipo ---' 
         WHEN GROUPING(ta.nombre) = 1 THEN '--- Todas las Temporadas ---' 
         ELSE t.tipo END AS temporada,
    COUNT(DISTINCT r.id_reserva) AS total_reservas,
    SUM(tar.valor_noche) AS ingresos_hospedaje,
    GROUPING(m.nombre) AS grp_mun,
    GROUPING(ta.nombre) AS grp_tipo,
    GROUPING(t.tipo) AS grp_temp
FROM NochesDesglosadas nd
JOIN Reserva r ON nd.id_reserva = r.id_reserva
JOIN Alojamiento a ON nd.id_alojamiento = a.id_alojamiento
JOIN Municipio m ON a.id_municipio = m.id_municipio
JOIN Tipo_Alojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN Temporada t ON nd.fecha_noche >= t.fecha_inicio AND nd.fecha_noche <= t.fecha_fin
JOIN Tarifa tar ON tar.id_habitacion = nd.id_habitacion AND tar.id_temporada = t.id_temporada
WHERE r.estado IN ('confirmada', 'completada') 
  AND EXTRACT(YEAR FROM nd.fecha_noche) = 2024
GROUP BY ROLLUP(m.nombre, ta.nombre, t.tipo)
ORDER BY GROUPING(m.nombre), m.nombre, GROUPING(ta.nombre), ta.nombre, GROUPING(t.tipo), t.tipo;


-- =============================================================================
-- CONSULTA 3: Top 3 de alojamientos con mayor ingreso por municipio (RANK OVER)
-- =============================================================================
WITH RankingIngresos AS (
    SELECT m.nombre AS municipio,
        a.id_alojamiento,
        a.nombre_comercial AS alojamiento,
        ta.nombre AS tipo_alojamiento,
        a.calificacion AS estrellas_autoasignadas,
        COUNT(DISTINCT r.id_reserva) AS reservas_atendidas,
        SUM((TRUNC(rh.checkout) - TRUNC(rh.checkin)) * rh.precio_noche_calculado) AS total_ingresos,
        RANK() OVER (
            PARTITION BY m.nombre
            ORDER BY SUM((TRUNC(rh.checkout) - TRUNC(rh.checkin)) * rh.precio_noche_calculado) DESC
        ) AS posicion_ranking
    FROM Municipio m
    JOIN Alojamiento a ON m.id_municipio = a.id_municipio
    JOIN Tipo_Alojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
    JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
    JOIN Reserva_Habitacion rh ON h.id_habitacion = rh.id_habitacion
    JOIN Reserva r ON rh.id_reserva = r.id_reserva
    WHERE r.estado IN ('confirmada', 'completada')
    GROUP BY m.nombre, a.id_alojamiento, a.nombre_comercial, ta.nombre, a.calificacion
)
SELECT municipio,
    posicion_ranking,
    alojamiento,
    tipo_alojamiento,
    estrellas_autoasignadas,
    reservas_atendidas,
    total_ingresos
FROM RankingIngresos
WHERE posicion_ranking <= 3
ORDER BY municipio, posicion_ranking;


-- =============================================================================
-- CONSULTA 4: Variación de ingresos mes contra mes utilizando LAG
-- =============================================================================
WITH IngresosMensuales AS (
    SELECT TRUNC(rh.checkin, 'MM') AS periodo_mes,
        TO_CHAR(TRUNC(rh.checkin, 'MM'), 'YYYY-MM') AS anio_mes,
        TO_CHAR(TRUNC(rh.checkin, 'MM'), 'Month YYYY', 'NLS_DATE_LANGUAGE = SPANISH') AS nombre_mes,
        COUNT(DISTINCT r.id_reserva) AS cantidad_reservas,
        SUM((TRUNC(rh.checkout) - TRUNC(rh.checkin)) * rh.precio_noche_calculado) AS ingreso_mes
    FROM Reserva r
    JOIN Reserva_Habitacion rh ON r.id_reserva = rh.id_reserva
    WHERE r.estado IN ('confirmada', 'completada')
    GROUP BY TRUNC(rh.checkin, 'MM')
)
SELECT anio_mes,
    nombre_mes,
    cantidad_reservas,
    ingreso_mes,
    LAG(ingreso_mes, 1) OVER (ORDER BY periodo_mes) AS ingreso_mes_anterior,
    (ingreso_mes - LAG(ingreso_mes, 1) OVER (ORDER BY periodo_mes)) AS variacion_absoluta,
    ROUND(
        ((ingreso_mes - LAG(ingreso_mes, 1) OVER (ORDER BY periodo_mes)) / 
        NULLIF(LAG(ingreso_mes, 1) OVER (ORDER BY periodo_mes), 0)) * 100, 
        2
    ) AS variacion_porcentual,
    CASE
        WHEN LAG(ingreso_mes, 1) OVER (ORDER BY periodo_mes) IS NULL THEN 'Periodo Base'
        WHEN ingreso_mes > LAG(ingreso_mes, 1) OVER (ORDER BY periodo_mes) THEN '▲ Crecimiento'
        WHEN ingreso_mes < LAG(ingreso_mes, 1) OVER (ORDER BY periodo_mes) THEN '▼ Decrecimiento'
        ELSE '= Sin Variación'
    END AS tendencia
FROM IngresosMensuales
ORDER BY periodo_mes;


-- =============================================================================
-- CONSULTA 5 CORREGIDA: Parametrizada con Variables de Enlace (Bind Variables)
-- (Corrección de duplicación de pagos agrupando por reserva)
-- =============================================================================
VARIABLE fecha_inicio VARCHAR2(10);
VARIABLE fecha_fin VARCHAR2(10);
EXEC :fecha_inicio := '2024-01-01';
EXEC :fecha_fin := '2026-12-31';

WITH PagosUnicos AS (
    SELECT id_reserva, SUM(monto) AS total_pagado
    FROM Pago 
    WHERE estado = 'exitoso' 
    GROUP BY id_reserva
)
SELECT m.nombre AS municipio, 
    a.nombre_comercial AS alojamiento, 
    ta.nombre AS tipo_alojamiento,
    COUNT(DISTINCT r.id_reserva) AS total_reservas_recibidas,
    SUM(CASE WHEN r.estado = 'completada' THEN 1 ELSE 0 END) AS reservas_completadas,
    SUM(CASE WHEN r.estado = 'cancelada' THEN 1 ELSE 0 END) AS reservas_canceladas,
    ROUND((SUM(CASE WHEN r.estado = 'cancelada' THEN 1 ELSE 0 END) / COUNT(DISTINCT r.id_reserva)) * 100, 2) AS tasa_cancelacion_pct,
    NVL(SUM(p.total_pagado), 0) AS total_pagado_exitoso
FROM Municipio m
JOIN Alojamiento a ON m.id_municipio = a.id_municipio
JOIN Tipo_Alojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
JOIN Reserva_Habitacion rh ON h.id_habitacion = rh.id_habitacion
JOIN Reserva r ON rh.id_reserva = r.id_reserva
LEFT JOIN PagosUnicos p ON r.id_reserva = p.id_reserva
WHERE r.fecha_reserva >= TO_DATE(:fecha_inicio, 'YYYY-MM-DD')
  AND r.fecha_reserva <= TO_DATE(:fecha_fin, 'YYYY-MM-DD')
GROUP BY m.nombre, a.nombre_comercial, ta.nombre
HAVING COUNT(DISTINCT r.id_reserva) > 0
ORDER BY total_pagado_exitoso DESC;


-- =============================================================================
-- CONSULTA 6 CORREGIDA: Transformación de columnas a filas con UNPIVOT
-- (Corrección de producto cartesiano agrupando pagos antes del UNPIVOT)
-- =============================================================================
WITH PagosReserva AS (
    SELECT id_reserva, estado, SUM(monto) AS monto_total
    FROM Pago 
    GROUP BY id_reserva, estado
),
ResumenFinanciero AS (
    SELECT m.nombre AS municipio,
        NVL(SUM(CASE WHEN p.estado = 'exitoso' THEN p.monto_total ELSE 0 END), 0) AS recaudo_exitoso,
        NVL(SUM(CASE WHEN p.estado = 'reembolsado' THEN p.monto_total ELSE 0 END), 0) AS monto_reembolsado,
        NVL(SUM(CASE WHEN p.estado = 'pendiente' THEN p.monto_total ELSE 0 END), 0) AS monto_pendiente
    FROM Municipio m
    JOIN Alojamiento a ON m.id_municipio = a.id_municipio
    JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
    JOIN Reserva_Habitacion rh ON h.id_habitacion = rh.id_habitacion
    JOIN Reserva r ON rh.id_reserva = r.id_reserva
    JOIN PagosReserva p ON r.id_reserva = p.id_reserva
    GROUP BY m.nombre
)
SELECT municipio, concepto_financiero, monto_total
FROM ResumenFinanciero UNPIVOT (
    monto_total FOR concepto_financiero IN (
        recaudo_exitoso AS 'Pagos Exitosos Efectivos',
        monto_reembolsado AS 'Reembolsos por Cancelación',
        monto_pendiente AS 'Saldos Pendientes de Cobro'
    )
) 
ORDER BY municipio, concepto_financiero;


-- =============================================================================
-- CONSULTA 7: Matriz de Calidad vs Rentabilidad
-- =============================================================================
SELECT m.nombre AS municipio,
    a.nombre_comercial AS alojamiento,
    ta.nombre AS tipo_alojamiento,
    a.calificacion AS estrellas_autoasignadas,
    ROUND(AVG(re.calificacion), 2) AS calificacion_real_clientes,
    ROUND(AVG(re.calificacion) - a.calificacion, 2) AS brecha_expectativa,
    COUNT(re.id_resena) AS cantidad_resenas_recibidas,
    COUNT(DISTINCT r.id_reserva) AS total_reservas_completadas,
    SUM((TRUNC(rh.checkout) - TRUNC(rh.checkin)) * rh.precio_noche_calculado) AS ingresos_totales,
    CASE
        WHEN AVG(re.calificacion) >= 4.0
        AND SUM((TRUNC(rh.checkout) - TRUNC(rh.checkin)) * rh.precio_noche_calculado) >= 30000000 
        THEN 'Estrella: Alta Calidad y Alta Rentabilidad'
        
        WHEN AVG(re.calificacion) < 3.5
        AND SUM((TRUNC(rh.checkout) - TRUNC(rh.checkin)) * rh.precio_noche_calculado) >= 30000000 
        THEN 'Alerta: Alto Recaudo con Baja Satisfacción (Riesgo)'
        
        WHEN AVG(re.calificacion) >= 4.0
        AND SUM((TRUNC(rh.checkout) - TRUNC(rh.checkin)) * rh.precio_noche_calculado) < 30000000 
        THEN 'Oportunidad: Excelente Calidad con Potencial de Expansión'
        
        ELSE 'Rendimiento Estándar'
    END AS clasificacion_estrategica
FROM Municipio m
JOIN Alojamiento a ON m.id_municipio = a.id_municipio
JOIN Tipo_Alojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
JOIN Reserva_Habitacion rh ON h.id_habitacion = rh.id_habitacion
JOIN Reserva r ON rh.id_reserva = r.id_reserva
JOIN Resena re ON r.id_reserva = re.id_reserva
WHERE r.estado = 'completada'
GROUP BY m.nombre, a.nombre_comercial, ta.nombre, a.calificacion
HAVING COUNT(re.id_resena) >= 5
ORDER BY ingresos_totales DESC, calificacion_real_clientes DESC;