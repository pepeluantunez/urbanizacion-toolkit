# Esquema Ligero de Trazabilidad

La trazabilidad no debe vivir solo como tabla suelta. Debe poder expresarse como red de relaciones minima y legible.

## Capas

- `nodes.json`: artefactos o unidades rastreables
- `edges.json`: relaciones entre nodos
- `coverage.json`: metricas agregadas

## Tipos de nodo recomendados

- `memoria_section`
- `anejo`
- `excel_source`
- `bc3_concept`
- `word_table`
- `review_output`
- `normative_source`

## Relaciones recomendadas

- `backs`
- `derived_from`
- `justifies`
- `summarizes`
- `checks`
- `exports_to`

## Cobertura minima

- `word_tables_with_excel_source_pct`
- `memoria_sections_backed_by_annex_pct`
- `bc3_concepts_with_document_support_pct`
- `outputs_with_authority_defined_pct`

## Regla de austeridad

Esto no es un grafo empresarial ni un lago de datos. Solo debe servir para responder cuatro preguntas:

1. que manda
2. de donde sale
3. que lo verifica
4. cuanto queda cubierto
