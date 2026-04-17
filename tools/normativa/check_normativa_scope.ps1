param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths,
    [string[]]$RequireDomains = @('accesibilidad', 'saneamiento', 'pluviales', 'seguridad', 'calidad'),
    [switch]$FailOnMissing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem

$supported = @('.docx', '.docm', '.xlsx', '.xlsm', '.md', '.txt', '.csv', '.html', '.htm', '.xml')

$domainPatterns = @{
    accesibilidad = '(?i)\baccesibil|itinerario accesible|barrera arquitecton'
    saneamiento   = '(?i)\bsaneamiento|colector|fecales|pozo|arqueta'
    pluviales     = '(?i)\bpluvial|embocadura|imborna|drenaje'
    seguridad     = '(?i)\bseguridad y salud|riesgo laboral|EPI|coordinador de seguridad'
    calidad       = '(?i)\bcontrol de calidad|ensayo|muestreo|recepcion'
}

$normaPatterns = @(
    '(?i)\bUNE(?:-EN)?\s*\d{2,5}(?:-\d+)?',
    '(?i)\bISO\s*\d{3,5}',
    '(?i)\bReal Decreto\s+\d+/\d{4}',
    '(?i)\bRD\s+\d+/\d{4}',
    '(?i)\bLey\s+\d+/\d{4}',
    '(?i)\bReglamento\b',
    '(?i)\bPG-3\b',
    '(?i)\bCTE\b',
    '(?i)\bOrden\s+[A-Z]{2,}\b',
    '(?i)\bInstruccion\b'
)

function Resolve-Files {
    param([string[]]$InputPaths)
    $resolved = @()
    foreach ($inputPath in $InputPaths) {
        $absolute = if ([System.IO.Path]::IsPathRooted($inputPath)) { $inputPath } else { Join-Path (Get-Location) $inputPath }
        if (-not (Test-Path -LiteralPath $absolute)) { throw "No existe la ruta: $inputPath" }

        $item = Get-Item -LiteralPath $absolute
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -Recurse -File |
                Where-Object { $_.Extension.ToLowerInvariant() -in $supported } |
                ForEach-Object { $resolved += $_.FullName }
        } else {
            if ($item.Extension.ToLowerInvariant() -notin $supported) {
                throw "Extension no soportada para revision normativa: $($item.FullName)"
            }
            $resolved += $item.FullName
        }
    }
    return @($resolved | Sort-Object -Unique)
}

function Read-ZipEntryText {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)
    $stream = $Entry.Open()
    try {
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        $stream.Dispose()
    }
}

function Read-OfficeVisibleText {
    param([string]$FilePath)
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    $regex = switch ($ext) {
        '.docx' { '<w:t(?:\s[^>]*)?>(.*?)</w:t>' }
        '.docm' { '<w:t(?:\s[^>]*)?>(.*?)</w:t>' }
        '.xlsx' { '<t(?:\s[^>]*)?>(.*?)</t>' }
        '.xlsm' { '<t(?:\s[^>]*)?>(.*?)</t>' }
        default { return '' }
    }
    $texts = @()
    $archive = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -notmatch '^(word|xl)/.*\.xml$') { continue }
            $xml = Read-ZipEntryText -Entry $entry
            foreach ($m in [regex]::Matches($xml, $regex)) {
                $txt = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
                if (-not [string]::IsNullOrWhiteSpace($txt)) { $texts += $txt.Trim() }
            }
        }
    } finally {
        $archive.Dispose()
    }
    return ($texts -join ' ')
}

function Read-PlainText {
    param([string]$FilePath)
    try { return Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8 } catch { return Get-Content -LiteralPath $FilePath -Raw -Encoding Default }
}

function Get-Text {
    param([string]$FilePath)
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($ext -in @('.docx', '.docm', '.xlsx', '.xlsm')) { return Read-OfficeVisibleText -FilePath $FilePath }
    return Read-PlainText -FilePath $FilePath
}

$files = @(Resolve-Files -InputPaths $Paths)
if ($files.Count -eq 0) { throw 'No se han encontrado ficheros compatibles para revision normativa.' }

$hasFailures = $false
foreach ($file in $files) {
    $text = Get-Text -FilePath $file
    $normaHits = @()
    foreach ($pattern in $normaPatterns) {
        foreach ($m in [regex]::Matches($text, $pattern)) {
            $v = $m.Value.Trim()
            if (-not [string]::IsNullOrWhiteSpace($v)) { $normaHits += $v }
        }
    }
    $normaHits = @($normaHits | Sort-Object -Unique)

    $activeDomains = @()
    foreach ($domain in $RequireDomains) {
        if (-not $domainPatterns.ContainsKey($domain)) { continue }
        if ([regex]::IsMatch($text, $domainPatterns[$domain])) {
            $activeDomains += $domain
        }
    }

    if ($activeDomains.Count -gt 0 -and $normaHits.Count -eq 0) {
        Write-Output ("FALLO NORMATIVA: {0}" -f $file)
        Write-Output ("  Dominios tecnicos detectados sin referencia normativa: {0}" -f ($activeDomains -join ', '))
        $hasFailures = $true
        continue
    }

    Write-Output ("OK NORMATIVA: {0}" -f $file)
    Write-Output ("  Dominios detectados: {0}" -f (if ($activeDomains.Count -gt 0) { $activeDomains -join ', ' } else { 'ninguno' }))
    Write-Output ("  Referencias normativas: {0}" -f $normaHits.Count)
    foreach ($hit in ($normaHits | Select-Object -First 10)) {
        Write-Output ("  - {0}" -f $hit)
    }
    if ($normaHits.Count -gt 10) {
        Write-Output ("  ... {0} referencias adicionales" -f ($normaHits.Count - 10))
    }
}

if ($FailOnMissing -and $hasFailures) {
    throw 'Revision normativa fallida por ausencia de referencias donde hay contenido tecnico.'
}
