# Graph Report - .  (2026-07-28)

## Corpus Check
- Corpus is ~13,418 words - fits in a single context window. You may not need a graph.

## Summary
- 458 nodes · 608 edges · 24 communities (16 shown, 8 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 14 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

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
- Procedure Data Model
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

## God Nodes (most connected - your core abstractions)
1. `ProcedimientosProvider` - 27 edges
2. `StatelessWidget` - 20 edges
3. `Win32Window` - 19 edges
4. `MessageHandler` - 12 edges
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
- `ProcDynamicApp` --inherits--> `StatelessWidget`  [EXTRACTED]
  lib/main.dart → lib/widgets/code_editor_panel.dart
- `_showUsuarioDialog` --references--> `ProcedimientosProvider`  [EXTRACTED]
  lib/screens/main_screen.dart → lib/providers/procedimientos_provider.dart
- `build` --references--> `ProcedimientosProvider`  [EXTRACTED]
  lib/widgets/procedure_card.dart → lib/providers/procedimientos_provider.dart

## Import Cycles
- None detected.

## Communities (24 total, 8 thin omitted)

### Community 0 - "Code Editor Core"
Cohesion: 0.02
Nodes (121): class _AutocompletePopup extends, CodeAutocompleteEditingValue, CodeChunkController?, CodeCommentFormatter get, CodeFindController, CodeIndicatorValueNotifier, Color?, double get (+113 more)

### Community 1 - "Windows Runner & Flutter Engine"
Cohesion: 0.06
Nodes (52): FlutterViewController, Point, RECT, Size, unique_ptr, DartProject, HWND, LPARAM (+44 more)

### Community 2 - "Procedures State Management"
Cohesion: 0.04
Nodes (48): dart:async, int get, activar, _ambiente, buscar, _cargando, _cargandoEditor, _cargandoMas (+40 more)

### Community 3 - "App Entry & UI Shell"
Cohesion: 0.07
Nodes (29): build, _buildDarkTheme, _buildLightTheme, main, ProcDynamicApp, build, createState, dispose (+21 more)

### Community 4 - "Editor UI Components"
Cohesion: 0.09
Nodes (25): config_badge.dart, _UsuarioButton, _AutocompletePopup, _EstadoChip, _FindActionBtn, _FindBar, _FindNavBtn, _FindToggle (+17 more)

### Community 5 - "Theme & Environment Selector"
Cohesion: 0.08
Nodes (22): bool get, isDark, _themeMode, toggle, _ambientes, AmbienteSelector, build, _colorForAmbiente (+14 more)

### Community 6 - "New Procedure Dialog"
Cohesion: 0.09
Nodes (22): CodeLineEditingController, FormState, build, _buildBody, _buildCodigoField, _buildDialogHeader, _buildFooter, _buildUsuarioField (+14 more)

### Community 7 - "SirWeb API Service"
Cohesion: 0.11
Nodes (17): dart:convert, activarProcedimiento, actualizarProcedimiento, _baseUrl, _call, crearProcedimiento, desactivarProcedimiento, _extractSseData (+9 more)

### Community 8 - "Main Screen Layout"
Cohesion: 0.14
Nodes (14): build, _buildAppBar, _buildEditorView, cdUsuario, createState, MainScreen, _MainScreenState, onTap (+6 more)

### Community 9 - "State & Widget Lifecycle"
Cohesion: 0.17
Nodes (12): ChangeNotifier, ProcedimientosProvider, ThemeProvider, initState, _showNewProcedureDialog, build, _buildEditor, _ConfigSelector (+4 more)

### Community 10 - "Project Configuration"
Cohesion: 0.17
Nodes (12): flutter_lints rules, Debug/Profile/Release Configs, C++17 Standard, Flutter Windows Build System, proc_dynamic_sirweb binary, Dart SDK ^3.12.1, Flutter Application, http package (+4 more)

### Community 11 - "Windows Entry Point"
Cohesion: 0.24
Nodes (9): _In_, _In_opt_, vector, wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments() (+1 more)

### Community 12 - "Procedure Data Model"
Cohesion: 0.17
Nodes (11): activo, cdProcedimiento, cdUsuario, copyWith, deTexto, feModificacion, fromJson, inConfiguracion (+3 more)

### Community 13 - "Stateful Widget Classes"
Cohesion: 0.23
Nodes (12): CodeEditorPanel, _CodeEditorPanelState, _EditorStatusBar, _EditorStatusBarState, NewProcedureDialog, _NewProcedureDialogState, ProcedureList, _ProcedureListState (+4 more)

### Community 14 - "Config Type Model"
Cohesion: 0.29
Nodes (6): cdModulo, ConfiguracionTipo, deArgumento, fromJson, label, String get

### Community 15 - "Dynamic Variable Model"
Cohesion: 0.33
Nodes (5): cdVariable, deVariable, fromJson, inConfiguracion, VariableDinamica

## Knowledge Gaps
- **252 isolated node(s):** `main`, `_buildDarkTheme`, `_buildLightTheme`, `build`, `ConfiguracionTipo` (+247 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ProcedimientosProvider` connect `State & Widget Lifecycle` to `Code Editor Core`, `Procedures State Management`, `App Entry & UI Shell`, `Editor UI Components`, `New Procedure Dialog`, `Main Screen Layout`, `Stateful Widget Classes`?**
  _High betweenness centrality (0.131) - this node is a cross-community bridge._
- **Why does `Procedimiento` connect `Procedure Data Model` to `Code Editor Core`, `Procedures State Management`, `Editor UI Components`?**
  _High betweenness centrality (0.052) - this node is a cross-community bridge._
- **Why does `StatelessWidget` connect `Editor UI Components` to `Code Editor Core`, `State & Widget Lifecycle`, `App Entry & UI Shell`, `Theme & Environment Selector`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `MessageHandler` (e.g. with `Destroy` and `GetClientArea`) actually correct?**
  _`MessageHandler` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `main`, `_buildDarkTheme`, `_buildLightTheme` to the rest of the system?**
  _252 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Code Editor Core` be split into smaller, more focused modules?**
  _Cohesion score 0.01639344262295082 - nodes in this community are weakly interconnected._
- **Should `Windows Runner & Flutter Engine` be split into smaller, more focused modules?**
  _Cohesion score 0.06253652834599649 - nodes in this community are weakly interconnected._