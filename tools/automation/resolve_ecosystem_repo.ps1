<#
.SYNOPSIS
    Resuelve la ruta de un repo del ecosistema sin depender de recordar la ruta hermana exacta.

.DESCRIPTION
    Busca un repositorio por nombre empezando desde la ruta indicada, probando:
      1. la ruta actual si ya es ese repo
      2. siblings de cada ancestro
      3. una busqueda acotada dentro de Documents\Claude

    Devuelve la ruta resuelta por stdout para que otros scripts la consuman.

.EXAMPLE
    .\tools\automation\resolve_ecosystem_repo.ps1 -RepoName urbanizacion-toolkit -StartPath .
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName,

    [string]$StartPath = "."
)

$ErrorActionPreference = "Stop"

function Test-RepoCandidate {
    param([string]$CandidatePath)

    if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $CandidatePath)) {
        return $null
    }

    try {
        $item = Get-Item -LiteralPath $CandidatePath -ErrorAction Stop
    }
    catch {
        return $null
    }

    if (-not $item.PSIsContainer) {
        return $null
    }

    if ($item.Name -ieq $RepoName) {
        return $item.FullName
    }

    return $null
}

$startFullPath = (Resolve-Path -LiteralPath $StartPath -ErrorAction Stop).Path
$cursor = $startFullPath

while (-not [string]::IsNullOrWhiteSpace($cursor)) {
    $asRepo = Test-RepoCandidate -CandidatePath $cursor
    if ($asRepo) {
        Write-Output $asRepo
        exit 0
    }

    $parent = Split-Path -Parent $cursor
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $sibling = Join-Path $parent $RepoName
        $resolvedSibling = Test-RepoCandidate -CandidatePath $sibling
        if ($resolvedSibling) {
            Write-Output $resolvedSibling
            exit 0
        }
    }

    if ($parent -eq $cursor) {
        break
    }
    $cursor = $parent
}

$fallbackRoots = @(
    (Join-Path $env:USERPROFILE "Documents\Claude\Projects"),
    (Join-Path $env:USERPROFILE "Documents\Claude")
) | Select-Object -Unique

foreach ($root in $fallbackRoots) {
    if (-not (Test-Path -LiteralPath $root)) {
        continue
    }

    $match = Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq $RepoName } |
        Select-Object -First 1

    if ($match) {
        Write-Output $match.FullName
        exit 0
    }
}

Write-Error "No se pudo resolver el repo '$RepoName' desde '$startFullPath'."
exit 1
