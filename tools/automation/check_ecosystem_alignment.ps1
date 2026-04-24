[CmdletBinding()]
param(
    [string]$ManifestPath = '.\CONFIG\ecosystem_alignment_manifest.json',
    [ValidateSet('text', 'json')]
    [string]$OutputFormat = 'text',
    [string]$OutPath,
    [switch]$FailOnDrift
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $toolsRoot
$resolver = Join-Path $toolsRoot 'resolve_ecosystem_repo.ps1'

if (-not (Test-Path -LiteralPath $resolver)) {
    throw "No existe resolve_ecosystem_repo.ps1 en $toolsRoot"
}

$toolkitRoot = & $resolver -RepoName 'urbanizacion-toolkit' -StartPath $projectRoot | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($toolkitRoot)) {
    throw 'No se pudo resolver urbanizacion-toolkit desde el proyecto local.'
}

$checker = Join-Path $toolkitRoot 'scripts\check_ecosystem_alignment.ps1'
if (-not (Test-Path -LiteralPath $checker)) {
    throw "No existe el checker canonico en $checker"
}

$manifestAbsolute = if ([System.IO.Path]::IsPathRooted($ManifestPath)) {
    $ManifestPath
}
else {
    Join-Path $projectRoot $ManifestPath
}

$invokeArgs = @{
    ManifestPath = $manifestAbsolute
    OutputFormat = $OutputFormat
}

if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
    $invokeArgs['OutPath'] = $OutPath
}

if ($FailOnDrift) {
    $invokeArgs['FailOnDrift'] = $true
}

& $checker @invokeArgs
