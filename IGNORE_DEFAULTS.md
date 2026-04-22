# IGNORE_DEFAULTS - urbanizacion-toolkit

> Ruido que no debe analizarse salvo orden expresa.

## Ignorar siempre

- `_archive/`
- `_bak_snapshots/`
- `scratch/`
- `.codex_tmp/`
- `~$*`
- `*.lock`
- `*.tmp`
- `*.temp`
- `*.bak`
- `*.autosave`
- `Thumbs.db`
- `.DS_Store`

## Ignorar salvo tarea especifica

- `urbanizacion-toolkit/` dentro de un proyecto
- `urbanizacion-plantilla-base/` dentro de un proyecto
- `00_PLANTILLA_BASE/`
- `tests/`
- `catalog/`
- `CONFIG/`
- `NORMATIVA/`
- exportaciones PDF repetidas
- historicos de importacion Presto
- carpetas auxiliares de maquetacion temporal

## Senales de ruido tipicas

- archivos `AUDITORIA_*`, `GUIA_*`, `PACK_*`, `RESUMEN_*` sueltos en raiz de un proyecto vivo
- duplicados con sufijos `_REFINADO`, `_v2`, `_ACTUALIZADO` sin manifest de vigencia
- BC3 historicos o de integracion paralela cuando ya hay un BC3 maestro definido
- documentos de otro expediente colocados en la raiz del repo actual

## Excepcion

Si la tarea pide expresamente revisar uno de estos elementos, deja de ignorarse para ese encargo.