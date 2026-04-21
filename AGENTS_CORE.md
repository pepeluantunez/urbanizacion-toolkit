# Reglas core del toolkit — válidas para todos los proyectos de urbanización

> Este archivo es la fuente canónica de las reglas operativas comunes.
> Los AGENTS.md de cada proyecto lo incluyen por referencia.
> Para actualizar una regla que aplica a todos los proyectos, editar aquí.
> Para añadir una regla solo de un proyecto, editar el AGENTS.md de ese proyecto.

---

## Regla core: control de mojibake y codificación

- Ninguna tarea sobre DOCX, XLSX, XML Office o BC3 se dará por terminada sin una verificación explícita final de codificación y texto corrupto.
- Es obligatorio comprobar que no aparecen secuencias tipo `Ã`, `Â`, `â€"`, `â€œ`, `â€`, `Ã'`, `Ã"`, `COMPROBACIÃ"N`, `URBANIZACIÃ"N` u otras equivalentes.
- Si se edita un `docx` por XML o script, hay que verificar tanto el XML interno como el resultado visible esperado.
- Si hay duda sobre la codificación, rehacer la escritura por un método que preserve UTF-8/Office XML antes de cerrar la tarea.

## Regla core: BC3 y presupuesto

- No crear ni dejar partidas a medias.
- Toda partida nueva o modificada debe quedar con código, nombre, descripción, unidad, descompuesto, recursos enlazados, medición y precio coherentes.
- No dejar textos como `PRECIO PENDIENTE`, conceptos huérfanos, recursos sin precio ni mediciones mal arrastradas.
- Tras tocar un BC3, comprobar siempre las líneas `~C`, `~D`, `~T` y `~M` afectadas.
- Snapshot obligatorio antes de cualquier modify, merge o recalc: `bc3_snapshot.ps1 -Path <archivo> -Label antes-<operacion>`.
- Tras la operación, comparar con `bc3_diff_report.ps1`. Si hay pérdidas críticas, detener y avisar antes de continuar.

## Regla core: Excel profesional y fórmulas

- En ficheros `XLSX` y `XLSM`, cualquier estandarización o maquetado debe preservar fórmulas. No se aceptan sustituciones silenciosas de fórmulas por valores.
- Si se estandariza un Excel existente, ejecutar control de fórmulas antes y después con `check_excel_formula_guard.ps1`.
- Si se crea un Excel nuevo para mediciones o trazabilidad, partir de plantilla o estructura profesional del proyecto, mantener tipografía `Montserrat` y dejar hojas legibles para impresión y revisión.

## Regla core: DOCX tablas y coherencia visual

- Las tablas en `DOCX` deben quedar visibles, legibles y coherentes con el texto del anejo.
- En contenido nuevo o normalizado se usará tipografía `Montserrat` de forma consistente.
- Tras editar tablas de Word, ejecutar control con `check_docx_tables_consistency.ps1`.
- Toda tabla técnica en anejos debe llevar numeración y descripción: formato `Tabla N. Descripción`.

## Regla core: maquetación profesional

- Mantener línea gráfica única: tipografía `Montserrat`, jerarquía de títulos estable, espaciados consistentes.
- Verificar que cada tabla quede contextualizada en el texto: llamada previa o posterior, título claro y unidades coherentes.
- En documentos largos de anejos, no dar por cerrada una maquetación sin una pasada final de legibilidad completa.

## Regla core: cierre obligatorio de cada tarea documental

1. Segunda pasada final de control cruzado.
2. Verificación de coherencia entre cálculo, tablas, mediciones y presupuesto.
3. Verificación final anti-mojibake antes de responder al usuario.

## Regla core: herramientas del toolkit

Las herramientas canónicas del toolkit son la fuente de verdad. Los proyectos las sincronizan con:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\sync_from_toolkit.ps1
```

| Herramienta | Propósito |
|-------------|-----------|
| `check_bc3_integrity.ps1` | Integridad BC3: mojibake, duplicados, huérfanos, placeholders |
| `check_bc3_import_parity.ps1` | Paridad BC3 maestro vs copia para importar en Presto |
| `check_docx_tables_consistency.ps1` | Tablas visibles y tipografía en DOCX |
| `check_excel_formula_guard.ps1` | Preservación de fórmulas en XLSX |
| `check_office_mojibake.ps1` | Mojibake en archivos Office |
| `check_traceability_consistency.ps1` | Trazabilidad transversal entre BC3, Excel y DOCX |
| `run_traceability_profile.ps1` | Trazabilidad por perfiles configurados |

## Regla core: aprendizaje continuo de skills

- Cuando falle una skill, script o herramienta, registrar el error antes de responder:
  `skill_error_logger.ps1 -Skill <nombre> -Error <descripcion> -Contexto <tarea>`
- Periódicamente (o cuando el usuario lo pida): `skill_self_improve.ps1` genera propuestas de mejora.
- Ninguna propuesta se aplica sin aprobación explícita del usuario.

## Enrutado automático por tipo de tarea

- Tarea DOCX/XLSX/Office → carril documental: editar → revisar → anti-mojibake.
- Tarea maquetación → carril maquetación: Montserrat, tablas visibles, coherencia visual.
- Tarea BC3/presupuesto → carril BC3: snapshot → modificar → diff → integridad.
- Tarea pluviales/SSA → carril pluviales: tocar solo lo necesario → contrastar fuente → control cruzado.
- Tarea mixta → coordinador: separar carriles, cerrar cada uno con su control específico.
