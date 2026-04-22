param(
    [string]$ManifestPath = '.\CONFIG\ecosystem_alignment_manifest.json',

    [ValidateSet('text', 'json')]
    [string]$OutputFormat = 'text',

    [string]$OutPath,

    [switch]$FailOnDrift
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Resolve-AbsolutePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    if ([System.IO.Path]::IsPathRooted($TargetPath)) {
        return [System.IO.Path]::GetFullPath($TargetPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $TargetPath))
}

function Get-ManifestProperties {
    param([Parameter(Mandatory = $true)]$Object)

    return @($Object.PSObject.Properties | Sort-Object Name)
}

function Get-ExistingFileHash {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) {
        return $null
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function New-RepoEntry {
    param(
        [string]$Repo,
        [string]$RelativePath,
        [string]$AbsolutePath
    )

    $exists = Test-Path -LiteralPath $AbsolutePath
    $hash = if ($exists) { Get-ExistingFileHash -Path $AbsolutePath } else { $null }

    return [pscustomobject]@{
        Repo = $Repo
        RelativePath = $RelativePath
        AbsolutePath = $AbsolutePath
        Exists = $exists
        Hash = $hash
    }
}

function Get-ItemStatus {
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][pscustomobject[]]$Entries
    )

    $ownerEntry = $Entries | Where-Object { $_.Repo -eq $Item.Owner } | Select-Object -First 1
    $existingEntries = @($Entries | Where-Object { $_.Exists -and -not [string]::IsNullOrWhiteSpace($_.Hash) })
    $missingRepos = @($Entries | Where-Object { -not $_.Exists } | ForEach-Object { $_.Repo })

    if ($null -eq $ownerEntry) {
        return 'owner-not-declared'
    }

    if (-not $ownerEntry.Exists) {
        return 'owner-missing'
    }

    if ($existingEntries.Count -le 1) {
        return 'owner-only'
    }

    $uniqueHashes = @($existingEntries | ForEach-Object { $_.Hash } | Sort-Object -Unique)
    if ($uniqueHashes.Count -eq 1) {
        if ($missingRepos.Count -eq 0) {
            return 'aligned'
        }

        return 'partial'
    }

    return 'drift'
}

function Convert-StatusToLabel {
    param([string]$Status)

    switch ($Status) {
        'aligned' { return 'ALIGNED' }
        'partial' { return 'PARTIAL' }
        'drift' { return 'DRIFT' }
        'owner-only' { return 'OWNER_ONLY' }
        'owner-missing' { return 'OWNER_MISSING' }
        'owner-not-declared' { return 'OWNER_NOT_DECLARED' }
        default { return $Status.ToUpperInvariant() }
    }
}

function Build-TextReport {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][pscustomobject[]]$Results
    )

    $summary = @(
        'aligned',
        'partial',
        'drift',
        'owner-only',
        'owner-missing',
        'owner-not-declared'
    ) | ForEach-Object {
        $statusName = $_
        "{0}={1}" -f (Convert-StatusToLabel -Status $statusName), (@($Results | Where-Object { $_.Status -eq $statusName }).Count)
    }

    $lines = @()
    $lines += '# Alineacion del ecosistema'
    $lines += ''
    $lines += ("Manifest: {0}" -f $Manifest.ManifestPath)
    $lines += ("Items revisados: {0}" -f $Results.Count)
    $lines += ("Resumen: {0}" -f ($summary -join '  '))
    $lines += ''

    foreach ($result in ($Results | Sort-Object Status, Id)) {
        $lines += ("- [{0}] {1} owner={2} mode={3}" -f (Convert-StatusToLabel -Status $result.Status), $result.Id, $result.Owner, $result.Mode)
        foreach ($entry in $result.Entries) {
            $state = if ($entry.Exists) { 'present' } else { 'missing' }
            $hashShort = if ($entry.Hash) { $entry.Hash.Substring(0, 12) } else { '-' }
            $lines += ("  - {0}: {1} :: {2} :: hash={3}" -f $entry.Repo, $state, $entry.RelativePath, $hashShort)
        }
        if ($result.Note) {
            $lines += ("  - note: {0}" -f $result.Note)
        }
    }

    return ($lines -join [Environment]::NewLine)
}

$manifestAbsolutePath = Resolve-AbsolutePath -BasePath (Get-Location).Path -TargetPath $ManifestPath
if (-not (Test-Path -LiteralPath $manifestAbsolutePath)) {
    throw "No existe el manifiesto de alineacion: $ManifestPath"
}

$manifestDirectory = Split-Path -Parent $manifestAbsolutePath
$manifestJson = Get-Content -LiteralPath $manifestAbsolutePath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($null -eq $manifestJson.repos) {
    throw 'El manifiesto no contiene el bloque "repos".'
}

if ($null -eq $manifestJson.items -or @($manifestJson.items).Count -eq 0) {
    throw 'El manifiesto no contiene items de alineacion.'
}

$repoRoots = @{}
foreach ($repoProperty in (Get-ManifestProperties -Object $manifestJson.repos)) {
    $repoRoots[$repoProperty.Name] = Resolve-AbsolutePath -BasePath $manifestDirectory -TargetPath ([string]$repoProperty.Value)
}

$results = @()
foreach ($item in @($manifestJson.items)) {
    $entries = @()
    foreach ($pathProperty in (Get-ManifestProperties -Object $item.paths)) {
        $repoName = $pathProperty.Name
        if (-not $repoRoots.ContainsKey($repoName)) {
            throw ("El item '{0}' referencia el repo '{1}', pero no existe en el bloque repos." -f $item.id, $repoName)
        }

        $relativePath = [string]$pathProperty.Value
        $absolutePath = Resolve-AbsolutePath -BasePath $repoRoots[$repoName] -TargetPath $relativePath
        $entries += New-RepoEntry -Repo $repoName -RelativePath $relativePath -AbsolutePath $absolutePath
    }

    $status = Get-ItemStatus -Item $item -Entries $entries
    $results += [pscustomobject]@{
        Id = [string]$item.id
        Owner = [string]$item.owner
        Mode = [string]$item.mode
        Note = [string]$item.note
        Status = $status
        Entries = @($entries | Sort-Object Repo)
    }
}

$payload = [pscustomobject]@{
    ManifestPath = $manifestAbsolutePath
    GeneratedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Results = $results
}

if ($OutputFormat -eq 'json') {
    $content = $payload | ConvertTo-Json -Depth 8
}
else {
    $content = Build-TextReport -Manifest ([pscustomobject]@{ ManifestPath = $manifestAbsolutePath }) -Results $results
}

if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
    $outAbsolutePath = Resolve-AbsolutePath -BasePath (Get-Location).Path -TargetPath $OutPath
    $outDirectory = Split-Path -Parent $outAbsolutePath
    if (-not [string]::IsNullOrWhiteSpace($outDirectory) -and -not (Test-Path -LiteralPath $outDirectory)) {
        New-Item -ItemType Directory -Force -Path $outDirectory | Out-Null
    }
    Set-Content -LiteralPath $outAbsolutePath -Value $content -Encoding UTF8
}

Write-Output $content

$driftCount = @($results | Where-Object { $_.Status -eq 'drift' }).Count
$ownerMissingCount = @($results | Where-Object { $_.Status -in @('owner-missing', 'owner-not-declared') }).Count
if ($FailOnDrift -and ($driftCount -gt 0 -or $ownerMissingCount -gt 0)) {
    throw ("Alineacion fallida: drift={0}, owner_missing={1}" -f $driftCount, $ownerMissingCount)
}
