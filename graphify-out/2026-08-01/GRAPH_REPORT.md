# Graph Report - proc_dynamic_sirweb  (2026-07-29)

## Corpus Check
- 38 files · ~15,023 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 484 nodes · 623 edges · 26 communities (17 shown, 9 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 14 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `cd64ac31`
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
- Stateful Widget Classes
- Config Type Model
- Dynamic Variable Model
- Plugin Registry
- Variable Autocomplete
- SQL Chunk Analysis
- Keyword Prompts
- Error Gutter Indicator
- Error Gutter Renderer
- Flutter Lints Config
- Misc Utilities
- main.dart
- CLAUDE.md

## God Nodes (most connected - your core abstractions)
1. `Win32Window` - 19 edges
2. `StatelessWidget` - 14 edges
3. `MessageHandler` - 12 edges
4. `ProcedimientosProvider` - 11 edges
5. `FlutterWindow` - 10 edges
6. `Create` - 10 edges
7. `WndProc` - 10 edges
8. `MessageHandler` - 8 edges
9. `Flutter Application` - 8 edges
10. `WindowClassRegistrar` - 7 edges

## Surprising Connections (you probably didn't know these)
- `proc_dynamic_sirweb` --DESCRIBED_BY--> `Flutter Application`  [EXTRACTED]
  README.md → pubspec.yaml
- `Flutter Application` --USES--> `flutter_lints rules`  [EXTRACTED]
  pubspec.yaml → analysis_options.yaml
- `OnCreate` --calls--> `RegisterPlugins()`  [INFERRED]
  windows/runner/flutter_window.h → windows/flutter/generated_plugin_registrant.cc
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `Win32Window::Win32Window()` --calls--> `Destroy`  [INFERRED]
  windows/runner/win32_window.cpp → windows/runner/win32_window.h

## Import Cycles
- None detected.

## Communities (26 total, 9 thin omitted)

### Community 0 - "Code Editor Core"
Cohesion: 0.01
Nodes (140): activo, attach, _beginRe, _buildFindRow, _buildReplaceRow, _caseRe, _charLimit, col (+132 more)

### Community 1 - "Windows Runner & Flutter Engine"
Cohesion: 0.06
Nodes (52): FlutterViewController, Point, RECT, Size, unique_ptr, DartProject, HWND, LPARAM (+44 more)

### Community 2 - "Procedures State Management"
Cohesion: 0.04
Nodes (48): dart:async, int get, activar, _ambiente, buscar, _cargando, _cargandoEditor, _cargandoMas (+40 more)

### Community 3 - "App Entry & UI Shell"
Cohesion: 0.06
Nodes (37): config_badge.dart, ProcedimientosProvider, activo, build, _EstadoBadge, onTap, procedimiento, ProcedureCard (+29 more)

### Community 4 - "Editor UI Components"
Cohesion: 0.14
Nodes (15): _UsuarioButton, _AutocompletePopup, _ConfigSelector, _EstadoChip, _FindActionBtn, _FindBar, _FindNavBtn, _FindToggle (+7 more)

### Community 5 - "Theme & Environment Selector"
Cohesion: 0.05
Nodes (35): bool get, ChangeNotifier, activo, cdProcedimiento, cdUsuario, copyWith, deTexto, feModificacion (+27 more)

### Community 6 - "New Procedure Dialog"
Cohesion: 0.09
Nodes (22): CodeLineEditingController, FormState, build, _buildBody, _buildCodigoField, _buildDialogHeader, _buildFooter, _buildUsuarioField (+14 more)

### Community 7 - "SirWeb API Service"
Cohesion: 0.11
Nodes (17): dart:convert, activarProcedimiento, actualizarProcedimiento, _baseUrl, _call, crearProcedimiento, desactivarProcedimiento, _extractSseData (+9 more)

### Community 8 - "Main Screen Layout"
Cohesion: 0.15
Nodes (12): cdUsuario, onTap, _buildAppBar, _buildEditorView, createState, build, build, ../widgets/ambiente_selector.dart (+4 more)

### Community 9 - "State & Widget Lifecycle"
Cohesion: 0.20
Nodes (10): initState, _showNewProcedureDialog, _showUsuarioDialog, _buildEditor, _showVariablesModal, build, _buildConfigDropdown, _crear (+2 more)

### Community 10 - "Project Configuration"
Cohesion: 0.17
Nodes (12): flutter_lints rules, Debug/Profile/Release Configs, C++17 Standard, Flutter Windows Build System, proc_dynamic_sirweb binary, Dart SDK ^3.12.1, Flutter Application, http package (+4 more)

### Community 11 - "Windows Entry Point"
Cohesion: 0.24
Nodes (9): _In_, _In_opt_, vector, wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments() (+1 more)

### Community 13 - "Stateful Widget Classes"
Cohesion: 0.27
Nodes (10): _EditorStatusBar, _EditorStatusBarState, MainScreen, _MainScreenState, CodeEditorPanel, _CodeEditorPanelState, NewProcedureDialog, _NewProcedureDialogState (+2 more)

### Community 14 - "Config Type Model"
Cohesion: 0.29
Nodes (6): cdModulo, ConfiguracionTipo, deArgumento, fromJson, label, String get

### Community 15 - "Dynamic Variable Model"
Cohesion: 0.33
Nodes (5): cdVariable, deVariable, fromJson, inConfiguracion, VariableDinamica

### Community 24 - "main.dart"
Cohesion: 0.18
Nodes (10): build, _buildDarkTheme, _buildLightTheme, main, ProcDynamicApp, package:provider/provider.dart, ../providers/theme_provider.dart, screens/main_screen.dart (+2 more)

## Knowledge Gaps
- **276 isolated node(s):** `cdUsuario`, `onTap`, `build`, `createState`, `build` (+271 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ProcedimientosProvider` connect `App Entry & UI Shell` to `Procedures State Management`, `Theme & Environment Selector`?**
  _High betweenness centrality (0.034) - this node is a cross-community bridge._
- **Why does `Procedimiento` connect `Theme & Environment Selector` to `Procedures State Management`, `App Entry & UI Shell`?**
  _High betweenness centrality (0.027) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `MessageHandler` (e.g. with `Destroy` and `GetClientArea`) actually correct?**
  _`MessageHandler` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `cdUsuario`, `onTap`, `build` to the rest of the system?**
  _276 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Code Editor Core` be split into smaller, more focused modules?**
  _Cohesion score 0.014184397163120567 - nodes in this community are weakly interconnected._
- **Should `Windows Runner & Flutter Engine` be split into smaller, more focused modules?**
  _Cohesion score 0.06253652834599649 - nodes in this community are weakly interconnected._
- **Should `Procedures State Management` be split into smaller, more focused modules?**
  _Cohesion score 0.04081632653061224 - nodes in this community are weakly interconnected._