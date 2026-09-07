# graphify.ps1
# Lanzador de graphify para este proyecto.
#
# El ejecutable `graphify` no esta en el PATH: graphify vive dentro del
# interprete de Python cuya ruta quedo guardada en graphify-out\.graphify_python
# durante la instalacion. Este script lo lee y delega todos los argumentos.
#
# Uso (desde la raiz del proyecto):
#   .\graphify.ps1 update .                 -> reindexa el codigo (sin LLM, sin costo)
#   .\graphify.ps1 query "como funciona X"  -> pregunta al grafo
#   .\graphify.ps1 path "A" "B"             -> camino mas corto entre dos nodos
#   .\graphify.ps1 explain "guardRequest"   -> explicacion de un nodo
#   .\graphify.ps1 god-nodes --top 10       -> hubs del proyecto
#   .\graphify.ps1 --help                   -> todos los comandos

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

$pythonFile = Join-Path $PSScriptRoot 'graphify-out\.graphify_python'

if (-not (Test-Path $pythonFile)) {
    Write-Host "No se encontro graphify-out\.graphify_python." -ForegroundColor Yellow
    Write-Host "Instala graphify con:  pip install graphifyy" -ForegroundColor Yellow
    Write-Host "y luego guarda el interprete con:" -ForegroundColor Yellow
    Write-Host '  python -c "import sys; open(''graphify-out/.graphify_python'',''w'').write(sys.executable)"' -ForegroundColor Yellow
    exit 1
}

$python = (Get-Content $pythonFile -Raw).Trim()

if (-not (Test-Path $python)) {
    Write-Host "El interprete registrado ya no existe: $python" -ForegroundColor Red
    Write-Host "Borra graphify-out\.graphify_python y vuelve a registrarlo." -ForegroundColor Red
    exit 1
}

if (-not $Args -or $Args.Count -eq 0) {
    $Args = @('--help')
}

& $python -m graphify @Args
exit $LASTEXITCODE

