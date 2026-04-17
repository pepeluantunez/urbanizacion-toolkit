param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem

$officeExtensions = @('.docx', '.docm', '.xlsx', '.xlsm', '.pptx', '.pptm')
$badLeadChars = @(
    [char]0x00C3,
    [char]0x00C2,
    [char]0x00E2,
    [char]0xFFFD
)

$knownQuestionTokens = @(
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
    }
    else {
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

function Resolve-OfficeFiles {
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
                Where-Object { $_.Extension.ToLowerInvariant() -in $officeExtensions } |
                ForEach-Object { $resolved += $_.FullName }
            continue
        }

        if ($item.Extension.ToLowerInvariant() -notin $officeExtensions) {
            throw "Extension no soportada para control Office: $($item.FullName)"
        }

        $resolved += $item.FullName
    }

    return @($resolved | Sort-Object -Unique)
}

function Get-ZipText {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)

    $stream = $Entry.Open()
    try {
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-VisibleTextChunks {
    param(
        [string]$Extension,
        [hashtable]$EntryMap
    )

    $chunks = @()
    foreach ($entryName in ($EntryMap.Keys | Sort-Object)) {
        try {
            [xml]$xmlDoc = $EntryMap[$entryName]
        }
        catch {
            continue
        }

        foreach ($node in $xmlDoc.SelectNodes('//*[local-name()="t"]')) {
            $decoded = [System.Net.WebUtility]::HtmlDecode($node.InnerText)
            $normalized = ($decoded -replace '\s+', ' ').Trim()
            if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                $chunks += [pscustomobject]@{
                    Scope = $entryName
                    Text = $normalized
                }
            }
        }
    }

    return @($chunks)
}

function Find-MojibakeInChunks {
    param([object[]]$Chunks)

    $findings = @()
    foreach ($chunk in $Chunks) {
        $text = [string]$chunk.Text
        $scope = [string]$chunk.Scope

        foreach ($token in $knownQuestionTokens) {
            if ($text.Contains($token)) {
                $findings += [pscustomobject]@{
                    Scope = $scope
                    Token = $token
                    Snippet = $text
                }
            }
        }

        if ($text -match '\b\p{L}{2,}\?\p{L}{1,}\b') {
            $findings += [pscustomobject]@{
                Scope = $scope
                Token = '?-in-word'
                Snippet = $text
            }
        }

        foreach ($badChar in $badLeadChars) {
            if ($text.Contains([string]$badChar)) {
                $findings += [pscustomobject]@{
                    Scope = $scope
                    Token = [string]$badChar
                    Snippet = $text
                }
            }
        }
    }

    return @($findings)
}

$files = @(Resolve-OfficeFiles -InputPaths $Paths)
if ($files.Count -eq 0) {
    throw 'No se han encontrado archivos Office compatibles.'
}

$hasFailures = $false
foreach ($file in $files) {
    $entryMap = @{}
    $archive = [System.IO.Compression.ZipFile]::OpenRead($file)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -notmatch '^(word|xl|ppt)/.*\.xml$') {
                continue
            }
            $entryMap[$entry.FullName] = Get-ZipText -Entry $entry
        }
    }
    finally {
        $archive.Dispose()
    }

    $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
    $chunks = @(Get-VisibleTextChunks -Extension $extension -EntryMap $entryMap)
    $findings = @(Find-MojibakeInChunks -Chunks $chunks)

    if ($findings.Count -eq 0) {
        Write-Output "OK OFFICE: $file"
        continue
    }

    $hasFailures = $true
    Write-Output "FALLO OFFICE: $file"
    foreach ($finding in ($findings | Select-Object -First 25)) {
        $snippet = [string]$finding.Snippet
        if ($snippet.Length -gt 180) {
            $snippet = $snippet.Substring(0, 180)
        }
        Write-Output ("  [{0}] token='{1}' texto='{2}'" -f $finding.Scope, $finding.Token, $snippet)
    }
    if ($findings.Count -gt 25) {
        Write-Output ("  ... {0} incidencias adicionales no mostradas" -f ($findings.Count - 25))
    }
}

if ($hasFailures) {
    throw 'Se han detectado incidencias de mojibake o codificacion en Office.'
}
