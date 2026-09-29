-- =============================================================================
-- PROYECTO INTEGRADOR: TurismoUQ
-- Plataforma de Reservas Turísticas del Quindío
-- Asignatura: Bases de Datos II
-- Motor: Oracle XE 21c / Database 12c+
-- Script: ScriptConsultas.sql (Las 7 Consultas de Análisis de la Entrega 1)
-- Equipo: Manuel Pineda Varela, Carlos Alonso Barahona y Santiago Solarte
-- Fecha: Septiembre 2026
-- =============================================================================

-- =============================================================================
-- CONSULTA 1: Ocupación por municipio y mes con PIVOT
-- =============================================================================
-- PREGUNTA DE NEGOCIO:
-- ¿Cuál es el nivel de ocupación mensual (medido en noches totales reservadas)
-- en cada uno de los 12 municipios del Quindío durante el año 2025?
--
-- TÉCNICA UTILIZADA:
-- Operador PIVOT de Oracle para transformar las filas de los 12 meses en columnas
-- matriciales, permitiendo a la gerencia comparar el comportamiento estacional.
-- =============================================================================

SELECT 
    municipio,
    NVL(Ene, 0) AS ene,
    NVL(Feb, 0) AS feb,
    NVL(Mar, 0) AS mar,
    NVL(Abr, 0) AS abr,
    NVL(May, 0) AS may,
    NVL(Jun, 0) AS jun,
    NVL(Jul, 0) AS jul,
    NVL(Ago, 0) AS ago,
    NVL(Sep, 0) AS sep,
    NVL(Oct, 0) AS oct,
    NVL(Nov, 0) AS nov,
    NVL(Dic, 0) AS dic,
    (NVL(Ene, 0) + NVL(Feb, 0) + NVL(Mar, 0) + NVL(Abr, 0) + 
     NVL(May, 0) + NVL(Jun, 0) + NVL(Jul, 0) + NVL(Ago, 0) + 
     NVL(Sep, 0) + NVL(Oct, 0) + NVL(Nov, 0) + NVL(Dic, 0)) AS total_anual_noches
FROM (
    SELECT 
        m.nombre AS municipio,
        EXTRACT(MONTH FROM rh.checkin) AS mes_num,
        (TRUNC(rh.checkout) - TRUNC(rh.checkin)) AS noches_estadia
    FROM Municipio m
    JOIN Alojamiento a ON m.id_municipio = a.id_municipio
    JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
    JOIN Reserva_Habitacion rh ON h.id_habitacion = rh.id_habitacion
    JOIN Reserva r ON rh.id_reserva = r.id_reserva
    WHERE r.estado IN ('confirmada', 'completada')
      AND EXTRACT(YEAR FROM rh.checkin) = 2025
)
PIVOT (
    SUM(noches_estadia)
    FOR mes_num IN (
        1 AS Ene, 2 AS Feb, 3 AS Mar, 4 AS Abr,
        5 AS May, 6 AS Jun, 7 AS Jul, 8 AS Ago,
        9 AS Sep, 10 AS Oct, 11 AS Nov, 12 AS Dic
    )
)
ORDER BY total_anual_noches DESC;


-- =============================================================================
-- CONSULTA 2: Ingresos por municipio, tipo de alojamiento y temporada
--              con ROLLUP y distinción de subtotales mediante GROUPING
-- =============================================================================
-- PREGUNTA DE NEGOCIO:
-- ¿Cuánto ingresa el departamento discriminado por municipio, tipo de hospedaje
-- y temporada turística, mostrando claramente subtotales jerárquicos y total general?
--
-- TÉCNICA UTILIZADA:
-- Cláusula ROLLUP sobre la jerarquía (Municipio -> Tipo -> Temporada) y la función
-- analítica GROUPING() para identificar dinámicamente si una fila corresponde a un
-- dato detallado, un subtotal intermedio o el total general consolidado.
-- =============================================================================

SELECT 
    CASE 
        WHEN GROUPING(m.nombre) = 1 THEN '>>> TOTAL DEPARTAMENTAL <<<'
        ELSE m.nombre 
    END AS municipio,
    
    CASE 
        WHEN GROUPING(m.nombre) = 0 AND GROUPING(ta.nombre) = 1 THEN '--- Subtotal Municipio ---'
        WHEN GROUPING(m.nombre) = 1 THEN '--- Todos los Tipos ---'
        ELSE ta.nombre 
    END AS tipo_alojamiento,
    
    CASE 
        WHEN GROUPING(ta.nombre) = 0 AND GROUPING(t.tipo) = 1 THEN '--- Subtotal Tipo ---'
        WHEN GROUPING(ta.nombre) = 1 THEN '--- Todas las Temporadas ---'
        ELSE t.tipo 
    END AS temporada,
    
    COUNT(DISTINCT r.id_reserva) AS total_reservas,
    SUM((TRUNC(rh.checkout) - TRUNC(rh.checkin)) * rh.precio_noche_calculado) AS ingresos_hospedaje,
    
    -- Indicadores binarios de agrupación para auditoría técnica
    GROUPING(m.nombre) AS grp_mun,
    GROUPING(ta.nombre) AS grp_tipo,
    GROUPING(t.tipo) AS grp_temp
FROM Municipio m
JOIN Alojamiento a ON m.id_municipio = a.id_municipio
JOIN Tipo_Alojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
JOIN Reserva_Habitacion rh ON h.id_habitacion = rh.id_habitacion
JOIN Reserva r ON rh.id_reserva = r.id_reserva
JOIN Temporada t ON rh.checkin >= t.fecha_inicio AND rh.checkin <= t.fecha_fin
WHERE r.estado IN ('confirmada', 'completada')
GROUP BY ROLLUP(m.nombre, ta.nombre, t.tipo)
ORDER BY 
    GROUPING(m.nombre), m.nombre,
    GROUPING(ta.nombre), ta.nombre,
    GROUPING(t.tipo), t.tipo;


-- =============================================================================
-- CONSULTA 3: Top 3 de alojamientos con mayor ingreso por municipio
--              utilizando RANK con PARTITION BY
-- =============================================================================
-- PREGUNTA DE NEGOCIO:
-- ¿Cuáles son los tres alojamientos líderes en facturación dentro de cada uno
-- de los municipios del Quindío?
--
-- TÉCNICA UTILIZADA:
-- Función de ventana analítica RANK() particionada por el municipio (PARTITION BY)
-- y ordenada de forma descendente por los ingresos totales generados. Se envuelve
-- en una expresión de tabla común (CTE) para filtrar RANK <= 3.
-- =============================================================================

WITH RankingIngresos AS (
    SELECT 
        m.nombre AS municipio,
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
    GROUP BY 
        m.nombre, 
        a.id_alojamiento, 
        a.nombre_comercial, 
        ta.nombre, 
        a.calificacion
)
SELECT 
    municipio,
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
-- PREGUNTA DE NEGOCIO:
-- ¿Cómo evolucionan financieramente los ingresos mes a mes en la plataforma,
-- cuál es la diferencia neta respecto al mes anterior y el porcentaje de crecimiento?
--
-- TÉCNICA UTILIZADA:
-- Función de ventana LAG() para consultar el valor del registro cronológico inmediatamente
-- anterior, calculando la variación absoluta, la tasa porcentual y una clasificación de tendencia.
-- =============================================================================

WITH IngresosMensuales AS (
    SELECT 
        TRUNC(rh.checkin, 'MM') AS periodo_mes,
        TO_CHAR(TRUNC(rh.checkin, 'MM'), 'YYYY-MM') AS anio_mes,
        TO_CHAR(TRUNC(rh.checkin, 'MM'), 'Month YYYY', 'NLS_DATE_LANGUAGE = SPANISH') AS nombre_mes,
        COUNT(DISTINCT r.id_reserva) AS cantidad_reservas,
        SUM((TRUNC(rh.checkout) - TRUNC(rh.checkin)) * rh.precio_noche_calculado) AS ingreso_mes
    FROM Reserva r
    JOIN Reserva_Habitacion rh ON r.id_reserva = rh.id_reserva
    WHERE r.estado IN ('confirmada', 'completada')
    GROUP BY TRUNC(rh.checkin, 'MM')
)
SELECT 
    anio_mes,
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
-- CONSULTA 5: Consulta parametrizada con variables de enlace (Bind Variables)
-- =============================================================================
-- PREGUNTA DE NEGOCIO:
-- Reporte operativo de auditoría gerencial: Filtrar el rendimiento de los alojamientos
-- y reservas dentro de una ventana de fechas parametrizable dinámicamente por el usuario.
--
-- TÉCNICA UTILIZADA:
-- Variables de enlace en Oracle (:fecha_inicio y :fecha_fin). Se evitan concatenaciones
-- directas para garantizar reutilización del plan de ejecución (soft parse) y seguridad.
--
-- GUÍA DE EJECUCIÓN EN SQL DEVELOPER / SQL*PLUS:
--   VARIABLE fecha_inicio VARCHAR2(10);
--   VARIABLE fecha_fin VARCHAR2(10);
--   EXEC :fecha_inicio := '2025-06-01';
--   EXEC :fecha_fin    := '2025-08-31';
-- =============================================================================

SELECT 
    m.nombre AS municipio,
    a.nombre_comercial AS alojamiento,
    ta.nombre AS tipo_alojamiento,
    COUNT(r.id_reserva) AS total_reservas_recibidas,
    SUM(CASE WHEN r.estado = 'completada' THEN 1 ELSE 0 END) AS reservas_completadas,
    SUM(CASE WHEN r.estado = 'cancelada' THEN 1 ELSE 0 END) AS reservas_canceladas,
    ROUND(
        (SUM(CASE WHEN r.estado = 'cancelada' THEN 1 ELSE 0 END) / COUNT(r.id_reserva)) * 100, 
        2
    ) AS tasa_cancelacion_pct,
    NVL(SUM(p.monto), 0) AS total_pagado_exitoso
FROM Municipio m
JOIN Alojamiento a ON m.id_municipio = a.id_municipio
JOIN Tipo_Alojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
JOIN Reserva_Habitacion rh ON h.id_habitacion = rh.id_habitacion
JOIN Reserva r ON rh.id_reserva = r.id_reserva
LEFT JOIN Pago p ON r.id_reserva = p.id_reserva AND p.estado = 'exitoso'
WHERE r.fecha_reserva >= TO_DATE(:fecha_inicio, 'YYYY-MM-DD')
  AND r.fecha_reserva <= TO_DATE(:fecha_fin, 'YYYY-MM-DD')
GROUP BY 
    m.nombre, 
    a.nombre_comercial, 
    ta.nombre
HAVING COUNT(r.id_reserva) > 0
ORDER BY total_pagado_exitoso DESC;


-- =============================================================================
-- CONSULTA 6: Transformación de columnas a filas con UNPIVOT
-- =============================================================================
-- PREGUNTA DE NEGOCIO:
-- Normalizar los diferentes conceptos financieros y estados de pago (recaudado,
-- pendiente, reembolsado) en un formato vertical estándar por municipio para
-- facilitar su integración con herramientas de reportería y Business Intelligence.
--
-- TÉCNICA UTILIZADA:
-- Operador UNPIVOT de Oracle para convertir métricas agregadas por columnas
-- (recaudo_exitoso, monto_reembolsado, monto_pendiente) en filas etiquetadas
-- con su concepto financiero y valor respectivo.
-- =============================================================================

WITH ResumenFinancieroMunicipio AS (
    SELECT 
        m.nombre AS municipio,
        NVL(SUM(CASE WHEN p.estado = 'exitoso' THEN p.monto ELSE 0 END), 0) AS recaudo_exitoso,
        NVL(SUM(CASE WHEN p.estado = 'reembolsado' THEN p.monto ELSE 0 END), 0) AS monto_reembolsado,
        NVL(SUM(CASE WHEN p.estado = 'pendiente' THEN p.monto ELSE 0 END), 0) AS monto_pendiente
    FROM Municipio m
    JOIN Alojamiento a ON m.id_municipio = a.id_municipio
    JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
    JOIN Reserva_Habitacion rh ON h.id_habitacion = rh.id_habitacion
    JOIN Reserva r ON rh.id_reserva = r.id_reserva
    JOIN Pago p ON r.id_reserva = p.id_reserva
    GROUP BY m.nombre
)
SELECT 
    municipio,
    concepto_financiero,
    monto_total
FROM ResumenFinancieroMunicipio
UNPIVOT (
    monto_total FOR concepto_financiero IN (
        recaudo_exitoso AS 'Pagos Exitosos Efectivos',
        monto_reembolsado AS 'Reembolsos por Cancelación',
        monto_pendiente AS 'Saldos Pendientes de Cobro'
    )
)
ORDER BY municipio, concepto_financiero;


-- =============================================================================
-- CONSULTA 7: Consulta libre de negocio - Matriz de Calidad vs Rentabilidad
-- =============================================================================
-- PREGUNTA DE NEGOCIO PROPUESTA:
-- ¿Existe coherencia entre la satisfacción real de los turistas (calificación en reseñas)
-- y los ingresos que generan los alojamientos? ¿Cuáles establecimientos tienen alta
-- satisfacción y alto recaudo (Líderes) frente a cuáles están en riesgo (baja calificación)?
--
-- TÉCNICA UTILIZADA:
-- Combina funciones de agregación condicional, AVG, JOINs con tablas de cruce,
-- cálculo de brecha de percepción (estrellas autoasignadas vs reseñas de clientes reales)
-- y segmentación estratégica mediante estructuras CASE y ordenamiento ponderado.
-- =============================================================================

SELECT 
    m.nombre AS municipio,
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
GROUP BY 
    m.nombre, 
    a.nombre_comercial, 
    ta.nombre, 
    a.calificacion
HAVING COUNT(re.id_resena) >= 5
ORDER BY ingresos_totales DESC, calificacion_real_clientes DESC;
