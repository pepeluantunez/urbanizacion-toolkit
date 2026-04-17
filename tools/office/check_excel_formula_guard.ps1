param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths,
    [string]$BaselineManifestPath,
    [string]$WriteManifestPath,
    [switch]$RequireFormulas
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem

$excelExtensions = @('.xlsx', '.xlsm')

function Convert-ToExtendedPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.StartsWith('\\?\')) {
        return $Path
    }

    if ($Path.StartsWith('\\')) {
        return '\\?\UNC\' + $Path.TrimStart('\')
    }

    return '\\?\' + $Path
}

function Resolve-ExistingPath {
    param([string]$InputPath)

    $absolute = if ([System.IO.Path]::IsPathRooted($InputPath)) {
        [System.IO.Path]::GetFullPath($InputPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $InputPath))
    }

    if ([System.IO.File]::Exists($absolute) -or [System.IO.Directory]::Exists($absolute)) {
        return $absolute
    }

    $extended = Convert-ToExtendedPath -Path $absolute
    if ([System.IO.File]::Exists($extended) -or [System.IO.Directory]::Exists($extended)) {
        return $extended
    }

    return $null
}

function Resolve-ExcelFiles {
    param([string[]]$InputPaths)

    $resolved = @()
    foreach ($inputPath in $InputPaths) {
        $absolute = Resolve-ExistingPath -InputPath $inputPath
        if ($null -eq $absolute) {
            throw "No existe la ruta: $inputPath"
        }

        $item = Get-Item -LiteralPath $absolute
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -Recurse -File |
                Where-Object { $_.Extension.ToLowerInvariant() -in $excelExtensions } |
                ForEach-Object { $resolved += $_.FullName }
            continue
        }

        if ($item.Extension.ToLowerInvariant() -notin $excelExtensions) {
            throw "Extension no soportada para control de formulas: $($item.FullName)"
        }

        $resolved += $item.FullName
    }

    return @($resolved | Sort-Object -Unique)
}

function Read-ZipEntryText {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)

    $stream = $Entry.Open()
    try {
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        try {
            return $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Normalize-ZipPath {
    param([string]$Path)
    $x = $Path -replace '\\', '/'
    while ($x.StartsWith('../')) {
        $x = $x.Substring(3)
    }
    if (-not $x.StartsWith('xl/')) {
        $x = 'xl/' + $x.TrimStart('/')
    }
    return $x
}

function Get-SheetNameMap {
    param([System.IO.Compression.ZipArchive]$Archive)

    $relsMap = @{}
    $relsEntry = $Archive.GetEntry('xl/_rels/workbook.xml.rels')
    if ($null -ne $relsEntry) {
        $relsXml = Read-ZipEntryText -Entry $relsEntry
        foreach ($rel in [regex]::Matches($relsXml, '<Relationship\b[^>]*>')) {
            $id = [regex]::Match($rel.Value, 'Id="([^"]+)"').Groups[1].Value
            $target = [regex]::Match($rel.Value, 'Target="([^"]+)"').Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($id) -and -not [string]::IsNullOrWhiteSpace($target)) {
                $relsMap[$id] = Normalize-ZipPath -Path $target
            }
        }
    }

    $sheetNameByXmlPath = @{}
    $workbookEntry = $Archive.GetEntry('xl/workbook.xml')
    if ($null -ne $workbookEntry) {
        $workbookXml = Read-ZipEntryText -Entry $workbookEntry
        foreach ($sheet in [regex]::Matches($workbookXml, '<sheet\b[^>]*>')) {
            $name = [regex]::Match($sheet.Value, 'name="([^"]+)"').Groups[1].Value
            $rid = [regex]::Match($sheet.Value, 'r:id="([^"]+)"').Groups[1].Value
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($rid)) { continue }
            if (-not $relsMap.ContainsKey($rid)) { continue }
            $sheetNameByXmlPath[$relsMap[$rid]] = $name
        }
    }

    return $sheetNameByXmlPath
}

function Get-FormulaInventory {
    param([string]$FilePath)

    $archive = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
    try {
        $sheetNameMap = Get-SheetNameMap -Archive $archive
        $rows = @()

        foreach ($entry in ($archive.Entries | Where-Object { $_.FullName -match '^xl/worksheets/.*\.xml$' } | Sort-Object FullName)) {
            $xml = Read-ZipEntryText -Entry $entry
            $formulaCount = [regex]::Matches($xml, '<f(?:\s|>)').Count
            $cellCount = [regex]::Matches($xml, '<c(?:\s|>)').Count
            $sheetName = if ($sheetNameMap.ContainsKey($entry.FullName)) { $sheetNameMap[$entry.FullName] } else { [System.IO.Path]::GetFileNameWithoutExtension($entry.FullName) }

            $rows += [pscustomobject]@{
                SheetXmlPath = $entry.FullName
                SheetName = $sheetName
                FormulaCount = $formulaCount
                CellCount = $cellCount
            }
        }

        return [pscustomobject]@{
            Sheets = @($rows)
            TotalFormulas = (($rows | Measure-Object -Property FormulaCount -Sum).Sum)
        }
    } finally {
        $archive.Dispose()
    }
}

function Get-RelativeStablePath {
    param([string]$FullPath)

    $cwd = (Get-Location).Path.TrimEnd('\')
    $full = if ($FullPath.StartsWith('\\?\UNC\')) {
        '\\' + $FullPath.Substring(8)
    } elseif ($FullPath.StartsWith('\\?\')) {
        $FullPath.Substring(4)
    } else {
        $FullPath
    }
    $full = [System.IO.Path]::GetFullPath($full)
    if ($full.StartsWith($cwd, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($cwd.Length).TrimStart('\')
    }
    return $full
}

function Build-Manifest {
    param([string[]]$Files)

    $manifest = @()
    foreach ($file in $Files) {
        $inventory = Get-FormulaInventory -FilePath $file
        $manifest += [pscustomobject]@{
            File = Get-RelativeStablePath -FullPath $file
            FullPath = $file
            TotalFormulas = [int]$inventory.TotalFormulas
            Sheets = @($inventory.Sheets)
        }
    }
    return @($manifest)
}

$files = @(Resolve-ExcelFiles -InputPaths $Paths)
if ($files.Count -eq 0) {
    throw 'No se han encontrado Excels compatibles.'
}

$currentManifest = Build-Manifest -Files $files

foreach ($item in $currentManifest) {
    Write-Output ("EXCEL: {0}" -f $item.File)
    Write-Output ("  Formulas totales: {0}" -f $item.TotalFormulas)
    foreach ($sheet in $item.Sheets) {
        Write-Output ("  - {0} ({1}) formulas={2} celdas={3}" -f $sheet.SheetName, $sheet.SheetXmlPath, $sheet.FormulaCount, $sheet.CellCount)
    }
}

$hasFailures = $false
if ($RequireFormulas) {
    foreach ($item in $currentManifest) {
        if ($item.TotalFormulas -le 0) {
            $hasFailures = $true
            Write-Output ("ERROR: sin formulas en {0}" -f $item.File)
        }
    }
}

if ($BaselineManifestPath) {
    $baselinePath = if ([System.IO.Path]::IsPathRooted($BaselineManifestPath)) { $BaselineManifestPath } else { Join-Path (Get-Location) $BaselineManifestPath }
    if (-not (Test-Path -LiteralPath $baselinePath)) {
        throw "No existe manifest base: $BaselineManifestPath"
    }

    $baselineManifest = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
    $baseIndex = @{}
    foreach ($file in @($baselineManifest)) {
        foreach ($sheet in @($file.Sheets)) {
            $key = "{0}|{1}" -f $file.File, $sheet.SheetXmlPath
            $baseIndex[$key] = [int]$sheet.FormulaCount
        }
    }

    $currentIndex = @{}
    foreach ($file in $currentManifest) {
        foreach ($sheet in @($file.Sheets)) {
            $key = "{0}|{1}" -f $file.File, $sheet.SheetXmlPath
            $currentIndex[$key] = [int]$sheet.FormulaCount
            if ($baseIndex.ContainsKey($key) -and $sheet.FormulaCount -lt $baseIndex[$key]) {
                $hasFailures = $true
                Write-Output ("ERROR: formulas reducidas en {0} / {1}: base={2} actual={3}" -f $file.File, $sheet.SheetName, $baseIndex[$key], $sheet.FormulaCount)
            }
        }
    }

    foreach ($key in $baseIndex.Keys) {
        if (-not $currentIndex.ContainsKey($key)) {
            $hasFailures = $true
            Write-Output ("ERROR: hoja no localizada respecto a base: {0}" -f $key)
        }
    }
}

if ($WriteManifestPath) {
    $manifestPath = if ([System.IO.Path]::IsPathRooted($WriteManifestPath)) { $WriteManifestPath } else { Join-Path (Get-Location) $WriteManifestPath }
    $parent = Split-Path -Parent $manifestPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $json = $currentManifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($manifestPath, $json, [System.Text.Encoding]::UTF8)
    Write-Output ("Manifest guardado: {0}" -f $manifestPath)
}

if ($hasFailures) {
    throw 'Control de formulas Excel fallido.'
}
