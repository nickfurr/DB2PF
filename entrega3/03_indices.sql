-- =============================================================================
-- ENTREGA 3 - TurismoUQ
-- 03. Indices y planes de ejecucion (3 consultas lentas + caso donde no ayuda).
-- Ejecutar con F5 en SQL Developer conectado con el usuario del proyecto.
-- =============================================================================
   SET LINESIZE 200
SET PAGESIZE 100
COLUMN plan_table_output FORMAT A110

-- Limpieza previa opcional (por si los indices ya existian de una corrida anterior)
begin
   for i in (
      select index_name
        from user_indexes
       where index_name in ( 'IDX_RH_HABITACION',
                             'IDX_RH_HAB_CHECKIN',
                             'FX_RH_ANIO',
                             'IDX_RESERVA_ESTADO' )
   ) loop
      execute immediate 'DROP INDEX ' || i.index_name;
   end loop;
end;
/

-- -----------------------------------------------------------------------------
-- CONSULTA 1: historial de reservas de una habitacion especifica (llave
-- foranea sin indice automatico en Oracle). Sin indice obliga a recorrer toda
-- la tabla Reserva_Habitacion; con idx_rh_habitacion pasa a INDEX RANGE SCAN.
-- -----------------------------------------------------------------------------
pro    === CONSULTA 1 (ANTES): Busqueda por id_habitacion sin indice ===
explain plan
   for
select id_reserva,
       checkin,
       checkout,
       precio_noche_calculado
  from reserva_habitacion
 where id_habitacion = 150;

select *
  from table ( dbms_xplan.display );

-- Indice sobre llave foranea
create index idx_rh_habitacion on
   reserva_habitacion (
      id_habitacion
   );

pro    === CONSULTA 1 (DESPUES): Con indice B-Tree idx_rh_habitacion ===
explain plan
   for
select id_reserva,
       checkin,
       checkout,
       precio_noche_calculado
  from reserva_habitacion
 where id_habitacion = 150;

select *
  from table ( dbms_xplan.display );

-- -----------------------------------------------------------------------------
-- CONSULTA 2: reservas de una habitacion a partir de una fecha. Filtra por dos
-- columnas, se resuelve con un indice COMPUESTO (id_habitacion, checkin).
-- El orden importa: la columna lider (id_habitacion) va primero.
-- -----------------------------------------------------------------------------
-- Se borra el indice simple anterior para medir el efecto limpio del compuesto
drop index idx_rh_habitacion;

pro    === CONSULTA 2 (ANTES): Filtro por habitacion y fecha sin indice ===
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

pro    === CONSULTA 2 (DESPUES): Con indice compuesto idx_rh_hab_checkin ===
explain plan
   for
select *
  from reserva_habitacion
 where id_habitacion = 150
   and checkin >= date '2025-06-01';

select *
  from table ( dbms_xplan.display );

-- Recrear tambien idx_rh_habitacion si se desea conservar o dejar el compuesto
-- (idx_rh_hab_checkin ya cubre busquedas por id_habitacion porque es columna lider)

-- -----------------------------------------------------------------------------
-- CONSULTA 3: reservas de un ano. EXTRACT(YEAR FROM checkin) es una funcion
-- sobre la columna, por eso un indice normal sobre checkin no sirve. Se crea un
-- indice FUNCIONAL sobre la misma expresion del WHERE.
-- -----------------------------------------------------------------------------
pro    === CONSULTA 3 (ANTES): Filtro con EXTRACT(YEAR FROM checkin) sin indice funcional ===
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

pro    === CONSULTA 3 (DESPUES): Con indice basado en funcion fx_rh_anio ===
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
pro    === CASO DONDE NO AYUDA (ANTES): Filtro por estado = confirmada sin indice ===
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

pro    === CASO DONDE NO AYUDA (DESPUES): Con idx_reserva_estado (sigue en TABLE ACCESS FULL) ===
explain plan
   for
select *
  from reserva
 where estado = 'confirmada';

select *
  from table ( dbms_xplan.display );

-- Ver los indices creados
select index_name,
       index_type,
       uniqueness
  from user_indexes
 where table_name in ( 'RESERVA_HABITACION',
                       'RESERVA' )
 order by index_name;

-- Limpieza (para volver a ejecutar en limpio):
-- DROP INDEX idx_rh_hab_checkin;
-- DROP INDEX fx_rh_anio;
-- DROP INDEX idx_reserva_estado;