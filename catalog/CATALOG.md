# Catalogo Toolkit

| id | kind | domain | safety | path | summary |
|---|---|---|---|---|---|
| bc3-tools | tool | bc3 | safe-write | `tools/python/bc3_tools.py` | Opera BC3 de forma determinista: info, export, merge, recalc, validate y modificaciones controladas. |
| excel-tools | tool | office | read-only | `tools/python/excel_tools.py` | Lee y extrae datos de Excel de forma determinista antes de cualquier analisis del LLM. |
| mediciones-validator | tool | traceability | read-only | `tools/python/mediciones_validator.py` | Cruza cantidades BC3 vs Excel sin delegar el calculo al LLM. |
| check-office-mojibake | tool | office | read-only | `tools/office/check_office_mojibake.ps1` | Comprueba mojibake y corrupcion textual en contenedores Office. |
| check-docx-tables-consistency | tool | office | read-only | `tools/office/check_docx_tables_consistency.ps1` | Valida tablas visibles, captions y coherencia tipografica en DOCX. |
| check-excel-formula-guard | tool | office | read-only | `tools/office/check_excel_formula_guard.ps1` | Protege formulas en libros Excel y detecta perdidas o cambios inesperados. |
| check-bc3-integrity | tool | bc3 | read-only | `tools/bc3/check_bc3_integrity.ps1` | Valida integridad estructural basica de BC3. |
| check-bc3-import-parity | tool | bc3 | read-only | `tools/bc3/check_bc3_import_parity.ps1` | Comprueba paridad estructural entre BC3 maestro y copia de importacion. |
| check-traceability-consistency | tool | traceability | read-only | `tools/traceability/check_traceability_consistency.ps1` | Busca anclas de coherencia entre BC3, Office y archivos de texto. |
| run-traceability-profile | tool | traceability | read-only | `tools/traceability/run_traceability_profile.ps1` | Ejecuta revisiones de trazabilidad por perfiles declarados. |
| check-normativa-scope | tool | normativa | read-only | `tools/normativa/check_normativa_scope.ps1` | Revisa presencia y alcance de referencias normativas en documentos o carpetas. |
| run-project-closeout | script | traceability | safe-write | `scripts/run_project_closeout.ps1` | Orquesta cierre rapido o mixto sobre rutas concretas. |
| run-estandar-proyecto | script | traceability | safe-write | `scripts/run_estandar_proyecto.ps1` | Orquesta cierre estandar del proyecto con trazabilidad opcional. |
| install-project-toolkit | script | bootstrap | safe-write | `scripts/install_project_toolkit.ps1` | Instala el toolkit reusable en un destino objetivo con opcion para no sobrescribir ficheros existentes. |
| check-ecosystem-alignment | script | automation | read-only | `scripts/check_ecosystem_alignment.ps1` | Compara alineacion por hash entre obra, toolkit y plantilla a partir de un manifiesto. |
| docx-utf8-helpers | script | office | safe-write | `scripts/docx_utf8_helpers.ps1` | Expande, reempaqueta y sanea contenedores DOCX con control de UTF-8 y mojibake. |
| detectar-impacto-cambios | script | traceability | read-only | `scripts/detectar_impacto_cambios.ps1` | Analiza cambios del repo y propone impactos, acciones derivadas y verificaciones recomendadas. |

## Contratos adicionales

- catalog/executors/EXECUTOR_CONTRACT.md: contrato minimo para ejecutores reutilizables.
- catalog/traceability/TRACEABILITY_GRAPH.md: esquema ligero para trazabilidad como red.
- catalog/traceability/coverage.schema.json: cobertura medible minima.

