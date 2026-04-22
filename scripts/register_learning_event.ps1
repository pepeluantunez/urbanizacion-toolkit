param(
    [string]$Root = '.',

    [Parameter(Mandatory = $true)]
    [string]$Skill,

    [Parameter(Mandatory = $true)]
    [string]$ErrorText,

    [string]$Contexto = '',

    [ValidateSet('script', 'skill', 'agente', 'herramienta')]
    [string]$Categoria = 'skill',

    [string]$RepoHint = '',

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

function Write-Utf8Json {
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
$logDir = Join-Path $rootAbsolutePath 'scratch\skill_improvement'
$logFile = Join-Path $logDir 'error_log.json'

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$log = @()
if (Test-Path -LiteralPath $logFile) {
    try {
        $loaded = Get-Content -LiteralPath $logFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $loaded) {
            if ($loaded -is [System.Collections.IEnumerable] -and $loaded -isnot [string]) {
                $log = @($loaded)
            }
            else {
                $log = @($loaded)
            }
        }
    }
    catch {
        $log = @()
    }
}

$entry = [pscustomobject]@{
    id = ([guid]::NewGuid().ToString())
    timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    skill = $Skill
    categoria = $Categoria
    error = $ErrorText
    contexto = $Contexto
    repo_hint = $RepoHint
    evidence_paths = @($EvidencePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    estado = 'pendiente'
    learning_status = 'pending_analysis'
    target_repo = ''
    proposal_key = ''
    resolution = ''
    resolved_at = ''
}

$log += $entry
$json = $log | ConvertTo-Json -Depth 8
Write-Utf8Json -Path $logFile -Content $json

Write-Host "[register_learning_event] Registrado: '$Skill' -> $ErrorText" -ForegroundColor Yellow
Write-Host "  Log: $logFile" -ForegroundColor DarkGray