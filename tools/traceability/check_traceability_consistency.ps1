param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths,

    [string[]]$Needles,

    [string[]]$RequiredCategories,

    [string]$OutMarkdownPath,

    [int]$MaxAutoNeedles = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem

$supportedExtensions = @(
    '.bc3',
    '.docx', '.docm',
    '.xlsx', '.xlsm',
    '.csv', '.txt', '.md', '.html', '.htm', '.xml'
)

$stopTokens = @(
    'XML', 'WORD', 'DOCX', 'DOCM', 'XLSX', 'XLSM', 'HTML', 'TEXT', 'TABLE',
    'TRUE', 'FALSE', 'SPAN', 'STYLE', 'SHEET', 'PRINT', 'WIDTH', 'HEIGHT',
    'CELL', 'ROW', 'DATA', 'WORKBOOK', 'WORKSHEET', 'RELATIONSHIP', 'SHAREDSTRINGS',
    'CONTENT', 'TYPES', 'OFFICE', 'MICROSOFT', 'DRAWING'
)

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

function Resolve-TraceFiles {
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
                Where-Object { $_.Extension.ToLowerInvariant() -in $supportedExtensions } |
                ForEach-Object { $resolved += $_.FullName }
            continue
        }

        if ($item.Extension.ToLowerInvariant() -notin $supportedExtensions) {
            throw "Extension no soportada para trazabilidad: $($item.FullName)"
        }

        $resolved += $item.FullName
    }

    return @($resolved | Sort-Object -Unique)
}

function Get-Category {
    param([string]$Extension)

    switch ($Extension.ToLowerInvariant()) {
        '.bc3' { return 'BC3' }
        '.xlsx' { return 'Excel' }
        '.xlsm' { return 'Excel' }
        '.docx' { return 'Word' }
        '.docm' { return 'Word' }
        default { return 'Text' }
    }
}

function Read-LooseText {
    param([string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    } catch {
        return Get-Content -LiteralPath $Path -Raw -Encoding Default
    }
}

function Get-ZipEntryText {
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

function Get-OfficeVisibleText {
    param([string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $regex = switch ($extension) {
        '.docx' { '<w:t[^>]*>(.*?)</w:t>' }
        '.docm' { '<w:t[^>]*>(.*?)</w:t>' }
        '.xlsx' { '<t[^>]*>(.*?)</t>' }
        '.xlsm' { '<t[^>]*>(.*?)</t>' }
        default { throw "Extension Office no soportada: $Path" }
    }

    $texts = @()
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -notmatch '^(word|xl)/.*\.xml$') { continue }
            $xml = Get-ZipEntryText -Entry $entry
            foreach ($match in [regex]::Matches($xml, $regex)) {
                $decoded = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
                if (-not [string]::IsNullOrWhiteSpace($decoded)) {
                    $texts += $decoded
                }
            }
        }
    } finally {
        $archive.Dispose()
    }

    return ($texts -join ' ')
}

function Get-SearchText {
    param([string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -in @('.docx', '.docm', '.xlsx', '.xlsm')) {
        return Get-OfficeVisibleText -Path $Path
    }

    return Read-LooseText -Path $Path
}

function Normalize-Text {
    param([string]$Text)

    $normalized = [System.Net.WebUtility]::HtmlDecode($Text)
    $normalized = $normalized -replace '\s+', ' '
    return $normalized.Trim()
}

function Get-AutoNeedles {
    param(
        [object[]]$FileContexts,
        [int]$Limit
    )

    $bc3Candidates = @{}
    foreach ($context in ($FileContexts | Where-Object { $_.Category -eq 'BC3' })) {
        foreach ($match in [regex]::Matches($context.NormalizedText, '(?:^|\s)~C\|([^|\s]+)\|')) {
            $token = $match.Groups[1].Value.Trim().ToUpperInvariant()
            if ($token.Length -lt 3 -or $token.Length -gt 40) { continue }
            if ($token -match '^[\d.]+$') { continue }
            if ($token.StartsWith('%')) { continue }
            if ($token -notmatch '[\d._#-]' -and $token.Length -lt 8) { continue }
            $bc3Candidates[$token] = $true
        }
    }

    if ($bc3Candidates.Count -gt 0) {
        $rankedBc3 = @(
            foreach ($token in $bc3Candidates.Keys) {
                $categories = New-Object 'System.Collections.Generic.HashSet[string]'
                $fileHits = 0
                foreach ($context in $FileContexts) {
                    if ($context.NormalizedText.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                        continue
                    }
                    $fileHits++
                    [void]$categories.Add($context.Category)
                }

                if ($categories.Count -lt 2) { continue }

                [pscustomobject]@{
                    Token = $token
                    CategoryCount = $categories.Count
                    FileHits = $fileHits
                }
            }
        )

        if ($rankedBc3.Count -gt 0) {
            return @(
                $rankedBc3 |
                    Sort-Object { -1 * $_.CategoryCount }, { -1 * $_.FileHits }, Token |
                    Select-Object -First $Limit -ExpandProperty Token
            )
        }
    }

    $candidates = @{}
    foreach ($context in $FileContexts) {
        foreach ($match in [regex]::Matches($context.NormalizedText, '\b(?:MCG-\d+\.\d+#|[A-Z]{2,}[A-Z0-9._/-]*\d+[A-Z0-9._/-]*|[A-Z]{2,}(?:[._/-][A-Z0-9]+)+|CP\d+|DN\d+)\b')) {
            $token = $match.Value.Trim().ToUpperInvariant()
            if ($token.Length -lt 3 -or $token.Length -gt 32) { continue }
            if ($token -match '^\d+$') { continue }
            if ($stopTokens -contains $token) { continue }

            if (-not $candidates.ContainsKey($token)) {
                $candidates[$token] = New-Object System.Collections.Generic.HashSet[string]
            }
            [void]$candidates[$token].Add($context.Path)
        }
    }

    return @(
        $candidates.GetEnumerator() |
            Where-Object { $_.Value.Count -ge 2 } |
            Sort-Object { -1 * $_.Value.Count }, Name |
            Select-Object -First $Limit |
            ForEach-Object { $_.Key }
    )
}

function Get-Snippet {
    param(
        [string]$Text,
        [string]$Needle
    )

    $index = $Text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -lt 0) { return '' }

    $start = [Math]::Max(0, $index - 45)
    $length = [Math]::Min(120, $Text.Length - $start)
    $snippet = $Text.Substring($start, $length)
    $snippet = $snippet -replace '\s+', ' '
    return $snippet.Trim()
}

$files = @(Resolve-TraceFiles -InputPaths $Paths)
if ($files.Count -eq 0) {
    throw 'No se han encontrado archivos compatibles para trazabilidad.'
}

$contexts = foreach ($file in $files) {
    $text = Get-SearchText -Path $file
    [pscustomobject]@{
        Path = $file
        Category = Get-Category -Extension ([System.IO.Path]::GetExtension($file))
        NormalizedText = Normalize-Text -Text $text
    }
}

$availableCategories = @($contexts | ForEach-Object { $_.Category } | Sort-Object -Unique)
$effectiveRequiredCategories = if ($RequiredCategories -and @($RequiredCategories).Count -gt 0) {
    @($RequiredCategories | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
} else {
    @($availableCategories)
}
$effectiveRequiredCategories = @($effectiveRequiredCategories | Where-Object { $_ -in $availableCategories } | Sort-Object -Unique)
if ($effectiveRequiredCategories.Count -eq 0) {
    $effectiveRequiredCategories = @($availableCategories)
}

$effectiveNeedles = if ($Needles -and @($Needles).Count -gt 0) {
    @($Needles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
} else {
    Get-AutoNeedles -FileContexts $contexts -Limit $MaxAutoNeedles
}
$effectiveNeedles = @($effectiveNeedles)

if (@($effectiveNeedles).Count -eq 0) {
    throw 'No se han encontrado anclas de trazabilidad. Usa -Needles para forzar conceptos concretos.'
}

$results = @()
foreach ($needle in $effectiveNeedles) {
    $hits = @()
    foreach ($context in $contexts) {
        if ($context.NormalizedText.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }

        $hits += [pscustomobject]@{
            Path = $context.Path
            Category = $context.Category
            Snippet = Get-Snippet -Text $context.NormalizedText -Needle $needle
        }
    }

    $hits = @($hits)
    $hitCategories = if (@($hits).Count -gt 0) {
        @($hits | ForEach-Object { $_.Category } | Sort-Object -Unique)
    } else {
        @()
    }
    $missingCategories = @($effectiveRequiredCategories | Where-Object { $_ -notin $hitCategories })
    $status = if (@($hitCategories).Count -eq 0) {
        'SIN_HUELLAS'
    } elseif (@($missingCategories).Count -eq 0) {
        'OK'
    } elseif (@($hitCategories).Count -ge 2) {
        'INCOMPLETA'
    } else {
        'DEBIL'
    }

    $results += [pscustomobject]@{
        Needle = $needle
        Status = $status
        Categories = $hitCategories
        MissingCategories = $missingCategories
        Hits = @($hits)
    }
}

$reportLines = @()
$reportLines += '# Revision de trazabilidad transversal'
$reportLines += ''
$reportLines += ("Archivos revisados: {0}" -f @($contexts).Count)
$reportLines += ("Categorias presentes: {0}" -f ($availableCategories -join ', '))
$reportLines += ("Categorias requeridas: {0}" -f ($effectiveRequiredCategories -join ', '))
$reportLines += ("Anclas revisadas: {0}" -f @($results).Count)
$reportLines += ''

$hasFailures = $false
foreach ($result in $results) {
    if ($result.Status -ne 'OK') { $hasFailures = $true }

    $line = "- [{0}] {1} :: categorias={2}" -f $result.Status, $result.Needle, ($result.Categories -join ', ')
    if (@($result.MissingCategories).Count -gt 0) {
        $line += " :: faltan={0}" -f ($result.MissingCategories -join ', ')
    }
    $reportLines += $line

    foreach ($hit in ($result.Hits | Select-Object -First 4)) {
        $reportLines += ("  - {0} :: {1}" -f $hit.Category, $hit.Path)
        if ($hit.Snippet) {
            $reportLines += ("    {0}" -f $hit.Snippet)
        }
    }
}

$report = $reportLines -join [Environment]::NewLine
Write-Output $report

if ($OutMarkdownPath) {
    $target = if ([System.IO.Path]::IsPathRooted($OutMarkdownPath)) {
        $OutMarkdownPath
    } else {
        Join-Path (Get-Location) $OutMarkdownPath
    }
    [System.IO.File]::WriteAllText($target, $report, [System.Text.Encoding]::UTF8)
    Write-Output ''
    Write-Output ("Informe guardado en: {0}" -f $target)
}

if ($hasFailures) {
    throw 'Se han detectado huecos de trazabilidad o coherencia incompleta.'
}
