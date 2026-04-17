$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $root 'catalog\catalog.json'
$markdownPath = Join-Path $root 'catalog\CATALOG.md'
$items = Get-Content -Raw $catalogPath | ConvertFrom-Json

$lines = @(
  '# Catalogo Toolkit',
  '',
  '| id | kind | domain | safety | path | summary |',
  '|---|---|---|---|---|---|'
)

foreach ($item in $items) {
  $lines += "| $($item.id) | $($item.kind) | $($item.domain) | $($item.safety) | ``$($item.path)`` | $($item.summary) |"
}

Set-Content -Path $markdownPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
Write-Host "Catalogo sincronizado en $markdownPath"
