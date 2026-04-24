param(
  [Parameter(Mandatory = $true)]
  [string]$TargetPath,

  [switch]$SkipExisting
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
    if (-not $SkipExisting) {
      Copy-Item -Path (Join-Path $sourcePath '*') -Destination $targetPath -Recurse -Force
      continue
    }

    foreach ($sourceFile in (Get-ChildItem -LiteralPath $sourcePath -Recurse -File)) {
      $relative = $sourceFile.FullName.Substring($sourcePath.Length).TrimStart('\')
      $targetFile = Join-Path $targetPath $relative
      $targetDir = Split-Path -Parent $targetFile
      if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
      }
      if (-not (Test-Path -LiteralPath $targetFile)) {
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetFile -Force
      }
    }

    foreach ($sourceDir in (Get-ChildItem -LiteralPath $sourcePath -Recurse -Directory)) {
      $relativeDir = $sourceDir.FullName.Substring($sourcePath.Length).TrimStart('\')
      $targetDir = Join-Path $targetPath $relativeDir
      if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
      }
    }
  }
}

if ($SkipExisting) {
  Write-Host "Toolkit instalado en $resolvedTarget sin sobrescribir ficheros existentes"
}
else {
  Write-Host "Toolkit instalado en $resolvedTarget"
}
