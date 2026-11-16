-- ENTREGA 3 - TurismoUQ
-- CONSULTA 2: reservas de una habitacion a partir de una fecha. Filtra por dos
-- columnas, se resuelve con un indice COMPUESTO (id_habitacion, checkin).
-- El orden importa: la columna lider (id_habitacion) va primero.
-- -----------------------------------------------------------------------------
-- Antes

explain plan
   for
select *
  from reserva_habitacion
 where id_habitacion = 150
   and checkin >= date '2025-06-01';

select *
  from table ( dbms_xplan.display );

-- Indice compuesto
create index idx_rh_hab_checkin on
   reserva_habitacion (
      id_habitacion,
      checkin
   );

-- Despues (usa el indice compuesto por las dos columnas)
explain plan
   for
select *
  from reserva_habitacion
 where id_habitacion = 150
   and checkin >= date '2025-06-01';

select *
  from table ( dbms_xplan.display );

-- -----------------------------------------------------------------------------
-- CONSULTA 3: reservas de un ano. EXTRACT(YEAR FROM checkin) es una funcion
-- sobre la columna, por eso un indice normal sobre checkin no sirve. Se crea un
-- indice FUNCIONAL sobre la misma expresion del WHERE.
-- -----------------------------------------------------------------------------
-- Antes
explain plan
   for
select *
  from reserva_habitacion
 where extract(year from checkin) = 2025;

select *
  from table ( dbms_xplan.display );

-- Indice funcional sobre la expresion
create index fx_rh_anio on
   reserva_habitacion ( extract(year from
      checkin
   ) );

-- Despues (ahora el filtro por ano puede usar el indice funcional)
explain plan
   for
select *
  from reserva_habitacion
 where extract(year from checkin) = 2025;

select *
  from table ( dbms_xplan.display );

-- -----------------------------------------------------------------------------
-- CASO DONDE EL INDICE NO AYUDA: filtrar Reserva por estado.
-- 'estado' tiene muy pocos valores distintos (4) y 'confirmada' devuelve cerca
-- de un tercio de la tabla. Leer esa fraccion por indice, fila por fila y
-- saltando al ROWID, cuesta mas que leer la tabla de corrido, asi que el
-- optimizador IGNORA el indice y se queda en TABLE ACCESS FULL. Es baja
-- selectividad: un indice solo ayuda cuando devuelve pocas filas por valor.
-- -----------------------------------------------------------------------------
explain plan
   for
select *
  from reserva
 where estado = 'confirmada';

select *
  from table ( dbms_xplan.display );

create index idx_reserva_estado on
   reserva (
      estado
   );

-- Aun con el indice creado, el plan sigue en TABLE ACCESS FULL
explain plan
   for
select *
  from reserva
 where estado = 'confirmada';

select *
  from table ( dbms_xplan.display );

-- Ver los indices creados
select index_name,
       uniqueness
  from user_indexes
 where table_name in ( 'RESERVA_HABITACION',
                       'RESERVA' )
 order by index_name;

-- Limpieza (para volver a ejecutar en limpio):
-- DROP INDEX idx_rh_habitacion;
-- DROP INDEX idx_rh_hab_checkin;
-- DROP INDEX fx_rh_anio;
-- DROP INDEX idx_reserva_estado;