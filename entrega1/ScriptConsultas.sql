-- =============================================================================
-- PROYECTO INTEGRADOR TurismoUQ - Bases de Datos II
-- Script 03: las 7 consultas de análisis (ejecutar después de ScriptDatos.sql)
--
-- Correcciones tras la retroalimentación de la Entrega 1:
--   * C2: incluye 2024, 2025 y 2026 y calcula el ingreso noche por noche con
--         la tarifa de la temporada en la que cae cada noche.
--   * C5: trae VARIABLE y EXEC, así que corre tal cual como script; los pagos
--         ya no se duplican en reservas con varias habitaciones.
--   * C6: misma corrección de duplicados que la C5.
--   * C7: reseñas e ingresos se agregan por separado (sin duplicados).
--   * Los precios de RESERVA_HABITACION ahora salen de TARIFA (ScriptDatos.sql),
--     por lo que C3, C4 y C7 reportan ingresos coherentes con las tarifas.
-- =============================================================================

-- =============================================================================
-- CONSULTA 1: Ocupación por municipio y mes con PIVOT (noches ocupadas en 2025)
-- =============================================================================
select municipio,
       nvl(
          ene,
          0
       ) as ene,
       nvl(
          feb,
          0
       ) as feb,
       nvl(
          mar,
          0
       ) as mar,
       nvl(
          abr,
          0
       ) as abr,
       nvl(
          may,
          0
       ) as may,
       nvl(
          jun,
          0
       ) as jun,
       nvl(
          jul,
          0
       ) as jul,
       nvl(
          ago,
          0
       ) as ago,
       nvl(
          sep,
          0
       ) as sep,
       nvl(
          oct,
          0
       ) as oct,
       nvl(
          nov,
          0
       ) as nov,
       nvl(
          dic,
          0
       ) as dic,
       ( nvl(
          ene,
          0
       ) + nvl(
          feb,
          0
       ) + nvl(
          mar,
          0
       ) + nvl(
          abr,
          0
       ) + nvl(
          may,
          0
       ) + nvl(
          jun,
          0
       ) + nvl(
          jul,
          0
       ) + nvl(
          ago,
          0
       ) + nvl(
          sep,
          0
       ) + nvl(
          oct,
          0
       ) + nvl(
          nov,
          0
       ) + nvl(
          dic,
          0
       ) ) as total_anual_noches
  from (
   select m.nombre as municipio,
          extract(month from rh.checkin) as mes_num,
          ( trunc(rh.checkout) - trunc(rh.checkin) ) as noches_estadia
     from municipio m
     join alojamiento a
   on m.id_municipio = a.id_municipio
     join habitacion h
   on a.id_alojamiento = h.id_alojamiento
     join reserva_habitacion rh
   on h.id_habitacion = rh.id_habitacion
     join reserva r
   on rh.id_reserva = r.id_reserva
    where r.estado in ( 'confirmada',
                        'completada' )
      and extract(year from rh.checkin) = 2025
) pivot (
   sum(noches_estadia)
   for mes_num
   in ( 1 as ene,2 as feb,3 as mar,4 as abr,5 as may,6 as jun,7 as jul,8 as ago,9 as sep,10 as oct,11 as nov,12 as dic )
)
 order by total_anual_noches desc;



-- =============================================================================
-- CONSULTA 2: Ingresos por municipio, tipo de alojamiento y temporada (ROLLUP)
-- Pregunta: ¿cuánto ingresa cada municipio y cada tipo de alojamiento en
-- temporada alta, media y baja, con subtotales y total departamental?
-- =============================================================================
with calendario as (
   select date '2024-01-01' + level - 1 as noche
     from dual
   connect by
      level <= date '2027-01-01' - date '2024-01-01'
),noches as (
   select rh.id_reserva_habitacion,
          rh.id_habitacion,
          h.id_alojamiento,
          c.noche
     from reserva_habitacion rh
     join reserva r
   on r.id_reserva = rh.id_reserva
     join habitacion h
   on h.id_habitacion = rh.id_habitacion
     join calendario c
   on c.noche >= rh.checkin
      and c.noche < rh.checkout          -- la noche del checkout no se cobra
    where r.estado in ( 'confirmada',
                        'completada' )
)
select case
          when grouping(m.nombre) = 1 then
             '>>> TOTAL DEPARTAMENTAL <<<'
          else
             m.nombre
       end as municipio,
       case
          when grouping(m.nombre) = 1  then
             '--- Todos los tipos ---'
          when grouping(ta.nombre) = 1 then
             '--- Subtotal municipio ---'
          else
             ta.nombre
       end as tipo_alojamiento,
       case
          when grouping(ta.nombre) = 1 then
             '--- Todas las temporadas ---'
          when grouping(t.tipo) = 1    then
             '--- Subtotal tipo ---'
          else
             t.tipo
       end as temporada,
       count(*) as noches_vendidas,
       sum(tar.valor_noche) as ingresos_hospedaje,
       grouping(m.nombre) as grp_municipio,
       grouping(ta.nombre) as grp_tipo,
       grouping(t.tipo) as grp_temporada
  from noches n
  join alojamiento a
on a.id_alojamiento = n.id_alojamiento
  join municipio m
on m.id_municipio = a.id_municipio
  join tipo_alojamiento ta
on ta.id_tipo_alojamiento = a.id_tipo_alojamiento
  join temporada t
on n.noche between t.fecha_inicio and t.fecha_fin
  join tarifa tar
on tar.id_habitacion = n.id_habitacion
   and tar.id_temporada = t.id_temporada
 group by rollup(m.nombre,
                 ta.nombre,
                 t.tipo)
 order by grouping(m.nombre),
          m.nombre,
          grouping(ta.nombre),
          ta.nombre,
          grouping(t.tipo),
          t.tipo;


-- =============================================================================
-- CONSULTA 3: Top 3 de alojamientos con mayor ingreso por municipio (RANK OVER)
-- =============================================================================
with rankingingresos as (
   select m.nombre as municipio,
          a.id_alojamiento,
          a.nombre_comercial as alojamiento,
          ta.nombre as tipo_alojamiento,
          a.calificacion as estrellas_autoasignadas,
          count(distinct r.id_reserva) as reservas_atendidas,
          sum((trunc(rh.checkout) - trunc(rh.checkin)) * rh.precio_noche_calculado) as total_ingresos,
          rank()
          over(partition by m.nombre
               order by sum((trunc(rh.checkout) - trunc(rh.checkin)) * rh.precio_noche_calculado) desc
          ) as posicion_ranking
     from municipio m
     join alojamiento a
   on m.id_municipio = a.id_municipio
     join tipo_alojamiento ta
   on a.id_tipo_alojamiento = ta.id_tipo_alojamiento
     join habitacion h
   on a.id_alojamiento = h.id_alojamiento
     join reserva_habitacion rh
   on h.id_habitacion = rh.id_habitacion
     join reserva r
   on rh.id_reserva = r.id_reserva
    where r.estado in ( 'confirmada',
                        'completada' )
    group by m.nombre,
             a.id_alojamiento,
             a.nombre_comercial,
             ta.nombre,
             a.calificacion
)
select municipio,
       posicion_ranking,
       alojamiento,
       tipo_alojamiento,
       estrellas_autoasignadas,
       reservas_atendidas,
       total_ingresos
  from rankingingresos
 where posicion_ranking <= 3
 order by municipio,
          posicion_ranking;


-- =============================================================================
-- CONSULTA 4: Variación de ingresos mes contra mes utilizando LAG
-- =============================================================================
with ingresosmensuales as (
   select trunc(
      rh.checkin,
      'MM'
   ) as periodo_mes,
          to_char(
             trunc(
                rh.checkin,
                'MM'
             ),
             'YYYY-MM'
          ) as anio_mes,
          to_char(
             trunc(
                rh.checkin,
                'MM'
             ),
             'Month YYYY',
             'NLS_DATE_LANGUAGE = SPANISH'
          ) as nombre_mes,
          count(distinct r.id_reserva) as cantidad_reservas,
          sum((trunc(rh.checkout) - trunc(rh.checkin)) * rh.precio_noche_calculado) as ingreso_mes
     from reserva r
     join reserva_habitacion rh
   on r.id_reserva = rh.id_reserva
    where r.estado in ( 'confirmada',
                        'completada' )
    group by trunc(
      rh.checkin,
      'MM'
   )
)
select anio_mes,
       nombre_mes,
       cantidad_reservas,
       ingreso_mes,
       lag(ingreso_mes,
           1)
       over(
           order by periodo_mes
       ) as ingreso_mes_anterior,
       ( ingreso_mes - lag(ingreso_mes,
           1)
                       over(
           order by periodo_mes
                       ) ) as variacion_absoluta,
       round(
          ((ingreso_mes - lag(ingreso_mes,
           1)
                          over(
              order by periodo_mes
                          )) / nullif(
             lag(ingreso_mes,
                 1)
             over(
                 order by periodo_mes
             ),
             0
          )) * 100,
          2
       ) as variacion_porcentual,
       case
          when lag(ingreso_mes,
              1)
               over(
              order by periodo_mes
               ) is null then
             'Periodo Base'
          when ingreso_mes > lag(ingreso_mes,
              1)
                             over(
              order by periodo_mes
                             ) then
             '▲ Crecimiento'
          when ingreso_mes < lag(ingreso_mes,
              1)
                             over(
              order by periodo_mes
                             ) then
             '▼ Decrecimiento'
          else
             '= Sin Variación'
       end as tendencia
  from ingresosmensuales
 order by periodo_mes;



-- =============================================================================
-- CONSULTA 5: Consulta parametrizada con variables de enlace (bind variables)
-- Pregunta: para las reservas hechas en un rango de fechas, ¿cuántas recibió
-- cada alojamiento, qué tasa de cancelación tuvo y cuánto recaudó en neto
-- (pagos exitosos menos reembolsos)?
--
-- Ejecutar como script (F5 en SQL Developer, o en SQL*Plus): VARIABLE y EXEC
-- definen y asignan las variables de enlace antes de la consulta.
-- =============================================================================
VARIABLE fecha_inicio VARCHAR2(10)
VARIABLE fecha_fin    VARCHAR2(10)
EXEC :fecha_inicio := '2025-01-01';
EXEC :fecha_fin    := '2025-12-31';

with reserva_alojamiento as (           -- una fila por reserva y alojamiento
   select distinct rh.id_reserva,
                   h.id_alojamiento
     from reserva_habitacion rh
     join habitacion h
   on h.id_habitacion = rh.id_habitacion
),pagos_reserva as (                      -- una fila por reserva
   select id_reserva,
          sum(
             case
                when estado = 'exitoso' then
                   monto
                else
                   0
             end
          ) as pagado,
          sum(
             case
                when estado = 'reembolsado' then
                   monto
                else
                   0
             end
          ) as reembolsado
     from pago
    group by id_reserva
)
select m.nombre as municipio,
       a.nombre_comercial as alojamiento,
       ta.nombre as tipo_alojamiento,
       count(*) as reservas_recibidas,
       sum(
          case
             when r.estado = 'completada' then
                1
             else
                0
          end
       ) as reservas_completadas,
       sum(
          case
             when r.estado = 'cancelada' then
                1
             else
                0
          end
       ) as reservas_canceladas,
       round(
          100 * sum(
             case
                when r.estado = 'cancelada' then
                   1
                else
                   0
             end
          ) / count(*),
          2
       ) as tasa_cancelacion_pct,
       sum(nvl(
          p.pagado,
          0
       )) as pagos_exitosos,
       sum(nvl(
          p.reembolsado,
          0
       )) as reembolsos,
       sum(nvl(
          p.pagado,
          0
       ) - nvl(
          p.reembolsado,
          0
       )) as recaudo_neto
  from reserva_alojamiento ra
  join reserva r
on r.id_reserva = ra.id_reserva
  join alojamiento a
on a.id_alojamiento = ra.id_alojamiento
  join municipio m
on m.id_municipio = a.id_municipio
  join tipo_alojamiento ta
on ta.id_tipo_alojamiento = a.id_tipo_alojamiento
  left join pagos_reserva p
on p.id_reserva = r.id_reserva
 where r.fecha_reserva between to_date(:fecha_inicio,
        'YYYY-MM-DD') and to_date(:fecha_fin,
        'YYYY-MM-DD')
 group by m.nombre,
          a.nombre_comercial,
          ta.nombre
 order by recaudo_neto desc;


-- =============================================================================
-- CONSULTA 6: De columnas a filas con UNPIVOT
-- Pregunta: ¿cómo se reparte el dinero de cada municipio entre pagos exitosos,
-- reembolsos, saldos pendientes y pagos fallidos?
-- =============================================================================
with reserva_municipio as (             -- una fila por reserva y municipio
   select distinct rh.id_reserva,
                   a.id_municipio
     from reserva_habitacion rh
     join habitacion h
   on h.id_habitacion = rh.id_habitacion
     join alojamiento a
   on a.id_alojamiento = h.id_alojamiento
),resumen_financiero as (
   select m.nombre as municipio,
          sum(
             case
                when p.estado = 'exitoso' then
                   p.monto
                else
                   0
             end
          ) as pagos_exitosos,
          sum(
             case
                when p.estado = 'reembolsado' then
                   p.monto
                else
                   0
             end
          ) as reembolsos,
          sum(
             case
                when p.estado = 'pendiente' then
                   p.monto
                else
                   0
             end
          ) as saldos_pendientes,
          sum(
             case
                when p.estado = 'fallido' then
                   p.monto
                else
                   0
             end
          ) as pagos_fallidos
     from reserva_municipio rm
     join municipio m
   on m.id_municipio = rm.id_municipio
     join pago p
   on p.id_reserva = rm.id_reserva
    group by m.nombre
)
select municipio,
       concepto_financiero,
       monto_total
  from resumen_financiero unpivot ( monto_total
   for concepto_financiero
in ( pagos_exitosos as 'Pagos exitosos',
     reembolsos as 'Reembolsos por cancelacion',
     saldos_pendientes as 'Saldos pendientes de cobro',
     pagos_fallidos as 'Intentos de pago fallidos' ) )
 order by municipio,
          concepto_financiero;


-- =============================================================================
-- CONSULTA 7 (libre): Matriz de calidad vs. rentabilidad
-- Pregunta de negocio: ¿qué alojamientos cobran bien pero dejan insatisfechos
-- a sus huéspedes, y cuáles tienen excelente calidad pero poco ingreso?
-- Compara las estrellas que el alojamiento se autoasigna con la calificación
-- real de las reseñas y con su ingreso por hospedaje.
-- =============================================================================
with resenas_alojamiento as (
   select ra.id_alojamiento,
          count(*) as cantidad_resenas,
          round(
             avg(re.calificacion),
             2
          ) as calificacion_clientes
     from resena re
     join (
      select distinct rh.id_reserva,
                      h.id_alojamiento
        from reserva_habitacion rh
        join habitacion h
      on h.id_habitacion = rh.id_habitacion
   ) ra
   on ra.id_reserva = re.id_reserva
    group by ra.id_alojamiento
),ingresos_alojamiento as (
   select h.id_alojamiento,
          count(distinct r.id_reserva) as reservas_completadas,
          sum((rh.checkout - rh.checkin) * rh.precio_noche_calculado) as ingresos_hospedaje
     from reserva_habitacion rh
     join reserva r
   on r.id_reserva = rh.id_reserva
     join habitacion h
   on h.id_habitacion = rh.id_habitacion
    where r.estado = 'completada'
    group by h.id_alojamiento
)
select m.nombre as municipio,
       a.nombre_comercial as alojamiento,
       ta.nombre as tipo_alojamiento,
       a.calificacion as estrellas_autoasignadas,
       rs.calificacion_clientes,
       round(
          rs.calificacion_clientes - a.calificacion,
          2
       ) as brecha_expectativa,
       rs.cantidad_resenas,
       ia.reservas_completadas,
       ia.ingresos_hospedaje,
       case
          when rs.calificacion_clientes >= 4.0
             and ia.ingresos_hospedaje >= 300000000 then
             'Estrella: alta calidad y alta rentabilidad'
          when rs.calificacion_clientes < 3.0
             and ia.ingresos_hospedaje >= 300000000 then
             'Alerta: alto recaudo con baja satisfaccion'
          when rs.calificacion_clientes >= 4.0 then
             'Oportunidad: excelente calidad con potencial de crecer'
          when rs.calificacion_clientes < 3.0  then
             'Riesgo: baja calidad y bajo ingreso'
          else
             'Rendimiento estandar'
       end as clasificacion_estrategica
  from alojamiento a
  join municipio m
on m.id_municipio = a.id_municipio
  join tipo_alojamiento ta
on ta.id_tipo_alojamiento = a.id_tipo_alojamiento
  join resenas_alojamiento rs
on rs.id_alojamiento = a.id_alojamiento
  join ingresos_alojamiento ia
on ia.id_alojamiento = a.id_alojamiento
 where rs.cantidad_resenas >= 5
 order by ia.ingresos_hospedaje desc,
          rs.calificacion_clientes desc;