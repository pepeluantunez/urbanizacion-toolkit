param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$bc3Extensions = @('.bc3', '.pzh')
$suspiciousTokens = @(
    [string][char]0x00C3,
    [string][char]0x00C2,
    [string][char]0x00E2,
    [string][char]0xFFFD
)
$placeholderTokens = @(
    'PRECIO PENDIENTE',
    'PENDIENTE DE DEFINIR',
    'POR DEFINIR',
    'REVISAR'
)
$ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)

function Resolve-Bc3Files {
    param([string[]]$InputPaths)

    $resolved = @()
    foreach ($inputPath in $InputPaths) {
        $absolute = if ([System.IO.Path]::IsPathRooted($inputPath)) {
            $inputPath
        } else {
            Join-Path (Get-Location) $inputPath
        }

        if (-not (Test-Path -LiteralPath $absolute)) {
            throw "No existe la ruta: $inputPath"
        }

        $item = Get-Item -LiteralPath $absolute
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -Recurse -File |
                Where-Object { $_.Extension.ToLowerInvariant() -in $bc3Extensions } |
                ForEach-Object { $resolved += $_.FullName }
            continue
        }

        if ($item.Extension.ToLowerInvariant() -notin $bc3Extensions) {
            throw "Extension no soportada para control BC3: $($item.FullName)"
        }

        $resolved += $item.FullName
    }

    return @($resolved | Sort-Object -Unique)
}

function Normalize-Records {
    param([string]$Raw)

    $lines = $Raw -split "`r?`n"
    $records = @()
    $nonRecordLines = @()
    $current = $null

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('~')) {
            if ($null -ne $current) {
                $records += $current
            }
            $current = $line.TrimEnd()
            continue
        }

        $nonRecordLines += $line.Trim()
        if ($null -ne $current) {
            $current = $current.TrimEnd() + ' ' + $line.Trim()
        }
    }

    if ($null -ne $current) {
        $records += $current
    }

    return [pscustomobject]@{
        Records = @($records)
        NonRecordLines = @($nonRecordLines)
    }
}

function Add-LineFindings {
    param(
        [string[]]$Lines,
        [string[]]$Tokens,
        [string]$Label
    )

    $results = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        foreach ($token in $Tokens) {
            if ($line -notlike "*$token*") { continue }
            $snippet = $line.Trim()
            if ($snippet.Length -gt 180) {
                $snippet = $snippet.Substring(0, 180)
            }
            $results += [pscustomobject]@{
                Label = $Label
                Line = $i + 1
                Token = $token
                Snippet = $snippet
            }
        }
    }
    return @($results)
}

function Test-KnownConceptReference {
    param(
        [string]$RecordType,
        [string]$ConceptCode,
        [hashtable]$ConceptCounts
    )

    if ($RecordType -in @('~E', '~V', '~K')) { return $true }
    if ($ConceptCounts.ContainsKey($ConceptCode)) { return $true }

    foreach ($part in ($ConceptCode -split '\\')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        if ($ConceptCounts.ContainsKey($part)) { return $true }
    }

    return $false
}

$files = @(Resolve-Bc3Files -InputPaths $Paths)
if ($files.Count -eq 0) {
    throw 'No se han encontrado archivos BC3 o PZH.'
}

$hasFailures = $false
foreach ($file in $files) {
    $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
    if ($extension -eq '.pzh') {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        if ($bytes.Length -eq 0) {
            $hasFailures = $true
            Write-Output "FALLO PZH: $file"
            Write-Output '  ERROR fichero vacio.'
            continue
        }

        $sampleLength = [Math]::Min($bytes.Length, 1024)
        $sample = $bytes[0..($sampleLength - 1)]
        $nulCount = @($sample | Where-Object { $_ -eq 0 }).Count
        $startsLikeTextBc3 = ($sampleLength -gt 0 -and $sample[0] -eq 0x7E)

        if (-not $startsLikeTextBc3 -or $nulCount -gt 0) {
            Write-Output "OK PZH: $file"
            Write-Output ("  Modo: binario  Tamano: {0} bytes  Validacion textual BC3 no aplicable." -f $bytes.Length)
            continue
        }
    }

    $raw = [System.IO.File]::ReadAllText($file, $ansiEncoding)
    $normalized = Normalize-Records -Raw $raw
    $records = $normalized.Records

    $conceptCounts = @{}
    $recordTypesByConcept = @{}
    $unknownConceptRecords = @()

    foreach ($record in $records) {
        $parts = $record.Split('|')
        if ($parts.Count -lt 2) { continue }

        $recordType = $parts[0]
        $conceptCode = $parts[1]
        if ([string]::IsNullOrWhiteSpace($conceptCode)) { continue }

        if (-not $recordTypesByConcept.ContainsKey($conceptCode)) {
            $recordTypesByConcept[$conceptCode] = New-Object System.Collections.Generic.HashSet[string]
        }
        [void]$recordTypesByConcept[$conceptCode].Add($recordType)

        if ($recordType -eq '~C') {
            if (-not $conceptCounts.ContainsKey($conceptCode)) {
                $conceptCounts[$conceptCode] = 0
            }
            $conceptCounts[$conceptCode]++
        }
    }

    foreach ($pair in $recordTypesByConcept.GetEnumerator()) {
        foreach ($recordType in $pair.Value) {
            if (Test-KnownConceptReference -RecordType $recordType -ConceptCode $pair.Key -ConceptCounts $conceptCounts) {
                continue
            }
            $unknownConceptRecords += [pscustomobject]@{
                Concept = $pair.Key
                RecordType = $recordType
            }
        }
    }

    $duplicateConcepts = @(
        $conceptCounts.GetEnumerator() |
            Where-Object { $_.Value -gt 1 } |
            Sort-Object Name
    )

    $missingTextConcepts = @(
        $recordTypesByConcept.GetEnumerator() |
            Where-Object { $_.Value.Contains('~C') -and -not $_.Value.Contains('~T') } |
            Sort-Object Name |
            ForEach-Object { $_.Key }
    )

    $mojibakeFindings = @(Add-LineFindings -Lines $records -Tokens $suspiciousTokens -Label 'mojibake')
    $placeholderFindings = @(Add-LineFindings -Lines $records -Tokens $placeholderTokens -Label 'placeholder')
    $questionMarkCount = ([regex]::Matches($raw, '\?')).Count

    $fileHasFailures = (
        $normalized.NonRecordLines.Count -gt 0 -or
        $duplicateConcepts.Count -gt 0 -or
        $unknownConceptRecords.Count -gt 0 -or
        $mojibakeFindings.Count -gt 0 -or
        $placeholderFindings.Count -gt 0
    )

    if ($fileHasFailures) {
        $hasFailures = $true
        Write-Output "FALLO BC3: $file"
    } else {
        Write-Output "OK BC3: $file"
    }

    Write-Output ("  Registros: {0}  Conceptos ~C: {1}  Interrogantes: {2}" -f $records.Count, $conceptCounts.Count, $questionMarkCount)

    if ($normalized.NonRecordLines.Count -gt 0) {
        Write-Output '  ERROR lineas fuera de registro BC3:'
        foreach ($line in ($normalized.NonRecordLines | Select-Object -First 10)) {
            Write-Output ("    {0}" -f $line)
        }
    }

    if ($duplicateConcepts.Count -gt 0) {
        Write-Output '  ERROR conceptos duplicados en ~C:'
        foreach ($duplicate in ($duplicateConcepts | Select-Object -First 15)) {
            Write-Output ("    {0} ({1} apariciones)" -f $duplicate.Key, $duplicate.Value)
        }
    }

    if ($unknownConceptRecords.Count -gt 0) {
        Write-Output '  ERROR registros sin concepto ~C asociado:'
        foreach ($unknown in ($unknownConceptRecords | Select-Object -First 15)) {
            Write-Output ("    {0} en concepto {1}" -f $unknown.RecordType, $unknown.Concept)
        }
    }

    if ($mojibakeFindings.Count -gt 0) {
        Write-Output '  ERROR patrones de mojibake detectados:'
        foreach ($finding in ($mojibakeFindings | Select-Object -First 15)) {
            Write-Output ("    linea {0} token='{1}' texto='{2}'" -f $finding.Line, $finding.Token, $finding.Snippet)
        }
    }

    if ($placeholderFindings.Count -gt 0) {
        Write-Output '  ERROR textos pendientes o marcadores:'
        foreach ($finding in ($placeholderFindings | Select-Object -First 15)) {
            Write-Output ("    linea {0} token='{1}' texto='{2}'" -f $finding.Line, $finding.Token, $finding.Snippet)
        }
    }

    if ($missingTextConcepts.Count -gt 0) {
        Write-Output '  AVISO conceptos con ~C pero sin ~T:'
        foreach ($concept in ($missingTextConcepts | Select-Object -First 15)) {
            Write-Output ("    {0}" -f $concept)
        }
        if ($missingTextConcepts.Count -gt 15) {
            Write-Output ("    ... {0} conceptos adicionales" -f ($missingTextConcepts.Count - 15))
        }
    }
}

if ($hasFailures) {
    throw 'Se han detectado incidencias de integridad o codificacion en BC3.'
}
