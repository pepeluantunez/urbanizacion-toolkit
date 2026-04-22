param(
    [string]$Root = '.',
    [string]$RulesPath,

    [ValidateSet('text', 'json')]
    [string]$OutputFormat = 'text',

    [string]$OutPath,

    [switch]$FailOnIssues
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

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $baseUri = [System.Uri]((Resolve-AbsolutePath -BasePath (Get-Location).Path -TargetPath $BasePath).TrimEnd('\') + '\')
    $targetUri = [System.Uri](Resolve-AbsolutePath -BasePath (Get-Location).Path -TargetPath $TargetPath)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('/', '\')
}

function Test-MatchList {
    param(
        [string]$Value,
        [object[]]$Patterns
    )

    foreach ($pattern in @($Patterns)) {
        if ([string]::IsNullOrWhiteSpace([string]$pattern)) {
            continue
        }

        if ($Value -match [string]$pattern) {
            return $true
        }
    }

    return $false
}

function New-Finding {
    param(
        [string]$Level,
        [string]$Kind,
        [string]$Path,
        [string]$Message
    )

    return [pscustomobject]@{
        Level = $Level
        Kind = $Kind
        Path = $Path
        Message = $Message
    }
}

function Build-TextReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,
        [Parameter(Mandatory = $true)]
        [pscustomobject[]]$Findings
    )

    $issues = @($Findings | Where-Object { $_.Level -eq 'issue' })
    $advisories = @($Findings | Where-Object { $_.Level -eq 'advisory' })

    $lines = @()
    $lines += '# Higiene del repo'
    $lines += ''
    $lines += ("Root: {0}" -f $RootPath)
    $lines += ("Issues: {0}" -f $issues.Count)
    $lines += ("Advisories: {0}" -f $advisories.Count)
    $lines += ''

    if ($issues.Count -gt 0) {
        $lines += '## Issues'
        foreach ($item in $issues) {
            $lines += ("- [{0}] {1}: {2}" -f $item.Kind, $item.Path, $item.Message)
        }
        $lines += ''
    }

    if ($advisories.Count -gt 0) {
        $lines += '## Advisories'
        foreach ($item in $advisories) {
            $lines += ("- [{0}] {1}: {2}" -f $item.Kind, $item.Path, $item.Message)
        }
    }

    return ($lines -join [Environment]::NewLine)
}

$rootAbsolutePath = Resolve-AbsolutePath -BasePath (Get-Location).Path -TargetPath $Root
if (-not (Test-Path -LiteralPath $rootAbsolutePath)) {
    throw "No existe la raiz del repo: $Root"
}

$rules = [pscustomobject]@{
    required_context_files = @()
    root_allowlist = @()
    root_allow_patterns = @()
    root_noise_patterns = @()
    foreign_root_patterns = @()
    local_support_dirs = @()
    suspicious_paths = @()
}

if (-not [string]::IsNullOrWhiteSpace($RulesPath)) {
    $rulesAbsolutePath = Resolve-AbsolutePath -BasePath $rootAbsolutePath -TargetPath $RulesPath
    if (-not (Test-Path -LiteralPath $rulesAbsolutePath)) {
        throw "No existe el fichero de reglas: $RulesPath"
    }

    $rules = Get-Content -LiteralPath $rulesAbsolutePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$findings = New-Object System.Collections.Generic.List[object]

foreach ($requiredFile in @($rules.required_context_files)) {
    $requiredAbsolute = Join-Path $rootAbsolutePath ([string]$requiredFile)
    if (-not (Test-Path -LiteralPath $requiredAbsolute)) {
        [void]$findings.Add((New-Finding -Level 'issue' -Kind 'missing-context' -Path ([string]$requiredFile) -Message 'Falta un archivo maestro obligatorio.'))
    }
}

$rootEntries = Get-ChildItem -LiteralPath $rootAbsolutePath -Force
foreach ($entry in $rootEntries) {
    $name = $entry.Name
    if ($name -eq '.git') {
        continue
    }

    $isAllowedByName = $name -in @($rules.root_allowlist)
    $isAllowedByPattern = Test-MatchList -Value $name -Patterns @($rules.root_allow_patterns)

    if (-not $isAllowedByName -and -not $isAllowedByPattern) {
        if (Test-MatchList -Value $name -Patterns @($rules.root_noise_patterns)) {
            [void]$findings.Add((New-Finding -Level 'issue' -Kind 'noisy-root' -Path $name -Message 'Elemento de ruido en raiz.'))
        }
        elseif ($entry.PSIsContainer -or $entry.Extension -in @('.md', '.txt', '.docx', '.docm', '.xlsx', '.xlsm', '.pdf')) {
            [void]$findings.Add((New-Finding -Level 'advisory' -Kind 'unclassified-root' -Path $name -Message 'Elemento en raiz fuera de la lista permitida.'))
        }
    }

    if (Test-MatchList -Value $name -Patterns @($rules.foreign_root_patterns)) {
        [void]$findings.Add((New-Finding -Level 'issue' -Kind 'foreign-root' -Path $name -Message 'Parece material de otro expediente.'))
    }
}

foreach ($supportDir in @($rules.local_support_dirs)) {
    $supportPath = Join-Path $rootAbsolutePath ([string]$supportDir)
    if (Test-Path -LiteralPath $supportPath) {
        [void]$findings.Add((New-Finding -Level 'advisory' -Kind 'support-dir' -Path ([string]$supportDir) -Message 'Directorio de apoyo del ecosistema presente; no debe leerse por defecto como si fuera parte del expediente.'))
    }
}

foreach ($suspiciousPath in @($rules.suspicious_paths)) {
    $absolutePath = Join-Path $rootAbsolutePath ([string]$suspiciousPath)
    if (Test-Path -LiteralPath $absolutePath) {
        $relativePath = Get-RelativePath -BasePath $rootAbsolutePath -TargetPath $absolutePath
        [void]$findings.Add((New-Finding -Level 'advisory' -Kind 'suspicious-path' -Path $relativePath -Message 'Ruta sospechosa o ajena al expediente; revisar si debe seguir aqui.'))
    }
}

$findingsArray = $findings.ToArray()

$payload = [pscustomobject]@{
    Root = $rootAbsolutePath
    GeneratedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Findings = $findingsArray
}

if ($OutputFormat -eq 'json') {
    $content = $payload | ConvertTo-Json -Depth 6
}
else {
    $content = Build-TextReport -RootPath $rootAbsolutePath -Findings $findingsArray
}

if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
    $outAbsolutePath = Resolve-AbsolutePath -BasePath $rootAbsolutePath -TargetPath $OutPath
    $outDirectory = Split-Path -Parent $outAbsolutePath
    if (-not [string]::IsNullOrWhiteSpace($outDirectory) -and -not (Test-Path -LiteralPath $outDirectory)) {
        New-Item -ItemType Directory -Force -Path $outDirectory | Out-Null
    }
    Set-Content -LiteralPath $outAbsolutePath -Value $content -Encoding UTF8
}

Write-Output $content

$issueCount = @($findingsArray | Where-Object { $_.Level -eq 'issue' }).Count
if ($FailOnIssues -and $issueCount -gt 0) {
    throw ("Higiene fallida: issues={0}" -f $issueCount)
}