# Scripts del toolkit

Scripts reutilizables del ecosistema comun.

## Orquestacion

- `install_project_toolkit.ps1`: instala `tools/`, `scripts/` y `catalog/` del toolkit en un proyecto. Acepta `-SkipExisting` para no sobrescribir ficheros ya personalizados en el destino.
- `check_ecosystem_alignment.ps1`: compara hashes entre obra, toolkit y plantilla a partir de un manifiesto explicito.
- `run_estandar_proyecto.ps1`: wrapper de pipeline estandar.
- `run_project_closeout.ps1`: wrapper de cierre rapido o mixto.
- `sync_catalog.ps1`: sincroniza el catalogo comun.

## Helpers tecnicos

- `docx_utf8_helpers.ps1`: utilidades de bajo nivel para expandir, reparar y reempaquetar contenedores DOCX con control de UTF-8 y mojibake.
- `detectar_impacto_cambios.ps1`: analiza cambios del repo y propone bloques impactados, acciones derivadas y verificaciones recomendadas.

## Regla simple

- Si un script sirve a varios expedientes sin conocer nombres de obra, va aqui.
- Si escribe sobre un anejo, BC3 o entregable concreto de una obra, se queda en el repo del proyecto hasta refactor.