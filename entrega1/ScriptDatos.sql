-- =============================================================================
-- PROYECTO INTEGRADOR TurismoUQ - Bases de Datos II
-- Script 02: carga de datos (volumen minimo y datos asimetricos)
-- Ejecutar una sola vez, despues de ScriptDDL.sql, sobre tablas vacias y ANTES
-- de crear los disparadores de la Entrega 2.
--
-- Correcciones frente a la version de la Entrega 1:
--   * Temporadas reales de 2024, 2025 y 2026: Semana Santa, mitad de ano,
--     puentes festivos y diciembre-enero son temporada alta; el resto se reparte
--     en media y baja. Todo dia entre 2024-01-01 y 2027-01-11 cae en exactamente
--     una temporada, asi que ninguna noche queda sin tarifa.
--   * TARIFA sale del cruce habitacion x temporada, y cada alojamiento decide
--     cuanto sube en alta (algunos casi nada, para competir por volumen).
--   * precio_noche_calculado se obtiene de TARIFA noche por noche (valor de la
--     estadia / noches), igual que hara fn_valor_estadia.
--   * Las reservas usan todas las habitaciones y NUNCA se solapan: el script
--     lleva un calendario de ocupacion en memoria y solo asigna habitaciones
--     libres. Las canceladas no ocupan la habitacion.
--   * Una reserva de grupo toma varias habitaciones del MISMO alojamiento, y a
--     veces una de ellas llega un dia despues.
--   * Los servicios contratados siempre son del alojamiento de la reserva.
--   * Pagos: pago unico o anticipo + saldo, intentos fallidos, saldos
--     pendientes y reembolso del 80 % si se cancela con mas de 5 dias.
--   * Resenas solo para reservas completadas, una por reserva.
--
-- Los numeros "aleatorios" salen de un generador congruencial con semilla fija
-- (funcion rnd): cada ejecucion produce exactamente los mismos datos, lo que
-- permite reproducir resultados y verificarlos.
-- Duracion aproximada: 1 a 3 minutos en Oracle XE.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    -- -------------------------------------------------------------------------
    -- Constantes de calendario
    -- -------------------------------------------------------------------------
    c_d0       CONSTANT DATE := DATE '2024-01-01';                    -- dia 0
    c_last     CONSTANT PLS_INTEGER := DATE '2027-01-11' - DATE '2024-01-01'; -- ultimo dia con temporada
    c_end_res  CONSTANT PLS_INTEGER := DATE '2026-12-31' - DATE '2024-01-01'; -- checkout maximo
    c_corte    CONSTANT PLS_INTEGER := DATE '2026-10-23' - DATE '2024-01-01'; -- "hoy" de los datos

    TYPE t_num  IS TABLE OF NUMBER        INDEX BY PLS_INTEGER;
    TYPE t_int  IS TABLE OF PLS_INTEGER   INDEX BY PLS_INTEGER;
    TYPE t_txt  IS TABLE OF VARCHAR2(200) INDEX BY PLS_INTEGER;
    TYPE t_bool IS TABLE OF BOOLEAN       INDEX BY PLS_INTEGER;

    g_seed NUMBER := 20261025;

    -- Temporadas
    alta_nom t_txt;  alta_ini t_int;  alta_fin t_int;  n_alta PLS_INTEGER := 0;
    day_alta    t_int;      -- dia -> indice de temporada alta
    day_season  t_int;      -- dia -> indice de temporada (1..n_temp)
    temp_id     t_num;  temp_tipo t_txt;  temp_ini t_int;  n_temp PLS_INTEGER := 0;

    -- Municipios, tipos, clientes
    mun_id  t_num;  mun_nom t_txt;  mun_pat t_txt;  mun_w t_int;
    tipo_id t_num;  -- 1=Hotel(H) 2=Finca(F) 3=Glamping(G) 4=Hostal(E)
    cli_id  t_num;

    -- Alojamientos
    a_id t_num;  a_tipo t_txt;  a_n t_int;  a_first t_int;  a_w t_int;
    a_af t_int;  a_altaf t_int;  a_bajaf t_int;  a_q t_int;
    a_sfirst t_int;  a_nserv t_int;
    n_aloj PLS_INTEGER := 0;  tot_w PLS_INTEGER := 0;

    -- Habitaciones, tarifas, servicios
    r_id t_num;  r_base t_int;  r_aloj t_int;  n_hab PLS_INTEGER := 0;
    tar  t_num;              -- (habitacion * 100 + temporada) -> valor noche
    s_id t_num;  s_precio t_num;  n_serv PLS_INTEGER := 0;

    -- Ocupacion: (habitacion * 2000 + dia) -> TRUE
    occ t_bool;

    -- Catalogos de texto
    nombres   SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
        'Laura','Carlos','Sofia','Andres','Valentina','Juan','Mariana','Diego','Camila','Santiago',
        'Daniela','Sebastian','Isabella','Mateo','Gabriela','Nicolas','Paula','Felipe','Natalia','Alejandro');
    apellidos SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
        'Martinez','Rodriguez','Gomez','Ramirez','Torres','Hernandez','Castro','Morales','Garcia','Lopez',
        'Gonzalez','Restrepo','Ospina','Arango','Giraldo','Cardona','Mejia','Zapata','Valencia','Quintero');
    nombres_aloj SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
        'El Mirador','La Esperanza','Los Arrayanes','Bambu','El Cafetal','Los Guaduales','Palma de Cera','El Roble',
        'Las Heliconias','Bosque de Niebla','La Cascada','El Eden','Monteverde','La Floresta','Los Naranjos','San Rafael',
        'El Recreo','La Pradera','Villa Maria','El Porvenir','Las Acacias','Buenos Aires','La Montana','El Paraiso',
        'Santa Barbara','La Primavera','El Bosque','Los Alpes','El Cedral','La Herradura','Puerto Espejo','La Victoria',
        'El Retiro','Las Palmas','La Bella','El Jardin','Cocora','La Coqueta','El Ocaso','Altos del Rio',
        'Barbas','Cafe y Niebla','La Alondra','El Guamo','Las Orquideas','La Tulia','El Silencio','Navarco',
        'Quebrada Negra','La Ceiba','Morelia','El Nogal','Tres Esquinas','La Maizena','El Laurel','Santa Ana',
        'La Rivera','Los Pinos','El Cairo','Mirador Andino');
    ciudades SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
        'Bogota','Medellin','Cali','Pereira','Manizales','Armenia','Ibague','Bucaramanga','Barranquilla','Cartagena',
        'Calarca','Cartago','Tulua','Neiva','Villavicencio','Pasto','Madrid','Ciudad de Mexico','Miami','Buenos Aires');
    -- Peso de cada ciudad (suma 100): mas turistas de Bogota, Medellin y Cali
    ciudad_w SYS.ODCINUMBERLIST := SYS.ODCINUMBERLIST(
        22,14,12,8,6,5,5,4,3,3, 3,3,2,2,2,1,1,1,2,1);
    servicios_cat SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
        'Desayuno tipico','Tour del cafe','Transporte al aeropuerto El Eden','Alquiler de bicicletas','Spa y masajes',
        'Cabalgata','Avistamiento de aves','Cena romantica','Tour al Valle del Cocora');
    servicios_precio SYS.ODCINUMBERLIST := SYS.ODCINUMBERLIST(
        25000, 85000, 70000, 45000, 150000, 90000, 75000, 160000, 110000);
    servicios_desc SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
        'Desayuno campesino con arepa, huevos, fruta y cafe de la region',
        'Recorrido por el cultivo y el beneficio del cafe, con catacion',
        'Traslado privado entre el alojamiento y el aeropuerto El Eden',
        'Bicicleta por dia para recorrer las veredas cercanas',
        'Sesion de masaje relajante y acceso a zona humeda',
        'Paseo a caballo de dos horas por caminos rurales',
        'Salida guiada al amanecer para observar aves endemicas',
        'Cena a la luz de las velas con menu de la cocina quindiana',
        'Excursion guiada al Valle del Cocora y sus palmas de cera');
    comentarios SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
        'Muy mala experiencia, la habitacion no correspondia a las fotos.',
        'No volveria, el servicio fue deficiente.',
        'Regular: buena ubicacion pero mantenimiento descuidado.',
        'Cumplio, aunque el ruido no dejaba descansar.',
        'Buena estadia, el personal fue amable.',
        'Lugar agradable y servicio cumplido.',
        'Muy buena experiencia, volveriamos con la familia.',
        'Excelente atencion y vista hermosa.',
        'Espectacular, de lo mejor del Quindio.',
        'Todo perfecto, supero nuestras expectativas.');

    -- Variables de trabajo
    v_id      NUMBER;
    v_ai      PLS_INTEGER;
    v_d       PLS_INTEGER;
    v_n       PLS_INTEGER;
    v_x       PLS_INTEGER;
    v_r       PLS_INTEGER;
    v_k       PLS_INTEGER;
    v_room    PLS_INTEGER;
    v_alta    BOOLEAN;
    v_tipo    VARCHAR2(20);
    v_rt      VARCHAR2(20);
    v_cap     PLS_INTEGER;
    v_base    PLS_INTEGER;
    v_estado  VARCHAR2(20);
    v_fres    PLS_INTEGER;
    v_cli     PLS_INTEGER;
    v_extra   PLS_INTEGER;
    v_delay   PLS_INTEGER;
    v_total   NUMBER;
    v_estadia NUMBER;
    v_linea   NUMBER;
    v_ant     NUMBER;
    v_pct     PLS_INTEGER;
    v_fc      PLS_INTEGER;
    v_cal     PLS_INTEGER;
    v_met     VARCHAR2(30);
    v_nl      PLS_INTEGER;
    v_s0      PLS_INTEGER;
    v_si      PLS_INTEGER;
    v_c       PLS_INTEGER;
    v_intentos PLS_INTEGER;
    v_nombre  VARCHAR2(200);
    v_tmp     PLS_INTEGER;

    -- Lineas de la reserva en curso
    l_room t_int;  l_in t_int;  n_lin PLS_INTEGER;

    -- Contadores para el resumen final
    cnt_rh PLS_INTEGER := 0;  cnt_rs PLS_INTEGER := 0;
    cnt_pago PLS_INTEGER := 0;  cnt_res PLS_INTEGER := 0;  cnt_tar PLS_INTEGER := 0;

    -- -------------------------------------------------------------------------
    -- Generador pseudoaleatorio (congruencial lineal, semilla fija).
    -- Devuelve un entero entre 0 y p_n - 1.
    -- -------------------------------------------------------------------------
    FUNCTION rnd (p_n PLS_INTEGER) RETURN PLS_INTEGER IS
    BEGIN
        g_seed := MOD(g_seed * 1103515245 + 12345, 2147483648);
        RETURN TRUNC(g_seed * p_n / 2147483648);
    END;

    -- Redondea a miles: p_valor * p_factor / p_divisor
    FUNCTION miles (p_valor NUMBER, p_factor NUMBER, p_divisor NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN TRUNC((p_valor * p_factor + p_divisor * 500) / (p_divisor * 1000)) * 1000;
    END;

    FUNCTION metodo RETURN VARCHAR2 IS
        v PLS_INTEGER := rnd(5);
    BEGIN
        RETURN CASE v WHEN 0 THEN 'tarjeta de credito' WHEN 1 THEN 'tarjeta debito'
                      WHEN 2 THEN 'PSE' WHEN 3 THEN 'transferencia' ELSE 'efectivo' END;
    END;

    FUNCTION tipo_mes (p_dia PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE WHEN EXTRACT(MONTH FROM c_d0 + p_dia) IN (4, 5, 6, 7, 12) THEN 'media' ELSE 'baja' END;
    END;

    FUNCTION libre (p_room PLS_INTEGER, p_in PLS_INTEGER, p_out PLS_INTEGER) RETURN BOOLEAN IS
    BEGIN
        FOR x IN p_in .. p_out - 1 LOOP
            IF occ.EXISTS(p_room * 2000 + x) THEN
                RETURN FALSE;
            END IF;
        END LOOP;
        RETURN TRUE;
    END;

    PROCEDURE add_alta (p_nombre VARCHAR2, p_ini DATE, p_fin DATE) IS
    BEGIN
        n_alta := n_alta + 1;
        alta_nom(n_alta) := p_nombre;
        alta_ini(n_alta) := p_ini - c_d0;
        alta_fin(n_alta) := p_fin - c_d0;
        FOR x IN alta_ini(n_alta) .. alta_fin(n_alta) LOOP
            IF day_alta.EXISTS(x) THEN
                RAISE_APPLICATION_ERROR(-20900, 'Temporadas altas solapadas: ' || p_nombre);
            END IF;
            day_alta(x) := n_alta;
        END LOOP;
    END;

    PROCEDURE add_temporada (p_nombre VARCHAR2, p_tipo VARCHAR2, p_ini PLS_INTEGER, p_fin PLS_INTEGER) IS
    BEGIN
        INSERT INTO Temporada (nombre, tipo, fecha_inicio, fecha_fin)
        VALUES (p_nombre, p_tipo, c_d0 + p_ini, c_d0 + p_fin)
        RETURNING id_temporada INTO v_id;
        n_temp := n_temp + 1;
        temp_id(n_temp)   := v_id;
        temp_tipo(n_temp) := p_tipo;
        temp_ini(n_temp)  := p_ini;
        FOR x IN p_ini .. p_fin LOOP
            day_season(x) := n_temp;
        END LOOP;
    END;

    PROCEDURE ins_pago (p_dia PLS_INTEGER, p_monto NUMBER, p_metodo VARCHAR2, p_estado VARCHAR2) IS
    BEGIN
        INSERT INTO Pago (id_reserva, fecha, monto, metodo, estado)
        VALUES (v_id, c_d0 + p_dia, p_monto, p_metodo, p_estado);
        cnt_pago := cnt_pago + 1;
    END;

BEGIN
    -- =========================================================================
    -- 1. Municipios (los 12 del Quindio) y tipos de alojamiento.
    --    mun_pat define cuantos alojamientos de cada tipo hay en el municipio
    --    (H hotel, F finca cafetera, G glamping, E hostal) y mun_w su
    --    atractivo turistico: Salento y Filandia reciben mucho mas que Genova.
    -- =========================================================================
    mun_nom(1)  := 'Armenia';     mun_pat(1)  := 'HHHHHEEFF';  mun_w(1)  := 9;
    mun_nom(2)  := 'Buenavista';  mun_pat(2)  := 'GF';         mun_w(2)  := 2;
    mun_nom(3)  := 'Calarca';     mun_pat(3)  := 'HHFFE';      mun_w(3)  := 5;
    mun_nom(4)  := 'Circasia';    mun_pat(4)  := 'FFGE';       mun_w(4)  := 4;
    mun_nom(5)  := 'Cordoba';     mun_pat(5)  := 'FG';         mun_w(5)  := 2;
    mun_nom(6)  := 'Filandia';    mun_pat(6)  := 'GGFFEEH';    mun_w(6)  := 8;
    mun_nom(7)  := 'Genova';      mun_pat(7)  := 'F';          mun_w(7)  := 1;
    mun_nom(8)  := 'La Tebaida';  mun_pat(8)  := 'HFFF';       mun_w(8)  := 4;
    mun_nom(9)  := 'Montenegro';  mun_pat(9)  := 'FFFFFHHG';   mun_w(9)  := 8;
    mun_nom(10) := 'Pijao';       mun_pat(10) := 'FE';         mun_w(10) := 2;
    mun_nom(11) := 'Quimbaya';    mun_pat(11) := 'FFFHHG';     mun_w(11) := 6;
    mun_nom(12) := 'Salento';     mun_pat(12) := 'EEEGGGFFHH'; mun_w(12) := 10;

    FOR i IN 1 .. 12 LOOP
        INSERT INTO Municipio (nombre) VALUES (mun_nom(i))
        RETURNING id_municipio INTO mun_id(i);
    END LOOP;

    INSERT INTO Tipo_Alojamiento (nombre) VALUES ('Hotel')          RETURNING id_tipo_alojamiento INTO tipo_id(1);
    INSERT INTO Tipo_Alojamiento (nombre) VALUES ('Finca cafetera') RETURNING id_tipo_alojamiento INTO tipo_id(2);
    INSERT INTO Tipo_Alojamiento (nombre) VALUES ('Glamping')       RETURNING id_tipo_alojamiento INTO tipo_id(3);
    INSERT INTO Tipo_Alojamiento (nombre) VALUES ('Hostal')         RETURNING id_tipo_alojamiento INTO tipo_id(4);

    -- =========================================================================
    -- 2. Temporadas 2024-2026.
    --    Primero se declaran las temporadas altas (diciembre-enero, Semana Santa,
    --    vacaciones de mitad de ano y puentes festivos de Colombia). Los huecos
    --    entre ellas se llenan con temporada media (abril-julio y diciembre) o
    --    baja (enero-marzo y agosto-noviembre). Se insertan en orden cronologico.
    -- =========================================================================
    add_alta('Temporada alta diciembre-enero 2023-2024',   DATE '2024-01-01', DATE '2024-01-08');
    add_alta('Semana Santa y puente de San Jose 2024',     DATE '2024-03-23', DATE '2024-03-31');
    add_alta('Puente de la Ascension 2024',                DATE '2024-05-11', DATE '2024-05-13');
    add_alta('Puente de Corpus Christi 2024',              DATE '2024-06-01', DATE '2024-06-03');
    add_alta('Puente del Sagrado Corazon 2024',            DATE '2024-06-08', DATE '2024-06-10');
    add_alta('Vacaciones de mitad de ano 2024',            DATE '2024-06-15', DATE '2024-07-31');
    add_alta('Puente de la Asuncion 2024',                 DATE '2024-08-17', DATE '2024-08-19');
    add_alta('Puente del Dia de la Raza 2024',             DATE '2024-10-12', DATE '2024-10-14');
    add_alta('Puente de Todos los Santos 2024',            DATE '2024-11-02', DATE '2024-11-04');
    add_alta('Puente Independencia de Cartagena 2024',     DATE '2024-11-09', DATE '2024-11-11');
    add_alta('Temporada alta diciembre-enero 2024-2025',   DATE '2024-12-15', DATE '2025-01-12');
    add_alta('Puente de San Jose 2025',                    DATE '2025-03-22', DATE '2025-03-24');
    add_alta('Semana Santa 2025',                          DATE '2025-04-12', DATE '2025-04-20');
    add_alta('Puente de la Ascension 2025',                DATE '2025-05-31', DATE '2025-06-02');
    add_alta('Vacaciones de mitad de ano 2025',            DATE '2025-06-14', DATE '2025-07-31');
    add_alta('Puente de la Asuncion 2025',                 DATE '2025-08-16', DATE '2025-08-18');
    add_alta('Puente del Dia de la Raza 2025',             DATE '2025-10-11', DATE '2025-10-13');
    add_alta('Puente de Todos los Santos 2025',            DATE '2025-11-01', DATE '2025-11-03');
    add_alta('Puente Independencia de Cartagena 2025',     DATE '2025-11-15', DATE '2025-11-17');
    add_alta('Puente de la Inmaculada Concepcion 2025',    DATE '2025-12-06', DATE '2025-12-08');
    add_alta('Temporada alta diciembre-enero 2025-2026',   DATE '2025-12-15', DATE '2026-01-12');
    add_alta('Puente de San Jose 2026',                    DATE '2026-03-21', DATE '2026-03-23');
    add_alta('Semana Santa 2026',                          DATE '2026-03-28', DATE '2026-04-05');
    add_alta('Puente de la Ascension 2026',                DATE '2026-05-16', DATE '2026-05-18');
    add_alta('Puente de Corpus Christi 2026',              DATE '2026-06-06', DATE '2026-06-08');
    add_alta('Vacaciones de mitad de ano 2026',            DATE '2026-06-13', DATE '2026-07-31');
    add_alta('Puente de la Asuncion 2026',                 DATE '2026-08-15', DATE '2026-08-17');
    add_alta('Puente del Dia de la Raza 2026',             DATE '2026-10-10', DATE '2026-10-12');
    add_alta('Puente de Todos los Santos 2026',            DATE '2026-10-31', DATE '2026-11-02');
    add_alta('Puente Independencia de Cartagena 2026',     DATE '2026-11-14', DATE '2026-11-16');
    add_alta('Temporada alta diciembre-enero 2026-2027',   DATE '2026-12-15', DATE '2027-01-11');

    v_d := 0;
    WHILE v_d <= c_last LOOP
        IF day_alta.EXISTS(v_d) THEN
            v_k := day_alta(v_d);
            add_temporada(alta_nom(v_k), 'alta', alta_ini(v_k), alta_fin(v_k));
            v_d := alta_fin(v_k) + 1;
        ELSE
            v_x    := v_d;
            v_tipo := tipo_mes(v_d);
            WHILE v_d + 1 <= c_last
                  AND NOT day_alta.EXISTS(v_d + 1)
                  AND tipo_mes(v_d + 1) = v_tipo LOOP
                v_d := v_d + 1;
            END LOOP;
            add_temporada('Temporada ' || v_tipo || ' ' || TO_CHAR(c_d0 + v_x, 'YYYY') ||
                          ' (' || TO_CHAR(c_d0 + v_x, 'DD/MM') || ' al ' || TO_CHAR(c_d0 + v_d, 'DD/MM') || ')',
                          v_tipo, v_x, v_d);
            v_d := v_d + 1;
        END IF;
    END LOOP;

    -- =========================================================================
    -- 3. Clientes: 3.000, de ciudades colombianas y algunas extranjeras.
    -- =========================================================================
    FOR i IN 1 .. 3000 LOOP
        v_x := rnd(20) + 1;                 -- nombre
        v_r := rnd(20) + 1;                 -- primer apellido
        v_k := rnd(20) + 1;                 -- segundo apellido
        v_n := rnd(100);                    -- ciudad (ponderada)
        v_c := 1;
        WHILE v_n >= ciudad_w(v_c) LOOP
            v_n := v_n - ciudad_w(v_c);
            v_c := v_c + 1;
        END LOOP;
        INSERT INTO Cliente (nombre, documento_identidad, correo, telefono, ciudad_origen)
        VALUES (nombres(v_x) || ' ' || apellidos(v_r) || ' ' || apellidos(v_k),
                CASE WHEN v_c >= 17 THEN 'PA' ELSE 'CC' END || TO_CHAR(1000000000 + i * 104729),
                LOWER(nombres(v_x) || '.' || apellidos(v_r)) || i || '@correo.com',
                '3' || LPAD(TO_CHAR(MOD(i * 7919 + 100000000, 1000000000)), 9, '0'),
                ciudades(v_c))
        RETURNING id_cliente INTO cli_id(i);
    END LOOP;

    -- =========================================================================
    -- 4. Alojamientos (60, repartidos de forma desigual) y habitaciones.
    --    Hoteles grandes de Armenia con 40 y 32 habitaciones, otros hoteles de
    --    12 a 28, fincas de 3 a 5, glampings de 4 a 8 y hostales de 6 a 12.
    --    Cada alojamiento tiene ademas:
    --      a_w     popularidad (cuantas reservas atrae)
    --      a_af    factor de precio propio (80 % a 130 %)
    --      a_altaf cuanto sube en temporada alta (105 % a 160 %)
    --      a_bajaf cuanto baja en temporada baja (78 % a 92 %)
    --      a_q     calidad real percibida (2 a 5), usada en las resenas
    -- =========================================================================
    FOR m IN 1 .. 12 LOOP
        FOR j IN 1 .. LENGTH(mun_pat(m)) LOOP
            n_aloj := n_aloj + 1;
            v_tipo := SUBSTR(mun_pat(m), j, 1);
            a_tipo(n_aloj) := v_tipo;

            IF v_tipo = 'H' THEN
                IF n_aloj = 1 THEN v_n := 40;
                ELSIF n_aloj = 2 THEN v_n := 32;
                ELSE v_n := 12 + rnd(17);
                END IF;
            ELSIF v_tipo = 'F' THEN v_n := 3 + rnd(3);
            ELSIF v_tipo = 'G' THEN v_n := 4 + rnd(5);
            ELSE                    v_n := 6 + rnd(7);
            END IF;
            a_n(n_aloj)     := v_n;
            a_first(n_aloj) := n_hab + 1;
            a_w(n_aloj)     := mun_w(m) * (30 + rnd(141));
            a_af(n_aloj)    := 80 + rnd(51);
            a_altaf(n_aloj) := 105 + rnd(56);
            a_bajaf(n_aloj) := 78 + rnd(15);
            a_q(n_aloj)     := 2 + rnd(4);
            tot_w := tot_w + a_w(n_aloj);

            -- Estrellas autoasignadas (glampings 4-5, hostales 2-4, el resto 3-5)
            IF    v_tipo = 'G' THEN v_x := 4 + rnd(2);
            ELSIF v_tipo = 'E' THEN v_x := 2 + rnd(3);
            ELSE                    v_x := 3 + rnd(3);
            END IF;

            v_nombre := CASE v_tipo WHEN 'H' THEN 'Hotel ' WHEN 'F' THEN 'Finca '
                                    WHEN 'G' THEN 'Glamping ' ELSE 'Hostal ' END || nombres_aloj(n_aloj);

            INSERT INTO Alojamiento (id_municipio, id_tipo_alojamiento, nombre_comercial,
                                     direccion, calificacion, contacto)
            VALUES (mun_id(m),
                    tipo_id(CASE v_tipo WHEN 'H' THEN 1 WHEN 'F' THEN 2 WHEN 'G' THEN 3 ELSE 4 END),
                    v_nombre,
                    CASE WHEN v_tipo IN ('H', 'E')
                         THEN 'Calle ' || (10 + MOD(n_aloj * 7, 40)) || ' # ' || (5 + MOD(n_aloj * 3, 30)) || '-' || (10 + MOD(n_aloj, 80)) || ', ' || mun_nom(m)
                         ELSE 'Vereda ' || nombres_aloj(61 - n_aloj) || ' km ' || (1 + MOD(n_aloj * 7, 15)) || ', ' || mun_nom(m) END,
                    v_x,
                    'reservas' || n_aloj || '@turismouq.co / 606 ' || (7300000 + n_aloj * 1371))
            RETURNING id_alojamiento INTO a_id(n_aloj);

            FOR h IN 1 .. v_n LOOP
                n_hab := n_hab + 1;
                v_r := rnd(100);
                IF v_tipo = 'H' THEN
                    v_rt := CASE WHEN v_r < 30 THEN 'sencilla' WHEN v_r < 75 THEN 'doble' ELSE 'suite' END;
                ELSIF v_tipo = 'F' THEN
                    v_rt := CASE WHEN v_r < 20 THEN 'sencilla' WHEN v_r < 70 THEN 'doble' ELSE 'cabagna' END;
                ELSIF v_tipo = 'G' THEN
                    v_rt := CASE WHEN v_r < 40 THEN 'doble' WHEN v_r < 75 THEN 'cabagna' ELSE 'suite' END;
                ELSE
                    v_rt := CASE WHEN v_r < 45 THEN 'sencilla' ELSE 'doble' END;
                END IF;

                IF    v_rt = 'sencilla' THEN v_cap := 1;
                ELSIF v_rt = 'doble'    THEN v_cap := 2 + rnd(2);
                ELSIF v_rt = 'suite'    THEN v_cap := 2 + rnd(3);
                ELSE                         v_cap := 4 + rnd(5);
                END IF;

                v_base := CASE v_tipo || v_rt
                    WHEN 'Hsencilla' THEN 140000 WHEN 'Hdoble'   THEN 190000 WHEN 'Hsuite'   THEN 320000
                    WHEN 'Fsencilla' THEN 120000 WHEN 'Fdoble'   THEN 180000 WHEN 'Fcabagna' THEN 260000
                    WHEN 'Gdoble'    THEN 230000 WHEN 'Gsuite'   THEN 300000 WHEN 'Gcabagna' THEN 280000
                    WHEN 'Esencilla' THEN  60000 ELSE 85000 END;
                r_base(n_hab) := v_base;
                r_aloj(n_hab) := n_aloj;

                INSERT INTO Habitacion (id_alojamiento, numero, capacidad, tipo, descripcion)
                VALUES (a_id(n_aloj),
                        CASE WHEN v_tipo = 'H' THEN 100 * (TRUNC((h - 1) / 10) + 1) + MOD(h - 1, 10) + 1 ELSE h END,
                        v_cap,
                        v_rt,
                        CASE v_rt
                            WHEN 'sencilla' THEN 'Habitacion sencilla con cama individual y bano privado'
                            WHEN 'doble'    THEN 'Habitacion doble con cama queen y vista a las montanas'
                            WHEN 'suite'    THEN 'Suite con sala, jacuzzi y balcon'
                            ELSE 'Cabana independiente con cocina, chimenea y zona verde' END)
                RETURNING id_habitacion INTO r_id(n_hab);
            END LOOP;
        END LOOP;
    END LOOP;

    -- =========================================================================
    -- 5. Tarifas: una por habitacion x temporada.
    --    valor = precio base del tipo de habitacion x factor del alojamiento
    --            x factor de la temporada (propio de cada alojamiento en alta y
    --            baja) x ajuste anual (2024 = 100 %, 2025 = 106 %, 2026 = 112 %).
    -- =========================================================================
    FOR h IN 1 .. n_hab LOOP
        v_ai := r_aloj(h);
        FOR t IN 1 .. n_temp LOOP
            v_x := CASE temp_tipo(t) WHEN 'alta' THEN a_altaf(v_ai)
                                     WHEN 'media' THEN 100
                                     ELSE a_bajaf(v_ai) END;
            v_r := CASE EXTRACT(YEAR FROM c_d0 + temp_ini(t))
                       WHEN 2024 THEN 100 WHEN 2025 THEN 106 ELSE 112 END;
            tar(h * 100 + t) := miles(r_base(h), a_af(v_ai) * v_x * v_r, 1000000);
            INSERT INTO Tarifa (id_habitacion, id_temporada, valor_noche)
            VALUES (r_id(h), temp_id(t), tar(h * 100 + t));
            cnt_tar := cnt_tar + 1;
        END LOOP;
    END LOOP;

    -- =========================================================================
    -- 6. Servicios: cada alojamiento ofrece de 1 a 3 servicios (los hoteles uno
    --    mas), tomados del catalogo y con precio propio.
    -- =========================================================================
    FOR i IN 1 .. n_aloj LOOP
        v_n := 1 + rnd(3) + CASE WHEN a_tipo(i) = 'H' THEN 1 ELSE 0 END;
        v_x := rnd(9);
        a_sfirst(i) := n_serv + 1;
        a_nserv(i)  := v_n;
        FOR j IN 0 .. v_n - 1 LOOP
            v_k := MOD(v_x + j, 9) + 1;
            n_serv := n_serv + 1;
            v_r := 85 + rnd(41);
            s_precio(n_serv) := miles(servicios_precio(v_k), v_r, 100);
            INSERT INTO Servicio (id_alojamiento, nombre, descripcion, precio)
            VALUES (a_id(i), servicios_cat(v_k), servicios_desc(v_k), s_precio(n_serv))
            RETURNING id_servicio INTO s_id(n_serv);
        END LOOP;
    END LOOP;

    -- =========================================================================
    -- 7. Usuarios del sistema: 2 administradores de la plataforma (sin
    --    alojamiento) y 8 encargados; al menos un encargado por tipo.
    -- =========================================================================
    INSERT INTO Usuario_Sistema (id_alojamiento, nombre, correo, rol)
    VALUES (NULL, 'Administrador General', 'admin@turismouq.co', 'administrador');
    INSERT INTO Usuario_Sistema (id_alojamiento, nombre, correo, rol)
    VALUES (NULL, 'Administrador Soporte', 'soporte@turismouq.co', 'administrador');

    v_k := 0;
    FOR t IN 1 .. 4 LOOP          -- primer alojamiento de cada tipo
        FOR i IN 1 .. n_aloj LOOP
            IF a_tipo(i) = SUBSTR('HFGE', t, 1) THEN
                v_k := v_k + 1;
                INSERT INTO Usuario_Sistema (id_alojamiento, nombre, correo, rol)
                VALUES (a_id(i), 'Encargado ' || v_k, 'encargado' || v_k || '@turismouq.co', 'encargado');
                EXIT;
            END IF;
        END LOOP;
    END LOOP;
    FOR i IN 1 .. 4 LOOP          -- cuatro encargados mas en alojamientos grandes
        v_k := v_k + 1;
        INSERT INTO Usuario_Sistema (id_alojamiento, nombre, correo, rol)
        VALUES (a_id(i * 10), 'Encargado ' || v_k, 'encargado' || v_k || '@turismouq.co', 'encargado');
    END LOOP;

    -- =========================================================================
    -- 8. Reservas, lineas de habitacion, servicios, pagos y resenas.
    --    * La fecha de check-in se sortea con mas peso en temporada alta
    --      (alta 100, media 55, baja 30) y con crecimiento anual (80/90/100).
    --    * El alojamiento se sortea segun su popularidad y se busca una
    --      habitacion libre en todo el rango; si no hay, se vuelve a sortear.
    --    * Estado segun la fecha de corte (23/10/2026): lo ya terminado queda
    --      completado (12 % cancelado); lo futuro queda confirmado, pendiente
    --      o cancelado.
    -- =========================================================================
    FOR k IN 1 .. 25000 LOOP
        v_intentos := 0;
        LOOP
            v_intentos := v_intentos + 1;
            IF v_intentos > 200 THEN
                RAISE_APPLICATION_ERROR(-20901, 'No se encontro habitacion libre para la reserva ' || k);
            END IF;

            LOOP   -- sorteo de la fecha de check-in con peso por temporada y ano
                v_d := rnd(c_end_res);
                v_x := CASE temp_tipo(day_season(v_d)) WHEN 'alta' THEN 100 WHEN 'media' THEN 55 ELSE 30 END
                     * CASE EXTRACT(YEAR FROM c_d0 + v_d) WHEN 2024 THEN 80 WHEN 2025 THEN 90 ELSE 100 END;
                EXIT WHEN rnd(10000) < v_x;
            END LOOP;

            v_alta := temp_tipo(day_season(v_d)) = 'alta';
            IF v_alta THEN v_n := 2 + rnd(5); ELSE v_n := 1 + rnd(4); END IF;

            IF v_d + v_n <= c_end_res THEN
                v_x  := rnd(tot_w);           -- alojamiento segun popularidad
                v_ai := 1;
                WHILE v_x >= a_w(v_ai) LOOP
                    v_x  := v_x - a_w(v_ai);
                    v_ai := v_ai + 1;
                END LOOP;

                v_room := NULL;
                v_x := rnd(a_n(v_ai));
                FOR j IN 0 .. a_n(v_ai) - 1 LOOP
                    v_r := a_first(v_ai) + MOD(v_x + j, a_n(v_ai));
                    IF libre(v_r, v_d, v_d + v_n) THEN
                        v_room := v_r;
                        EXIT;
                    END IF;
                END LOOP;
                EXIT WHEN v_room IS NOT NULL;
            END IF;
        END LOOP;

        -- Estado de la reserva
        IF v_d + v_n <= c_corte THEN
            v_estado := CASE WHEN rnd(100) < 12 THEN 'cancelada' ELSE 'completada' END;
        ELSIF v_d > c_corte THEN
            v_r := rnd(100);
            v_estado := CASE WHEN v_r < 10 THEN 'cancelada' WHEN v_r < 35 THEN 'pendiente' ELSE 'confirmada' END;
        ELSE
            v_estado := 'confirmada';       -- huesped alojado en la fecha de corte
        END IF;

        -- Anticipacion de la reserva: mas larga en temporada alta
        IF v_alta THEN v_fres := v_d - (15 + rnd(76)); ELSE v_fres := v_d - (1 + rnd(60)); END IF;

        -- Cliente: el 35 % de las reservas es de 300 clientes frecuentes
        IF rnd(100) < 35 THEN v_cli := rnd(300) + 1; ELSE v_cli := rnd(3000) + 1; END IF;

        INSERT INTO Reserva (id_cliente, fecha_reserva, estado)
        VALUES (cli_id(v_cli), c_d0 + v_fres, v_estado)
        RETURNING id_reserva INTO v_id;
        cnt_res := cnt_res + 1;

        -- Lineas de habitacion: la principal y, en el 12 % de los casos, 1 o 2
        -- habitaciones mas del mismo alojamiento (a veces llegan un dia despues).
        n_lin := 1;  l_room(1) := v_room;  l_in(1) := v_d;
        IF rnd(100) < 12 AND a_n(v_ai) > 1 THEN
            v_extra := 1 + rnd(2);
            IF v_n >= 2 AND rnd(100) < 30 THEN v_delay := 1; ELSE v_delay := 0; END IF;
            FOR j IN 1 .. a_n(v_ai) - 1 LOOP
                EXIT WHEN v_extra = 0;
                v_r := a_first(v_ai) + MOD(v_room - a_first(v_ai) + j, a_n(v_ai));
                IF libre(v_r, v_d + v_delay, v_d + v_n) THEN
                    n_lin := n_lin + 1;
                    l_room(n_lin) := v_r;
                    l_in(n_lin)   := v_d + v_delay;
                    v_extra := v_extra - 1;
                END IF;
            END LOOP;
        END IF;

        v_estadia := 0;
        FOR l IN 1 .. n_lin LOOP
            v_linea := 0;
            FOR x IN l_in(l) .. v_d + v_n - 1 LOOP          -- noche por noche
                v_linea := v_linea + tar(l_room(l) * 100 + day_season(x));
                IF v_estado <> 'cancelada' THEN
                    occ(l_room(l) * 2000 + x) := TRUE;
                END IF;
            END LOOP;
            v_estadia := v_estadia + v_linea;
            INSERT INTO Reserva_Habitacion (id_reserva, id_habitacion, checkin, checkout, precio_noche_calculado)
            VALUES (v_id, r_id(l_room(l)), c_d0 + l_in(l), c_d0 + v_d + v_n,
                    ROUND(v_linea / (v_d + v_n - l_in(l)), 2));
            cnt_rh := cnt_rh + 1;
        END LOOP;

        -- Servicios del mismo alojamiento (1 a 4 lineas distintas)
        v_total := v_estadia;
        v_nl := LEAST(a_nserv(v_ai), 1 + rnd(4));
        v_s0 := rnd(a_nserv(v_ai));
        FOR j IN 0 .. v_nl - 1 LOOP
            v_si := a_sfirst(v_ai) + MOD(v_s0 + j, a_nserv(v_ai));
            v_c  := 1 + rnd(4);
            INSERT INTO Reserva_Servicio (id_reserva, id_servicio, cantidad, precio_cobrado)
            VALUES (v_id, s_id(v_si), v_c, s_precio(v_si));
            v_total := v_total + v_c * s_precio(v_si);
            cnt_rs := cnt_rs + 1;
        END LOOP;

        -- Pagos segun el estado
        IF v_estado = 'completada' THEN
            IF rnd(100) < 6 THEN                           -- intento rechazado
                v_met := metodo;
                ins_pago(v_fres, v_total, v_met, 'fallido');
            END IF;
            IF rnd(100) < 55 THEN                          -- pago unico
                v_met := metodo;
                ins_pago(v_fres, v_total, v_met, 'exitoso');
            ELSE                                           -- anticipo + saldo al llegar
                v_pct := 30 + 20 * rnd(2);
                v_ant := miles(v_total, v_pct, 100);
                v_met := metodo;
                ins_pago(v_fres, v_ant, v_met, 'exitoso');
                v_met := metodo;
                ins_pago(v_d, v_total - v_ant, v_met, 'exitoso');
            END IF;
        ELSIF v_estado = 'confirmada' THEN
            IF rnd(100) < 50 THEN                          -- anticipo pagado, saldo por cobrar
                v_pct := 30 + 20 * rnd(2);
                v_ant := miles(v_total, v_pct, 100);
                v_met := metodo;
                ins_pago(v_fres, v_ant, v_met, 'exitoso');
                v_met := metodo;
                ins_pago(v_d, v_total - v_ant, v_met, 'pendiente');
            ELSE
                v_met := metodo;
                ins_pago(v_fres, v_total, v_met, 'exitoso');
            END IF;
        ELSIF v_estado = 'pendiente' THEN                  -- anticipo aun sin confirmar
            v_pct := 30 + 20 * rnd(2);
            v_ant := miles(v_total, v_pct, 100);
            v_met := metodo;
            ins_pago(v_fres, v_ant, v_met, 'pendiente');
        ELSE                                               -- cancelada
            v_pct := 30 + 20 * rnd(2);
            v_ant := miles(v_total, v_pct, 100);
            v_met := metodo;
            ins_pago(v_fres, v_ant, v_met, 'exitoso');
            v_fc := v_fres + rnd(v_d - v_fres + 1);        -- dia de la cancelacion
            IF v_d - v_fc > 5 THEN                         -- mas de 5 dias: reembolso del 80 %
                ins_pago(v_fc, miles(v_ant, 80, 100), v_met, 'reembolsado');
            END IF;
        END IF;

        -- Resena: solo reservas completadas, aprox. la mitad de ellas
        IF v_estado = 'completada' AND rnd(100) < 52 THEN
            v_tmp := rnd(3);
            v_cal := LEAST(5, GREATEST(1, a_q(v_ai) + v_tmp - 1));
            v_tmp := rnd(100);
            INSERT INTO Resena (id_reserva, calificacion, comentario)
            VALUES (v_id, v_cal,
                    CASE WHEN v_tmp < 30 THEN NULL ELSE comentarios(2 * v_cal - MOD(k, 2)) END);
        END IF;
    END LOOP;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Datos generados correctamente.');
    DBMS_OUTPUT.PUT_LINE('Temporadas: ' || n_temp || ' | Alojamientos: ' || n_aloj ||
                         ' | Habitaciones: ' || n_hab || ' | Tarifas: ' || cnt_tar);
    DBMS_OUTPUT.PUT_LINE('Servicios: ' || n_serv || ' | Reservas: ' || cnt_res ||
                         ' | Reserva_Habitacion: ' || cnt_rh || ' | Reserva_Servicio: ' || cnt_rs ||
                         ' | Pagos: ' || cnt_pago);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/
