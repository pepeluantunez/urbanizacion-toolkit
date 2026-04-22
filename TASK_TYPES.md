# TASK_TYPES - urbanizacion-toolkit

> Taxonomia practica para clasificar la tarea antes de empezar.

## 1. Maquetacion DOCX

- Objetivo: mejorar formato, estructura visual y tablas de un Word.
- Entradas minimas: DOCX objetivo y, si aplica, plantilla de referencia.
- Leer normalmente: el DOCX afectado y su plantilla directa.
- No leer normalmente: BC3, otros anejos, normativa y planos.
- Profundidad recomendada: focalizado.
- Salida esperada: DOCX maquetado y verificado.

## 2. Excel a Word

- Objetivo: pasar datos o tablas de Excel a Word con tablas reales, no imagenes.
- Entradas minimas: Excel fuente y DOCX destino.
- Leer normalmente: solo el Excel y el DOCX implicados.
- No leer normalmente: BC3, otros anejos, normativa.
- Profundidad recomendada: focalizado.
- Salida esperada: tabla Word coherente con el Excel.

## 3. Auditoria BC3

- Objetivo: detectar partidas incompletas, mediciones ausentes, descompuestos rotos o incoherencias.
- Entradas minimas: BC3 vigente y, si existe, changelog o fuente de mediciones.
- Leer normalmente: BC3 activo, changelog y fuentes puntuales afectadas.
- No leer normalmente: memoria completa, todos los anejos, historicos completos.
- Profundidad recomendada: global en el BC3, focalizado en el alcance afectado.
- Salida esperada: lista de incidencias o BC3 corregido con verificaciones.

## 4. Trazabilidad documental

- Objetivo: comprobar coherencia entre memoria, anejos, Excel, BC3 y tablas.
- Entradas minimas: `FUENTES_MAESTRAS.md` y los documentos implicados.
- Leer normalmente: solo las piezas del cruce solicitado.
- No leer normalmente: carpetas no afectadas, historicos, ruido auxiliar.
- Profundidad recomendada: focalizado salvo cierre global.
- Salida esperada: discrepancias, bloqueadores o confirmacion de alineacion.

## 5. Revision civil

- Objetivo: revisar coherencia tecnica de un anejo o bloque civil.
- Entradas minimas: anejo objetivo y su fuente de calculo o medicion.
- Leer normalmente: el anejo y la fuente tecnica asociada.
- No leer normalmente: disciplinas ajenas, toolkit, plantilla.
- Profundidad recomendada: focalizado.
- Salida esperada: observaciones tecnicas y cambios propuestos.

## 6. Limpieza de mojibake

- Objetivo: detectar y corregir texto corrupto.
- Entradas minimas: archivo afectado.
- Leer normalmente: el archivo afectado y, si aplica, su contenedor Office.
- No leer normalmente: el resto del proyecto.
- Profundidad recomendada: archivo completo.
- Salida esperada: archivo saneado y verificado.

## 7. Actualizacion de memoria del proyecto

- Objetivo: mantener al dia `MAPA_PROYECTO.md`, `FUENTES_MAESTRAS.md`, `DECISIONES_PROYECTO.md`, `ESTADO_PROYECTO.md` o `TRIAGE.md`.
- Entradas minimas: estructura de raiz y contexto de la sesion.
- Leer normalmente: capa corta de contexto y rutas clave.
- No leer normalmente: documentos tecnicos no afectados.
- Profundidad recomendada: triage o focalizado.
- Salida esperada: contexto del proyecto claro y breve.

## 8. Cierre de entrega

- Objetivo: comprobar coherencia minima antes de entrega.
- Entradas minimas: lista de entregables y fuentes maestras.
- Leer normalmente: `ESTADO_PROYECTO.md`, `FUENTES_MAESTRAS.md` y documentos con pendientes conocidos.
- No leer normalmente: historicos completos o carpetas no incluidas en la entrega.
- Profundidad recomendada: global pero superficial.
- Salida esperada: bloqueadores, pendientes y estado de entrega.

## 9. Auditoria global

- Objetivo: revisar estructura, fronteras de repo, ruido y deuda operativa.
- Entradas minimas: raiz del repo, archivos maestros y trazas de conflicto.
- Leer normalmente: estructura de carpetas, archivos maestros, README y AGENTS.
- No leer normalmente: contenido completo de cada entregable tecnico.
- Profundidad recomendada: global y superficial.
- Salida esperada: diagnostico priorizado.