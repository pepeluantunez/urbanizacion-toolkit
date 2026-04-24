# Instrucciones del Toolkit

## Objetivo

Este repo contiene solo piezas reutilizables entre proyectos tecnicos de urbanizacion.

## Orden de lectura recomendado

1. `SYSTEM_RULES.md`
2. `TASK_TYPES.md`
3. `IGNORE_DEFAULTS.md`
4. `TRIAGE.md`
5. `EJECUTORES_PRIORITARIOS.md` si la tarea requiere automatizacion o cierre transversal

## Si debe vivir aqui

- verificadores genericos
- scripts reutilizables
- catalogos e indices
- fixtures de prueba
- workflows y MCP que no dependan de un expediente concreto

## Si no debe vivir aqui

- entregables de una obra
- BC3 maestro de un expediente
- auditorias con nombres o codigos de proyecto
- documentos de trabajo activos de una obra concreta

## Principios operativos

- No leer todo el proyecto por defecto.
- Hacer triage antes de un analisis profundo.
- Diferenciar siempre entre fuente, derivado, salida y obsoleto.
- Priorizar cambios focalizados frente a auditorias globales si basta con eso.
- No mezclar proyecto vivo, plantilla base y toolkit reusable en una misma lectura salvo que la tarea sea precisamente de ecosistema.

## Cierres obligatorios

- Office y BC3: control anti-mojibake antes de cerrar.
- BC3: snapshot y diff antes y despues de modificar.
- Excel: preservar formulas.
- DOCX: tablas visibles, captions y coherencia visual.

## Canon

- Las reglas globales viven en `SYSTEM_RULES.md`.
- La taxonomia de tareas vive en `TASK_TYPES.md`.
- Las exclusiones por defecto viven en `IGNORE_DEFAULTS.md`.
- El selector de tarea vive en `TRIAGE.md`.
- Los ejecutores priorizados viven en `EJECUTORES_PRIORITARIOS.md`.

## Regla de aceptacion

- Si una herramienta requiere conocer nombres, codigos o rutas de Guadalmar para ser util, todavia no esta lista para toolkit.
- Si se reutiliza igual en dos proyectos, debe acabar aqui.
- Ningun cambio se da por bueno sin una verificacion proporcional al riesgo de la herramienta afectada.
