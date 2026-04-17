param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $true)]
    [string]$DerivedPath,
    [string]$MappingPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$encoding = [System.Text.Encoding]::GetEncoding(1252)

function Get-Bc3Lines {
    param([string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    return [System.IO.File]::ReadAllLines($resolved, $encoding)
}

function Get-RecordCounts {
    param([string[]]$Lines)

    $counts = [ordered]@{}
    foreach ($type in @("C", "D", "T", "M", "O", "A", "E", "V", "K")) {
        $counts[$type] = @($Lines | Where-Object { $_.StartsWith("~$type|") }).Count
    }
    return $counts
}

function Import-MappingRows {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    return @((Import-Csv -LiteralPath $Path -Encoding UTF8))
}

function Rewrite-DecompositionBody {
    param(
        [string]$Body,
        [hashtable]$ReverseMap
    )

    $parts = $Body -split '\\'
    for ($i = 0; $i -le ($parts.Length - 3); $i += 3) {
        if ($parts[$i] -and $ReverseMap.ContainsKey($parts[$i])) {
            $parts[$i] = $ReverseMap[$parts[$i]]
        }
    }
    return ($parts -join '\')
}

function Rewrite-MeasurementKey {
    param(
        [string]$CompositeKey,
        [hashtable]$ReverseMap
    )

    $segments = $CompositeKey -split '\\', 2
    if ($segments.Length -ge 1 -and $ReverseMap.ContainsKey($segments[0])) {
        $segments[0] = $ReverseMap[$segments[0]]
    }
    if ($segments.Length -eq 2 -and $ReverseMap.ContainsKey($segments[1])) {
        $segments[1] = $ReverseMap[$segments[1]]
    }
    return ($segments -join '\')
}

function Normalize-DerivedLine {
    param(
        [string]$Line,
        [hashtable]$ReverseMap
    )

    if (-not $Line.StartsWith("~")) {
        return $Line
    }

    $parts = $Line.Split("|")
    if ($parts.Length -lt 2) {
        return $Line
    }

    switch -Regex ($parts[0]) {
        '^~C$' {
            if ($ReverseMap.ContainsKey($parts[1])) {
                $parts[1] = $ReverseMap[$parts[1]]
            }
            return ($parts -join "|")
        }
        '^~D$' {
            if ($ReverseMap.ContainsKey($parts[1])) {
                $parts[1] = $ReverseMap[$parts[1]]
            }
            if ($parts.Length -ge 3) {
                $parts[2] = Rewrite-DecompositionBody -Body $parts[2] -ReverseMap $ReverseMap
            }
            return ($parts -join "|")
        }
        '^~T$' {
            if ($ReverseMap.ContainsKey($parts[1])) {
                $parts[1] = $ReverseMap[$parts[1]]
            }
            return ($parts -join "|")
        }
        '^~M$' {
            if ($parts.Length -ge 2) {
                $parts[1] = Rewrite-MeasurementKey -CompositeKey $parts[1] -ReverseMap $ReverseMap
            }
            return ($parts -join "|")
        }
        '^~O$' {
            if ($ReverseMap.ContainsKey($parts[1])) {
                $parts[1] = $ReverseMap[$parts[1]]
            }
            return ($parts -join "|")
        }
        '^~A$' {
            if ($ReverseMap.ContainsKey($parts[1])) {
                $parts[1] = $ReverseMap[$parts[1]]
            }
            return ($parts -join "|")
        }
        default {
            return $Line
        }
    }
}

$sourceFullPath = (Resolve-Path -LiteralPath $SourcePath).Path
$derivedFullPath = (Resolve-Path -LiteralPath $DerivedPath).Path
$sourceLines = Get-Bc3Lines -Path $sourceFullPath
$derivedLines = Get-Bc3Lines -Path $derivedFullPath
$sourceCounts = Get-RecordCounts -Lines $sourceLines
$derivedCounts = Get-RecordCounts -Lines $derivedLines
$mappingRows = @(Import-MappingRows -Path $MappingPath)
$sourceHash = (Get-FileHash -LiteralPath $sourceFullPath -Algorithm SHA256).Hash
$derivedHash = (Get-FileHash -LiteralPath $derivedFullPath -Algorithm SHA256).Hash

$reverseMap = @{}
$mode = "exact_copy"
foreach ($row in $mappingRows) {
    if ($row.ImportCode -and $row.ImportCode -ne "*") {
        $reverseMap[$row.ImportCode] = $row.OriginalCode
    }
    if ($row.Mode) {
        $mode = [string]$row.Mode
    }
}

$normalizedDerivedLines =
    if (@($mappingRows).Count -gt 0 -and $mode -ne "exact_copy") {
        foreach ($line in $derivedLines) {
            Normalize-DerivedLine -Line $line -ReverseMap $reverseMap
        }
    }
    else {
        $derivedLines
    }

$diffs = New-Object System.Collections.Generic.List[string]

if ($sourceLines.Length -ne $derivedLines.Length) {
    $diffs.Add("Numero de lineas distinto: origen=$($sourceLines.Length), derivado=$($derivedLines.Length)") | Out-Null
}

foreach ($type in $sourceCounts.Keys) {
    if ($sourceCounts[$type] -ne $derivedCounts[$type]) {
        $diffs.Add("Conteo distinto en registro ${type}: origen=$($sourceCounts[$type]), derivado=$($derivedCounts[$type])") | Out-Null
    }
}

if (-not ($mode -eq "exact_copy" -and $sourceHash -eq $derivedHash)) {
    for ($i = 0; $i -lt [Math]::Min($sourceLines.Length, $normalizedDerivedLines.Length); $i++) {
        if ($sourceLines[$i] -ne $normalizedDerivedLines[$i]) {
            $diffs.Add("Diferencia normalizada en linea $($i + 1).") | Out-Null
            break
        }
    }
}

if ($mode -eq "exact_copy" -and $sourceHash -ne $derivedHash) {
    $diffs.Add("Hash SHA256 distinto entre origen y derivado en modo exact_copy.") | Out-Null
}

if (@($diffs).Count -gt 0) {
    Write-Output "FALLO IMPORT PARITY: $derivedFullPath"
    Write-Output "  Origen:  $sourceFullPath"
    if (-not [string]::IsNullOrWhiteSpace($MappingPath)) {
        Write-Output "  Mapping: $MappingPath"
    }
    Write-Output "  Modo: $mode"
    Write-Output "  SHA256 origen:  $sourceHash"
    Write-Output "  SHA256 derivado: $derivedHash"
    foreach ($item in $diffs) {
        Write-Output "  $item"
    }
    exit 1
}

Write-Output "OK IMPORT PARITY: $derivedFullPath"
Write-Output "  Origen:  $sourceFullPath"
if (-not [string]::IsNullOrWhiteSpace($MappingPath)) {
    Write-Output "  Mapping: $MappingPath"
}
Write-Output "  Modo: $mode"
Write-Output "  SHA256 derivado: $derivedHash"
foreach ($type in $sourceCounts.Keys) {
    Write-Output ("  Conteo {0}: origen={1} derivado={2}" -f $type, $sourceCounts[$type], $derivedCounts[$type])
}
