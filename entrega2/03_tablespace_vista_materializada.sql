-- ENTREGA 2 - TurismoUQ
-- 03. Tablespace del historico de reservas y vista materializada de ocupacion.

SET SERVEROUTPUT ON

-- Tablespace propio para el historico de reservas.
CREATE TABLESPACE ts_reservas_hist
    DATAFILE 'ts_reservas_hist_01.dbf' SIZE 50M AUTOEXTEND ON NEXT 10M;

BEGIN
    EXECUTE IMMEDIATE 'ALTER USER ' || USER || ' QUOTA UNLIMITED ON ts_reservas_hist';
END;
/

SELECT tablespace_name, COUNT(*) AS datafiles
  FROM dba_data_files
 WHERE tablespace_name = 'TS_RESERVAS_HIST'
 GROUP BY tablespace_name;

-- Vista materializada de ocupacion mensual por alojamiento.
DROP MATERIALIZED VIEW mv_ocupacion_mensual;
CREATE MATERIALIZED VIEW mv_ocupacion_mensual
    TABLESPACE ts_reservas_hist
    BUILD IMMEDIATE
    REFRESH COMPLETE ON DEMAND
AS
SELECT m.nombre                                   AS municipio,
       a.id_alojamiento,
       a.nombre_comercial,
       TO_CHAR(rh.checkin, 'YYYY-MM')             AS anio_mes,
       COUNT(DISTINCT r.id_reserva)               AS reservas,
       SUM(TRUNC(rh.checkout) - TRUNC(rh.checkin)) AS noches_ocupadas
  FROM Municipio m
  JOIN Alojamiento        a  ON a.id_municipio  = m.id_municipio
  JOIN Habitacion         h  ON h.id_alojamiento = a.id_alojamiento
  JOIN Reserva_Habitacion rh ON rh.id_habitacion = h.id_habitacion
  JOIN Reserva            r  ON r.id_reserva     = rh.id_reserva
 WHERE r.estado IN ('confirmada', 'completada')
 GROUP BY m.nombre, a.id_alojamiento, a.nombre_comercial, TO_CHAR(rh.checkin, 'YYYY-MM');

SELECT municipio, nombre_comercial, anio_mes, reservas, noches_ocupadas
  FROM mv_ocupacion_mensual
 WHERE anio_mes = '2025-07'
 ORDER BY noches_ocupadas DESC;

-- EXEC DBMS_MVIEW.REFRESH('mv_ocupacion_mensual', 'C');
