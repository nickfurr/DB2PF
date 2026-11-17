# TurismoUQ · Proyecto integrador de Bases de Datos II

Base de datos de una plataforma de reservas turísticas del Quindío: alojamientos de los 12 municipios, temporadas y tarifas, reservas de una o varias habitaciones, pagos, servicios complementarios y reseñas.

**Universidad del Quindío** · Bases de Datos II (12338) · Grupo **01D** · 2026-2 · Docente: Carolina Londoño Idárraga  
**Equipo `DeleteSinWhere`:** Manuel Pineda Varela · Carlos Alonso Barahona Álvarez · Santiago Solarte Trujillo  
**Motor:** Oracle Database 26ai Free  
**Video de sustentación:** https://www.youtube.com/watch?v=QzkeoMvO52I  
**Documento final:** `Proyecto_Integrador_BDII_TurismoUQ.pdf`

## Contenido

```text
DB2PF/
├── README.md                                  Guía de estructura y ejecución del repositorio
├── diagrama.png                               Diagrama entidad-relación
├── Proyecto_Integrador_BDII_TurismoUQ.pdf     Documento final consolidado (referencia en PDF)
├── entregaFinal/                              Entrega consolidada en orden secuencial de ejecución
│   ├── 00_reinicio_bd.sql                     Limpieza segura de objetos del esquema (opcional)
│   ├── 01_tablespace_system.sql               Tablespace TS_RESERVAS_HIST y cuota (ejecutar como SYSTEM)
│   ├── 02_DDL.sql                             15 tablas, restricciones y comentarios
│   ├── 03_carga_datos.sql                     Carga determinística y asimétrica (25.000 reservas)
│   ├── 04_verificacion_datos.sql              Conteos y 14 controles de consistencia en 0
│   ├── 05_consultas_analisis.sql              Las 7 consultas analíticas de gerencia
│   ├── 06_paquete.sql                         Paquete pkg_turismo (1 o N habitaciones y FOR UPDATE)
│   ├── 07_disparadores.sql                    Auditoría de TARIFA y disparadores compuestos de solape
│   ├── 08_historico_vista_materializada.sql   Particionamiento histórico y mv_ocupacion_mensual
│   ├── 09_transacciones.sql                   sp_registrar_pago y sp_reservar_y_pagar (SAVEPOINT)
│   ├── 10_indices.sql                         3 índices (FK, compuesto, funcional) + caso sin índice
│   ├── 11a_seguridad_system.sql               Perfil, 4 roles y 4 usuarios (ejecutar como SYSTEM)
│   ├── 11b_seguridad_esquema.sql              Vistas de recepción y GRANT diferenciados a los 4 roles
│   ├── 12_pruebas_completas.sql               Batería integral de pruebas (Entregas 2 y 3)
│   ├── verificacion_datos.txt                 Evidencia de conteos y controles en base limpia
│   └── evidencia_pruebas_final.txt            Salida consolidada de 12_pruebas_completas.sql
├── entrega1/                                  Entrega 1 · Modelo y consultas de análisis
│   ├── Entrega1.md
│   ├── ScriptDDL.sql
│   ├── ScriptDatos.sql
│   ├── ScriptVerificacion.sql
│   ├── verificacion_datos.txt
│   └── ScriptConsultas.sql
├── entrega2/                                  Entrega 2 · Capa PL/SQL
│   ├── 01_paquete.sql
│   ├── 02_disparadores.sql
│   ├── 03a_tablespace_system.sql
│   ├── 03b_historico_vista_materializada.sql
│   ├── 04_pruebas.sql
│   └── evidencia_pruebas_entrega2.txt
└── entrega3/                                  Entrega 3 · Transacciones, concurrencia, índices y seguridad
    ├── 01a_pago.sql
    ├── 01b_reserva.sql
    ├── 01c_pruebas_transacciones.sql
    ├── 03_indices.sql
    ├── 04a_seguridad_system.sql
    ├── 04b_seguridad_esquema.sql
    ├── imagenes_indices/                      Capturas de los planes de ejecución de 03_indices.sql
    └── experimentoConcurrencia/               Experimento en 2 sesiones (02_concurrencia.sql + PDF)
```

## Orden completo de ejecución (`entregaFinal/`)

> **Importante sobre privilegios (`SYSTEM` vs. usuario del proyecto):**  
> Todos los scripts se ejecutan con el **usuario dueño del esquema del proyecto** (el esquema donde se crean las tablas), **excepto `entregaFinal/01_tablespace_system.sql` y `entregaFinal/11a_seguridad_system.sql`**, que **deben ejecutarse conectados como `SYSTEM`** en el mismo contenedor/PDB donde vive el usuario del proyecto (`FREEPDB1` / `XEPDB1` / `CDB$ROOT`), ya que crear tablespaces, roles, perfiles y usuarios son operaciones administrativas.

En Oracle SQL Developer, cada script se ejecuta como script (`F5`) en este orden exacto:

| Paso | Script (`entregaFinal/`) | Usuario | Qué hace |
| :---: | :--- | :---: | :--- |
| 0 | `00_reinicio_bd.sql` | proyecto | *(Opcional)* Limpia objetos previos de forma segura. En base limpia ignora lo que no existe. |
| 1 | `01_tablespace_system.sql` | **`SYSTEM`** | Crea `TS_RESERVAS_HIST` junto al datafile de `USERS` y da cuota ilimitada al esquema. |
| 2 | `02_DDL.sql` | proyecto | Crea las 15 tablas (incluida `AUDITORIA_TARIFA`), restricciones `CHECK`/`UNIQUE` y comentarios. |
| 3 | `03_carga_datos.sql` | proyecto | Carga determinística y asimétrica (~7 s). **Debe ejecutarse antes de crear los disparadores.** |
| 4 | `04_verificacion_datos.sql` | proyecto | Verifica volúmenes y 14 controles de consistencia (todos deben dar `0`); genera `verificacion_datos.txt`. |
| 5 | `05_consultas_analisis.sql` | proyecto | Ejecuta las 7 consultas gerenciales de análisis (`PIVOT`, `ROLLUP`, `RANK`, `LAG`, bind, `UNPIVOT`, libre). |
| 6 | `06_paquete.sql` | proyecto | Compila `pkg_turismo` (sobrecargas de 1 o varias habitaciones en `sp_crear_reserva` y `FOR UPDATE`). |
| 7 | `07_disparadores.sql` | proyecto | Crea disparadores compuestos de solape (`trg_reserva_no_solape`), reactivación, temporadas y auditoría de tarifas. |
| 8 | `08_historico_vista_materializada.sql` | proyecto | Particiona `Reserva` y `Reserva_Habitacion` llevando 2024–2025 a `TS_RESERVAS_HIST` y crea `mv_ocupacion_mensual`. |
| 9 | `09_transacciones.sql` | proyecto | Compila `sp_registrar_pago` y `sp_reservar_y_pagar` (transacción atómica con `SAVEPOINT`). |
| 10 | `10_indices.sql` | proyecto | Crea `idx_rh_habitacion`, `idx_rh_hab_checkin`, `fx_cliente_correo_upper` y evalúa `idx_reserva_estado` con `EXPLAIN PLAN`. |
| 11a | `11a_seguridad_system.sql` | **`SYSTEM`** | Crea `perfil_recepcion`, los 4 roles y los 4 usuarios de prueba (habilita `_ORACLE_SCRIPT` si corre en `CDB$ROOT`). |
| 11b | `11b_seguridad_esquema.sql` | proyecto | Crea `v_recepcion_reservas` y `v_recepcion_habitaciones`, y otorga `GRANT` diferenciados a los 4 roles. |
| 12 | `12_pruebas_completas.sql` | proyecto | Ejecuta toda la batería de pruebas de Entregas 2 y 3 y guarda `evidencia_pruebas_final.txt`. |

*Nota:* Si el usuario dueño del esquema en su instancia se llama distinto a `PROJEC` (por ejemplo `LIMPIA`), cambie `DEFINE esquema = PROJEC` al inicio de `entregaFinal/01_tablespace_system.sql` antes de ejecutarlo como `SYSTEM`. El experimento de concurrencia en 2 sesiones está documentado en `entrega3/experimentoConcurrencia/`.

## Datos cargados

| Tabla | Filas | Tabla | Filas |
|---|---:|---|---:|
| Municipio | 12 | Reserva | 25.000 |
| Tipo_Alojamiento | 4 | Reserva_Habitacion | 28.937 |
| Alojamiento | 60 | Reserva_Servicio | 42.534 |
| Habitacion | 585 | Pago | 38.447 |
| Temporada | 65 | Servicio | 127 |
| Tarifa | 38.025 | Resena | 10.634 |
| Cliente | 3.000 | Usuario_Sistema | 10 |

Los datos salen de un generador con semilla fija: cada carga produce exactamente los mismos datos. Las temporadas siguen el calendario real de 2024 a 2026 (Semana Santa, mitad de año, puentes festivos y diciembre-enero en temporada alta), los precios salen de `TARIFA` noche por noche y ninguna habitación queda reservada dos veces en las mismas fechas.

## Entrega 2 en resumen

| Requisito | Objeto |
|---|---|
| `fn_valor_estadia` | `pkg_turismo.fn_valor_estadia`: recorre la estadía noche por noche y aplica la tarifa de la temporada de cada noche |
| `sp_crear_reserva` | `pkg_turismo.sp_crear_reserva`: sobrecargado para **una o varias habitaciones** del mismo alojamiento en una sola reserva; usa `FOR UPDATE` sobre `Habitacion` y valida fechas, capacidad, cliente y disponibilidad (`-20010` a `-20019`) |
| Cursor con parámetros | `pkg_turismo.sp_liquidacion_mensual`: liquidación mensual por alojamiento |
| Paquete | `pkg_turismo` |
| Disparador de sentencia | `trg_auditoria_tarifa` (compuesto: registra en `AFTER STATEMENT`) |
| Disparador de fila | `trg_reserva_no_solape` (compuesto: captura filas afectadas y valida al cerrar la sentencia sin `ORA-04091`) |
| Tablespace | `TS_RESERVAS_HIST`, con las particiones 2024 y 2025 de `Reserva` y `Reserva_Habitacion` |
| Vista materializada | `mv_ocupacion_mensual`, refresco completo diario a las 2:00 a.m. |

## Entrega 3 en resumen

| Requisito | Objeto / Archivo |
|---|---|
| Transacción atómica + `SAVEPOINT` | `sp_registrar_pago`, `sp_reservar_y_pagar` (`entregaFinal/09_transacciones.sql`) y pruebas en `12_pruebas_completas.sql` |
| Concurrencia (2 sesiones + `FOR UPDATE`) | `entrega3/experimentoConcurrencia/02_concurrencia.sql` y `DOCUMENTO_CONCURRENCIA.pdf` |
| Índices (3 consultas + caso donde no ayuda) | `entregaFinal/10_indices.sql`: `idx_rh_habitacion` (FK), `idx_rh_hab_checkin` (compuesto), `fx_cliente_correo_upper` (funcional sobre `UPPER(correo)`) e `idx_reserva_estado` (baja selectividad) |
| Seguridad (4 roles, vistas y perfil) | `11a_seguridad_system.sql` y `11b_seguridad_esquema.sql`: `perfil_recepcion`, `rol_recepcion` (solo vistas + procedimientos), `rol_admin_aloj`, `rol_gerente` y `rol_auditor` |
