# graphify-watch.ps1
# Inicia el watcher de graphify en background.
# Ejecutar desde la raiz del proyecto: .\graphify-watch.ps1
#
# Comportamiento:
#   - Cambios en .dart/.cpp/.h/etc → rebuild automatico de graph.json (sin LLM, sin costo)
#   - Cambios en .md/.yaml/docs     → notifica que se debe correr `graphify update .`

$PYTHON = Get-Content "graphify-out\.graphify_python" -ErrorAction Stop
Write-Host "graphify watcher iniciando..." -ForegroundColor Cyan
Write-Host "Monitoreando: $PWD" -ForegroundColor Gray
Write-Host "Presiona Ctrl+C para detener." -ForegroundColor Gray
Write-Host ""

& $PYTHON -m graphify.watch . --debounce 3
