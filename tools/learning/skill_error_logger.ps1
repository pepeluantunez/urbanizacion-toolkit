<#
.SYNOPSIS
    Registra errores de ejecucion de skills y agentes en un log estructurado JSON.

.DESCRIPTION
    Cada vez que una skill, script o agente falla, este script registra el error
    con contexto suficiente para que skill_self_improve.ps1 pueda analizarlo
    y proponer correcciones.

.PARAMETER Skill
    Nombre de la skill o script que ha fallado (ej: "anejo-generator", "check_bc3_integrity.ps1")

.PARAMETER Error
    Descripcion del error o mensaje de fallo

.PARAMETER Contexto
    Descripcion breve de la tarea que se estaba ejecutando

.PARAMETER Categoria
    Tipo de fallo: "script", "skill", "agente", "herramienta" (por defecto: "skill")

.EXAMPLE
    .\skill_error_logger.ps1 -Skill "anejo-generator" -Error "KeyError en columna Unidad" -Contexto "Generando anejo de mediciones pluviales"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Skill,

    [Parameter(Mandatory=$true)]
    [string]$Error,

    [Parameter(Mandatory=$false)]
    [string]$Contexto = "",

    [Parameter(Mandatory=$false)]
    [ValidateSet("script", "skill", "agente", "herramienta")]
    [string]$Categoria = "skill"
)

$ErrorActionPreference = "Stop"

# Ruta del log
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$LogDir = Join-Path $ProjectRoot "scratch\skill_improvement"
$LogFile = Join-Path $LogDir "error_log.json"

# Crear directorio si no existe
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Cargar log existente o inicializar
$Log = @()
if (Test-Path $LogFile) {
    try {
        $Log = Get-Content $LogFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $Log) { $Log = @() }
        # Asegurar que es array
        if ($Log -isnot [System.Collections.IEnumerable]) { $Log = @($Log) }
    } catch {
        Write-Warning "No se pudo leer el log existente. Se inicializa uno nuevo."
        $Log = @()
    }
}

# Nuevo registro
$Registro = [PSCustomObject]@{
    timestamp  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    skill      = $Skill
    categoria  = $Categoria
    error      = $Error
    contexto   = $Contexto
    estado     = "pendiente"  # pendiente | revisado | aplicado | descartado
}

$Log += $Registro

# Guardar
$Log | ConvertTo-Json -Depth 5 | Set-Content $LogFile -Encoding UTF8

Write-Host "[skill_error_logger] Registrado: '$Skill' -> $Error" -ForegroundColor Yellow
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
