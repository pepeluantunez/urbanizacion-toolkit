param(
    [string]$Profile = 'base_general',
    [string]$ProfileFile = '.\\CONFIG\\trazabilidad_profiles.json',
    [string[]]$Needles,
    [switch]$StrictProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

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

$profilePath = if ([System.IO.Path]::IsPathRooted($ProfileFile)) {
    $ProfileFile
} else {
    Join-Path (Get-Location) $ProfileFile
}

if (-not (Test-Path -LiteralPath $profilePath)) {
    throw "No existe el fichero de perfiles de trazabilidad: $ProfileFile"
}

$json = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$profileNames = @($json.PSObject.Properties.Name)
if ($profileNames -notcontains $Profile) {
    throw ("Perfil no encontrado: {0}. Perfiles disponibles: {1}" -f $Profile, ($profileNames -join ', '))
}

$profileConfig = $json.$Profile
$profileNeedles = @()
if ($profileConfig -is [System.Collections.IEnumerable] -and -not ($profileConfig -is [string]) -and -not ($profileConfig.PSObject.Properties.Name -contains 'paths')) {
    $inputPaths = @($profileConfig)
}
else {
    $inputPaths = @($profileConfig.paths)
    $profileNeedles = @($profileConfig.needles)
}

if ($inputPaths.Count -eq 0) {
    throw "El perfil '$Profile' no contiene rutas."
}

$supportedExtensions = @('.bc3', '.docx', '.docm', '.xlsx', '.xlsm', '.csv', '.txt', '.md', '.html', '.htm', '.xml')
$resolved = @()
$missing = @()
$unsupported = @()
foreach ($p in $inputPaths) {
    $abs = Resolve-ExistingPath -InputPath $p
    if ($null -ne $abs) {
        $item = Get-Item -LiteralPath $abs
        if ($item.PSIsContainer) {
            $resolved += $item.FullName
        } else {
            $ext = [System.IO.Path]::GetExtension($item.FullName).ToLowerInvariant()
            if ($supportedExtensions -contains $ext) {
                $resolved += $item.FullName
            } else {
                $unsupported += $p
            }
        }
    } else {
        $missing += $p
    }
}

Write-Output ("Perfil trazabilidad: {0}" -f $Profile)
Write-Output ("Modo perfil: {0}" -f ($(if ($StrictProfile) { 'estricto' } else { 'flexible' })))
Write-Output ("Rutas configuradas: {0}" -f $inputPaths.Count)
Write-Output ("Rutas existentes: {0}" -f $resolved.Count)
if ($missing.Count -gt 0) {
    Write-Output ("Rutas ausentes: {0}" -f $missing.Count)
    foreach ($m in ($missing | Select-Object -First 20)) {
        Write-Output ("  - {0}" -f $m)
    }
}
if ($unsupported.Count -gt 0) {
    Write-Output ("Rutas no soportadas (omitidas): {0}" -f $unsupported.Count)
    foreach ($u in ($unsupported | Select-Object -First 20)) {
        Write-Output ("  - {0}" -f $u)
    }
    Write-Output 'Recomendacion: convertir esas fuentes a .xlsx/.md/.txt para trazabilidad automatica completa.'
}

if ($StrictProfile -and ($missing.Count -gt 0 -or $unsupported.Count -gt 0)) {
    throw ("Perfil '{0}' invalido en modo estricto: faltan {1} ruta(s) y hay {2} ruta(s) no soportada(s)." -f $Profile, $missing.Count, $unsupported.Count)
}

if ($resolved.Count -eq 0) {
    throw "No hay rutas existentes para el perfil '$Profile'."
}

$checker = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'check_traceability_consistency.ps1'
if (-not (Test-Path -LiteralPath $checker)) {
    throw "No existe el verificador de trazabilidad: $checker"
}

$specialAnejoChecker = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'check_anejo13_14_value_traceability.ps1'
$freshnessChecker = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'check_annex_live_source_freshness.ps1'
$electricFolderExclusions = @(
    '9.- Red de Media Tensión',
    '10.- Red de Baja Tensión',
    '11.-Red de Alumbrado'
)

$effectiveNeedles = @()
if ($Needles -and $Needles.Count -gt 0) {
    $effectiveNeedles = @($Needles)
}
elseif ($profileNeedles.Count -gt 0) {
    $effectiveNeedles = @($profileNeedles)
}

if ($effectiveNeedles.Count -gt 0) {
    & $checker -Paths $resolved -Needles $effectiveNeedles
} else {
    & $checker -Paths $resolved
}

if ($Profile -in @('control_calidad_plan_obra', 'residuos_sys', 'todo_integral', 'memoria_integral')) {
    if (-not (Test-Path -LiteralPath $specialAnejoChecker)) {
        throw "No existe el verificador especializado de anejos 13/14: $specialAnejoChecker"
    }

    & $specialAnejoChecker -Root (Get-Location).Path
}

if ($Profile -in @('base_general', 'pluviales_fecales', 'control_calidad_plan_obra', 'residuos_sys', 'todo_integral', 'memoria_integral', 'instalaciones_electricas')) {
    if (-not (Test-Path -LiteralPath $freshnessChecker)) {
        throw "No existe el verificador de frescura documental: $freshnessChecker"
    }

    if ($Profile -eq 'instalaciones_electricas') {
        & $freshnessChecker -Root (Get-Location).Path
    }
    else {
        & $freshnessChecker -Root (Get-Location).Path -ExcludeFolders $electricFolderExclusions
    }
}
