# Graph Report - proc_dynamic_sirweb  (2026-08-05)

## Corpus Check
- 53 files · ~20,715 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 670 nodes · 768 edges · 75 communities (29 shown, 46 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 14 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `0b5749cc`
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
- app_tab.dart
- procedure_card.dart
- StatelessWidget
- package:proc_dynamic_sirweb/models/procedimiento.dart
- ../widgets/procedure_list.dart
- ../widgets/search_bar_widget.dart

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
10. `SearchTabState` - 6 edges

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

## Communities (75 total, 46 thin omitted)

### Community 1 - "Windows Runner & Flutter Engine"
Cohesion: 0.09
Nodes (39): PluginRegistry, Point, RECT, Size, RegisterPlugins(), OnCreate, HWND, LPARAM (+31 more)

### Community 2 - "Procedures State Management"
Cohesion: 0.03
Nodes (61): _, toString, activar, _configuracionesCargadas, ambiente, cargando, cargandoEditor, cargandoMas (+53 more)

### Community 3 - "App Entry & UI Shell"
Cohesion: 0.07
Nodes (32): build, createState, _EditorPage, _EditorPageState, _error, main, _status, _TestApp (+24 more)

### Community 5 - "Theme & Environment Selector"
Cohesion: 0.05
Nodes (38): ambiente_selector.dart, ambientes, AmbienteSelector, build, colorForAmbiente, onChanged, value, build (+30 more)

### Community 6 - "New Procedure Dialog"
Cohesion: 0.06
Nodes (33): _editor_oracle_theme.dart, FormState, ambiente, build, _buildCodeSection, _buildCodigoField, _buildConfigSelector, _buildFooter (+25 more)

### Community 7 - "SirWeb API Service"
Cohesion: 0.06
Nodes (29): dart:convert, JavascriptRuntime?, activarProcedimiento, actualizarProcedimiento, _baseUrl, _call, crearProcedimiento, desactivarProcedimiento (+21 more)

### Community 8 - "Main Screen Layout"
Cohesion: 0.05
Nodes (41): cdUsuario, onTap, _UsuarioButton, build, _buildDarkTheme, _buildLightTheme, loadFromPrefs, main (+33 more)

### Community 10 - "Project Configuration"
Cohesion: 0.17
Nodes (12): flutter_lints rules, Debug/Profile/Release Configs, C++17 Standard, Flutter Windows Build System, proc_dynamic_sirweb binary, Dart SDK ^3.12.1, Flutter Application, http package (+4 more)

### Community 11 - "Windows Entry Point"
Cohesion: 0.09
Nodes (24): FlutterViewController, _In_, _In_opt_, unique_ptr, vector, DartProject, HWND, LPARAM (+16 more)

### Community 12 - "monaco_editor_widget.dart"
Cohesion: 0.06
Nodes (32): dart:async, EditorOptions get, attach, build, clearContent, clearErrors, col, controller (+24 more)

### Community 13 - "Stateful Widget Classes"
Cohesion: 0.12
Nodes (16): @action, buscar, cargarConfiguraciones, cargarMas, cargarVariablesDinamicas, crear, guardar, limpiarMensajes (+8 more)

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

### Community 43 - "IconData"
Cohesion: 0.05
Nodes (40): _editor_plsql_checker.dart, _editor_plsql_completions.dart, IconData, _activeProcId, build, _buildDocTabs, _buildToolbar, _checkPlSql (+32 more)

### Community 53 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 54 - "ChangeNotifier"
Cohesion: 0.17
Nodes (11): ChangeNotifier, SearchTabState, ambiente, build, onAmbienteChanged, onNewProcedure, state, procedure_list.dart (+3 more)

### Community 57 - "List"
Cohesion: 0.11
Nodes (18): buscar, cargando, cargandoMas, cargarMas, clearError, config, error, estado (+10 more)

### Community 59 - "package:flutter/foundation.dart"
Cohesion: 0.05
Nodes (34): oracleDark, oracleDarkTheme, oracleLight, oracleLightTheme, beginRe, blockStartCol, blockStartLine, buf (+26 more)

### Community 67 - "Timer?"
Cohesion: 0.18
Nodes (11): build, createState, dispose, initState, _onScroll, ProcedureList, _ProcedureListState, _scrollController (+3 more)

### Community 69 - "app_tab.dart"
Cohesion: 0.18
Nodes (10): ambiente, AppTab, _counter, inSearchMode, loading, procedimiento, searchState, tabId (+2 more)

### Community 70 - "procedure_card.dart"
Cohesion: 0.22
Nodes (8): config_badge.dart, activo, build, onTap, procedimiento, version, ../models/procedimiento.dart, Procedimiento

### Community 71 - "StatelessWidget"
Cohesion: 0.25
Nodes (8): _DocTab, _ToolBtn, ConfigBadge, _EstadoBadge, ProcedureCard, _VersionBadge, SearchTabView, StatelessWidget

## Knowledge Gaps
- **387 isolated node(s):** `main`, `loadFromPrefs`, `_buildDarkTheme`, `_buildLightTheme`, `build` (+382 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **46 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `SearchTabState` connect `ChangeNotifier` to `List`, `Theme & Environment Selector`, `Timer?`, `app_tab.dart`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **Why does `Win32Window` connect `Windows Runner & Flutter Engine` to `Windows Entry Point`?**
  _High betweenness centrality (0.004) - this node is a cross-community bridge._
- **Why does `FlutterWindow` connect `Windows Entry Point` to `Windows Runner & Flutter Engine`?**
  _High betweenness centrality (0.003) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `MessageHandler` (e.g. with `Destroy` and `GetClientArea`) actually correct?**
  _`MessageHandler` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `main`, `loadFromPrefs`, `_buildDarkTheme` to the rest of the system?**
  _387 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Windows Runner & Flutter Engine` be split into smaller, more focused modules?**
  _Cohesion score 0.08686868686868687 - nodes in this community are weakly interconnected._
- **Should `Procedures State Management` be split into smaller, more focused modules?**
  _Cohesion score 0.03225806451612903 - nodes in this community are weakly interconnected._