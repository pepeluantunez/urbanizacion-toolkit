Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-LongPath {
    param([string]$Path)

    if ($Path.StartsWith('\\?\')) {
        return $Path
    }

    return '\\?\' + [System.IO.Path]::GetFullPath($Path)
}

function Open-FileReadShared {
    param([string]$Path)

    return [System.IO.File]::Open((Get-LongPath $Path), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
}

function Read-Utf8Text {
    param([string]$Path)

    return [System.IO.File]::ReadAllText((Get-LongPath $Path), [System.Text.Encoding]::UTF8)
}

function Write-Utf8Text {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Get-LongPath $Path), $Content, $utf8NoBom)
}

function Expand-DocxPackage {
    param(
        [string]$DocxPath,
        [string]$Destination
    )

    $destinationLong = Get-LongPath $Destination
    if ([System.IO.Directory]::Exists($destinationLong)) {
        [System.IO.Directory]::Delete($destinationLong, $true)
    }
    [void][System.IO.Directory]::CreateDirectory($destinationLong)

    $fs = Open-FileReadShared -Path $DocxPath
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            foreach ($entry in $zip.Entries) {
                $normalizedName = $entry.FullName.Replace([char]'\', [char]'/')
                if ([string]::IsNullOrWhiteSpace($normalizedName)) {
                    continue
                }

                $targetPath = Join-Path $Destination ($normalizedName.Replace([char]'/', [char]'\'))
                if ($normalizedName.EndsWith('/')) {
                    [void][System.IO.Directory]::CreateDirectory((Get-LongPath $targetPath))
                    continue
                }

                $targetDirectory = Split-Path -Path $targetPath -Parent
                if (-not [string]::IsNullOrWhiteSpace($targetDirectory)) {
                    [void][System.IO.Directory]::CreateDirectory((Get-LongPath $targetDirectory))
                }

                $entryStream = $entry.Open()
                $fileStream = [System.IO.File]::Create((Get-LongPath $targetPath))
                try {
                    $entryStream.CopyTo($fileStream)
                }
                finally {
                    $fileStream.Dispose()
                    $entryStream.Dispose()
                }
            }
        }
        finally {
            $zip.Dispose()
        }
    }
    finally {
        $fs.Dispose()
    }
}

function Pack-DirectoryAsDocx {
    param(
        [string]$SourceDirectory,
        [string]$DestinationDocx
    )

    $destinationLong = Get-LongPath $DestinationDocx
    if ([System.IO.File]::Exists($destinationLong)) {
        [System.IO.File]::Delete($destinationLong)
    }

    $destStream = [System.IO.File]::Open($destinationLong, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($destStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $rootLong = Get-LongPath $SourceDirectory
            $rootPrefix = $rootLong.TrimEnd([char]'\')

            foreach ($file in (Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File)) {
                $fullLong = Get-LongPath $file.FullName
                $relative = $fullLong.Substring($rootPrefix.Length).TrimStart([char]'\')
                $entryName = $relative.Replace([char]'\', [char]'/')
                $entry = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
                $entryStream = $entry.Open()
                $fileStream = [System.IO.File]::Open($fullLong, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $fileStream.CopyTo($entryStream)
                }
                finally {
                    $fileStream.Dispose()
                    $entryStream.Dispose()
                }
            }
        }
        finally {
            $zip.Dispose()
        }
    }
    finally {
        $destStream.Dispose()
    }
}

function Get-MojibakePatterns {
    $replacementChar = [string][char]0xFFFD
    $replacementTriplet = ([string][char]0x00EF) + [char]0x00BF + [char]0x00BD
    return @(
        [string][char]0x00C3,
        [string][char]0x00C2,
        [string][char]0x00E2,
        $replacementChar,
        $replacementTriplet
    )
}

function Get-KnownQuestionArtifactTokens {
    return @(
        'URBANIZACI?N',
        'M?LAGA',
        '?NDICE',
        'N.?',
        'n.?',
        'ejecuci?n',
        'elaboraci?n',
        'geod?sico',
        'Geod?sico',
        'Espa?a',
        'verificaci?n',
        'Instrucci?n',
        'geom?trico',
        'Elevaci?n',
        'Inclinaci?n',
        'iluminaci?n',
        'C?ncavo'
    )
}

function Get-SuspiciousTextTokens {
    return @((Get-MojibakePatterns) + (Get-KnownQuestionArtifactTokens) | Select-Object -Unique)
}

function Get-MojibakePenalty {
    param([string]$Text)

    if ($null -eq $Text) {
        return [int]::MaxValue
    }

    $score = 0
    foreach ($pattern in (Get-MojibakePatterns)) {
        $score += ([regex]::Matches($Text, [regex]::Escape($pattern))).Count * 100
    }

    foreach ($token in (Get-KnownQuestionArtifactTokens)) {
        $score += ([regex]::Matches($Text, [regex]::Escape($token))).Count * 50
    }

    $score += ([regex]::Matches($Text, '\?')).Count * 5
    return $score
}

function Repair-KnownReplacementArtifacts {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $replacementChar = [string][char]0xFFFD
    $replacementTriplet = ([string][char]0x00EF) + [char]0x00BF + [char]0x00BD
    $ordIndicator = [string][char]0x00BA
    $enDash = [string][char]0x2013
    $aUpper = [string][char]0x00C1
    $aLower = [string][char]0x00E1
    $eLower = [string][char]0x00E9
    $iLower = [string][char]0x00ED
    $nLower = [string][char]0x00F1
    $oLower = [string][char]0x00F3
    $iUpper = [string][char]0x00CD
    $oUpper = [string][char]0x00D3
    $questionMark = '?'

    $fixed = $Text
    foreach ($bad in @($replacementChar, $replacementTriplet, $questionMark)) {
        $fixed = $fixed.Replace("N.${bad}", "N.${ordIndicator}")
        $fixed = $fixed.Replace("n.${bad}", "n.${ordIndicator}")
        $fixed = $fixed.Replace("4.${bad} REPLANTEO", "4.${enDash} REPLANTEO")
        $fixed = $fixed.Replace("${bad}rea", "${aUpper}rea")
        $fixed = $fixed.Replace("Urbanizaci${bad}n", "Urbanizaci${oLower}n")
        $fixed = $fixed.Replace("M${bad}laga", "M${aLower}laga")
        $fixed = $fixed.Replace("M${bad}LAGA", "M${aUpper}LAGA")
        $fixed = $fixed.Replace("Alineaci${bad}n", "Alineaci${oLower}n")
        $fixed = $fixed.Replace("alineaci${bad}n", "alineaci${oLower}n")
        $fixed = $fixed.Replace("Instrucci${bad}n", "Instrucci${oLower}n")
        $fixed = $fixed.Replace("instrucci${bad}n", "instrucci${oLower}n")
        $fixed = $fixed.Replace("geod${bad}sico", "geod${eLower}sico")
        $fixed = $fixed.Replace("Geod${bad}sico", "Geod${eLower}sico")
        $fixed = $fixed.Replace("Espa${bad}a", "Espa${nLower}a")
        $fixed = $fixed.Replace("Par${bad}metros", "Par${aLower}metros")
        $fixed = $fixed.Replace("par${bad}metros", "par${aLower}metros")
        $fixed = $fixed.Replace("Terrapl${bad}n", "Terrapl${eLower}n")
        $fixed = $fixed.Replace("terrapl${bad}n", "terrapl${eLower}n")
        $fixed = $fixed.Replace("Hormig${bad}n", "Hormig${oLower}n")
        $fixed = $fixed.Replace("hormig${bad}n", "hormig${oLower}n")
        $fixed = $fixed.Replace("titulaci${bad}n", "titulaci${oLower}n")
        $fixed = $fixed.Replace("descripci${bad}n", "descripci${oLower}n")
        $fixed = $fixed.Replace("ejecuci${bad}n", "ejecuci${oLower}n")
        $fixed = $fixed.Replace("elaboraci${bad}n", "elaboraci${oLower}n")
        $fixed = $fixed.Replace("verificaci${bad}n", "verificaci${oLower}n")
        $fixed = $fixed.Replace("geom${bad}trico", "geom${eLower}trico")
        $fixed = $fixed.Replace("Elevaci${bad}n", "Elevaci${oLower}n")
        $fixed = $fixed.Replace("Inclinaci${bad}n", "Inclinaci${oLower}n")
        $fixed = $fixed.Replace("iluminaci${bad}n", "iluminaci${oLower}n")
        $fixed = $fixed.Replace("C${bad}ncavo", "C${oLower}ncavo")
        $fixed = $fixed.Replace("${bad}NDICE", "${iUpper}NDICE")
        $fixed = $fixed.Replace("URBANIZACI${bad}N", "URBANIZACI${oUpper}N")
    }

    return $fixed
}

function Repair-MojibakeText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'

    function Add-Candidate {
        param(
            [System.Collections.Generic.List[string]]$List,
            [System.Collections.Generic.HashSet[string]]$Set,
            [string]$Value
        )

        if ([string]::IsNullOrEmpty($Value)) {
            return
        }

        $normalized = Repair-KnownReplacementArtifacts -Text $Value
        if ($Set.Add($normalized)) {
            [void]$List.Add($normalized)
        }
    }

    Add-Candidate -List $candidates -Set $seen -Value $Text

    if ((Get-MojibakePenalty -Text $Text) -eq 0) {
        return $candidates[0]
    }

    $current = $Text
    for ($i = 0; $i -lt 4; $i++) {
        $next = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::GetEncoding(1252).GetBytes($current))
        Add-Candidate -List $candidates -Set $seen -Value $next
        if ($next -eq $current) {
            break
        }
        $current = $next
        if ((Get-MojibakePenalty -Text $current) -eq 0) {
            break
        }
    }

    $best = $candidates[0]
    $bestScore = Get-MojibakePenalty -Text $best
    foreach ($candidate in $candidates) {
        $candidateScore = Get-MojibakePenalty -Text $candidate
        if ($candidateScore -lt $bestScore) {
            $best = $candidate
            $bestScore = $candidateScore
            continue
        }
        if ($candidateScore -eq $bestScore -and $candidate.Length -gt $best.Length) {
            $best = $candidate
        }
    }

    return $best
}

function Get-PackageTextFindings {
    param(
        [string]$PackageRoot,
        [string[]]$Extensions = @('.xml', '.rels'),
        [int]$MaxFindingsPerFile = 5
    )

    $findings = @()
    foreach ($file in (Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in $Extensions })) {
        $raw = Read-Utf8Text -Path $file.FullName
        $fileCount = 0
        foreach ($pattern in (Get-SuspiciousTextTokens)) {
            foreach ($match in [regex]::Matches($raw, '.{0,40}' + [regex]::Escape($pattern) + '.{0,80}')) {
                $snippet = $match.Value -replace '\r|\n', ' '
                $findings += [pscustomobject]@{
                    Path = $file.FullName
                    Token = $pattern
                    Snippet = $snippet.Trim()
                }
                $fileCount++
                if ($fileCount -ge $MaxFindingsPerFile) {
                    break
                }
            }
            if ($fileCount -ge $MaxFindingsPerFile) {
                break
            }
        }
    }

    return @($findings)
}

function Repair-PackageTextFiles {
    param(
        [string]$PackageRoot,
        [string[]]$Extensions = @('.xml', '.rels')
    )

    $changed = 0
    foreach ($file in (Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in $Extensions })) {
        $raw = Read-Utf8Text -Path $file.FullName
        $fixed = Repair-MojibakeText -Text $raw
        if ($fixed -ne $raw) {
            Write-Utf8Text -Path $file.FullName -Content $fixed
            $changed++
        }
    }

    return $changed
}
