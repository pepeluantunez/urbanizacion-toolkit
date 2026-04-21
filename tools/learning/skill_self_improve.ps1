<#
.SYNOPSIS
    Analiza el log de errores de skills y propone correcciones concretas.

.DESCRIPTION
    Lee scratch\skill_improvement\error_log.json, agrupa los errores por skill
    y patron, y genera un informe de propuestas de mejora en
    scratch\skill_improvement\propuestas_mejora.md

    NO aplica ningun cambio automaticamente. Todas las propuestas requieren
    revision y aprobacion manual antes de ser incorporadas.

.PARAMETER SoloSkill
    Si se especifica, analiza solo los errores de esa skill concreta.

.PARAMETER MarcarRevisados
    Si se activa, marca como "revisado" en el log todos los registros procesados.

.EXAMPLE
    .\skill_self_improve.ps1
    .\skill_self_improve.ps1 -SoloSkill "anejo-generator"
    .\skill_self_improve.ps1 -MarcarRevisados
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SoloSkill = "",

    [Parameter(Mandatory=$false)]
    [switch]$MarcarRevisados
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$LogDir = Join-Path $ProjectRoot "scratch\skill_improvement"
$LogFile = Join-Path $LogDir "error_log.json"
$PropostasFile = Join-Path $LogDir "propuestas_mejora.md"
$AgentsFile = Join-Path $ProjectRoot "AGENTS.md"

# Verificar que existe el log
if (-not (Test-Path $LogFile)) {
    Write-Host "[skill_self_improve] No existe log de errores todavia. Ejecuta primero skill_error_logger.ps1 cuando ocurra un fallo." -ForegroundColor Cyan
    exit 0
}

# Cargar log
$Log = Get-Content $LogFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $Log -or $Log.Count -eq 0) {
    Write-Host "[skill_self_improve] El log esta vacio. Sin errores registrados." -ForegroundColor Green
    exit 0
}

# Filtrar si se pide una skill concreta
$Errores = $Log | Where-Object { $_.estado -eq "pendiente" }
if ($SoloSkill -ne "") {
    $Errores = $Errores | Where-Object { $_.skill -eq $SoloSkill }
}

if ($Errores.Count -eq 0) {
    Write-Host "[skill_self_improve] No hay errores pendientes de revision." -ForegroundColor Green
    exit 0
}

Write-Host "[skill_self_improve] Analizando $($Errores.Count) errores pendientes..." -ForegroundColor Cyan

# Agrupar por skill
$PorSkill = $Errores | Group-Object -Property skill

# Generar informe de propuestas
$Fecha = Get-Date -Format "yyyy-MM-dd HH:mm"
$Informe = @"
# Propuestas de mejora de skills y agentes
Generado: $Fecha
Estado: PENDIENTE DE REVISION Y APROBACION MANUAL

---

"@

foreach ($Grupo in $PorSkill) {
    $NombreSkill = $Grupo.Name
    $ErroresSkill = $Grupo.Group
    $NumErrores = $ErroresSkill.Count

    $Informe += "## Skill: ``$NombreSkill`` ($NumErrores error(es) registrados)`n`n"

    # Listar errores
    $Informe += "### Errores registrados`n`n"
    foreach ($E in $ErroresSkill) {
        $Informe += "- **[$($E.timestamp)]** $($E.error)`n"
        if ($E.contexto -ne "") {
            $Informe += "  - Contexto: $($E.contexto)`n"
        }
    }
    $Informe += "`n"

    # Detectar patrones por palabras clave en el error
    $TextosError = ($ErroresSkill | ForEach-Object { $_.error }) -join " "

    $Informe += "### Propuesta de correccion`n`n"

    # Patrones conocidos
    if ($TextosError -match "mojibake|encoding|UTF|Ã|â€") {
        $Informe += "**Patron detectado:** Error de codificacion/mojibake`n`n"
        $Informe += "**Accion propuesta para AGENTS.md o SKILL.md de ``$NombreSkill``:**`n"
        $Informe += "- Anadir regla explicita: antes de escribir cualquier archivo, verificar encoding UTF-8.`n"
        $Informe += "- Recordar ejecutar ``check_office_mojibake.ps1`` como paso obligatorio de cierre.`n`n"
    }
    elseif ($TextosError -match "formula|KeyError|columna|header|xlsx|excel") {
        $Informe += "**Patron detectado:** Error en lectura/escritura de Excel`n`n"
        $Informe += "**Accion propuesta para AGENTS.md o SKILL.md de ``$NombreSkill``:**`n"
        $Informe += "- Obligar a usar ``excel_tools.py`` antes de leer cualquier xlsx.`n"
        $Informe += "- Anadir snapshot previo de formulas con ``check_excel_formula_guard.ps1``.`n`n"
    }
    elseif ($TextosError -match "bc3|~C|~D|~T|~M|partida|presupuesto") {
        $Informe += "**Patron detectado:** Error en BC3 o presupuesto`n`n"
        $Informe += "**Accion propuesta para AGENTS.md o SKILL.md de ``$NombreSkill``:**`n"
        $Informe += "- Recordar revisar lineas ~C, ~D, ~T, ~M tras toda modificacion.`n"
        $Informe += "- Anadir ``check_bc3_integrity.ps1`` como paso de cierre obligatorio.`n`n"
    }
    elseif ($TextosError -match "tabla|caption|Montserrat|tipografia|docx|word") {
        $Informe += "**Patron detectado:** Error de maquetacion en DOCX`n`n"
        $Informe += "**Accion propuesta para AGENTS.md o SKILL.md de ``$NombreSkill``:**`n"
        $Informe += "- Anadir paso de verificacion con ``check_docx_tables_consistency.ps1``.`n"
        $Informe += "- Verificar que se usa tipografia Montserrat en todo contenido nuevo.`n`n"
    }
    elseif ($TextosError -match "trazabilidad|traceability|coher|inconsistencia") {
        $Informe += "**Patron detectado:** Error de trazabilidad o coherencia documental`n`n"
        $Informe += "**Accion propuesta para AGENTS.md o SKILL.md de ``$NombreSkill``:**`n"
        $Informe += "- Ejecutar ``check_traceability_consistency.ps1`` tras cualquier cambio en mediciones o presupuesto.`n"
        $Informe += "- Verificar que medicion, tabla y BC3 quedan sincronizados antes de cerrar la tarea.`n`n"
    }
    else {
        $Informe += "**Patron:** No identificado automaticamente. Revision manual requerida.`n`n"
        $Informe += "**Accion propuesta:**`n"
        $Informe += "- Analizar los errores anteriores manualmente.`n"
        $Informe += "- Considerar anadir una regla especifica en AGENTS.md para este tipo de fallo.`n`n"
    }

    # Mostrar donde aplicar el cambio
    $SkillDir = Join-Path $ProjectRoot ".claude\skills\$NombreSkill"
    $SkillMd = Join-Path $SkillDir "SKILL.md"
    if (Test-Path $SkillMd) {
        $Informe += "**Archivo a modificar:** ``.claude\skills\$NombreSkill\SKILL.md``  `n"
    } else {
        $Informe += "**Archivo a modificar:** ``AGENTS.md`` (seccion correspondiente al carril de esta skill)  `n"
    }

    $Informe += "`n---`n`n"
}

$Informe += @"
## Instrucciones de uso

1. Revisa cada propuesta anterior.
2. Si la apruebas, aplica el cambio manualmente en el archivo indicado.
3. Marca los errores como revisados ejecutando:
   ``.\tools\skill_self_improve.ps1 -MarcarRevisados``
4. Haz commit con mensaje tipo: ``fix(agents): correccion basada en errores registrados [skill_self_improve]``

**IMPORTANTE: Este archivo es solo una propuesta. Ningun cambio se aplica automaticamente.**
"@

# Guardar informe
$Informe | Set-Content $PropostasFile -Encoding UTF8

# Marcar como revisados si se pidio
if ($MarcarRevisados) {
    foreach ($E in $Errores) {
        $E.estado = "revisado"
    }
    $Log | ConvertTo-Json -Depth 5 | Set-Content $LogFile -Encoding UTF8
    Write-Host "[skill_self_improve] Errores marcados como revisados en el log." -ForegroundColor Green
}

Write-Host "[skill_self_improve] Propuestas generadas en:" -ForegroundColor Green
Write-Host "  $PropostasFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Revisa el archivo y aprueba manualmente los cambios antes de aplicarlos." -ForegroundColor Yellow
