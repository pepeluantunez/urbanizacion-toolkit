# Contrato de Ejecutores

Cada ejecutor reusable del toolkit debe poder describirse con este contrato minimo.

## Campos minimos

- `id`
- `kind`
- `domain`
- `path`
- `summary`
- `inputs`
- `outputs`
- `safety`

## Campos recomendados

- `config`
- `exclusions`
- `fixtures`
- `failure_criteria`
- `owner`

## Regla practica

Un ejecutor serio no solo dice lo que hace. Tambien debe dejar claro:

- que necesita para correr
- que no debe leer o tocar
- como se valida
- que condiciones lo hacen fallar

## Ejemplo corto

```json
{
  "id": "check-traceability-consistency",
  "kind": "tool",
  "domain": "traceability",
  "path": "tools/traceability/check_traceability_consistency.ps1",
  "summary": "Busca anclas de coherencia entre BC3, Office y texto.",
  "inputs": ["bc3", "docx", "xlsx", "csv", "md"],
  "outputs": ["informe de trazabilidad"],
  "safety": "read-only",
  "config": ["CONFIG/trazabilidad_profiles.json"],
  "exclusions": ["_archive", ".codex_tmp"],
  "fixtures": ["tests/fixtures/traceability"],
  "failure_criteria": [
    "fuente maestra no localizada",
    "tabla Word sin fuente identificada cuando aplica",
    "partida BC3 sin respaldo documental exigido"
  ],
  "owner": "urbanizacion-toolkit"
}
```
