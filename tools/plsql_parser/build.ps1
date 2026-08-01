#!/usr/bin/env pwsh
# ─── build.ps1 ────────────────────────────────────────────────────────────────
# Genera el bundle ANTLR4 PL/SQL → assets/plsql_checker.js
#
# Requisitos:
#   - Node.js 18+   (https://nodejs.org)
#   - Java 11+      (https://adoptium.net)
#
# Uso:
#   cd tools/plsql_parser
#   ./build.ps1
# ──────────────────────────────────────────────────────────────────────────────

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ToolDir  = $PSScriptRoot
$Root     = Split-Path -Parent $ToolDir
$GenDir   = Join-Path $ToolDir 'generated'
$GramDir  = Join-Path $ToolDir 'grammar'
$AssetDir = Join-Path $Root 'assets'
$Jar      = Join-Path $ToolDir 'antlr-4.13.2-complete.jar'

function Info  { param($m) Write-Host "  $m" -ForegroundColor Cyan }
function OK    { param($m) Write-Host "  OK   $m" -ForegroundColor Green }
function Warn  { param($m) Write-Host "  WARN $m" -ForegroundColor Yellow }
function Fail  { param($m) Write-Host "`n  ERR  $m" -ForegroundColor Red; exit 1 }
function Title { param($m) Write-Host "`n─── $m " -ForegroundColor White }

# ── 1. Verificar herramientas ─────────────────────────────────────────────────
Title "Verificando herramientas"

try   { $v = node --version 2>&1; OK "Node.js $v" }
catch { Fail "Node.js no encontrado. Instala desde https://nodejs.org" }

try   { $v = npm --version 2>&1; OK "npm $v" }
catch { Fail "npm no encontrado" }

try   { $v = (java -version 2>&1 | Out-String).Trim().Split("`n")[0]; OK "Java: $v" }
catch { Fail "Java no encontrado. Instala JDK 11+ desde https://adoptium.net" }

# ── 2. Descargar ANTLR4 jar ───────────────────────────────────────────────────
Title "ANTLR4 jar"

if (!(Test-Path $Jar)) {
  Info "Descargando antlr-4.13.2-complete.jar (~7 MB)..."
  Invoke-WebRequest `
    -Uri     'https://www.antlr.org/download/antlr-4.13.2-complete.jar' `
    -OutFile $Jar `
    -UseBasicParsing
  OK "Descargado"
} else {
  OK "Ya existe: $(Split-Path -Leaf $Jar)"
}

# ── 3. Descargar gramáticas ───────────────────────────────────────────────────
Title "Gramáticas PL/SQL Oracle (grammars-v4)"

$base = 'https://raw.githubusercontent.com/antlr/grammars-v4/master/sql/plsql'
$downloads = @(
  @{ url = "$base/PlSqlLexer.g4";                dst = (Join-Path $GramDir 'PlSqlLexer.g4')  }
  @{ url = "$base/PlSqlParser.g4";               dst = (Join-Path $GramDir 'PlSqlParser.g4') }
  @{ url = "$base/JavaScript/PlSqlLexerBase.js";  dst = (Join-Path $GenDir  'PlSqlLexerBase.js') }
  @{ url = "$base/JavaScript/PlSqlParserBase.js"; dst = (Join-Path $GenDir  'PlSqlParserBase.js') }
)

foreach ($d in $downloads) {
  if (!(Test-Path $d.dst)) {
    $name = Split-Path -Leaf $d.dst
    Info "Descargando $name..."
    try {
      Invoke-WebRequest -Uri $d.url -OutFile $d.dst -UseBasicParsing
      OK $name
    } catch {
      Warn "No se pudo descargar $name : $_"
    }
  } else {
    OK "Ya existe: $(Split-Path -Leaf $d.dst)"
  }
}

# ── 4. Generar parser JS con ANTLR4 ───────────────────────────────────────────
Title "Generando Lexer + Parser en JavaScript"

Info "Ejecutando ANTLR4 (puede tardar ~20-40 s la primera vez)..."
$antlrArgs = @(
  '-jar', $Jar,
  '-Dlanguage=JavaScript',
  '-visitor',
  '-o', $GenDir,
  (Join-Path $GramDir 'PlSqlLexer.g4'),
  (Join-Path $GramDir 'PlSqlParser.g4')
)

$proc = Start-Process java -ArgumentList $antlrArgs -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
  Fail "ANTLR4 fallo (exit $($proc.ExitCode)). Revisa que el JAR es valido."
}

# ANTLR4 puede anidar en subdirectorios segun la ruta de la gramatica.
# Aplanamos todo a $GenDir.
Get-ChildItem $GenDir -Recurse -File -Filter '*.js' | Where-Object {
  $_.DirectoryName -ne $GenDir
} | ForEach-Object {
  $dest = Join-Path $GenDir $_.Name
  if (!(Test-Path $dest)) {
    Copy-Item $_.FullName $dest
    OK "Movido: $($_.Name)"
  }
}

$required = @('PlSqlLexer.js', 'PlSqlParser.js')
foreach ($f in $required) {
  if (!(Test-Path (Join-Path $GenDir $f))) {
    Fail "No se genero $f — revisa que las gramaticas sean correctas"
  }
}
OK "Archivos generados: PlSqlLexer.js, PlSqlParser.js"

# ── 5. npm install ────────────────────────────────────────────────────────────
Title "Instalando dependencias npm"

Push-Location $ToolDir
try {
  npm install --silent 2>&1 | Out-Null
  OK "node_modules listo"
} finally {
  Pop-Location
}

# ── 6. Crear carpeta de assets ────────────────────────────────────────────────
$null = New-Item -ItemType Directory -Force $AssetDir

# ── 7. Rollup build ───────────────────────────────────────────────────────────
Title "Build con rollup + terser"

Push-Location $ToolDir
try {
  npx rollup --config rollup.config.mjs 2>&1
} finally {
  Pop-Location
}

$out = Join-Path $AssetDir 'plsql_checker.js'
if (!(Test-Path $out)) { Fail "El bundle no se genero en: $out" }

$sizeKB = [math]::Round((Get-Item $out).Length / 1024, 0)
OK "assets/plsql_checker.js  ($sizeKB KB)"

# ── Fin ───────────────────────────────────────────────────────────────────────
Title "Build completado"
Write-Host @"

  El bundle esta listo. Pasos finales en Flutter:

  1. Asegurate de que pubspec.yaml tenga:
       flutter:
         assets:
           - assets/plsql_checker.js

  2. flutter pub get
  3. flutter run

"@ -ForegroundColor White
