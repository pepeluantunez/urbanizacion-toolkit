<#
.SYNOPSIS
    Busca texto o lista ficheros con fallback seguro cuando rg no esta disponible o falla.

.DESCRIPTION
    Intenta usar rg por velocidad. Si rg no existe o falla por entorno
    (por ejemplo acceso denegado), cae automaticamente a Get-ChildItem +
    Select-String con exclusiones de ruido habituales.

.EXAMPLE
    .\tools\automation\find_in_workspace.ps1 -Pattern "TODO" -Path .

.EXAMPLE
    .\tools\automation\find_in_workspace.ps1 -Pattern "sync_from_toolkit" -Path . -FilesOnly
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Pattern,

    [string]$Path = ".",

    [switch]$FilesOnly
)

$ErrorActionPreference = "Stop"

$resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
$excludeRegex = "\\\.git\\|\\\.codex_tmp\\|\\scratch\\|\\_archive\\|\\_ARCHIVO_LOCAL_DOCS\\|\\node_modules\\|\\bin\\|\\obj\\"

function Invoke-Ripgrep {
    param(
        [string]$PatternValue,
        [string]$SearchPath,
        [switch]$ListFilesOnly
    )

    $rg = Get-Command rg -ErrorAction SilentlyContinue
    if (-not $rg) {
        return $false
    }

    $args = @(
        "--line-number",
        "--hidden",
        "--glob", "!.git",
        "--glob", "!.codex_tmp",
        "--glob", "!scratch",
        "--glob", "!_archive",
        "--glob", "!_ARCHIVO_LOCAL_DOCS",
        "--glob", "!node_modules",
        "--glob", "!bin",
        "--glob", "!obj"
    )

    if ($ListFilesOnly) {
        $args += "--files-with-matches"
    }

    $args += @($PatternValue, $SearchPath)

    try {
        & $rg.Source @args
        return $true
    }
    catch {
        Write-Warning "rg no se pudo usar correctamente. Fallback a PowerShell. Motivo: $($_.Exception.Message)"
        return $false
    }
}

if (Invoke-Ripgrep -PatternValue $Pattern -SearchPath $resolvedPath -ListFilesOnly:$FilesOnly) {
    exit 0
}

$files = Get-ChildItem -LiteralPath $resolvedPath -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $excludeRegex }

if ($FilesOnly) {
    $matches = $files | Select-String -Pattern $Pattern -List
    $matches | ForEach-Object { $_.Path } | Sort-Object -Unique
    exit 0
}

$files | Select-String -Pattern $Pattern | ForEach-Object {
    "{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.TrimEnd()
}
