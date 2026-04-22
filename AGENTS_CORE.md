# AGENTS_CORE - urbanizacion-toolkit

> Reglas core reutilizables para proyectos de urbanizacion.
> Este archivo debe mantenerse corto: enruta a la documentacion minima y evita duplicar contexto.

## Orden de lectura recomendado

1. `SYSTEM_RULES.md`
2. `TASK_TYPES.md`
3. `IGNORE_DEFAULTS.md`
4. `TRIAGE.md`
5. `EJECUTORES_PRIORITARIOS.md` si la tarea requiere automatizacion o cierre transversal

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