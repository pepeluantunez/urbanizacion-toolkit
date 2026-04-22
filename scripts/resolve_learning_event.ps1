param(
    [string]$Root = '.',
    [string[]]$Ids,
    [string]$ProposalKey = '',

    [ValidateSet('revisado', 'aplicado', 'descartado')]
    [string]$Estado = 'aplicado',

    [string]$Resolucion = '',
    [string]$TargetRepo = '',
    [string[]]$EvidencePaths
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

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$rootAbsolutePath = Resolve-AbsolutePath -BasePath (Get-Location).Path -TargetPath $Root
$logPath = Join-Path $rootAbsolutePath 'scratch\skill_improvement\error_log.json'
$backlogPath = Join-Path $rootAbsolutePath 'scratch\skill_improvement\learning_backlog.json'

if (-not (Test-Path -LiteralPath $logPath)) {
    throw 'No existe el log de errores.'
}

$log = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8 | ConvertFrom-Json
$entries = if ($log -is [System.Collections.IEnumerable] -and $log -isnot [string]) { @($log) } else { @($log) }

$selectedIds = New-Object System.Collections.Generic.List[string]
foreach ($id in @($Ids)) {
    if (-not [string]::IsNullOrWhiteSpace($id)) {
        [void]$selectedIds.Add($id)
    }
}

if ($selectedIds.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($ProposalKey)) {
    if (-not (Test-Path -LiteralPath $backlogPath)) {
        throw 'No existe learning_backlog.json para resolver por proposal key.'
    }

    $backlog = Get-Content -LiteralPath $backlogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($proposal in @($backlog.proposals)) {
        if ($proposal.key -eq $ProposalKey) {
            foreach ($entry in @($proposal.entries)) {
                [void]$selectedIds.Add([string]$entry.id)
            }
        }
    }
}

if ($selectedIds.Count -eq 0) {
    throw 'Debes indicar -Ids o -ProposalKey.'
}

$now = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
$updated = 0
foreach ($entry in $entries) {
    if ($selectedIds.Contains([string]$entry.id)) {
        $entry.estado = $Estado
        $entry.learning_status = switch ($Estado) {
            'revisado' { 'analyzed' }
            'aplicado' { 'resolved' }
            'descartado' { 'discarded' }
        }
        if (-not [string]::IsNullOrWhiteSpace($Resolucion)) {
            $entry.resolution = $Resolucion
        }
        if (-not [string]::IsNullOrWhiteSpace($TargetRepo)) {
            $entry.target_repo = $TargetRepo
        }
        if ($Estado -in @('aplicado', 'descartado')) {
            $entry.resolved_at = $now
        }
        if ($EvidencePaths) {
            $entry.evidence_paths = @($EvidencePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        $updated++
    }
}

Write-Utf8Text -Path $logPath -Content ($entries | ConvertTo-Json -Depth 8)
Write-Host ("[resolve_learning_event] Actualizados: {0}" -f $updated) -ForegroundColor Green