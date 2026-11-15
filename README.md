# TurismoUQ · Proyecto integrador de Bases de Datos II

Base de datos de una plataforma de reservas turísticas del Quindío: alojamientos de los 12 municipios, temporadas y tarifas, reservas de una o varias habitaciones, pagos, servicios complementarios y reseñas.

**Universidad del Quindío** · Bases de Datos II (12338) · 2026-2 · Docente: Carolina Londoño Idárraga  
**Equipo:** Manuel Pineda Varela · Carlos Alonso Barahona · Santiago Solarte  
**Motor:** Oracle Database 26ai Free

## Contenido

```
DB2PF/
├── Reinicio_BD.sql                          Borra todos los objetos para empezar de cero
├── Entrega1_TurismoUQ.docx                  Documento de la Entrega 1 (MER, reglas, decisiones)
├── entrega1/                                Entrega 1 · Modelo y consultas de análisis
│   ├── ScriptDDL.sql                        Tablas, restricciones y comentarios
│   ├── ScriptDatos.sql                      Carga de datos (volumen mínimo, asimétrica)
│   ├── ScriptVerificacion.sql               Controles de calidad de la carga
│   ├── verificacion_datos.txt               Resultado de la verificación (evidencia)
│   ├── ScriptConsultas.sql                  Las 7 consultas de análisis
│   ├── Entrega1.md                          Documento de la Entrega 1 en Markdown
│   └── diagrama.png                         Diagrama entidad-relación
└── entrega2/                                Entrega 2 · Capa PL/SQL
    ├── 01_paquete.sql                       pkg_turismo: fn_valor_estadia, sp_crear_reserva (1 o N habs),
    │                                        sp_liquidacion_mensual (cursor), sp_desglose_estadia
    ├── 02_disparadores.sql                  Auditoría de TARIFA (sentencia), solape de reservas (fila),
    │                                        reactivación de canceladas, solape de temporadas
    ├── 03a_tablespace_system.sql            Tablespace del histórico (se ejecuta como SYSTEM)
    ├── 03b_historico_vista_materializada.sql Particiones del histórico y vista de ocupación mensual
    ├── 04_pruebas.sql                       Pruebas de cada objeto; genera la evidencia
    └── evidencia_pruebas_entrega2.txt       Salida de las pruebas (la crea 04_pruebas.sql)
```

## Orden completo de ejecución

> **Importante sobre privilegios (`SYSTEM` vs. usuario del proyecto):**  
> Todos los scripts se ejecutan con el usuario dueño del esquema del proyecto (`PROJEC`), **excepto `entrega2/03a_tablespace_system.sql`**, que **debe ejecutarse conectado como `SYSTEM`** en la misma PDB (`FREEPDB1` / `XEPDB1`) porque crear un `TABLESPACE` y otorgar `QUOTA` sobre él es una operación administrativa del motor.

En SQL Developer, cada script se ejecuta como script (`F5`).

| Paso | Script | Usuario | Qué hace |
| :---: | :--- | :---: | :--- |
| 1 | `Reinicio_BD.sql` | `PROJEC` | Borra objetos anteriores. En una base limpia sus errores de "no existe" son normales. |
| 2 | `entrega1/ScriptDDL.sql` | `PROJEC` | Crea las 15 tablas con sus restricciones y comentarios. |
| 3 | `entrega1/ScriptDatos.sql` | `PROJEC` | Carga los datos (1 a 3 minutos). **Debe ejecutarse antes de crear los disparadores.** |
| 4 | `entrega1/ScriptVerificacion.sql` | `PROJEC` | Verifica la carga y genera `verificacion_datos.txt`. Todos los controles deben dar `0`. |
| — | `entrega1/ScriptConsultas.sql` | `PROJEC` | Las 7 consultas de análisis de la Entrega 1 (se pueden correr en cualquier momento después del paso 3). |
| 5 | `entrega2/03a_tablespace_system.sql` | **`SYSTEM`** | Crea el tablespace `TS_RESERVAS_HIST` y otorga cuota ilimitada al esquema del proyecto (`PROJEC`). |
| 6 | `entrega2/01_paquete.sql` | `PROJEC` | Compila el paquete `pkg_turismo` (con soporte de una o varias habitaciones en `sp_crear_reserva`). |
| 7 | `entrega2/02_disparadores.sql` | `PROJEC` | Crea los disparadores de auditoría, solape de reservas, reactivación y solape de temporadas. |
| 8 | `entrega2/03b_historico_vista_materializada.sql` | `PROJEC` | Particiona `Reserva` y `Reserva_Habitacion` llevando 2024 y 2025 a `TS_RESERVAS_HIST` y crea `mv_ocupacion_mensual`. |
| 9 | `entrega2/04_pruebas.sql` | `PROJEC` | Ejecuta la batería de pruebas completa y guarda la salida en `evidencia_pruebas_entrega2.txt`. |

*Nota:* El paso 5 (`03a_tablespace_system.sql` como `SYSTEM`) puede ejecutarse en cualquier momento antes del paso 8. Si el esquema del proyecto tiene un nombre distinto a `PROJEC`, basta con cambiar la línea `DEFINE esquema = PROJEC` al inicio de `03a_tablespace_system.sql`.

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
| `sp_crear_reserva` | `pkg_turismo.sp_crear_reserva`: sobrecargado para **una o varias habitaciones** del mismo alojamiento en una sola reserva; valida fechas, capacidad, cliente y disponibilidad con errores propios (`-20010` a `-20019`) |
| Cursor con parámetros | `pkg_turismo.sp_liquidacion_mensual`: liquidación mensual por alojamiento |
| Paquete | `pkg_turismo` |
| Disparador de sentencia | `trg_auditoria_tarifa` (compuesto: registra en `AFTER STATEMENT`) |
| Disparador de fila | `trg_reserva_no_solape` (compuesto: toma cada fila y valida al cerrar la sentencia) |
| Tablespace | `TS_RESERVAS_HIST`, con las particiones 2024 y 2025 de `Reserva` y `Reserva_Habitacion` |
| Vista materializada | `mv_ocupacion_mensual`, refresco completo diario a las 2:00 a.m. |
