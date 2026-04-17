param(
  [Parameter(Mandatory = $true)]
  [string]$TargetPath
)

$ErrorActionPreference = 'Stop'

$toolkitRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $TargetPath)) {
  New-Item -ItemType Directory -Force -Path $TargetPath | Out-Null
}
$resolvedTarget = (Resolve-Path -LiteralPath $TargetPath).Path

$copies = @(
  @{ Source = 'tools'; Target = 'tools' },
  @{ Source = 'scripts'; Target = 'scripts' },
  @{ Source = 'catalog'; Target = 'catalog' }
)

foreach ($copy in $copies) {
  $sourcePath = Join-Path $toolkitRoot $copy.Source
  $targetPath = Join-Path $resolvedTarget $copy.Target
  if (Test-Path $sourcePath) {
    New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
    Copy-Item -Path (Join-Path $sourcePath '*') -Destination $targetPath -Recurse -Force
  }
}

Write-Host "Toolkit instalado en $resolvedTarget"
