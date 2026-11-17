-- =============================================================================
-- ENTREGA 2 - TurismoUQ
-- 03b. Historico de reservas en su tablespace y vista materializada de ocupacion.
-- Ejecutar con el usuario del proyecto, despues de 01, 02 y de que SYSTEM haya
-- ejecutado 03a_tablespace_system.sql (que crea TS_RESERVAS_HIST).
-- El script se puede correr varias veces: cada paso revisa si ya esta hecho.
-- =============================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100

-- =============================================================================
-- 1. TABLESPACE PROPIO PARA EL HISTORICO DE RESERVAS
--
-- Justificacion: por que separar el historico
--   * Las reservas de anos cerrados (2024 y 2025) ya no cambian: la estadia
--     termino, se pago y se reseno. Son mas de la mitad de las filas y cada ano
--     se suma uno nuevo. Las de 2026 en adelante, en cambio, se crean,
--     confirman y cancelan todos los dias.
--   * Respaldos: el tablespace del ano en curso se respalda a diario; el del
--     historico, solo cuando se cierra un ano. Incluso se puede poner en
--     READ ONLY (ALTER TABLESPACE ts_reservas_hist READ ONLY) para que nadie
--     altere reservas viejas por error y para que el respaldo se haga una vez.
--   * Rendimiento: con las tablas particionadas por fecha, una consulta de las
--     reservas actuales solo lee la particion actual (partition pruning) y no
--     recorre los anos viejos.
--   * Espacio: el historico crece por su lado, en su propio datafile, y se
--     puede llevar a un disco mas barato sin tocar el tablespace operativo.
--
-- Como se usa: fragmentacion horizontal por rango de fechas (particiones).
--   RESERVA            se parte por fecha_reserva
--   RESERVA_HABITACION se parte por checkin
--   p_2024 y p_2025 viven en ts_reservas_hist; p_actual (2026 en adelante)
--   queda en el tablespace por defecto del usuario. Las consultas no cambian:
--   Oracle reune las particiones de forma transparente.
--   Al cerrar un ano se separa su particion y se lleva al historico:
--     ALTER TABLE Reserva_Habitacion SPLIT PARTITION p_actual
--       AT (DATE '2027-01-01')
--       INTO (PARTITION p_2026 TABLESPACE ts_reservas_hist, PARTITION p_actual);
-- =============================================================================

-- 1.1 Comprobar que SYSTEM ya creo el tablespace y dio la cuota (script 03a)
DECLARE
    v_cuota NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_cuota
      FROM user_ts_quotas
     WHERE tablespace_name = 'TS_RESERVAS_HIST';
    IF v_cuota = 0 THEN
        RAISE_APPLICATION_ERROR(-20031,
            'Falta el tablespace TS_RESERVAS_HIST o la cuota sobre el: ' ||
            'ejecute primero 03a_tablespace_system.sql como SYSTEM.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('TS_RESERVAS_HIST disponible para ' || USER || '.');
END;
/

-- 1.2 Particionar RESERVA y RESERVA_HABITACION por ano. Los anos cerrados van
--     al tablespace del historico. ENABLE ROW MOVEMENT permite que un UPDATE
--     de la fecha mueva la fila a la particion que le corresponde.
DECLARE
    PROCEDURE particionar (p_tabla VARCHAR2, p_columna VARCHAR2) IS
        v_ya NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_ya FROM user_part_tables WHERE table_name = UPPER(p_tabla);
        IF v_ya > 0 THEN
            DBMS_OUTPUT.PUT_LINE(p_tabla || ' ya estaba particionada.');
        ELSE
            EXECUTE IMMEDIATE
                'ALTER TABLE ' || p_tabla || ' MODIFY PARTITION BY RANGE (' || p_columna || ') (' ||
                '  PARTITION p_2024   VALUES LESS THAN (DATE ''2025-01-01'') TABLESPACE ts_reservas_hist,' ||
                '  PARTITION p_2025   VALUES LESS THAN (DATE ''2026-01-01'') TABLESPACE ts_reservas_hist,' ||
                '  PARTITION p_actual VALUES LESS THAN (MAXVALUE))';
            DBMS_OUTPUT.PUT_LINE(p_tabla || ' particionada por ' || p_columna || '.');
        END IF;
        EXECUTE IMMEDIATE 'ALTER TABLE ' || p_tabla || ' ENABLE ROW MOVEMENT';
    END;
BEGIN
    particionar('Reserva',            'fecha_reserva');
    particionar('Reserva_Habitacion', 'checkin');

    -- Si algun indice (PK, UNIQUE) quedo UNUSABLE tras el cambio, se reconstruye.
    FOR i IN (SELECT index_name
                FROM user_indexes
               WHERE table_name IN ('RESERVA', 'RESERVA_HABITACION')
                 AND status = 'UNUSABLE') LOOP
        EXECUTE IMMEDIATE 'ALTER INDEX ' || i.index_name || ' REBUILD';
        DBMS_OUTPUT.PUT_LINE('Indice reconstruido: ' || i.index_name);
    END LOOP;
END;
/

-- 1.3 Evidencia: particiones, su tablespace y filas en cada una

SELECT 'RESERVA' AS tabla, 'P_2024' AS particion, COUNT(*) AS filas FROM Reserva PARTITION (p_2024)
UNION ALL SELECT 'RESERVA', 'P_2025',   COUNT(*) FROM Reserva PARTITION (p_2025)
UNION ALL SELECT 'RESERVA', 'P_ACTUAL', COUNT(*) FROM Reserva PARTITION (p_actual)
UNION ALL SELECT 'RESERVA_HABITACION', 'P_2024',   COUNT(*) FROM Reserva_Habitacion PARTITION (p_2024)
UNION ALL SELECT 'RESERVA_HABITACION', 'P_2025',   COUNT(*) FROM Reserva_Habitacion PARTITION (p_2025)
UNION ALL SELECT 'RESERVA_HABITACION', 'P_ACTUAL', COUNT(*) FROM Reserva_Habitacion PARTITION (p_actual);

SELECT table_name, partition_name, tablespace_name, high_value
  FROM user_tab_partitions
 WHERE table_name IN ('RESERVA', 'RESERVA_HABITACION')
 ORDER BY table_name, partition_position;

-- =============================================================================
-- 2. VISTA MATERIALIZADA DE OCUPACION MENSUAL
--
-- Que precalcula: por alojamiento y mes, las noches ocupadas, las noches
-- disponibles (habitaciones x dias del mes) y el porcentaje de ocupacion.
--   * Las noches se cuentan noche por noche contra un calendario: una estadia
--     del 30 de junio al 3 de julio suma 1 noche a junio y 2 a julio.
--   * Solo cuentan reservas confirmadas o completadas.
--   * Aparecen tambien los meses sin ocupacion (0 %), para no esconder los
--     alojamientos que no venden.
--   * El calendario va del primer checkin al ultimo checkout registrados, asi
--     que la vista crece sola cuando entran reservas de anos nuevos.
--
-- Politica de refresco: REFRESH COMPLETE, programado todos los dias a las
-- 2:00 a.m. (START WITH / NEXT), y a demanda con DBMS_MVIEW.REFRESH.
--   * Es un tablero de gerencia mensual: basta con los datos al cierre del dia
--     anterior. Nadie decide la ocupacion del mes por una reserva de hace una
--     hora.
--   * ON COMMIT no conviene: obligaria a recalcular en el COMMIT de cada
--     reserva, justo en la operacion que mas se usa y que en la Entrega 3
--     estudiamos con concurrencia. Ademas exige REFRESH FAST, y esta consulta
--     no es refrescable rapido (usa un calendario con CONNECT BY, COUNT
--     DISTINCT y un LEFT JOIN contra una cuadricula alojamiento x mes).
--   * El refresco completo recalcula unas 90.000 noches en pocos segundos, de
--     madrugada, cuando casi no hay reservas entrando.
-- =============================================================================

-- 2.1 Borrar la vista si existe (en una base limpia no existe: no es error)
BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_ocupacion_mensual';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -12003 THEN
            RAISE;
        END IF;
END;
/

-- 2.2 Crear la vista
CREATE MATERIALIZED VIEW mv_ocupacion_mensual
    BUILD IMMEDIATE
    REFRESH COMPLETE
    START WITH TRUNC(SYSDATE) + 1 + 2/24
    NEXT TRUNC(SYSDATE) + 1 + 2/24
AS
WITH limites AS (
    SELECT TRUNC(MIN(checkin), 'YYYY') AS desde,
           MAX(checkout)              AS hasta
      FROM Reserva_Habitacion
),
calendario AS (
    SELECT l.desde + LEVEL - 1 AS dia
      FROM limites l
    CONNECT BY LEVEL <= l.hasta - l.desde
),
meses AS (
    SELECT DISTINCT TRUNC(dia, 'MM') AS mes FROM calendario
),
habitaciones AS (
    SELECT id_alojamiento, COUNT(*) AS habitaciones
      FROM Habitacion
     GROUP BY id_alojamiento
),
noches AS (
    SELECT h.id_alojamiento,
           TRUNC(c.dia, 'MM')           AS mes,
           COUNT(*)                     AS noches_ocupadas,
           COUNT(DISTINCT rh.id_reserva) AS reservas
      FROM Reserva_Habitacion rh
      JOIN Reserva    r ON r.id_reserva    = rh.id_reserva
      JOIN Habitacion h ON h.id_habitacion = rh.id_habitacion
      JOIN calendario c ON c.dia >= rh.checkin
                       AND c.dia <  rh.checkout
     WHERE r.estado IN ('confirmada', 'completada')
     GROUP BY h.id_alojamiento, TRUNC(c.dia, 'MM')
)
SELECT m.nombre                                   AS municipio,
       a.id_alojamiento,
       a.nombre_comercial,
       ta.nombre                                  AS tipo_alojamiento,
       me.mes,
       TO_CHAR(me.mes, 'YYYY-MM')                 AS anio_mes,
       hb.habitaciones,
       NVL(n.reservas, 0)                         AS reservas,
       NVL(n.noches_ocupadas, 0)                  AS noches_ocupadas,
       hb.habitaciones * (ADD_MONTHS(me.mes, 1) - me.mes) AS noches_disponibles,
       ROUND(100 * NVL(n.noches_ocupadas, 0)
                 / (hb.habitaciones * (ADD_MONTHS(me.mes, 1) - me.mes)), 2) AS pct_ocupacion
  FROM Alojamiento a
  JOIN Municipio        m  ON m.id_municipio         = a.id_municipio
  JOIN Tipo_Alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
  JOIN habitaciones     hb ON hb.id_alojamiento      = a.id_alojamiento
 CROSS JOIN meses me
  LEFT JOIN noches n ON n.id_alojamiento = a.id_alojamiento
                    AND n.mes            = me.mes;

COMMENT ON MATERIALIZED VIEW mv_ocupacion_mensual IS
    'Ocupacion mensual por alojamiento: noches ocupadas, disponibles y porcentaje. Refresco completo diario a las 2:00 a.m.';

-- 2.3 Evidencia: definicion del refresco y una muestra
SELECT mview_name, refresh_mode, refresh_method, build_mode,
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI') AS ultimo_refresco,
       staleness
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';

SELECT municipio, nombre_comercial, anio_mes, habitaciones, reservas,
       noches_ocupadas, noches_disponibles, pct_ocupacion
  FROM mv_ocupacion_mensual
 WHERE anio_mes = '2025-07'
 ORDER BY pct_ocupacion DESC
 FETCH FIRST 10 ROWS ONLY;
