# run_estandar_proyecto.ps1
# Pipeline estandar de verificacion del proyecto POU 2026.
# Ejecuta en secuencia todos los checks disponibles y genera un snapshot
# de versiones al inicio y al final.
#
# Uso:
#   .\run_estandar_proyecto.ps1 -Paths ruta\bc3, ruta\docx\, ruta\excels\
#   .\run_estandar_proyecto.ps1 -Paths . -Modo estricto -TraceProfile memoria -AutoFixDocxCaptions
#   .\run_estandar_proyecto.ps1 -Paths . -Bc3Path PRESUPUESTO\535.2.bc3 -Bc3Ref PRESUPUESTO\535.2.bc3.pre_recalc.bak
#   .\run_estandar_proyecto.ps1 -Paths . -Bc3Path PRESUPUESTO\535.2.bc3 -PemMemoria 1234567.89

param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths,

    [ValidateSet('flexible', 'estricto')]
    [string]$Modo = 'flexible',

    [string]$TraceProfile,

    [string[]]$Needles,

    [switch]$AutoFixDocxCaptions,

    # BC3 especifico a verificar en deep check y diff
    [string]$Bc3Path,

    # BC3 de referencia para diff (opcional)
    [string]$Bc3Ref,

    # PEM declarado en memoria para comparar con BC3 (opcional)
    [double]$PemMemoria = 0,

    # Ruta del informe de salida Word (usa la plantilla)
    [string]$InformeOut,

    # Si se indica, no genera snapshot de versiones (mas rapido en debug)
    [switch]$SinSnapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$toolsRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $toolsRoot

# Resolver Python
$python = Get-Command python3 -ErrorAction SilentlyContinue
if ($null -eq $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
$pythonExe = if ($null -ne $python) { $python.Source } else { $null }

function Invoke-PythonScript {
    param([string]$Script, [string[]]$Args)
    if ($null -eq $pythonExe) {
        Write-Output "  AVISO: Python no disponible, omitiendo $Script"
        return $false
    }
    $full = Join-Path $toolsRoot $Script
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Output "  AVISO: Script no encontrado: $Script"
        return $false
    }
    & $pythonExe $full @Args
    return ($LASTEXITCODE -eq 0)
}

$strict = $Modo -eq 'estricto'

$resolvedFiles = @()
foreach ($p in $Paths) {
    $abs = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path (Get-Location) $p }
    if (-not (Test-Path -LiteralPath $abs)) { throw "No existe la ruta: $p" }
    $item = Get-Item -LiteralPath $abs
    if ($item.PSIsContainer) {
        $resolvedFiles += Get-ChildItem -LiteralPath $item.FullName -Recurse -File | ForEach-Object { $_.FullName }
    } else {
        $resolvedFiles += $item.FullName
    }
}
$resolvedFiles = @($resolvedFiles | Sort-Object -Unique)

$docFiles = @($resolvedFiles | Where-Object { [System.IO.Path]::GetExtension($_).ToLowerInvariant() -in @('.docx', '.docm') })
$bc3Files  = @($resolvedFiles | Where-Object { [System.IO.Path]::GetExtension($_).ToLowerInvariant() -in @('.bc3', '.pzh') })
$xlsFiles  = @($resolvedFiles | Where-Object { [System.IO.Path]::GetExtension($_).ToLowerInvariant() -in @('.xlsx', '.xlsm') })

# BC3 especifico adicional
$effectiveBc3 = @()
if ($Bc3Path) {
    $absbc3 = if ([System.IO.Path]::IsPathRooted($Bc3Path)) { $Bc3Path } else { Join-Path (Get-Location) $Bc3Path }
    if (Test-Path -LiteralPath $absbc3) { $effectiveBc3 = @($absbc3) }
} elseif ($bc3Files.Count -gt 0) {
    $effectiveBc3 = $bc3Files
}

Write-Output ("=" * 70)
Write-Output ("  PIPELINE ESTANDAR POU 2026  ({0})" -f $Modo.ToUpper())
Write-Output ("  Fecha: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'))
Write-Output ("=" * 70)
Write-Output ("  Ficheros detectados: {0} total  (BC3={1}  DOCX={2}  Excel={3})" -f $resolvedFiles.Count, $bc3Files.Count, $docFiles.Count, $xlsFiles.Count)
Write-Output ""

# ── SNAPSHOT INICIAL ────────────────────────────────────────────────────────
if (-not $SinSnapshot -and $effectiveBc3.Count -gt 0) {
    Write-Output "== [0] Snapshot de versiones (inicio) =="
    Invoke-PythonScript 'py_track_versions.py' (@('snapshot') + $effectiveBc3 + @('--label', ("inicio_pipeline_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmm')))) | Out-Null
    Write-Output ""
}

# ── 1. BC3 INTEGRIDAD BASICA ────────────────────────────────────────────────
if ($effectiveBc3.Count -gt 0) {
    Write-Output "== [1] BC3 – Integridad basica =="
    try {
        & "$toolsRoot\check_bc3_integrity.ps1" -Paths $effectiveBc3
    } catch {
        Write-Output ("  FALLO check_bc3_integrity: {0}" -f $_.Exception.Message)
        if ($strict) { throw }
    }
    Write-Output ""

    # ── 2. BC3 DEEP CHECK ───────────────────────────────────────────────────
    Write-Output "== [2] BC3 – Deep check (descomposiciones + precios) =="
    Invoke-PythonScript 'py_bc3_deep_check.py' $effectiveBc3 | Out-Null
    Write-Output ""

    # ── 3. BC3 PEM CHECK ────────────────────────────────────────────────────
    if ($PemMemoria -gt 0) {
        Write-Output "== [3] BC3 – PEM vs Memoria =="
        foreach ($bc3f in $effectiveBc3) {
            Invoke-PythonScript 'py_bc3_pem_check.py' @($bc3f, '--pem', $PemMemoria.ToString('F2', [System.Globalization.CultureInfo]::InvariantCulture)) | Out-Null
        }
        Write-Output ""
    }

    # ── 4. BC3 DIFF ─────────────────────────────────────────────────────────
    if ($Bc3Ref) {
        $absRef = if ([System.IO.Path]::IsPathRooted($Bc3Ref)) { $Bc3Ref } else { Join-Path (Get-Location) $Bc3Ref }
        if (Test-Path -LiteralPath $absRef) {
            Write-Output "== [4] BC3 – Diff contra referencia =="
            foreach ($bc3f in $effectiveBc3) {
                $diffOut = [System.IO.Path]::ChangeExtension($bc3f, '.diff.md')
                Invoke-PythonScript 'py_bc3_diff.py' @($absRef, $bc3f, '--out', $diffOut) | Out-Null
            }
            Write-Output ""
        }
    }
}

# ── 5. DOCX ─────────────────────────────────────────────────────────────────
if ($AutoFixDocxCaptions -and $docFiles.Count -gt 0) {
    Write-Output "== [5a] DOCX – Autofix captions =="
    & "$toolsRoot\autofix_docx_captions.ps1" -Paths $docFiles -CaptionPrefix 'Tabla' -DefaultDescription 'Descripcion' -UseMontserrat $true
    Write-Output ""
}

Write-Output "== [5b] DOCX – Cierre documental / presupuesto =="
& "$toolsRoot\run_project_closeout.ps1" -Paths $Paths -StrictDocxLayout $strict -RequireTableCaption $strict -CheckExcelFormulas $true
Write-Output ""

# ── 6. EXTRACCION ESTRUCTURA DOCX ───────────────────────────────────────────
if ($docFiles.Count -gt 0) {
    Write-Output "== [6] DOCX – Extraccion estructura (needles para trazabilidad) =="
    $structOut = Join-Path (Get-Location) '.codex_tmp\doc_structure.json'
    Invoke-PythonScript 'py_extract_doc_structure.py' (@($docFiles | Select-Object -First 3) + @('--out', $structOut)) | Out-Null
    Write-Output ""
}

# ── 7. TRAZABILIDAD ─────────────────────────────────────────────────────────
if (-not [string]::IsNullOrWhiteSpace($TraceProfile)) {
    Write-Output "== [7] Trazabilidad por perfil =="
    if ($Needles -and $Needles.Count -gt 0) {
        & "$toolsRoot\run_traceability_profile.ps1" -Profile $TraceProfile -Needles $Needles -StrictProfile:$strict
    } else {
        & "$toolsRoot\run_traceability_profile.ps1" -Profile $TraceProfile -StrictProfile:$strict
    }
    Write-Output ""
} elseif ($Needles -and $Needles.Count -gt 0) {
    Write-Output "== [7] Trazabilidad por anclas =="
    & "$toolsRoot\check_traceability_consistency.ps1" -Paths $resolvedFiles -Needles $Needles
    Write-Output ""
}

# ── 8. SNAPSHOT FINAL + CHECKPOINT ─────────────────────────────────────────
if (-not $SinSnapshot -and $effectiveBc3.Count -gt 0) {
    Write-Output "== [8] Snapshot de versiones (fin de pipeline) =="
    $checkpointLabel = "pipeline_{0}_{1}" -f $Modo, (Get-Date -Format 'yyyyMMdd_HHmm')
    Invoke-PythonScript 'py_track_versions.py' (@('snapshot') + $effectiveBc3 + @('--label', $checkpointLabel)) | Out-Null
    Invoke-PythonScript 'py_track_versions.py' @('checkpoint', '--label', $checkpointLabel) | Out-Null
    Write-Output ""
}

# ── 9. INFORME WORD (opcional) ───────────────────────────────────────────────
if ($InformeOut) {
    $templatePath = Join-Path $projectRoot '00_PLANTILLA_BASE\INFORME_VERIFICACION_TEMPLATE.docx'
    if (Test-Path -LiteralPath $templatePath) {
        Write-Output "== [9] Generando informe Word =="
        $dataJson = Join-Path (Split-Path $InformeOut) 'informe_datos.json'
        if (-not (Test-Path -LiteralPath $dataJson)) {
            $jsonData = [ordered]@{
                VERIFICADOR           = $env:USERNAME
                FECHA_VERIFICACION    = (Get-Date -Format 'yyyy-MM-dd')
                FICHERO_BC3           = ($effectiveBc3 | Select-Object -First 1 | Split-Path -Leaf)
                FICHERO_MEMORIA       = ($docFiles | Select-Object -First 1 | Split-Path -Leaf)
                VERSION               = 'pipeline_auto'
                RESULTADO_GLOBAL      = 'Ver detalle en consola'
                total_errores         = 0
                total_avisos          = 0
                resumen_bc3_errores   = 0
                resumen_bc3_avisos    = 0
                resumen_docx_errores  = 0
                resumen_docx_avisos   = 0
                resumen_excel_errores = 0
                resumen_excel_avisos  = 0
                resumen_pem_estado    = if ($PemMemoria -gt 0) { 'Ver' } else { 'N/A' }
                resumen_traza_errores = 0
                resumen_traza_avisos  = 0
                bc3_integridad_resultado  = 'Ver consola'
                bc3_hallazgos             = @()
                pem_bc3                   = '-'
                pem_memoria               = if ($PemMemoria -gt 0) { $PemMemoria.ToString('N2') } else { '-' }
                pem_desviacion            = '-'
                trazabilidad_anclas       = @()
                docx_mojibake_resultado   = 'Ver consola'
                excel_formulas_resultado  = 'Ver consola'
                excel_hallazgos           = @()
                observaciones             = 'Completar manualmente tras revision de consola.'
            } | ConvertTo-Json -Depth 4
            [System.IO.File]::WriteAllText($dataJson, $jsonData, [System.Text.Encoding]::UTF8)
        }
        Invoke-PythonScript 'py_generate_report.py' @('--template', $templatePath, '--data', $dataJson, '--out', $InformeOut) | Out-Null
        Write-Output ("  Informe Word: {0}" -f $InformeOut)
        Write-Output ""
    } else {
        Write-Output "  AVISO: Plantilla no encontrada en 00_PLANTILLA_BASE (omitiendo informe Word)"
    }
}

Write-Output ("=" * 70)
Write-Output "  PIPELINE OK"
Write-Output ("=" * 70)
