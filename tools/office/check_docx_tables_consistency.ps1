param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths,
    [string]$ExpectedFont = 'Montserrat',
    [bool]$EnforceFont = $true,
    [bool]$RequireTableCaption = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem

$docExtensions = @('.docx', '.docm')

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

function Resolve-DocFiles {
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
                Where-Object { $_.Extension.ToLowerInvariant() -in $docExtensions } |
                ForEach-Object { $resolved += $_.FullName }
            continue
        }

        if ($item.Extension.ToLowerInvariant() -notin $docExtensions) {
            throw "Extension no soportada para control DOCX: $($item.FullName)"
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

function Get-ParagraphText {
    param([string]$ParagraphXml)

    $parts = @()
    foreach ($m in [regex]::Matches($ParagraphXml, '<w:t(?:\s[^>]*)?>(.*?)</w:t>')) {
        $txt = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
        if (-not [string]::IsNullOrWhiteSpace($txt)) {
            $parts += $txt.Trim()
        }
    }
    return ($parts -join ' ').Trim()
}

function Get-ExplicitFontValues {
    param([string]$Xml)

    $fonts = @()
    foreach ($fontTag in [regex]::Matches($Xml, '<w:rFonts\b[^>]*>')) {
        foreach ($attr in [regex]::Matches($fontTag.Value, 'w:(?:ascii|hAnsi|eastAsia|cs)="([^"]+)"')) {
            $val = $attr.Groups[1].Value.Trim()
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $fonts += $val
            }
        }
    }
    return @($fonts | Sort-Object -Unique)
}

function Test-CaptionPattern {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $m = [regex]::Match($Text, '^\s*Tabla\s*(?:N[ºo.]?\s*)?(\d+)(?:[.\-:)]\s*|\s+)(.+)$', 'IgnoreCase')
    if (-not $m.Success) { return $false }
    $description = $m.Groups[2].Value.Trim()
    return ($description.Length -ge 6)
}

$files = @(Resolve-DocFiles -InputPaths $Paths)
if ($files.Count -eq 0) {
    throw 'No se han encontrado DOCX o DOCM compatibles.'
}

$hasFailures = $false
foreach ($file in $files) {
    $archive = [System.IO.Compression.ZipFile]::OpenRead($file)
    try {
        $docEntry = $archive.GetEntry('word/document.xml')
        if ($null -eq $docEntry) {
            throw "No existe word/document.xml en $file"
        }

        $documentXml = Read-ZipEntryText -Entry $docEntry
        $stylesXml = ''
        $stylesEntry = $archive.GetEntry('word/styles.xml')
        if ($null -ne $stylesEntry) {
            $stylesXml = Read-ZipEntryText -Entry $stylesEntry
        }
    } finally {
        $archive.Dispose()
    }

    $bodyMatch = [regex]::Match($documentXml, '<w:body\b[\s\S]*?</w:body>')
    $bodyXml = if ($bodyMatch.Success) { $bodyMatch.Value } else { $documentXml }
    $nodes = [regex]::Matches($bodyXml, '<w:p\b[\s\S]*?</w:p>|<w:tbl\b[\s\S]*?</w:tbl>')

    $sequence = @()
    foreach ($node in $nodes) {
        if ($node.Value.StartsWith('<w:p')) {
            $sequence += [pscustomobject]@{
                Type = 'p'
                Xml = $node.Value
                Text = Get-ParagraphText -ParagraphXml $node.Value
            }
        } else {
            $sequence += [pscustomobject]@{
                Type = 'tbl'
                Xml = $node.Value
                Text = ''
            }
        }
    }

    $tableCount = 0
    $fileFindings = @()
    for ($i = 0; $i -lt $sequence.Count; $i++) {
        $node = $sequence[$i]
        if ($node.Type -ne 'tbl') { continue }
        $tableCount++

        $tableTextMatches = [regex]::Matches($node.Xml, '<w:t(?:\s[^>]*)?>(.*?)</w:t>')
        $visibleTexts = @()
        foreach ($t in $tableTextMatches) {
            $txt = [System.Net.WebUtility]::HtmlDecode($t.Groups[1].Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($txt)) {
                $visibleTexts += $txt
            }
        }
        if ($visibleTexts.Count -eq 0) {
            $fileFindings += "Tabla $tableCount sin texto visible."
        }

        $hiddenCount = [regex]::Matches($node.Xml, '<w:vanish(?:\s|/|>)').Count
        if ($hiddenCount -gt 0) {
            $fileFindings += "Tabla $tableCount contiene texto oculto (w:vanish)."
        }

        if ($RequireTableCaption) {
            $caption = ''
            for ($j = $i - 1; $j -ge 0; $j--) {
                if ($sequence[$j].Type -ne 'p') { continue }
                if ([string]::IsNullOrWhiteSpace($sequence[$j].Text)) { continue }
                $caption = $sequence[$j].Text
                break
            }
            if (-not (Test-CaptionPattern -Text $caption)) {
                for ($j = $i + 1; $j -lt $sequence.Count; $j++) {
                    if ($sequence[$j].Type -ne 'p') { continue }
                    if ([string]::IsNullOrWhiteSpace($sequence[$j].Text)) { continue }
                    $caption = $sequence[$j].Text
                    break
                }
            }
            if (-not (Test-CaptionPattern -Text $caption)) {
                $fileFindings += "Tabla $tableCount sin caption valido tipo 'Tabla N. Descripcion'."
            }
        }

        if ($EnforceFont) {
            $fonts = Get-ExplicitFontValues -Xml $node.Xml
            $mismatches = @(
                $fonts | Where-Object {
                    $_ -and
                    $_ -notlike '+*' -and
                    $_ -ne $ExpectedFont
                }
            )
            if ($mismatches.Count -gt 0) {
                $fileFindings += ("Tabla $tableCount con fuentes distintas a {0}: {1}" -f $ExpectedFont, (($mismatches | Sort-Object -Unique) -join ', '))
            }
        }
    }

    if ($EnforceFont -and -not [string]::IsNullOrWhiteSpace($stylesXml)) {
        $styleFonts = Get-ExplicitFontValues -Xml $stylesXml
        $styleMismatches = @(
            $styleFonts | Where-Object {
                $_ -and
                $_ -notlike '+*' -and
                $_ -ne $ExpectedFont
            }
        )
        if ($styleMismatches.Count -gt 0) {
            $fileFindings += ("Estilos con fuentes distintas a {0}: {1}" -f $ExpectedFont, (($styleMismatches | Sort-Object -Unique) -join ', '))
        }
    }

    if ($fileFindings.Count -eq 0) {
        Write-Output ("OK DOCX: {0} (tablas: {1})" -f $file, $tableCount)
        continue
    }

    $hasFailures = $true
    Write-Output ("FALLO DOCX: {0} (tablas: {1})" -f $file, $tableCount)
    foreach ($finding in $fileFindings) {
        Write-Output ("  - {0}" -f $finding)
    }
}

if ($hasFailures) {
    throw 'Control DOCX de tablas/coherencia visual fallido.'
}
