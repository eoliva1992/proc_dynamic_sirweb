# Graph Report - proc_dynamic_sirweb  (2026-08-04)

## Corpus Check
- 46 files · ~15,217 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 507 nodes · 566 edges · 69 communities (21 shown, 48 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 14 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `16e0e74d`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Code Editor Core
- Windows Runner & Flutter Engine
- Procedures State Management
- App Entry & UI Shell
- Editor UI Components
- Theme & Environment Selector
- New Procedure Dialog
- SirWeb API Service
- Main Screen Layout
- State & Widget Lifecycle
- Project Configuration
- Windows Entry Point
- monaco_editor_widget.dart
- Stateful Widget Classes
- Config Type Model
- Dynamic Variable Model
- Variable Autocomplete
- SQL Chunk Analysis
- Keyword Prompts
- Error Gutter Indicator
- Error Gutter Renderer
- Flutter Lints Config
- Misc Utilities
- main.dart
- package.json
- CLAUDE.md
- procedimiento.dart
- ErrorCollector
- _editor_js_engine_stub.dart
- rollup.config.mjs
- _editor_js_engine_stub.dart
- class _AutocompletePopup extends
- CodeAutocompleteEditingValue
- CodeChunkController?
- CodeCommentFormatter get
- CodeFindController?
- CodeIndicatorValueNotifier
- Color?
- double get
- IconData
- package:flutter/rendering.dart
- package:re_highlight/re_highlight.dart
- package:re_highlight/styles/vs2015.dart
- Size get
- static const double
- static const int
- static final
- ThemeData
- ValueNotifier
- manifest.json
- ChangeNotifier
- CodeLineEditingController
- int get
- List
- monaco_editor_widget.dart
- package:flutter/foundation.dart
- package:provider/provider.dart
- package:re_editor/re_editor.dart
- package:re_highlight/languages/javascript.dart
- package:re_highlight/languages/sql.dart
- package:re_highlight/styles/github.dart
- Procedimiento? get
- ThemeMode get
- Timer?
- ViewMode get

## God Nodes (most connected - your core abstractions)
1. `Win32Window` - 19 edges
2. `MessageHandler` - 12 edges
3. `FlutterWindow` - 10 edges
4. `Create` - 10 edges
5. `WndProc` - 10 edges
6. `MessageHandler` - 8 edges
7. `Flutter Application` - 8 edges
8. `WindowClassRegistrar` - 7 edges
9. `Destroy` - 7 edges
10. `OnCreate` - 6 edges

## Surprising Connections (you probably didn't know these)
- `proc_dynamic_sirweb` --DESCRIBED_BY--> `Flutter Application`  [EXTRACTED]
  README.md → pubspec.yaml
- `Flutter Application` --USES--> `flutter_lints rules`  [EXTRACTED]
  pubspec.yaml → analysis_options.yaml
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `Win32Window::Win32Window()` --calls--> `Destroy`  [INFERRED]
  windows/runner/win32_window.cpp → windows/runner/win32_window.h
- `Flutter Application` --BUILT_BY--> `Flutter Windows Build System`  [EXTRACTED]
  pubspec.yaml → windows/CMakeLists.txt

## Import Cycles
- None detected.

## Communities (69 total, 48 thin omitted)

### Community 1 - "Windows Runner & Flutter Engine"
Cohesion: 0.06
Nodes (54): FlutterViewController, PluginRegistry, Point, RECT, Size, unique_ptr, RegisterPlugins(), DartProject (+46 more)

### Community 2 - "Procedures State Management"
Cohesion: 0.03
Nodes (62): _, toString, activar, _configuracionesCargadas, ambiente, cargando, cargandoEditor, cargandoMas (+54 more)

### Community 3 - "App Entry & UI Shell"
Cohesion: 0.07
Nodes (34): config_badge.dart, ProcDynamicApp, build, createState, _EditorPage, _EditorPageState, _error, main (+26 more)

### Community 5 - "Theme & Environment Selector"
Cohesion: 0.07
Nodes (29): _ambientes, AmbienteSelector, build, _colorForAmbiente, onChanged, value, build, _colors (+21 more)

### Community 6 - "New Procedure Dialog"
Cohesion: 0.09
Nodes (23): FormState, build, _buildBody, _buildCodigoField, _buildConfigDropdown, _buildDialogHeader, _buildFooter, _buildUsuarioField (+15 more)

### Community 7 - "SirWeb API Service"
Cohesion: 0.06
Nodes (29): dart:convert, JavascriptRuntime?, activarProcedimiento, actualizarProcedimiento, _baseUrl, _call, crearProcedimiento, desactivarProcedimiento (+21 more)

### Community 8 - "Main Screen Layout"
Cohesion: 0.05
Nodes (38): cdUsuario, onTap, _UsuarioButton, build, _buildDarkTheme, _buildLightTheme, loadFromPrefs, main (+30 more)

### Community 10 - "Project Configuration"
Cohesion: 0.17
Nodes (12): flutter_lints rules, Debug/Profile/Release Configs, C++17 Standard, Flutter Windows Build System, proc_dynamic_sirweb binary, Dart SDK ^3.12.1, Flutter Application, http package (+4 more)

### Community 11 - "Windows Entry Point"
Cohesion: 0.24
Nodes (9): _In_, _In_opt_, vector, wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments() (+1 more)

### Community 12 - "monaco_editor_widget.dart"
Cohesion: 0.06
Nodes (34): dart:async, EditorOptions get, attach, build, clearContent, clearErrors, col, controller (+26 more)

### Community 13 - "Stateful Widget Classes"
Cohesion: 0.13
Nodes (15): @action, buscar, cargarConfiguraciones, cargarMas, cargarVariablesDinamicas, crear, guardar, limpiarMensajes (+7 more)

### Community 14 - "Config Type Model"
Cohesion: 0.29
Nodes (6): cdModulo, ConfiguracionTipo, deArgumento, fromJson, label, String get

### Community 15 - "Dynamic Variable Model"
Cohesion: 0.33
Nodes (5): cdVariable, deVariable, fromJson, inConfiguracion, VariableDinamica

### Community 25 - "package.json"
Cohesion: 0.11
Nodes (18): antlr4, rollup, @rollup/plugin-commonjs, @rollup/plugin-node-resolve, @rollup/plugin-terser, dependencies, antlr4, description (+10 more)

### Community 28 - "procedimiento.dart"
Cohesion: 0.06
Nodes (29): bool get, _, toString, class, activo, cdProcedimiento, cdUsuario, copyWith (+21 more)

### Community 31 - "_editor_js_engine_stub.dart"
Cohesion: 0.50
Nodes (3): evalJsSyntax, evalPlSqlSyntax, initPlSqlEngine

### Community 53 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

## Knowledge Gaps
- **260 isolated node(s):** `main`, `loadFromPrefs`, `_buildDarkTheme`, `_buildLightTheme`, `build` (+255 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **48 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Are the 4 inferred relationships involving `MessageHandler` (e.g. with `Destroy` and `GetClientArea`) actually correct?**
  _`MessageHandler` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `main`, `loadFromPrefs`, `_buildDarkTheme` to the rest of the system?**
  _260 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Windows Runner & Flutter Engine` be split into smaller, more focused modules?**
  _Cohesion score 0.05817028027498678 - nodes in this community are weakly interconnected._
- **Should `Procedures State Management` be split into smaller, more focused modules?**
  _Cohesion score 0.031746031746031744 - nodes in this community are weakly interconnected._
- **Should `App Entry & UI Shell` be split into smaller, more focused modules?**
  _Cohesion score 0.06756756756756757 - nodes in this community are weakly interconnected._
- **Should `Theme & Environment Selector` be split into smaller, more focused modules?**
  _Cohesion score 0.06653225806451613 - nodes in this community are weakly interconnected._
- **Should `New Procedure Dialog` be split into smaller, more focused modules?**
  _Cohesion score 0.08695652173913043 - nodes in this community are weakly interconnected._