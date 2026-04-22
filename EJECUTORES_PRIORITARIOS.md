# EJECUTORES_PRIORITARIOS - urbanizacion-toolkit

> Pocas automatizaciones, pero con alcance claro y reutilizable.

## 1. excel_word_bridge

- Objetivo: sustituir imagenes de tablas por tablas reales en Word y sincronizar tablas desde Excel.
- Entradas minimas: Excel fuente, DOCX destino y reglas de estilo.
- Debe leer: solo el Excel fuente, el DOCX destino y la plantilla si aplica.
- No debe leer: BC3, resto de anejos, normativa salvo necesidad puntual.
- Salida esperada: DOCX con tablas reales, formato profesional y verificacion de coincidencia.
- Maduracion recomendada: apoyarse en `check_docx_tables_consistency.ps1` y un comparador simple de valores.

## 2. bc3_auditor

- Objetivo: detectar partidas sin medicion, descompuestos ausentes, rendimientos incoherentes y conflictos entre descripcion, unidad y descompuesto.
- Entradas minimas: BC3 vigente y, si existe, changelog o fuentes de medicion.
- Debe leer: BC3 activo y solo las fuentes necesarias para contrastes.
- No debe leer: toda la memoria ni todos los anejos por defecto.
- Salida esperada: informe de incidencias con severidad y, cuando proceda, propuesta de correccion.
- Maduracion recomendada: apoyarse en `check_bc3_integrity.ps1` y revisiones focalizadas de `~C`, `~D`, `~T`, `~M`.

## 3. delivery_closeout

- Objetivo: comprobar coherencia documental minima antes de una entrega.
- Entradas minimas: lista de entregables, `FUENTES_MAESTRAS.md` y `ESTADO_PROYECTO.md`.
- Debe leer: capa corta de contexto y solo los documentos con pendientes o cruces criticos.
- No debe leer: todo el arbol documental salvo cierre integral solicitado.
- Salida esperada: bloqueadores, pendientes y estado de lista para entrega.
- Maduracion recomendada: apoyarse en `run_project_closeout.ps1` y perfiles de trazabilidad.