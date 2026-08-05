# Graph Report - proc_dynamic_sirweb  (2026-08-01)

## Corpus Check
- 44 files · ~15,517 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 491 nodes · 581 edges · 53 communities (23 shown, 30 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 14 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `cd853f6c`
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

## God Nodes (most connected - your core abstractions)
1. `Win32Window` - 19 edges
2. `MessageHandler` - 12 edges
3. `ProcedimientosProvider` - 11 edges
4. `FlutterWindow` - 10 edges
5. `Create` - 10 edges
6. `WndProc` - 10 edges
7. `MessageHandler` - 8 edges
8. `Flutter Application` - 8 edges
9. `WindowClassRegistrar` - 7 edges
10. `Destroy` - 7 edges

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

## Communities (53 total, 30 thin omitted)

### Community 0 - "Code Editor Core"
Cohesion: 0.03
Nodes (62): activo, _code, _emit, _err, _errs, _EstadoChip, _fallbackConfigs, _handleEnd (+54 more)

### Community 1 - "Windows Runner & Flutter Engine"
Cohesion: 0.09
Nodes (39): PluginRegistry, Point, RECT, Size, RegisterPlugins(), OnCreate, HWND, LPARAM (+31 more)

### Community 2 - "Procedures State Management"
Cohesion: 0.04
Nodes (47): int get, activar, _ambiente, buscar, _cargando, _cargandoEditor, _cargandoMas, cargarConfiguraciones (+39 more)

### Community 3 - "App Entry & UI Shell"
Cohesion: 0.06
Nodes (39): ChangeNotifier, config_badge.dart, ProcedimientosProvider, ThemeProvider, activo, build, _EstadoBadge, onTap (+31 more)

### Community 5 - "Theme & Environment Selector"
Cohesion: 0.08
Nodes (22): bool get, isDark, _themeMode, toggle, _ambientes, AmbienteSelector, build, _colorForAmbiente (+14 more)

### Community 6 - "New Procedure Dialog"
Cohesion: 0.09
Nodes (22): CodeLineEditingController, FormState, build, _buildBody, _buildCodigoField, _buildDialogHeader, _buildFooter, _buildUsuarioField (+14 more)

### Community 7 - "SirWeb API Service"
Cohesion: 0.06
Nodes (29): dart:convert, JavascriptRuntime?, activarProcedimiento, actualizarProcedimiento, _baseUrl, _call, crearProcedimiento, desactivarProcedimiento (+21 more)

### Community 8 - "Main Screen Layout"
Cohesion: 0.14
Nodes (13): cdUsuario, onTap, _UsuarioButton, _buildAppBar, _buildEditorView, createState, build, build (+5 more)

### Community 9 - "State & Widget Lifecycle"
Cohesion: 0.20
Nodes (10): _ConfigSelector, initState, _showNewProcedureDialog, _showUsuarioDialog, _showVariablesModal, build, _buildConfigDropdown, _crear (+2 more)

### Community 10 - "Project Configuration"
Cohesion: 0.17
Nodes (12): flutter_lints rules, Debug/Profile/Release Configs, C++17 Standard, Flutter Windows Build System, proc_dynamic_sirweb binary, Dart SDK ^3.12.1, Flutter Application, http package (+4 more)

### Community 11 - "Windows Entry Point"
Cohesion: 0.09
Nodes (24): FlutterViewController, _In_, _In_opt_, unique_ptr, vector, DartProject, HWND, LPARAM (+16 more)

### Community 12 - "monaco_editor_widget.dart"
Cohesion: 0.06
Nodes (34): dart:async, EditorOptions get, _attach, build, clearErrors, col, controller, createState (+26 more)

### Community 13 - "Stateful Widget Classes"
Cohesion: 0.32
Nodes (8): MainScreen, _MainScreenState, CodeEditorPanel, _CodeEditorPanelState, NewProcedureDialog, _NewProcedureDialogState, State, StatefulWidget

### Community 14 - "Config Type Model"
Cohesion: 0.29
Nodes (6): cdModulo, ConfiguracionTipo, deArgumento, fromJson, label, String get

### Community 15 - "Dynamic Variable Model"
Cohesion: 0.33
Nodes (5): cdVariable, deVariable, fromJson, inConfiguracion, VariableDinamica

### Community 24 - "main.dart"
Cohesion: 0.18
Nodes (10): build, _buildDarkTheme, _buildLightTheme, main, ProcDynamicApp, ../providers/procedimientos_provider.dart, ../providers/theme_provider.dart, screens/main_screen.dart (+2 more)

### Community 25 - "package.json"
Cohesion: 0.11
Nodes (18): antlr4, rollup, @rollup/plugin-commonjs, @rollup/plugin-node-resolve, @rollup/plugin-terser, dependencies, antlr4, description (+10 more)

### Community 28 - "procedimiento.dart"
Cohesion: 0.17
Nodes (11): activo, cdProcedimiento, cdUsuario, copyWith, deTexto, feModificacion, fromJson, inConfiguracion (+3 more)

### Community 31 - "_editor_js_engine_stub.dart"
Cohesion: 0.50
Nodes (3): evalJsSyntax, evalPlSqlSyntax, initPlSqlEngine

## Knowledge Gaps
- **263 isolated node(s):** `_rt`, `_rtInitialized`, `_plSqlReady`, `_plSqlLoading`, `_initRuntime` (+258 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **30 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ProcedimientosProvider` connect `App Entry & UI Shell` to `Procedures State Management`?**
  _High betweenness centrality (0.034) - this node is a cross-community bridge._
- **Why does `Procedimiento` connect `procedimiento.dart` to `Procedures State Management`, `App Entry & UI Shell`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._
- **Why does `MonacoController` connect `monaco_editor_widget.dart` to `Code Editor Core`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `MessageHandler` (e.g. with `Destroy` and `GetClientArea`) actually correct?**
  _`MessageHandler` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `_rt`, `_rtInitialized`, `_plSqlReady` to the rest of the system?**
  _263 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Code Editor Core` be split into smaller, more focused modules?**
  _Cohesion score 0.031746031746031744 - nodes in this community are weakly interconnected._
- **Should `Windows Runner & Flutter Engine` be split into smaller, more focused modules?**
  _Cohesion score 0.08686868686868687 - nodes in this community are weakly interconnected._