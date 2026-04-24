[CmdletBinding()]
param(
    [string]$ToolkitPath = "",
    [string]$TemplatePath = "",
    [switch]$SkipToolkitSync,
    [switch]$SkipMachineGuard,
    [switch]$SkipLockRefresh
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $toolsRoot
$resolver = Join-Path $toolsRoot 'resolve_ecosystem_repo.ps1'
$syncScript = Join-Path $toolsRoot 'sync_from_toolkit.ps1'
$guardScript = Join-Path $toolsRoot 'check_machine_guard.ps1'
$lockPath = Join-Path $projectRoot 'CONFIG\toolkit.lock.json'

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [string]$PreferredPath = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        try {
            return (Resolve-Path -LiteralPath $PreferredPath -ErrorAction Stop).Path
        }
        catch {
        }
    }

    if (-not (Test-Path -LiteralPath $resolver)) {
        throw "No existe resolve_ecosystem_repo.ps1 en $toolsRoot"
    }

    $resolved = & $resolver -RepoName $RepoName -StartPath $projectRoot | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        throw "No se pudo resolver el repo '$RepoName' desde '$projectRoot'."
    }

    return [string]$resolved
}

function Get-GitHeadCommit {
    param([Parameter(Mandatory = $true)][string]$RepoPath)

    $commit = & git -C $RepoPath rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) {
        return ''
    }

    return ($commit | Select-Object -First 1).Trim()
}

function Update-ToolkitLock {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ToolkitRepoPath,
        [Parameter(Mandatory = $true)][string]$TemplateRepoPath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "No existe CONFIG\\toolkit.lock.json en $projectRoot"
    }

    $lock = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $lock.toolkit_repo = 'urbanizacion-toolkit'
    $lock.toolkit_branch = 'main'
    $lock.toolkit_commit = Get-GitHeadCommit -RepoPath $ToolkitRepoPath
    $lock.template_repo = 'urbanizacion-plantilla-base'
    $lock.template_branch = 'main'
    $lock.template_commit = Get-GitHeadCommit -RepoPath $TemplateRepoPath
    $lock.last_foundation_sync = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')

    $json = $lock | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

    return $lock
}

$toolkitRoot = Resolve-RepoPath -RepoName 'urbanizacion-toolkit' -PreferredPath $ToolkitPath
$templateRoot = Resolve-RepoPath -RepoName 'urbanizacion-plantilla-base' -PreferredPath $TemplatePath

Write-Output '== Update project foundation =='
Write-Output ("Proyecto: {0}" -f $projectRoot)
Write-Output ("Toolkit: {0}" -f $toolkitRoot)
Write-Output ("Plantilla: {0}" -f $templateRoot)

if (-not $SkipToolkitSync) {
    if (-not (Test-Path -LiteralPath $syncScript)) {
        throw "No existe sync_from_toolkit.ps1 en $toolsRoot"
    }

    Write-Output '== Sync toolkit =='
    & $syncScript -ToolkitPath $toolkitRoot
}

if (-not $SkipLockRefresh) {
    Write-Output '== Refresh toolkit lock =='
    $lock = Update-ToolkitLock -Path $lockPath -ToolkitRepoPath $toolkitRoot -TemplateRepoPath $templateRoot
    Write-Output ("toolkit_commit={0}" -f $lock.toolkit_commit)
    Write-Output ("template_commit={0}" -f $lock.template_commit)
    Write-Output ("last_foundation_sync={0}" -f $lock.last_foundation_sync)
}

if (-not $SkipMachineGuard) {
    if (-not (Test-Path -LiteralPath $guardScript)) {
        throw "No existe check_machine_guard.ps1 en $toolsRoot"
    }

    Write-Output '== Machine guard =='
    & $guardScript
}

Write-Output 'PROJECT FOUNDATION OK'
