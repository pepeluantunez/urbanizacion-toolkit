[CmdletBinding()]
param(
    [string]$ContractPath = '.\CONFIG\repo_contract.json',
    [string]$AlignmentManifestPath = '.\CONFIG\ecosystem_alignment_manifest.json',
    [switch]$SkipRepoContract,
    [switch]$SkipEcosystemAlignment
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $toolsRoot
$repoContractChecker = Join-Path $toolsRoot 'check_repo_contract.ps1'
$alignmentChecker = Join-Path $toolsRoot 'check_ecosystem_alignment.ps1'

Write-Output '== Guarda de maquina =='
Write-Output ("Proyecto: {0}" -f $projectRoot)

if (-not $SkipRepoContract) {
    if (-not (Test-Path -LiteralPath $repoContractChecker)) {
        throw "No existe check_repo_contract.ps1 en $toolsRoot"
    }

    Write-Output '== Contrato de repo =='
    & $repoContractChecker -ContractPath $ContractPath -RootPath $projectRoot
}

if (-not $SkipEcosystemAlignment) {
    if (-not (Test-Path -LiteralPath $alignmentChecker)) {
        throw "No existe check_ecosystem_alignment.ps1 en $toolsRoot"
    }

    Write-Output '== Alineacion del ecosistema =='
    & $alignmentChecker -ManifestPath $AlignmentManifestPath -FailOnDrift
}

Write-Output 'MACHINE GUARD OK'
