param(
    [string]$Root = "C:\Users\USUARIO\Documents\Claude\Projects\MEJORA CARRETERA GUADALMAR\PROYECTO 535\535.2\535.2.2 Mejora Carretera Guadalmar\POU 2026",
    [string[]]$Paths,
    [switch]$Apply,
    [ValidateSet('text', 'json')]
    [string]$OutputFormat = 'text'
)

$ErrorActionPreference = 'Stop'

function Normalize-RepoPath {
    param([string]$Path, [string]$RootPath)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }

    $candidate = $Path.Trim()
    $isRooted = $false
    try {
        $isRooted = [IO.Path]::IsPathRooted($candidate)
    }
    catch {
        $isRooted = $false
    }

    if ($isRooted) {
        $rootResolved = (Resolve-Path -LiteralPath $RootPath).Path
        $fullResolved = $candidate
        try { $fullResolved = (Resolve-Path -LiteralPath $candidate).Path } catch { }
        if ($fullResolved.StartsWith($rootResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
            $candidate = $fullResolved.Substring($rootResolved.Length).TrimStart('\', '/')
        }
    }

    return ($candidate -replace '\\', '/').Trim()
}

function Get-GitChangedEntries {
    param([string]$RootPath)

    $entries = @{}

    function Invoke-GitLines {
        param([string[]]$Args)

        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $raw = @(& git @Args 2>&1)
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }

        return @(
            $raw |
                ForEach-Object { [string]$_ } |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_) -and
                    $_ -notmatch '^warning: in the working copy'
                }
        )
    }

    function Add-Entry {
        param([string]$Path, [string]$Status)

        $normalized = Normalize-RepoPath -Path $Path -RootPath $RootPath
        if ([string]::IsNullOrWhiteSpace($normalized)) { return }

        if (-not $entries.ContainsKey($normalized)) {
            $entries[$normalized] = [ordered]@{
                Path = $normalized
                Statuses = New-Object System.Collections.Generic.List[string]
            }
        }

        if (-not $entries[$normalized].Statuses.Contains($Status)) {
            [void]$entries[$normalized].Statuses.Add($Status)
        }
    }

    Push-Location $RootPath
    try {
        foreach ($path in @(Invoke-GitLines -Args @('diff', '--name-only', '--diff-filter=ACMRTUXB', '--relative'))) {
            Add-Entry -Path $path -Status 'modified'
        }
        foreach ($path in @(Invoke-GitLines -Args @('diff', '--cached', '--name-only', '--diff-filter=ACMRTUXB', '--relative'))) {
            Add-Entry -Path $path -Status 'staged'
        }
        foreach ($path in @(Invoke-GitLines -Args @('ls-files', '--others', '--exclude-standard'))) {
            Add-Entry -Path $path -Status 'untracked'
        }
    }
    finally {
        Pop-Location
    }

    return @($entries.Values | Sort-Object Path)
}

function Get-InputEntries {
    param([string]$RootPath, [string[]]$SelectedPaths)

    if ($SelectedPaths -and $SelectedPaths.Count -gt 0) {
        $expandedPaths = @()
        foreach ($rawPath in @($SelectedPaths)) {
            foreach ($piece in @([regex]::Split($rawPath, ',(?=(?:[A-Za-z]:)?(?:DOCS/|PRESUPUESTO/|scripts/|tools/))'))) {
                if (-not [string]::IsNullOrWhiteSpace($piece)) {
                    $expandedPaths += $piece.Trim()
                }
            }
        }

        $gitMap = @{}
        foreach ($entry in (Get-GitChangedEntries -RootPath $RootPath)) {
            $gitMap[$entry.Path] = $entry
        }

        $result = @()
        foreach ($path in $expandedPaths) {
            $normalized = Normalize-RepoPath -Path $path -RootPath $RootPath
            if ([string]::IsNullOrWhiteSpace($normalized)) { continue }
            if ($gitMap.ContainsKey($normalized)) {
                $result += $gitMap[$normalized]
            }
            else {
                $result += [pscustomobject]@{
                    Path = $normalized
                    Statuses = @('provided')
                }
            }
        }
        return @($result | Sort-Object Path -Unique)
    }

    return @(Get-GitChangedEntries -RootPath $RootPath)
}

function New-StringList {
    return New-Object System.Collections.Generic.List[string]
}

function Add-UniqueString {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    if (-not $List.Contains($Value)) {
        [void]$List.Add($Value)
    }
}

function Add-Impact {
    param(
        [hashtable]$ImpactMap,
        [pscustomobject]$Entry,
        [string]$Key,
        [string]$Title,
        [string]$Block,
        [string]$Priority,
        [string]$Reason,
        [string[]]$Actions,
        [string[]]$Derived,
        [string[]]$Checks,
        [string]$Note
    )

    if (-not $ImpactMap.Contains($Key)) {
        $ImpactMap[$Key] = [ordered]@{
            Key = $Key
            Title = $Title
            Block = $Block
            Priority = $Priority
            Reason = $Reason
            Note = $Note
            ChangedFiles = New-StringList
            Statuses = New-StringList
            Actions = New-StringList
            Derived = New-StringList
            Checks = New-StringList
            Executions = New-StringList
            Verification = New-StringList
        }
    }

    Add-UniqueString -List $ImpactMap[$Key].ChangedFiles -Value $Entry.Path
    foreach ($status in @($Entry.Statuses)) {
        Add-UniqueString -List $ImpactMap[$Key].Statuses -Value $status
    }
    foreach ($action in @($Actions)) {
        Add-UniqueString -List $ImpactMap[$Key].Actions -Value $action
    }
    foreach ($derivedItem in @($Derived)) {
        Add-UniqueString -List $ImpactMap[$Key].Derived -Value $derivedItem
    }
    foreach ($check in @($Checks)) {
        Add-UniqueString -List $ImpactMap[$Key].Checks -Value $check
    }
}

function Get-BlockLabel {
    param([string]$Path)

    if ($Path -match '^DOCS/Documentos de Trabajo/([^/]+)/') { return $Matches[1] }
    if ($Path -match '^PRESUPUESTO/') { return 'PRESUPUESTO' }
    if ($Path -match '^DOCS/') { return 'DOCS' }
    if ($Path -match '^scripts/') { return 'scripts' }
    if ($Path -match '^tools/') { return 'tools' }
    return 'Proyecto'
}

function Get-Extension {
    param([string]$Path)
    $ext = [IO.Path]::GetExtension($Path)
    if ($null -eq $ext) { $ext = '' }
    return $ext.ToLowerInvariant()
}

function Test-SpecialRule {
    param(
        [pscustomobject]$Entry,
        [hashtable]$ImpactMap
    )

    $path = $Entry.Path

    if ($path -match '^DOCS/Documentos de Trabajo/4\.- Trazado, Replanteo y Mediciones Auxiliares/Informe de P\.K\. (de PI|incremental) de alineaciones\.html$' -or
        $path -match '^DOCS/Documentos de Trabajo/4\.- Trazado, Replanteo y Mediciones Auxiliares/Anejo4_PK_(PI|Incremental)_Alineaciones\.csv$' -or
        $path -match '^DOCS/Documentos de Trabajo/4\.- Trazado, Replanteo y Mediciones Auxiliares/Anejo4_PK_Alineaciones_Trazable\.xls$' -or
        $path -match '^DOCS/Documentos de Trabajo/4\.- Trazado, Replanteo y Mediciones Auxiliares/Actualizacion_Anejo4_PK_Alineaciones\.md$' -or
        $path -match '^DOCS/Documentos de Trabajo/4\.- Trazado, Replanteo y Mediciones Auxiliares/Anejo4_HTML_WORD_Trazabilidad\.(xls|md)$') {

        Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
            -Key 'anejo4-pk-alineaciones' `
            -Title 'Anejo 4 - PK de alineaciones' `
            -Block '4.- Trazado, Replanteo y Mediciones Auxiliares' `
            -Priority 'alta' `
            -Reason 'Se ha tocado una fuente o derivado del paquete de PK de alineaciones del Anejo 4.' `
            -Actions @(
                'Regenerar el paquete con scripts/build_anejo4_alignment_pk_package.ps1',
                'Regenerar la matriz HTML-Word con scripts/build_anejo4_html_word_traceability.ps1',
                'Actualizar o revisar el Word con scripts/update_anejo4_docx_pk.ps1',
                'Comprobar si hay nueva alineacion o cambio de longitud por eje'
            ) `
            -Derived @(
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anejo4_PK_PI_Alineaciones.csv',
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anejo4_PK_Incremental_Alineaciones.csv',
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anejo4_PK_Alineaciones_Trazable.xls',
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Actualizacion_Anejo4_PK_Alineaciones.md',
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anejo4_HTML_WORD_Trazabilidad.xls',
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anejo4_HTML_WORD_Trazabilidad.md',
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anexo 4 - Replanteo y Mediciones Auxiliares.docx'
            ) `
            -Checks @(
                'tools/check_office_mojibake.ps1 sobre el Word/Excel afectados',
                'tools/check_docx_tables_consistency.ps1 sobre el Anexo 4',
                'No mover BC3 automaticamente salvo medicion derivada y defendible'
            ) `
            -Note 'Si aparece una alineacion nueva como AV. MCE, este es el impacto correcto a revisar.'
        return $true
    }

    if ($path -match '^DOCS/Documentos de Trabajo/4\.- Trazado, Replanteo y Mediciones Auxiliares/(Informe de curva y P\.K\. de VAV\.html|Informe de P\.K\. incremental de VAV\.html|CF\.txt|CP1\.txt|CP2\.txt|CF\.pdf|CP1\.pdf|CP2\.pdf|TRAMO1\.pdf|TRAMO2\.pdf|Mediciones_Auxiliares_Trazado\.xlsx|Actualizacion_Mediciones_Zanja_CF_CP1_CP2\.md|Anejo4_HTML_WORD_Trazabilidad\.xls|Anejo4_HTML_WORD_Trazabilidad\.md)$') {
        Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
            -Key 'anejo4-mediciones-auxiliares' `
            -Title 'Anejo 4 - mediciones auxiliares y trazado' `
            -Block '4.- Trazado, Replanteo y Mediciones Auxiliares' `
            -Priority 'alta' `
            -Reason 'Se ha tocado una fuente o derivado de mediciones auxiliares del Anejo 4.' `
            -Actions @(
                'Revisar tablas de mediciones auxiliares',
                'Regenerar la matriz HTML-Word con scripts/build_anejo4_html_word_traceability.ps1',
                'Si solo fallan headings del 2.2, aplicar scripts/fix_anejo4_alzado_heading_styles.ps1',
                'Si procede, ejecutar scripts/update_anejo4_mediciones_tables.ps1',
                'Si el bloque cambia de forma sustancial, reconstruir con scripts/rebuild_anejo4_mediciones_profesional.ps1'
            ) `
            -Derived @(
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Mediciones_Auxiliares_Trazado.xlsx',
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anejo4_HTML_WORD_Trazabilidad.xls',
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anejo4_HTML_WORD_Trazabilidad.md',
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Revision_Anexo4_Mediciones_Auxiliares.md',
                'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anexo 4 - Replanteo y Mediciones Auxiliares.docx'
            ) `
            -Checks @(
                'tools/check_office_mojibake.ps1',
                'tools/check_excel_formula_guard.ps1 si se toca Excel',
                'tools/check_traceability_consistency.ps1 si arrastra a mediciones o presupuesto'
            ) `
            -Note 'Aqui puede haber impacto en mediciones, pero no todo cambio de fuente implica BC3.'
        return $true
    }

    if ($path -match '^DOCS/Documentos de Trabajo/17\.- Seguridad y Salud/' -and
        $path -match '(Dimensionado|SyS_|Seguridad & Salud|Anejo 17)') {
        Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
            -Key 'anejo17-sys' `
            -Title 'Anejo 17 - Seguridad y Salud' `
            -Block '17.- Seguridad y Salud' `
            -Priority 'alta' `
            -Reason 'El cambio entra en el bloque de Seguridad y Salud, con posible arrastre documental y de trazabilidad.' `
            -Actions @(
                'Revisar coherencia entre docx, excel, xml y BC3/PZH',
                'Si procede, ejecutar scripts/sync_sys_traceability.ps1'
            ) `
            -Derived @(
                'DOCS/Documentos de Trabajo/17.- Seguridad y Salud/Anejo 17 - Estudio de Seguridad y Salud.docx',
                'DOCS/Documentos de Trabajo/17.- Seguridad y Salud/Dimensionado_SyS_Guadalmar.xlsx',
                'DOCS/Documentos de Trabajo/17.- Seguridad y Salud/535.2.2-Seguridad & Salud.bc3',
                'DOCS/Documentos de Trabajo/17.- Seguridad y Salud/535.2.2-Seguridad & Salud.pzh'
            ) `
            -Checks @(
                'tools/check_office_mojibake.ps1',
                'tools/check_excel_formula_guard.ps1',
                'tools/check_docx_tables_consistency.ps1',
                'tools/check_bc3_integrity.ps1',
                'tools/check_traceability_consistency.ps1'
            ) `
            -Note 'Este bloque mezcla documento, trazabilidad y presupuesto; requiere cierre coordinado.'
        return $true
    }

    if ($path -match '^DOCS/Documentos de Trabajo/13\.- Estudio de Gestion de Residuos/' -or
        $path -match '^DOCS/Documentos de Trabajo/14\.- Control de Calidad/' -or
        $path -match '^DOCS/Documentos de Trabajo/15\.- Plan de Obra/') {
        $block = Get-BlockLabel -Path $path
        Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
            -Key ("bloque-" + $block) `
            -Title ("Bloque documental - " + $block) `
            -Block $block `
            -Priority 'media' `
            -Reason 'Se ha modificado un bloque documental de anejo con posible arrastre sobre su Word y soportes Excel.' `
            -Actions @(
                'Revisar el anejo y sus soportes de origen',
                'Mantener solo lo necesario y cerrar el bloque con sus checks'
            ) `
            -Derived @() `
            -Checks @(
                'tools/check_office_mojibake.ps1',
                'tools/check_docx_tables_consistency.ps1 si hay Word con tablas',
                'tools/check_excel_formula_guard.ps1 si hay Excel'
            ) `
            -Note 'No asumir impacto BC3 salvo que haya mediciones o partidas afectadas.'
        return $true
    }

    return $false
}

function Add-GenericImpact {
    param(
        [pscustomobject]$Entry,
        [hashtable]$ImpactMap
    )

    $path = $Entry.Path
    $ext = Get-Extension -Path $path
    $block = Get-BlockLabel -Path $path

    switch ($ext) {
        '.docx' {
            Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
                -Key ("word:" + $path) `
                -Title ("Documento Word - " + $block) `
                -Block $block `
                -Priority 'media' `
                -Reason 'Se ha detectado un Word cambiado; suele impactar el anejo o informe del mismo bloque.' `
                -Actions @(
                    'Revisar el contenido visible modificado',
                    'Si hay tablas, captions o maquetacion, cerrar el documento antes de subir'
                ) `
                -Derived @() `
                -Checks @(
                    'tools/check_office_mojibake.ps1',
                    'tools/check_docx_tables_consistency.ps1'
                ) `
                -Note 'Un Word modificado no implica por si solo cambios en BC3.'
            return
        }
        '.docm' {
            Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
                -Key ("word:" + $path) `
                -Title ("Documento Word - " + $block) `
                -Block $block `
                -Priority 'media' `
                -Reason 'Se ha detectado un DOCM cambiado; requiere el mismo cierre documental que un DOCX.' `
                -Actions @('Revisar el contenido visible modificado') `
                -Derived @() `
                -Checks @(
                    'tools/check_office_mojibake.ps1',
                    'tools/check_docx_tables_consistency.ps1'
                ) `
                -Note 'Controlar tablas, captions y fuentes.'
            return
        }
        '.xlsx' {
            Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
                -Key ("excel:" + $path) `
                -Title ("Excel - " + $block) `
                -Block $block `
                -Priority 'media' `
                -Reason 'Se ha detectado un Excel cambiado; puede ser fuente, soporte o entregable del bloque.' `
                -Actions @(
                    'Revisar si el Excel es fuente o salida final',
                    'Si deriva de un bloque documental, revisar el anejo asociado'
                ) `
                -Derived @() `
                -Checks @(
                    'tools/check_office_mojibake.ps1',
                    'tools/check_excel_formula_guard.ps1'
                ) `
                -Note 'Preservar formulas antes de dar el cambio por cerrado.'
            return
        }
        '.xlsm' {
            Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
                -Key ("excel:" + $path) `
                -Title ("Excel - " + $block) `
                -Block $block `
                -Priority 'media' `
                -Reason 'Se ha detectado un Excel con macros cambiado; requiere control reforzado.' `
                -Actions @('Revisar si el archivo es fuente o entregable final') `
                -Derived @() `
                -Checks @(
                    'tools/check_office_mojibake.ps1',
                    'tools/check_excel_formula_guard.ps1'
                ) `
                -Note 'No sustituir formulas por valores.'
            return
        }
        '.xls' {
            Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
                -Key ("xls-legacy:" + $path) `
                -Title ("Excel legacy - " + $block) `
                -Block $block `
                -Priority 'baja' `
                -Reason 'Se ha detectado un XLS legado; suele ser soporte historico o fuente auxiliar.' `
                -Actions @('Verificar si existe una version xlsx maquetada mas fiable') `
                -Derived @() `
                -Checks @('Revisar manualmente la coherencia del contenido') `
                -Note 'La validacion automatica es mas limitada que en XLSX.'
            return
        }
        '.bc3' {
            Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
                -Key ("bc3:" + $path) `
                -Title ("BC3 - " + $block) `
                -Block $block `
                -Priority 'alta' `
                -Reason 'Se ha detectado un BC3 cambiado; puede arrastrar mediciones, textos y recursos.' `
                -Actions @(
                    'Revisar partidas y lineas afectadas',
                    'Confirmar que no quedan conceptos huerfanos ni precios incoherentes'
                ) `
                -Derived @() `
                -Checks @(
                    'tools/check_bc3_integrity.ps1',
                    'tools/check_traceability_consistency.ps1 si arrastra a docs o Excel'
                ) `
                -Note 'Controlar siempre las lineas ~C, ~D, ~T y ~M afectadas.'
            return
        }
        '.pzh' {
            Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
                -Key ("pzh:" + $path) `
                -Title ("PZH - " + $block) `
                -Block $block `
                -Priority 'alta' `
                -Reason 'Se ha detectado un PZH cambiado; suele ir ligado a presupuesto o SyS.' `
                -Actions @('Revisar coherencia con su BC3 de referencia') `
                -Derived @() `
                -Checks @(
                    'tools/check_bc3_integrity.ps1',
                    'tools/check_traceability_consistency.ps1 si hay arrastre documental'
                ) `
                -Note 'No cerrar este cambio sin revisar su contenedor presupuestario.'
            return
        }
        '.html' {
            Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
                -Key ("html:" + $path) `
                -Title ("Fuente HTML - " + $block) `
                -Block $block `
                -Priority 'media' `
                -Reason 'Se ha detectado un HTML cambiado; normalmente es una exportacion fuente para tablas, PK o informes.' `
                -Actions @('Revisar si este HTML alimenta CSV, Excel o Word del mismo bloque') `
                -Derived @() `
                -Checks @('Comprobar el paquete derivado del bloque antes de subirlo') `
                -Note 'Los HTML suelen ser disparadores de regeneracion, no entregables finales.'
            return
        }
        '.csv' {
            Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
                -Key ("csv:" + $path) `
                -Title ("CSV derivado - " + $block) `
                -Block $block `
                -Priority 'media' `
                -Reason 'Se ha detectado un CSV cambiado; puede ser una salida trazable o una fuente intermedia.' `
                -Actions @('Revisar el documento o Excel que consuma este CSV') `
                -Derived @() `
                -Checks @('Comprobar trazabilidad del bloque si hay arrastre a documentos o presupuesto') `
                -Note 'El CSV suele ser soporte, no cierre final.'
            return
        }
        default {
            Add-Impact -ImpactMap $ImpactMap -Entry $Entry `
                -Key ("generic:" + $path) `
                -Title ("Cambio detectado - " + $block) `
                -Block $block `
                -Priority 'baja' `
                -Reason 'Se ha detectado un cambio que no entra en una regla especifica.' `
                -Actions @('Revisar manualmente el bloque y decidir si genera arrastre') `
                -Derived @() `
                -Checks @() `
                -Note 'Si este tipo de cambio se repite, conviene anadir una regla especifica al detector.'
            return
        }
    }
}

function Build-Report {
    param([object[]]$Entries)

    $impactMap = @{}
    foreach ($entry in $Entries) {
        $matched = Test-SpecialRule -Entry $entry -ImpactMap $impactMap
        if (-not $matched) {
            Add-GenericImpact -Entry $entry -ImpactMap $impactMap
        }
    }

    $priorityOrder = @{
        alta = 0
        media = 1
        baja = 2
    }

    $impacts = @(
        $impactMap.Values |
            Sort-Object @{ Expression = { $priorityOrder[$_.Priority] } }, @{ Expression = { $_.Block } }, @{ Expression = { $_.Title } }
    )

    return [pscustomobject]@{
        Root = (Resolve-Path -LiteralPath $Root).Path
        GeneratedAt = (Get-Date).ToString('s')
        EntriesAnalyzed = @($Entries)
        ImpactCount = $impacts.Count
        Impacts = $impacts
    }
}

function Invoke-PowerShellFile {
    param(
        [string]$RootPath,
        [string]$FilePath,
        [string[]]$ArgumentList
    )

    $fullPath = Join-Path $RootPath $FilePath
    $splat = @{}
    $index = 0
    while ($index -lt $ArgumentList.Count) {
        $name = [string]$ArgumentList[$index]
        if (-not $name.StartsWith('-')) {
            $index++
            continue
        }

        $paramName = $name.TrimStart('-')
        if (($index + 1) -lt $ArgumentList.Count -and -not ([string]$ArgumentList[$index + 1]).StartsWith('-')) {
            $value = $ArgumentList[$index + 1]
            if ($value -is [string]) {
                switch -Regex ($value) {
                    '^(1|true)$' { $value = $true; break }
                    '^(0|false)$' { $value = $false; break }
                }
            }
            $splat[$paramName] = $value
            $index += 2
        }
        else {
            $splat[$paramName] = $true
            $index += 1
        }
    }

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        try {
            $output = @(& $fullPath @splat 2>&1)
            $exitCode = if ($?) { 0 } else { 1 }
        }
        catch {
            $output = @($_.Exception.Message)
            $exitCode = 1
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

function Repair-DocxContainer {
    param(
        [string]$RootPath,
        [string]$RelativePath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $source = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "No existe el DOCX a reparar: $source"
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $tmpExtract = Join-Path (Join-Path $RootPath '.codex_tmp') ("docx_repair_" + $timestamp + "_" + [guid]::NewGuid().ToString('N'))
    $tmpZip = Join-Path (Join-Path $RootPath '.codex_tmp') ("docx_repair_" + $timestamp + ".zip")

    New-Item -ItemType Directory -Force -Path $tmpExtract | Out-Null

    try {
        $srcZip = [System.IO.Compression.ZipFile]::OpenRead($source)
        foreach ($entry in $srcZip.Entries) {
            $safeName = $entry.FullName -replace '\\', '/'
            if ([string]::IsNullOrWhiteSpace($safeName)) { continue }

            $destPath = Join-Path $tmpExtract $safeName
            $destDir = Split-Path -Parent $destPath
            if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            }

            $inStream = $entry.Open()
            $outStream = [System.IO.File]::Open($destPath, [System.IO.FileMode]::Create)
            try { $inStream.CopyTo($outStream) } finally { $outStream.Dispose(); $inStream.Dispose() }
        }
        $srcZip.Dispose()

        if (Test-Path -LiteralPath $tmpZip) {
            Remove-Item -LiteralPath $tmpZip -Force
        }

        $fs = [System.IO.File]::Open($tmpZip, [System.IO.FileMode]::Create)
        try {
            $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create, $false)
            $base = (Resolve-Path -LiteralPath $tmpExtract).Path
            Get-ChildItem -LiteralPath $base -Recurse -File | ForEach-Object {
                $relative = $_.FullName.Substring($base.Length).TrimStart('\', '/') -replace '\\', '/'
                $zipEntry = $zip.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
                $entryStream = $zipEntry.Open()
                $fileStream = [System.IO.File]::OpenRead($_.FullName)
                try { $fileStream.CopyTo($entryStream) } finally { $fileStream.Dispose(); $entryStream.Dispose() }
            }
            $zip.Dispose()
        }
        finally {
            $fs.Dispose()
        }

        Copy-Item -LiteralPath $tmpZip -Destination $source -Force
    }
    finally {
        if (Test-Path -LiteralPath $tmpExtract) {
            Remove-Item -LiteralPath $tmpExtract -Recurse -Force
        }
        if (Test-Path -LiteralPath $tmpZip) {
            Remove-Item -LiteralPath $tmpZip -Force
        }
    }
}

function Add-ExecutionLine {
    param(
        [hashtable]$Impact,
        [string]$Prefix,
        [string]$Text
    )

    Add-UniqueString -List $Impact.Executions -Value ($Prefix + ' ' + $Text)
}

function Add-VerificationLine {
    param(
        [hashtable]$Impact,
        [string]$Prefix,
        [string]$Text
    )

    Add-UniqueString -List $Impact.Verification -Value ($Prefix + ' ' + $Text)
}

function Invoke-ImpactActions {
    param(
        [pscustomobject]$Report,
        [string]$RootPath
    )

    foreach ($impact in @($Report.Impacts)) {
        switch ($impact.Key) {
            'anejo4-pk-alineaciones' {
                $build = Invoke-PowerShellFile -RootPath $RootPath -FilePath 'scripts/build_anejo4_alignment_pk_package.ps1' -ArgumentList @('-Root', $RootPath)
                if ($build.ExitCode -eq 0) {
                    Add-ExecutionLine -Impact $impact -Prefix '[OK]' -Text 'Paquete de PK de alineaciones regenerado con scripts/build_anejo4_alignment_pk_package.ps1'
                }
                else {
                    Add-ExecutionLine -Impact $impact -Prefix '[FALLO]' -Text 'Fallo al regenerar el paquete de PK de alineaciones'
                }

                $doc = Invoke-PowerShellFile -RootPath $RootPath -FilePath 'scripts/update_anejo4_docx_pk.ps1' -ArgumentList @('-Root', $RootPath)
                if ($doc.ExitCode -eq 0) {
                    Add-ExecutionLine -Impact $impact -Prefix '[OK]' -Text 'Documento derivado generado con scripts/update_anejo4_docx_pk.ps1'
                    Repair-DocxContainer -RootPath $RootPath -RelativePath 'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anexo 4 - Replanteo y Mediciones Auxiliares_ACT.docx'
                    Add-ExecutionLine -Impact $impact -Prefix '[OK]' -Text 'Contenedor DOCX normalizado para permitir checks de tablas'
                }
                else {
                    Add-ExecutionLine -Impact $impact -Prefix '[FALLO]' -Text 'Fallo al generar el documento derivado del Anejo 4'
                }

                $trace = Invoke-PowerShellFile -RootPath $RootPath -FilePath 'scripts/build_anejo4_html_word_traceability.ps1' -ArgumentList @('-Root', $RootPath)
                if ($trace.ExitCode -eq 0) {
                    Add-ExecutionLine -Impact $impact -Prefix '[OK]' -Text 'Matriz HTML-Word regenerada con scripts/build_anejo4_html_word_traceability.ps1'
                }
                else {
                    Add-ExecutionLine -Impact $impact -Prefix '[FALLO]' -Text 'Fallo al regenerar la matriz HTML-Word del Anejo 4'
                }

                $checkOffice = Invoke-PowerShellFile -RootPath $RootPath -FilePath 'tools/check_office_mojibake.ps1' -ArgumentList @(
                    '-Paths',
                    'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anexo 4 - Replanteo y Mediciones Auxiliares_ACT.docx'
                )
                if ($checkOffice.ExitCode -eq 0) {
                    Add-VerificationLine -Impact $impact -Prefix '[OK]' -Text 'check_office_mojibake sobre Anexo 4 - ACT'
                }
                else {
                    Add-VerificationLine -Impact $impact -Prefix '[FALLO]' -Text 'check_office_mojibake sobre Anexo 4 - ACT'
                }

                $checkDoc = Invoke-PowerShellFile -RootPath $RootPath -FilePath 'tools/check_docx_tables_consistency.ps1' -ArgumentList @(
                    '-Paths',
                    'DOCS/Documentos de Trabajo/4.- Trazado, Replanteo y Mediciones Auxiliares/Anexo 4 - Replanteo y Mediciones Auxiliares_ACT.docx',
                    '-ExpectedFont', 'Montserrat',
                    '-EnforceFont', '1',
                    '-RequireTableCaption', '1'
                )
                if ($checkDoc.ExitCode -eq 0) {
                    Add-VerificationLine -Impact $impact -Prefix '[OK]' -Text 'check_docx_tables_consistency sobre Anexo 4 - ACT'
                }
                else {
                    Add-VerificationLine -Impact $impact -Prefix '[FALLO]' -Text 'check_docx_tables_consistency sobre Anexo 4 - ACT'
                }

                foreach ($line in @($build.Output + $doc.Output + $trace.Output + $checkOffice.Output + $checkDoc.Output)) {
                    if ($line -match '^(Documento actualizado:|OK OFFICE:|FALLO DOCX:|Control DOCX|OK|FALLO)') {
                        Add-VerificationLine -Impact $impact -Prefix '[DETALLE]' -Text $line
                    }
                }
            }
            'anejo4-mediciones-auxiliares' {
                $trace = Invoke-PowerShellFile -RootPath $RootPath -FilePath 'scripts/build_anejo4_html_word_traceability.ps1' -ArgumentList @('-Root', $RootPath)
                if ($trace.ExitCode -eq 0) {
                    Add-ExecutionLine -Impact $impact -Prefix '[OK]' -Text 'Matriz HTML-Word regenerada con scripts/build_anejo4_html_word_traceability.ps1'
                }
                else {
                    Add-ExecutionLine -Impact $impact -Prefix '[FALLO]' -Text 'Fallo al regenerar la matriz HTML-Word del Anejo 4'
                }
            }
            default {
                Add-ExecutionLine -Impact $impact -Prefix '[PENDIENTE]' -Text 'Sin automatizacion segura todavia; solo deteccion y propuesta de impacto'
            }
        }
    }
}

function Write-TextReport {
    param([pscustomobject]$Report)

    if ($Report.EntriesAnalyzed.Count -eq 0) {
        Write-Output 'No se han detectado cambios para analizar.'
        return
    }

    Write-Output 'DETECTOR DE IMPACTO DE CAMBIOS'
    Write-Output ('Raiz: ' + $Report.Root)
    Write-Output ('Archivos analizados: ' + $Report.EntriesAnalyzed.Count)
    Write-Output ('Impactos detectados: ' + $Report.ImpactCount)
    Write-Output ''

    foreach ($impact in $Report.Impacts) {
        Write-Output ('[' + $impact.Priority.ToUpperInvariant() + '] ' + $impact.Title)
        Write-Output ('Bloque: ' + $impact.Block)
        Write-Output ('Motivo: ' + $impact.Reason)
        if ($impact.Note) {
            Write-Output ('Nota: ' + $impact.Note)
        }

        Write-Output 'Archivos origen detectados:'
        foreach ($file in @($impact.ChangedFiles)) {
            $statusLine = ($Report.EntriesAnalyzed | Where-Object { $_.Path -eq $file } | Select-Object -First 1).Statuses -join ', '
            Write-Output ('  - [' + $statusLine + '] ' + $file)
        }

        if ($impact.Derived.Count -gt 0) {
            Write-Output 'Arrastre probable:'
            foreach ($item in @($impact.Derived)) {
                Write-Output ('  - ' + $item)
            }
        }

        if ($impact.Actions.Count -gt 0) {
            Write-Output 'Accion recomendada:'
            foreach ($item in @($impact.Actions)) {
                Write-Output ('  - ' + $item)
            }
        }

        if ($impact.Checks.Count -gt 0) {
            Write-Output 'Control final sugerido:'
            foreach ($item in @($impact.Checks)) {
                Write-Output ('  - ' + $item)
            }
        }

        if ($impact.Executions.Count -gt 0) {
            Write-Output 'Ejecucion automatica:'
            foreach ($item in @($impact.Executions)) {
                Write-Output ('  - ' + $item)
            }
        }

        if ($impact.Verification.Count -gt 0) {
            Write-Output 'Verificacion automatica:'
            foreach ($item in @($impact.Verification)) {
                Write-Output ('  - ' + $item)
            }
        }

        Write-Output ''
    }
}

$entries = @(Get-InputEntries -RootPath $Root -SelectedPaths $Paths)
$report = Build-Report -Entries $entries

if ($Apply) {
    Invoke-ImpactActions -Report $report -RootPath $Root
}

if ($OutputFormat -eq 'json') {
    $report | ConvertTo-Json -Depth 8
}
else {
    Write-TextReport -Report $report
}
