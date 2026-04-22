# SYSTEM_RULES - urbanizacion-toolkit

> Reglas globales reutilizables del sistema.
> Estas reglas valen para cualquier proyecto que use este toolkit.

## 1. No analizar todo el proyecto por defecto

- Antes de trabajar, consultar `MAPA_PROYECTO.md` y `FUENTES_MAESTRAS.md` del proyecto.
- Leer solo las rutas necesarias para la tarea concreta.
- Si no existe capa corta de contexto, hacer primero un triage superficial de raiz.

## 2. No inventar datos ni normativa

- Si un dato no consta, decir `no consta`.
- Si una norma no esta en las fuentes del proyecto o en el corpus normativo activo, no citarla como si estuviera verificada.
- No rellenar huecos tecnicos con suposiciones.

## 3. Jerarquia de fuentes

Regla general:

1. Fuente tecnica vigente del proyecto
2. Documento vivo del proyecto
3. Salida derivada
4. Plantilla base
5. Historicos, backups y residuos de sesion

Si el proyecto define una jerarquia mas precisa en `FUENTES_MAESTRAS.md`, esa manda.

## 4. Triage obligatorio antes de analisis profundo

- Clasificar el tipo de tarea.
- Fijar objetivo exacto.
- Delimitar archivos a leer y a ignorar.
- Elegir modo: `triage`, `focalizado` o `global`.

Ver `TRIAGE.md`.

## 5. Diferenciar archivo fuente, derivado, salida y obsoleto

- Fuente: documento que manda.
- Derivado: documento generado o sincronizado desde una fuente.
- Salida: entregable final.
- Obsoleto: version anterior, copia temporal o material que no debe usarse.

No tratar derivados u obsoletos como si fueran la fuente.

## 6. Excluir ruido por defecto

- Ignorar temporales, locks, backups, snapshots y residuos de sesiones.
- Ignorar PDFs repetidos, exportaciones intermedias y carpetas auxiliares salvo orden expresa.
- Ver `IGNORE_DEFAULTS.md`.

## 7. Preferir cambios focalizados

- Si basta con tocar un archivo o un conjunto corto de rutas, no abrir media arboleda.
- Reservar auditorias globales para cierres, trazabilidad transversal o encargos de diagnostico.

## 8. Cierres obligatorios por tipo de archivo

- DOCX/XLSX/XML Office/BC3: control anti-mojibake.
- BC3: snapshot antes, snapshot despues, diff e integridad.
- XLSX/XLSM: control de formulas antes y despues si hay maquetado.
- DOCX: control de tablas visibles, tipografia y captions.

## 9. Herramientas canonicas

- `check_office_mojibake.ps1`
- `check_bc3_integrity.ps1`
- `check_excel_formula_guard.ps1`
- `check_docx_tables_consistency.ps1`
- `check_traceability_consistency.ps1`
- `run_traceability_profile.ps1`
- `run_project_closeout.ps1`

## 10. Fronteras de repositorio

- El toolkit no debe contener entregables de proyecto.
- La plantilla no debe convertirse en un proyecto vivo.
- El proyecto vivo no debe absorber toolkit y plantilla como si fueran parte de su ambito documental.