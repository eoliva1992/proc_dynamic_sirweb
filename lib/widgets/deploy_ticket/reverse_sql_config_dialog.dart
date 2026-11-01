import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import '../../models/reverse_sql_config.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart';
import 'reverse_sql_visual_form.dart';
import 'reverse_sql_yaml_editor.dart';

enum _ConfigMode { visual, yaml }

/// Ventana flotante / modal para editar o visualizar archivos YAML de Reverse SQL (RSQL).
/// Permite alternar entre Formulario Visual Estructurado y Editor YAML con sincronización bidireccional.
/// Soporta arrastre, minimizado en dock de tarjetas, maximizado (F11) y cierre rápido (Esc).
class ReverseSqlConfigDialog extends StatefulWidget {
  /// Contenido inicial YAML si ya existe, o null para usar plantilla inicial.
  final String? initialYaml;

  /// Ruta inicial del archivo en disco si ya fue seleccionado previamente.
  final String? initialFilePath;

  /// Nombre del script / artefacto (ej. rev_insert.yaml)
  final String? scriptName;

  /// Título de la ventana flotante.
  final String title;

  /// Callback para cerrar la ventana modal cuando se muestra como floating window o dialog.
  final VoidCallback? onClose;

  /// Callback cuando el usuario guarda los cambios o selecciona guardar como archivo.
  final void Function(String yamlContent, String? filePath, String scriptName)?
  onSave;

  const ReverseSqlConfigDialog({
    super.key,
    this.initialYaml,
    this.initialFilePath,
    this.scriptName,
    this.title = 'Configuración de Extracción RSQL (YAML)',
    this.onClose,
    this.onSave,
  });

  /// Muestra el diálogo como ventana flotante libre en el overlay de la app.
  static VoidCallback show(
    BuildContext context, {
    String? initialYaml,
    String? initialFilePath,
    String? scriptName,
    String title = 'Configuración de Extracción RSQL (YAML)',
    void Function(String yamlContent, String? filePath, String scriptName)?
    onSave,
  }) {
    return showFloatingWindow(
      context,
      (close) => ReverseSqlConfigDialog(
        initialYaml: initialYaml,
        initialFilePath: initialFilePath,
        scriptName: scriptName,
        title: title,
        onClose: close,
        onSave: onSave,
      ),
    );
  }

  @override
  State<ReverseSqlConfigDialog> createState() => _ReverseSqlConfigDialogState();
}

class _ReverseSqlConfigDialogState extends State<ReverseSqlConfigDialog> {
  _ConfigMode _mode = _ConfigMode.visual;
  late String _yamlContent;
  late ReverseSqlConfig _config;
  String? _currentFilePath;
  late String _currentScriptName;
  late final TextEditingController _scriptNameCtrl;
  bool _isLoading = false;
  bool _isDirty = false;

  // ── Gestión de ventana flotante (arrastre, minimizar, maximizar) ──
  int? _slot;
  bool _minimized = false;
  bool _maximized = false;
  Offset _position = Offset.zero;
  Duration _anim = Duration.zero;
  double? _winW;
  double? _winH;
  double _restoreW = 960;
  double _restoreH = 740;
  Offset _restorePos = Offset.zero;

  @override
  void initState() {
    super.initState();
    _currentFilePath = widget.initialFilePath;
    _currentScriptName =
        widget.scriptName ??
        (widget.initialFilePath != null
            ? widget.initialFilePath!.split(Platform.pathSeparator).last
            : 'reverseSql.yaml');
    _scriptNameCtrl = TextEditingController(text: _currentScriptName);

    final content = widget.initialYaml?.trim();

    if (content != null && content.isNotEmpty) {
      _yamlContent = widget.initialYaml!;
      _config = ReverseSqlConfig.parseYaml(_yamlContent);
    } else {
      _config = const ReverseSqlConfig(
        tables: [
          ReverseSqlTableConfig(
            dml: ReverseSqlDml.merge,
            name: '',
            pkAdd: true,
            filters: {},
          ),
        ],
      );
      _yamlContent = _config.toYaml();

      // Si no trajo contenido en memoria pero se especificó una ruta o nombre,
      // intentamos cargar automáticamente el archivo físico desde el disco.
      if (widget.initialFilePath != null &&
          widget.initialFilePath!.isNotEmpty) {
        _tryLoadFromFile(widget.initialFilePath!);
      }
    }
  }

  Future<void> _tryLoadFromFile(String candidatePath) async {
    try {
      File file = File(candidatePath);
      if (!file.existsSync()) {
        // Probar relativa al directorio actual
        final resolved = File(
          '${Directory.current.path}${Platform.pathSeparator}$candidatePath',
        );
        if (resolved.existsSync()) {
          file = resolved;
        }
      }

      if (file.existsSync()) {
        setState(() => _isLoading = true);
        final content = await file.readAsString();
        if (mounted) {
          setState(() {
            _currentFilePath = file.path;
            _currentScriptName = file.path.split(Platform.pathSeparator).last;
            _scriptNameCtrl.text = _currentScriptName;
            _yamlContent = content;
            _config = ReverseSqlConfig.parseYaml(content);
            _isLoading = false;
          });
          AppToast.info('Configuración cargada desde: $_currentScriptName');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _switchMode(_ConfigMode newMode) {
    if (_mode == newMode) return;

    if (_mode == _ConfigMode.visual && newMode == _ConfigMode.yaml) {
      // Sincronizar visual -> yaml
      _yamlContent = _config.toYaml();
    } else if (_mode == _ConfigMode.yaml && newMode == _ConfigMode.visual) {
      // Sincronizar yaml -> visual
      try {
        final parsed = ReverseSqlConfig.parseYaml(_yamlContent);
        _config = parsed;
      } catch (e) {
        AppToast.warning(
          'El YAML actual contiene errores de sintaxis; mostrando versión previa en modo visual.',
        );
      }
    }

    setState(() {
      _mode = newMode;
    });
  }

  Future<void> _pickAndOpenFile() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Seleccionar archivo de configuración RSQL (.yaml / .yml)',
        type: FileType.custom,
        allowedExtensions: const ['yaml', 'yml', 'txt'],
      );

      final path = result?.files.single.path;
      if (path == null) return;

      final file = File(path);
      final content = await file.readAsString();
      final fileName = path.split(Platform.pathSeparator).last;

      setState(() {
        _currentFilePath = path;
        _currentScriptName = fileName;
        _scriptNameCtrl.text = fileName;
        _yamlContent = content;
        _config = ReverseSqlConfig.parseYaml(content);
        _isDirty = true;
      });

      AppToast.info('Archivo cargado: $fileName');
    } catch (e) {
      AppToast.error('Error al abrir el archivo YAML: $e');
    }
  }

  Future<void> _saveToFile() async {
    try {
      final contentToSave = _mode == _ConfigMode.visual
          ? _config.toYaml()
          : _yamlContent;

      String? savePath = _currentFilePath;

      savePath ??= await FilePicker.saveFile(
        dialogTitle: 'Guardar configuración YAML',
        fileName: _currentScriptName.isNotEmpty
            ? _currentScriptName
            : 'reverseSql.yaml',
        type: FileType.custom,
        allowedExtensions: const ['yaml', 'yml'],
      );

      if (savePath == null) return;

      final file = File(savePath);
      await file.writeAsString(contentToSave);
      final fileName = savePath.split(Platform.pathSeparator).last;

      setState(() {
        _currentFilePath = savePath;
        _currentScriptName = fileName;
        _isDirty = false;
        _yamlContent = contentToSave;
      });

      widget.onSave?.call(contentToSave, savePath, fileName);
      AppToast.success('Archivo guardado correctamente');
    } catch (e) {
      AppToast.error('Error al guardar el archivo YAML: $e');
    }
  }

  @override
  void dispose() {
    FloatingWindowSlots.release(_slot);
    _scriptNameCtrl.dispose();
    super.dispose();
  }

  void _toggleMaximized() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_maximized) {
        _winW = _restoreW;
        _winH = _restoreH;
        _position = _restorePos;
        _maximized = false;
      } else {
        _restoreW = _winW ?? 960;
        _restoreH = _winH ?? 740;
        _restorePos = _position;
        _position = Offset.zero;
        _maximized = true;
      }
    });
  }

  void _toggleMinimized() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_minimized) {
        FloatingWindowSlots.release(_slot);
        _slot = null;
        _minimized = false;
      } else {
        _slot = FloatingWindowSlots.take();
        _minimized = true;
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _closeDialog() {
    FloatingWindowSlots.release(_slot);
    _slot = null;
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _onConfirm() {
    final finalYaml = _mode == _ConfigMode.visual
        ? _config.toYaml()
        : _yamlContent;

    widget.onSave?.call(finalYaml, _currentFilePath, _currentScriptName);
    _closeDialog();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1F25) : Colors.white;
    final screen = MediaQuery.sizeOf(context);

    if (_maximized) {
      _winW = screen.width;
      _winH = screen.height;
    } else {
      _winW ??= 960.0.clamp(560.0, screen.width - 32);
      _winH ??= 740.0.clamp(420.0, screen.height - 32);
    }

    if (_winW! > screen.width) _winW = screen.width;
    if (_winH! > screen.height) _winH = screen.height;

    final double w, h, left, top;
    if (_minimized) {
      w = FloatingWindowSlots.barW;
      h = FloatingWindowSlots.barH;
      final (l, t) = FloatingWindowSlots.offsetFor(_slot ?? 0, screen);
      left = l;
      top = t;
    } else {
      w = _winW!;
      h = _winH!;
      left = _maximized
          ? 0.0
          : ((screen.width - w) / 2 + _position.dx).clamp(
              0.0,
              (screen.width - w).clamp(0.0, double.infinity),
            );
      top = _maximized
          ? 0.0
          : ((screen.height - h) / 2 + _position.dy).clamp(
              0.0,
              (screen.height - h).clamp(0.0, double.infinity),
            );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
        const SingleActivator(LogicalKeyboardKey.escape): _closeDialog,
      },
      child: Focus(
        autofocus: !_minimized,
        canRequestFocus: !_minimized,
        descendantsAreFocusable: !_minimized,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: _anim,
              curve: Curves.easeOutCubic,
              left: left,
              top: top,
              width: w,
              height: h,
              child: Material(
                color: Colors.transparent,
                child: AnimatedContainer(
                  duration: _anim,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(
                      _maximized ? 0 : (_minimized ? 8 : 16),
                    ),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(
                        alpha: isDark ? 0.35 : 0.6,
                      ),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.55 : 0.18,
                        ),
                        blurRadius: _minimized ? 16 : 32,
                        offset: Offset(0, _minimized ? 4 : 12),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _minimized
                      ? MinimizedWindowCard(
                          title: _currentScriptName.isNotEmpty
                              ? _currentScriptName
                              : widget.title,
                          icon: Icons.tune_rounded,
                          accentColor: const Color(0xFF0F766E),
                          badge: 'RSQL',
                          onRestore: _toggleMinimized,
                          onClose: _closeDialog,
                        )
                      : OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: 0,
                          maxWidth: double.infinity,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: SizedBox(
                            width: _winW,
                            height: _winH,
                            child: Column(
                              children: [
                                _buildHeader(cs, isDark),
                                Expanded(
                                  child: _mode == _ConfigMode.visual
                                      ? ReverseSqlVisualForm(
                                          config: _config,
                                          onChanged: (updated) {
                                            setState(() {
                                              _config = updated;
                                              _yamlContent = updated.toYaml();
                                              _isDirty = true;
                                            });
                                          },
                                        )
                                      : ReverseSqlYamlEditor(
                                          yamlContent: _yamlContent,
                                          onChanged: (text) {
                                            _yamlContent = text;
                                            _isDirty = true;
                                            try {
                                              _config =
                                                  ReverseSqlConfig.parseYaml(
                                                    text,
                                                  );
                                            } catch (_) {
                                              // Ignorar errores parciales mientras escribe
                                            }
                                          },
                                          onResetTemplate: () {
                                            setState(() {
                                              _config = const ReverseSqlConfig(
                                                tables: [
                                                  ReverseSqlTableConfig(
                                                    dml: ReverseSqlDml.merge,
                                                    name:
                                                        'procedimientodinamico',
                                                    pkAdd: true,
                                                    filters: {
                                                      'cd_procedimiento':
                                                          "= 'EJEMPLO'",
                                                    },
                                                  ),
                                                ],
                                              );
                                              _yamlContent = _config.toYaml();
                                              _isDirty = true;
                                            });
                                          },
                                        ),
                                ),
                                _buildFooter(cs, isDark),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),

            // Resize handle derecho
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 5,
                top: top + 54,
                width: 10,
                height: (h - 64).clamp(0.0, double.infinity),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(
                        600.0,
                        screen.width - 20,
                      );
                    }),
                  ),
                ),
              ),

            // Resize handle inferior
            if (!_maximized && !_minimized)
              Positioned(
                left: left + 16,
                top: top + h - 5,
                width: (w - 32).clamp(0.0, double.infinity),
                height: 10,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winH = (_winH! + d.delta.dy).clamp(
                        420.0,
                        screen.height - 20,
                      );
                    }),
                  ),
                ),
              ),

            // Resize handle esquina inferior derecha
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 18,
                top: top + h - 18,
                width: 22,
                height: 22,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(
                        600.0,
                        screen.width - 20,
                      );
                      _winH = (_winH! + d.delta.dy).clamp(
                        420.0,
                        screen.height - 20,
                      );
                    }),
                    child: CustomPaint(
                      painter: WindowGripPainter(
                        isDark ? Colors.white30 : Colors.black26,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    final headerBorderColor = isDark
        ? const Color(0xFF33353F)
        : Colors.grey.shade300;

    Widget titleArea(Widget child) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _minimized ? _toggleMinimized : _toggleMaximized,
      child: child,
    );

    return MouseRegion(
      cursor: (_maximized || _minimized)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (_maximized || _minimized)
            ? null
            : (d) => setState(() {
                _anim = Duration.zero;
                _position += d.delta;
              }),
        child: ConstellationHeader(
          height: 54,
          onDark: true,
          lineColor: Colors.white.withValues(alpha: 0.25),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_maximized ? 0 : 16),
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF0F766E), // Teal-700
                Color.lerp(
                      const Color(0xFF115E59), // Teal-800
                      isDark ? Colors.black : const Color(0xFF042F2E),
                      0.35,
                    ) ??
                    const Color(0xFF115E59),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(_maximized ? 0 : 16),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              titleArea(
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.settings_suggest_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              titleArea(
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: const Text(
                    '[RSQL]',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Consolas, monospace',
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: titleArea(
                  Text(
                    widget.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Campo para el nombre del archivo / script
              SizedBox(
                width: 170,
                height: 30,
                child: TextField(
                  controller: _scriptNameCtrl,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Consolas, monospace',
                    color: isDark ? Colors.white : const Color(0xFF1F2328),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    isDense: true,
                    hintText: 'Archivo .yaml',
                    hintStyle: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    prefixIcon: const Icon(
                      Icons.description_outlined,
                      size: 14,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 30,
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF16181D) : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: headerBorderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: headerBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: Colors.white,
                        width: 1.2,
                      ),
                    ),
                  ),
                  onChanged: (val) {
                    _currentScriptName = val.trim();
                    _isDirty = true;
                  },
                ),
              ),
              if (_isDirty)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.amber.shade300,
                        width: 0.8,
                      ),
                    ),
                    child: const Text(
                      'Modificado',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),

              // Selector de vista: Visual vs YAML
              SegmentedButton<_ConfigMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _ConfigMode.visual,
                    label: Text('Visual', style: TextStyle(fontSize: 11.5)),
                    icon: Icon(Icons.dashboard_customize_outlined, size: 13),
                  ),
                  ButtonSegment(
                    value: _ConfigMode.yaml,
                    label: Text('YAML', style: TextStyle(fontSize: 11.5)),
                    icon: Icon(Icons.code_rounded, size: 13),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (set) {
                  if (set.isNotEmpty) _switchMode(set.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return cs.primary;
                    }
                    return Colors.white70;
                  }),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return Colors.white.withValues(alpha: 0.12);
                  }),
                ),
              ),
              const SizedBox(width: 6),

              IconButton(
                tooltip: 'Cargar desde archivo .yaml',
                icon: const Icon(Icons.folder_open_rounded, size: 17),
                color: Colors.white,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _pickAndOpenFile,
              ),
              IconButton(
                tooltip: 'Guardar como archivo .yaml',
                icon: const Icon(Icons.save_as_rounded, size: 17),
                color: Colors.white,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _saveToFile,
              ),
              const SizedBox(width: 6),

              // Botones de control de ventana (Minimizar, Maximizar, Cerrar)
              WindowButton(
                icon: Icons.remove_rounded,
                tooltip: 'Minimizar',
                onTap: _toggleMinimized,
              ),
              const SizedBox(width: 2),
              WindowButton(
                icon: _maximized
                    ? Icons.close_fullscreen_rounded
                    : Icons.crop_square_rounded,
                tooltip: _maximized
                    ? 'Restaurar tamaño (F11)'
                    : 'Maximizar (F11)',
                onTap: _toggleMaximized,
              ),
              const SizedBox(width: 2),
              WindowButton(
                icon: Icons.close_rounded,
                tooltip: 'Cerrar (Esc)',
                isClose: true,
                onTap: _closeDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF262831) : Colors.grey.shade100,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF33353F) : Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          if (_isDirty)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: Colors.amber),
                SizedBox(width: 6),
                Text(
                  'Cambios pendientes',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => _closeDialog(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              side: BorderSide(
                color: cs.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.8),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Cancelar', style: TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text(
              'Aplicar a Ticket',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _onConfirm,
          ),
        ],
      ),
    );
  }
}
