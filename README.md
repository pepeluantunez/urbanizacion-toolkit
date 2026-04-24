# urbanizacion-toolkit

Toolkit reusable para proyectos tecnicos de urbanizacion.

## Rol del repo

- reglas globales reutilizables
- taxonomia de tareas y triage
- ejecutores prioritarios
- herramientas y scripts compartidos
- catalogo y pruebas del ecosistema

## Archivos clave

- `AGENTS.md`: entrada corta y unica del toolkit
- `SYSTEM_RULES.md`: reglas globales
- `TASK_TYPES.md`: tipos de tarea
- `IGNORE_DEFAULTS.md`: ruido a excluir
- `TRIAGE.md`: selector de tarea
- `EJECUTORES_PRIORITARIOS.md`: automatizaciones prioritarias

## No contiene

- entregables de proyectos
- BC3 maestros de un expediente concreto
- memoria, anejos o auditorias de una obra viva

## Familias

- `tools/`
- `tools/python/` para scripts canonicos de bc3 y Excel
- `tools/automation/` para resolucion de rutas y busqueda segura sin depender del entorno
- `tools/automation/check_machine_guard.ps1` para validar contrato de repo + alineacion toolkit/plantilla/obra antes de dar un proyecto por sano
- `scripts/`
- `catalog/`
- `tests/`
