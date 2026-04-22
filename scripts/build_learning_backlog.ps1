param(
    [string]$Root = '.',
    [string]$RulesPath = '.\CONFIG\learning_loop_rules.json',
    [string]$LogPath = '.\scratch\skill_improvement\error_log.json',
    [string]$SoloSkill = '',
    [switch]$MarkReviewed,

    [ValidateSet('text', 'json')]
    [string]$OutputFormat = 'text',

    [string]$OutPath
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Resolve-AbsolutePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    if ([System.IO.Path]::IsPathRooted($TargetPath)) {
        return [System.IO.Path]::GetFullPath($TargetPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $TargetPath))
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-DefaultRuleSet {
    return @(
        [pscustomobject]@{
            key = 'encoding'
            pattern = 'mojibake|encoding|utf|\u00C3|\u00C2|\u00E2|\?'
            target_repo = 'toolkit'
            action_kind = 'rule-or-tool'
            summary = 'Endurecer reglas y utilidades de codificacion o mojibake.'
            suggested_files = @('AGENTS.md', 'tools/check_office_mojibake.ps1')
        },
        [pscustomobject]@{
            key = 'excel'
            pattern = 'formula|xlsx|excel|columna|header|worksheet'
            target_repo = 'toolkit'
            action_kind = 'tool-or-skill'
            summary = 'Mejorar guardas de Excel y helpers de lectura/escritura.'
            suggested_files = @('tools/check_excel_formula_guard.ps1', 'scripts/xml_excel_helpers.ps1')
        },
        [pscustomobject]@{
            key = 'bc3'
            pattern = 'bc3|~C|~D|~T|~M|partida|presupuesto|presto'
            target_repo = 'toolkit'
            action_kind = 'tool-or-protocol'
            summary = 'Reforzar verificadores BC3 o protocolos de snapshot y paridad.'
            suggested_files = @('tools/check_bc3_integrity.ps1', 'tools/check_bc3_import_parity.ps1')
        },
        [pscustomobject]@{
            key = 'docx'
            pattern = 'docx|word|tabla|caption|montserrat|tipografia'
            target_repo = 'toolkit'
            action_kind = 'tool-or-skill'
            summary = 'Reforzar verificadores DOCX y reglas de maquetacion.'
            suggested_files = @('tools/check_docx_tables_consistency.ps1')
        },
        [pscustomobject]@{
            key = 'traceability'
            pattern = 'trazabilidad|traceability|coher|inconsisten'
            target_repo = 'toolkit'
            action_kind = 'tool-or-profile'
            summary = 'Mejorar controles de trazabilidad o perfiles de cierre.'
            suggested_files = @('tools/check_traceability_consistency.ps1', 'tools/run_traceability_profile.ps1')
        },
        [pscustomobject]@{
            key = 'repo-hygiene'
            pattern = 'repo|raiz|root|ruido|mezcla|toolkit|plantilla|worktree'
            target_repo = 'toolkit'
            action_kind = 'repo-guard'
            summary = 'Endurecer guardas de higiene o fronteras de repositorio.'
            suggested_files = @('scripts/check_repo_hygiene.ps1', 'DOCS/REPO_BOUNDARIES.md')
        }
    )
}

function Resolve-Proposal {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Entry,
        [Parameter(Mandatory = $true)]
        [pscustomobject[]]$Rules
    )

    $text = ("{0} {1} {2}" -f $Entry.skill, $Entry.error, $Entry.contexto)
    foreach ($rule in $Rules) {
        if ($text -match $rule.pattern) {
            return $rule
        }
    }

    return [pscustomobject]@{
        key = 'manual-review'
        target_repo = if ([string]::IsNullOrWhiteSpace($Entry.repo_hint)) { 'obra' } else { $Entry.repo_hint }
        action_kind = 'manual-review'
        summary = 'Revision manual del fallo y clasificacion de la mejora.'
        suggested_files = @('AGENTS.md')
    }
}

function Build-Markdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPathValue,
        [Parameter(Mandatory = $true)]
        [pscustomobject[]]$Proposals
    )

    $lines = @()
    $lines += '# Propuestas de mejora de skills y agentes'
    $lines += ("Generado: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'))
    $lines += 'Estado: PENDIENTE DE REVISION Y APROBACION MANUAL'
    $lines += ''
    $lines += ("Log analizado: {0}" -f $LogPathValue)
    $lines += ''

    foreach ($proposal in $Proposals) {
        $lines += ("## Propuesta: {0}" -f $proposal.key)
        $lines += ''
        $lines += ("- Repo sugerido: {0}" -f $proposal.target_repo)
        $lines += ("- Tipo de accion: {0}" -f $proposal.action_kind)
        $lines += ("- Errores agrupados: {0}" -f $proposal.count)
        $lines += ("- Resumen: {0}" -f $proposal.summary)
        if ($proposal.suggested_files.Count -gt 0) {
            $lines += ("- Archivos sugeridos: {0}" -f (($proposal.suggested_files | ForEach-Object { $_ }) -join ', '))
        }
        $lines += ''
        $lines += '### Registros'
        foreach ($entry in $proposal.entries) {
            $lines += ("- {0} [{1}] {2}" -f $entry.id, $entry.skill, $entry.error)
            if (-not [string]::IsNullOrWhiteSpace($entry.contexto)) {
                $lines += ("  Contexto: {0}" -f $entry.contexto)
            }
        }
        $lines += ''
        $lines += '### Siguiente paso'
        $lines += ("- Si apruebas la mejora, resuelvela en {0} y luego marca los ids anteriores con resolve_learning_event.ps1." -f $proposal.target_repo)
        $lines += ''
    }

    if ($Proposals.Count -eq 0) {
        $lines += 'No hay errores pendientes de analisis.'
    }

    return ($lines -join [Environment]::NewLine)
}

$rootAbsolutePath = Resolve-AbsolutePath -BasePath (Get-Location).Path -TargetPath $Root
$logAbsolutePath = Resolve-AbsolutePath -BasePath $rootAbsolutePath -TargetPath $LogPath

if (-not (Test-Path -LiteralPath $logAbsolutePath)) {
    Write-Host "[build_learning_backlog] No existe log de errores todavia." -ForegroundColor Cyan
    exit 0
}

$rules = @()
$rulesAbsolutePath = Resolve-AbsolutePath -BasePath $rootAbsolutePath -TargetPath $RulesPath
if (Test-Path -LiteralPath $rulesAbsolutePath) {
    $loadedRules = Get-Content -LiteralPath $rulesAbsolutePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $rules = @($loadedRules.rules)
}
else {
    $rules = Get-DefaultRuleSet
}

$log = Get-Content -LiteralPath $logAbsolutePath -Raw -Encoding UTF8 | ConvertFrom-Json
$allEntries = if ($log -is [System.Collections.IEnumerable] -and $log -isnot [string]) { @($log) } else { @($log) }
$entries = @($allEntries)
$entries = $entries | Where-Object { $_.estado -notin @('aplicado', 'descartado') }
if (-not [string]::IsNullOrWhiteSpace($SoloSkill)) {
    $entries = $entries | Where-Object { $_.skill -eq $SoloSkill }
}

$entries = @($entries)
if ($entries.Count -eq 0) {
    Write-Host "[build_learning_backlog] No hay errores pendientes de revision." -ForegroundColor Green
    exit 0
}

$bucket = @{}
foreach ($entry in $entries) {
    $proposal = Resolve-Proposal -Entry $entry -Rules $rules
    $key = "{0}|{1}|{2}" -f $proposal.key, $entry.skill, $proposal.target_repo
    if (-not $bucket.ContainsKey($key)) {
        $bucket[$key] = [ordered]@{
            key = $proposal.key
            target_repo = $proposal.target_repo
            action_kind = $proposal.action_kind
            summary = $proposal.summary
            suggested_files = @($proposal.suggested_files)
            entries = New-Object System.Collections.Generic.List[object]
        }
    }

    $entry.proposal_key = $proposal.key
    [void]$bucket[$key].entries.Add($entry)
}

$proposalList = New-Object System.Collections.Generic.List[object]
foreach ($value in $bucket.Values) {
    [void]$proposalList.Add([pscustomobject]@{
        key = $value.key
        target_repo = $value.target_repo
        action_kind = $value.action_kind
        summary = $value.summary
        suggested_files = @($value.suggested_files)
        count = $value.entries.Count
        entries = $value.entries.ToArray()
    })
}

$proposals = @($proposalList.ToArray() | Sort-Object target_repo, key)

$scratchDir = Join-Path $rootAbsolutePath 'scratch\skill_improvement'
$markdownPath = Join-Path $scratchDir 'propuestas_mejora.md'
$jsonPath = Join-Path $scratchDir 'learning_backlog.json'

$markdown = Build-Markdown -LogPathValue $logAbsolutePath -Proposals $proposals
$json = ([pscustomobject]@{
    root = $rootAbsolutePath
    generated_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    log_path = $logAbsolutePath
    proposals = $proposals
}) | ConvertTo-Json -Depth 8

Write-Utf8Text -Path $markdownPath -Content $markdown
Write-Utf8Text -Path $jsonPath -Content $json

if ($MarkReviewed) {
    foreach ($entry in $entries) {
        $entry.estado = 'revisado'
        $entry.learning_status = 'analyzed'
    }
    Write-Utf8Text -Path $logAbsolutePath -Content (@($allEntries) | ConvertTo-Json -Depth 8)
}

$content = if ($OutputFormat -eq 'json') { $json } else { $markdown }
if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
    $outAbsolutePath = Resolve-AbsolutePath -BasePath $rootAbsolutePath -TargetPath $OutPath
    Write-Utf8Text -Path $outAbsolutePath -Content $content
}

Write-Output $content