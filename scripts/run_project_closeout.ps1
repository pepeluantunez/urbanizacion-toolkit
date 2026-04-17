param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths,
    [bool]$StrictDocxLayout = $true,
    [bool]$RequireTableCaption = $true,
    [bool]$CheckExcelFormulas = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$officeExtensions = @('.docx', '.docm', '.xlsx', '.xlsm', '.pptx', '.pptm')
$bc3Extensions = @('.bc3', '.pzh')
$docExtensions = @('.docx', '.docm')
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

function Resolve-InputFiles {
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
                Where-Object {
                    $_.Extension.ToLowerInvariant() -in $officeExtensions -or
                    $_.Extension.ToLowerInvariant() -in $bc3Extensions
                } |
                ForEach-Object { $resolved += $_.FullName }
            continue
        }

        $resolved += $item.FullName
    }

    return @($resolved | Sort-Object -Unique)
}

$allFiles = @(Resolve-InputFiles -InputPaths $Paths)
$officeFiles = @($allFiles | Where-Object { [System.IO.Path]::GetExtension($_).ToLowerInvariant() -in $officeExtensions })
$bc3Files = @($allFiles | Where-Object { [System.IO.Path]::GetExtension($_).ToLowerInvariant() -in $bc3Extensions })
$docFiles = @($allFiles | Where-Object { [System.IO.Path]::GetExtension($_).ToLowerInvariant() -in $docExtensions })
$excelFiles = @($allFiles | Where-Object { [System.IO.Path]::GetExtension($_).ToLowerInvariant() -in $excelExtensions })

if ($officeFiles.Count -eq 0 -and $bc3Files.Count -eq 0) {
    throw 'No se han encontrado archivos Office ni BC3 compatibles para revisar.'
}

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$officeChecker = Join-Path $toolsRoot 'check_office_mojibake.ps1'
$bc3Checker = Join-Path $toolsRoot 'check_bc3_integrity.ps1'
$docChecker = Join-Path $toolsRoot 'check_docx_tables_consistency.ps1'
$excelChecker = Join-Path $toolsRoot 'check_excel_formula_guard.ps1'

$hadFailure = $false

if ($officeFiles.Count -gt 0) {
    Write-Output '== Control Office =='
    try {
        & $officeChecker -Paths $officeFiles
    } catch {
        $hadFailure = $true
        Write-Output $_.Exception.Message
    }
}

if ($bc3Files.Count -gt 0) {
    Write-Output '== Control BC3 =='
    try {
        & $bc3Checker -Paths $bc3Files
    } catch {
        $hadFailure = $true
        Write-Output $_.Exception.Message
    }
}

if ($docFiles.Count -gt 0) {
    Write-Output '== Control DOCX tablas =='
    try {
        & $docChecker -Paths $docFiles -ExpectedFont 'Montserrat' -EnforceFont $StrictDocxLayout -RequireTableCaption $RequireTableCaption
    } catch {
        $hadFailure = $true
        Write-Output $_.Exception.Message
    }
}

if ($excelFiles.Count -gt 0 -and $CheckExcelFormulas) {
    Write-Output '== Control Excel formulas =='
    try {
        & $excelChecker -Paths $excelFiles
    } catch {
        $hadFailure = $true
        Write-Output $_.Exception.Message
    }
}

if ($hadFailure) {
    exit 1
}
