import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../models/deploy_ticket.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart';
import '../monaco_editor_widget.dart';

/// Ventana flotante / modal para visualización y edición de scripts
/// (Scripts SQL personalizados / Bloques Lógicos BLK).
///
/// Soporta gestión multi-script (lista con agregar, renombrar, eliminar,
/// seleccionar y editar) o modo individual clásico con editor Monaco.
/// Cuenta con soporte de arrastre, minimizado en dock de tarjetas,
/// maximizado (F11) y cierre rápido (Esc).
class ScriptCodeEditorDialog extends StatefulWidget {
  /// Lista de scripts a gestionar en el modal.
  final List<DeployTicketScript>? scripts;

  /// Nombre del script inicialmente seleccionado en la lista.
  final String? initialSelectedName;

  /// Contenido inicial si se usa en modo script único.
  final String? initialCode;

  /// Ruta inicial de archivo físico en disco si se usa en modo script único.
  final String? initialFilePath;

  /// Nombre inicial del script en modo único.
  final String? scriptName;

  /// Título de la ventana flotante.
  final String title;

  /// Lenguaje Monaco: 'plsql', 'sql', 'yaml', etc.
  final String language;

  /// Color temático de acento (Teal para SQL, Cyan para BLK, etc.).
  final Color themeColor;

  /// Icono de cabecera.
  final IconData icon;

  /// Callback para guardar el script individual activo (retrocompatibilidad).
  final void Function(String codeContent, String? filePath, String scriptName)?
  onSave;

  /// Callback cuando se guardan o aplican todos los scripts gestionados en el modal.
  final void Function(List<DeployTicketScript> scripts)? onSaveScripts;

  /// Callback de cierre.
  final VoidCallback? onClose;

  const ScriptCodeEditorDialog({
    super.key,
    this.scripts,
    this.initialSelectedName,
    this.initialCode,
    this.initialFilePath,
    this.scriptName,
    this.title = 'Editor de Script',
    this.language = 'plsql',
    this.themeColor = Colors.teal,
    this.icon = Icons.code_rounded,
    this.onSave,
    this.onSaveScripts,
    this.onClose,
  });

  /// Muestra el diálogo como ventana flotante libre en el overlay de la app.
  static VoidCallback show(
    BuildContext context, {
    List<DeployTicketScript>? scripts,
    String? initialSelectedName,
    String? initialCode,
    String? initialFilePath,
    String? scriptName,
    String title = 'Editor de Script',
    String language = 'plsql',
    Color themeColor = Colors.teal,
    IconData icon = Icons.code_rounded,
    void Function(String codeContent, String? filePath, String scriptName)?
    onSave,
    void Function(List<DeployTicketScript> scripts)? onSaveScripts,
  }) {
    return showFloatingWindow(
      context,
      (close) => ScriptCodeEditorDialog(
        scripts: scripts,
        initialSelectedName: initialSelectedName,
        initialCode: initialCode,
        initialFilePath: initialFilePath,
        scriptName: scriptName,
        title: title,
        language: language,
        themeColor: themeColor,
        icon: icon,
        onSave: onSave,
        onSaveScripts: onSaveScripts,
        onClose: close,
      ),
    );
  }

  @override
  State<ScriptCodeEditorDialog> createState() => _ScriptCodeEditorDialogState();
}

class _ScriptCodeEditorDialogState extends State<ScriptCodeEditorDialog> {
  late final MonacoEditorController _monacoCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  late List<DeployTicketScript> _scriptsList;
  int _selectedIndex = 0;
  String _searchQuery = '';

  String? _currentFilePath;
  bool _isDirty = false;
  bool _isLoading = false;

  // ── Gestión de ventana flotante (arrastre, minimizar, maximizar, resize) ──
  int? _slot;
  bool _minimized = false;
  bool _maximized = false;
  Offset _position = Offset.zero;
  Duration _anim = Duration.zero;
  double? _winW;
  double? _winH;
  double _restoreW = 1080;
  double _restoreH = 760;
  Offset _restorePos = Offset.zero;

  @override
  void initState() {
    super.initState();
    _monacoCtrl = MonacoEditorController();

    // Inicializar lista de scripts
    if (widget.scripts != null && widget.scripts!.isNotEmpty) {
      _scriptsList = widget.scripts!.map((s) => s.copyWith()).toList();

      if (widget.initialSelectedName != null &&
          widget.initialSelectedName!.isNotEmpty) {
        final found = _scriptsList.indexWhere(
          (s) => s.nombre == widget.initialSelectedName,
        );
        _selectedIndex = found >= 0 ? found : 0;
      } else {
        _selectedIndex = 0;
      }
    } else {
      final defaultName =
          widget.scriptName ??
          (widget.initialFilePath != null
              ? widget.initialFilePath!.split(Platform.pathSeparator).last
              : (widget.language == 'yaml' ? 'script.yaml' : 'script.sql'));
      _scriptsList = [
        DeployTicketScript(
          nombre: defaultName,
          contenido: widget.initialCode ?? '',
        ),
      ];
      _selectedIndex = 0;
    }

    _currentFilePath = widget.initialFilePath;
    final active = _activeScript;
    _nameController.text = active?.nombre ?? '';

    // Si viene con ruta física y contenido vacío, intentar cargar desde disco
    if (active != null &&
        active.contenido.trim().isEmpty &&
        widget.initialFilePath != null &&
        widget.initialFilePath!.isNotEmpty) {
      _tryLoadFromFile(widget.initialFilePath!);
    }
  }

  @override
  void dispose() {
    FloatingWindowSlots.release(_slot);
    _searchCtrl.dispose();
    _nameController.dispose();
    super.dispose();
  }

  DeployTicketScript? get _activeScript {
    if (_selectedIndex >= 0 && _selectedIndex < _scriptsList.length) {
      return _scriptsList[_selectedIndex];
    }
    return null;
  }

  Future<void> _commitActiveEditorText() async {
    if (_selectedIndex >= 0 && _selectedIndex < _scriptsList.length) {
      final text = await _monacoCtrl.getText();
      if (text != null) {
        _scriptsList[_selectedIndex] = _scriptsList[_selectedIndex].copyWith(
          contenido: text,
        );
      }
    }
  }

  Future<void> _selectScriptIndex(int index) async {
    if (index < 0 || index >= _scriptsList.length || index == _selectedIndex) {
      return;
    }
    await _commitActiveEditorText();

    setState(() {
      _selectedIndex = index;
      _currentFilePath = null;
      final current = _scriptsList[index];
      _nameController.text = current.nombre;
    });

    _monacoCtrl.setText(_scriptsList[index].contenido);
  }

  Future<void> _addNewScript() async {
    await _commitActiveEditorText();

    final isBlk =
        widget.title.toLowerCase().contains('bloque') ||
        widget.title.toLowerCase().contains('blk');

    // Nomenclatura diferenciada:
    // Para BLK: sin guión bajo (BLK1, BLK2, etc.)
    // Para SQL: script1.sql, script2.sql, etc.
    var counter = _scriptsList.length + 1;
    String newName;

    if (isBlk) {
      newName = 'BLK$counter.sql';
      while (_scriptsList.any(
        (s) =>
            s.nombre.toLowerCase() == newName.toLowerCase() ||
            s.nombre.toLowerCase() == 'blk$counter',
      )) {
        counter++;
        newName = 'BLK$counter.sql';
      }
    } else {
      newName = 'script$counter.sql';
      while (_scriptsList.any(
        (s) => s.nombre.toLowerCase() == newName.toLowerCase(),
      )) {
        counter++;
        newName = 'script$counter.sql';
      }
    }

    final newScript = DeployTicketScript(
      nombre: newName,
      contenido: isBlk
          ? 'BEGIN\n  -- Bloque lógico\n  NULL;\nEND;\n/'
          : '-- Script SQL personalizado\n',
    );

    setState(() {
      _scriptsList.add(newScript);
      _selectedIndex = _scriptsList.length - 1;
      _nameController.text = newName;
      _currentFilePath = null;
      _isDirty = true;
    });

    _monacoCtrl.setText(newScript.contenido);
  }

  Future<void> _removeScript(int index) async {
    if (index < 0 || index >= _scriptsList.length) return;
    if (_scriptsList.length == 1) {
      AppToast.warning('Debe existir al menos un script en la lista.');
      return;
    }

    await _commitActiveEditorText();

    setState(() {
      _scriptsList.removeAt(index);
      if (_selectedIndex >= _scriptsList.length) {
        _selectedIndex = _scriptsList.length - 1;
      }
      _nameController.text = _scriptsList[_selectedIndex].nombre;
      _currentFilePath = null;
      _isDirty = true;
    });

    _monacoCtrl.setText(_scriptsList[_selectedIndex].contenido);
  }

  Future<void> _tryLoadFromFile(String candidatePath) async {
    try {
      File file = File(candidatePath);
      if (!file.existsSync()) {
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
        final fileName = file.path.split(Platform.pathSeparator).last;
        if (mounted) {
          setState(() {
            _currentFilePath = file.path;
            if (_selectedIndex >= 0 && _selectedIndex < _scriptsList.length) {
              _scriptsList[_selectedIndex] = _scriptsList[_selectedIndex]
                  .copyWith(nombre: fileName, contenido: content);
              _nameController.text = fileName;
            }
            _isLoading = false;
            _isDirty = true;
          });
          _monacoCtrl.setText(content);
          AppToast.info('Archivo cargado: $fileName');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndOpenFile() async {
    try {
      final isYaml = widget.language == 'yaml';
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: isYaml
            ? const ['yaml', 'yml', 'txt']
            : const ['sql', 'pls', 'plsql', 'txt', 'prc', 'pck'],
        dialogTitle: 'Seleccionar archivo de script',
      );

      final path = result?.files.single.path;
      if (path == null) return;

      final file = File(path);
      final content = await file.readAsString();
      final fileName = path.split(Platform.pathSeparator).last;

      setState(() {
        _currentFilePath = path;
        if (_selectedIndex >= 0 && _selectedIndex < _scriptsList.length) {
          _scriptsList[_selectedIndex] = _scriptsList[_selectedIndex].copyWith(
            nombre: fileName,
            contenido: content,
          );
        }
        _nameController.text = fileName;
        _isDirty = true;
      });

      _monacoCtrl.setText(content);
      AppToast.info('Archivo cargado: $fileName');
    } catch (e) {
      AppToast.error('Error al abrir archivo de script: $e');
    }
  }

  Future<void> _saveToFile() async {
    try {
      final currentCode =
          await _monacoCtrl.getText() ?? (_activeScript?.contenido ?? '');
      String? savePath = _currentFilePath;
      final name = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : (_activeScript?.nombre ?? 'script.sql');

      savePath ??= await FilePicker.saveFile(
        dialogTitle: 'Guardar script en disco',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: widget.language == 'yaml'
            ? const ['yaml', 'yml', 'txt']
            : const ['sql', 'txt', 'pls'],
      );

      if (savePath == null) return;

      final file = File(savePath);
      await file.writeAsString(currentCode);
      final fileName = savePath.split(Platform.pathSeparator).last;

      setState(() {
        _currentFilePath = savePath;
        if (_selectedIndex >= 0 && _selectedIndex < _scriptsList.length) {
          _scriptsList[_selectedIndex] = _scriptsList[_selectedIndex].copyWith(
            nombre: fileName,
            contenido: currentCode,
          );
        }
        _nameController.text = fileName;
        _isDirty = false;
      });

      AppToast.success('Script guardado en disco: $fileName');
    } catch (e) {
      AppToast.error('Error al guardar archivo: $e');
    }
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
        _restoreW = _winW ?? 1080;
        _restoreH = _winH ?? 760;
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

  Future<void> _onConfirm() async {
    await _commitActiveEditorText();

    // Actualizar nombre del script activo si se editó en el input
    final currentName = _nameController.text.trim();
    if (_selectedIndex >= 0 && _selectedIndex < _scriptsList.length) {
      if (currentName.isNotEmpty) {
        _scriptsList[_selectedIndex] = _scriptsList[_selectedIndex].copyWith(
          nombre: currentName,
        );
      }
    }

    final active = _activeScript;
    if (active != null) {
      widget.onSave?.call(active.contenido, _currentFilePath, active.nombre);
    }

    widget.onSaveScripts?.call(List<DeployTicketScript>.from(_scriptsList));
    _closeDialog();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1F25) : Colors.white;
    final borderColor = isDark ? const Color(0xFF33353F) : Colors.grey.shade300;
    final screen = MediaQuery.sizeOf(context);

    final isBlk =
        widget.title.toLowerCase().contains('blk') ||
        widget.title.toLowerCase().contains('bloque');

    if (_maximized) {
      _winW = screen.width;
      _winH = screen.height;
    } else {
      _winW ??= 1080.0.clamp(600.0, screen.width - 32);
      _winH ??= 760.0.clamp(440.0, screen.height - 32);
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

    final query = _searchQuery.trim().toLowerCase();
    final filteredIndices = <int>[];
    for (var i = 0; i < _scriptsList.length; i++) {
      if (query.isEmpty ||
          _scriptsList[i].nombre.toLowerCase().contains(query)) {
        filteredIndices.add(i);
      }
    }

    final active = _activeScript;

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
                          title: _nameController.text.isNotEmpty
                              ? _nameController.text
                              : widget.title,
                          icon: widget.icon,
                          accentColor: widget.themeColor,
                          badge: isBlk ? 'BLK' : 'SQL',
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
                                _buildHeader(cs, isDark, isBlk),
                                Expanded(
                                  child: _buildBody(
                                    isDark,
                                    borderColor,
                                    filteredIndices,
                                    active,
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

  Widget _buildHeader(ColorScheme cs, bool isDark, bool isBlk) {
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
                widget.themeColor,
                Color.lerp(
                      widget.themeColor,
                      isDark ? Colors.black : const Color(0xFF042F2E),
                      0.4,
                    ) ??
                    widget.themeColor,
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
                  child: Icon(
                    widget.icon,
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
                  child: Text(
                    isBlk ? '[BLK]' : '[SQL]',
                    style: const TextStyle(
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_scriptsList.length} ${widget.language.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              const SizedBox(width: 10),

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

  Widget _buildBody(
    bool isDark,
    Color borderColor,
    List<int> filteredIndices,
    DeployTicketScript? active,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Columna Izquierda: Panel de Navegación / Gestión de Scripts
        SizedBox(
          width: 250,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF181A20) : const Color(0xFFF7F8FA),
              border: Border(
                right: BorderSide(
                  color: borderColor,
                  width: 0.8,
                ),
              ),
            ),
            child: Column(
              children: [
                // Barra superior de búsqueda y botón "+ Nuevo"
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: SizedBox(
                                              height: 32,
                                              child: TextField(
                                                controller: _searchCtrl,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                                decoration: InputDecoration(
                                                  hintText:
                                                      'Filtrar scripts...',
                                                  hintStyle: TextStyle(
                                                    fontSize: 11,
                                                    color: isDark
                                                        ? Colors.white38
                                                        : Colors.black38,
                                                  ),
                                                  prefixIcon: const Icon(
                                                    Icons.search_rounded,
                                                    size: 15,
                                                  ),
                                                  prefixIconConstraints:
                                                      const BoxConstraints(
                                                        minWidth: 28,
                                                        minHeight: 32,
                                                      ),
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 0,
                                                      ),
                                                  filled: true,
                                                  fillColor: isDark
                                                      ? const Color(0xFF22242B)
                                                      : Colors.white,
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    borderSide: BorderSide(
                                                      color: borderColor,
                                                    ),
                                                  ),
                                                  enabledBorder:
                                                      OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        borderSide: BorderSide(
                                                          color: borderColor,
                                                        ),
                                                      ),
                                                  focusedBorder:
                                                      OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        borderSide: BorderSide(
                                                          color:
                                                              widget.themeColor,
                                                          width: 1.2,
                                                        ),
                                                      ),
                                                  suffixIcon:
                                                      _searchQuery.isNotEmpty
                                                      ? IconButton(
                                                          icon: const Icon(
                                                            Icons.clear,
                                                            size: 13,
                                                          ),
                                                          onPressed: () {
                                                            _searchCtrl.clear();
                                                            setState(() {
                                                              _searchQuery = '';
                                                            });
                                                          },
                                                        )
                                                      : null,
                                                ),
                                                onChanged: (val) {
                                                  setState(() {
                                                    _searchQuery = val;
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      FilledButton.tonalIcon(
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          backgroundColor: widget.themeColor
                                              .withValues(alpha: 0.15),
                                        ),
                                        icon: Icon(
                                          Icons.add_rounded,
                                          size: 16,
                                          color: widget.themeColor,
                                        ),
                                        label: Text(
                                          'Nuevo Script',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: widget.themeColor,
                                          ),
                                        ),
                                        onPressed: _addNewScript,
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1, thickness: 0.8),

                                // Lista de scripts
                                Expanded(
                                  child: filteredIndices.isEmpty
                                      ? Center(
                                          child: Text(
                                            'Sin coincidencias',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: isDark
                                                  ? Colors.white38
                                                  : Colors.black38,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: filteredIndices.length,
                                          itemBuilder: (context, i) {
                                            final originalIdx =
                                                filteredIndices[i];
                                            final script =
                                                _scriptsList[originalIdx];
                                            final isSelected =
                                                originalIdx == _selectedIndex;

                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              child: Material(
                                                color: isSelected
                                                    ? widget.themeColor
                                                          .withValues(
                                                            alpha: isDark
                                                                ? 0.25
                                                                : 0.15,
                                                          )
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  onTap: () =>
                                                      _selectScriptIndex(
                                                        originalIdx,
                                                      ),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? widget.themeColor
                                                                  .withValues(
                                                                    alpha: 0.5,
                                                                  )
                                                            : Colors
                                                                  .transparent,
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 6,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        // Prefijo visual para distinguir BLK y SQL
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 5,
                                                            vertical: 1.5,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: (widget.title
                                                                        .toLowerCase()
                                                                        .contains(
                                                                          'blk',
                                                                        ) ||
                                                                    widget.title
                                                                        .toLowerCase()
                                                                        .contains(
                                                                          'bloque',
                                                                        ) ||
                                                                    script.nombre
                                                                        .toUpperCase()
                                                                        .startsWith(
                                                                          'BLK',
                                                                        ))
                                                                ? Colors.cyan
                                                                    .withValues(
                                                                      alpha:
                                                                          0.2,
                                                                    )
                                                                : Colors.teal
                                                                    .withValues(
                                                                      alpha:
                                                                          0.2,
                                                                    ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                      4,
                                                                    ),
                                                            border: Border.all(
                                                              color: (widget
                                                                          .title
                                                                          .toLowerCase()
                                                                          .contains(
                                                                            'blk',
                                                                          ) ||
                                                                      widget
                                                                          .title
                                                                          .toLowerCase()
                                                                          .contains(
                                                                            'bloque',
                                                                          ) ||
                                                                      script
                                                                          .nombre
                                                                          .toUpperCase()
                                                                          .startsWith(
                                                                            'BLK',
                                                                          ))
                                                                  ? Colors.cyan
                                                                  : Colors.teal,
                                                              width: 0.6,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            (widget.title
                                                                        .toLowerCase()
                                                                        .contains(
                                                                          'blk',
                                                                        ) ||
                                                                    widget.title
                                                                        .toLowerCase()
                                                                        .contains(
                                                                          'bloque',
                                                                        ) ||
                                                                    script.nombre
                                                                        .toUpperCase()
                                                                        .startsWith(
                                                                          'BLK',
                                                                        ))
                                                                ? 'BLK'
                                                                : 'SQL',
                                                            style: TextStyle(
                                                              fontSize: 9.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontFamily:
                                                                  'Consolas, monospace',
                                                              color: (widget
                                                                          .title
                                                                          .toLowerCase()
                                                                          .contains(
                                                                            'blk',
                                                                          ) ||
                                                                      widget
                                                                          .title
                                                                          .toLowerCase()
                                                                          .contains(
                                                                            'bloque',
                                                                          ) ||
                                                                      script
                                                                          .nombre
                                                                          .toUpperCase()
                                                                          .startsWith(
                                                                            'BLK',
                                                                          ))
                                                                  ? (isDark
                                                                      ? Colors
                                                                          .cyanAccent
                                                                      : Colors
                                                                          .cyan
                                                                          .shade800)
                                                                  : (isDark
                                                                      ? Colors
                                                                          .tealAccent
                                                                      : Colors
                                                                          .teal
                                                                          .shade800),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            script.nombre,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 11.5,
                                                              fontWeight:
                                                                  isSelected
                                                                  ? FontWeight
                                                                        .bold
                                                                  : FontWeight
                                                                        .w500,
                                                              fontFamily:
                                                                  'Consolas, monospace',
                                                              color: isSelected
                                                                  ? (isDark
                                                                        ? Colors
                                                                              .white
                                                                        : Colors
                                                                              .black87)
                                                                  : (isDark
                                                                        ? Colors
                                                                              .grey
                                                                              .shade300
                                                                        : Colors
                                                                              .grey
                                                                              .shade800),
                                                            ),
                                                          ),
                                                        ),
                                                        IconButton(
                                                          tooltip:
                                                              'Eliminar script',
                                                          icon: const Icon(
                                                            Icons.close_rounded,
                                                            size: 14,
                                                          ),
                                                          splashRadius: 14,
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(
                                                                minWidth: 24,
                                                                minHeight: 24,
                                                              ),
                                                          onPressed: () =>
                                                              _removeScript(
                                                                originalIdx,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Columna Derecha: Barra de Herramientas y Editor Monaco
                        Expanded(
                          child: Column(
                            children: [
                              // Barra de herramientas del script activo
                              _buildActiveScriptToolbar(borderColor, isDark),

                              // Área del editor Monaco
                              Expanded(
                                child: MonacoEditorWidget(
                                  controller: _monacoCtrl,
                                  initialCode: active?.contenido ?? '',
                                  language: widget.language,
                                  darkTheme: isDark,
                                  onChanged: (text) {
                                    if (_selectedIndex >= 0 &&
                                        _selectedIndex < _scriptsList.length) {
                                      _scriptsList[_selectedIndex] =
                                          _scriptsList[_selectedIndex].copyWith(
                                            contenido: text,
                                          );
                                    }
                                    if (!_isDirty) {
                                      setState(() => _isDirty = true);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
  }

  Widget _buildActiveScriptToolbar(Color borderColor, bool isDark) {
    final isBlk =
        widget.title.toLowerCase().contains('blk') ||
        widget.title.toLowerCase().contains('bloque') ||
        _nameController.text.toUpperCase().startsWith('BLK');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26262B) : const Color(0xFFF6F8FA),
        border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: widget.themeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(widget.icon, size: 15, color: widget.themeColor),
          ),
          const SizedBox(width: 8),

          // Distintivo visual del tipo de artefacto
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isBlk
                  ? Colors.cyan.withValues(alpha: 0.18)
                  : Colors.teal.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isBlk ? Colors.cyan : Colors.teal,
                width: 0.8,
              ),
            ),
            child: Text(
              isBlk ? '[BLK]' : '[SQL]',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                fontFamily: 'Consolas, monospace',
                color: isBlk
                    ? (isDark ? Colors.cyanAccent : Colors.cyan.shade900)
                    : (isDark ? Colors.tealAccent : Colors.teal.shade900),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Campo editable de nombre del archivo / script
          SizedBox(
            width: 240,
            height: 32,
            child: TextField(
              controller: _nameController,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Consolas, monospace',
                color: isDark ? Colors.white : const Color(0xFF1F2328),
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                isDense: true,
                hintText: 'Nombre del archivo',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                prefixIcon: const Icon(Icons.edit_note_rounded, size: 16),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 26,
                  minHeight: 32,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF16181D) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: widget.themeColor, width: 1.2),
                ),
              ),
              onChanged: (val) {
                if (_selectedIndex >= 0 &&
                    _selectedIndex < _scriptsList.length) {
                  _scriptsList[_selectedIndex] = _scriptsList[_selectedIndex]
                      .copyWith(nombre: val.trim());
                }
                setState(() => _isDirty = true);
              },
            ),
          ),
          if (_isDirty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amber.shade700, width: 0.8),
                ),
                child: Text(
                  'Modificado',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade800,
                  ),
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Cargar desde archivo en disco',
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            onPressed: _pickAndOpenFile,
          ),
          IconButton(
            tooltip: 'Guardar archivo en disco',
            icon: const Icon(Icons.save_as_rounded, size: 18),
            onPressed: _saveToFile,
          ),
        ],
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
                  'Cambios pendientes en scripts',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            )
          else if (_currentFilePath != null)
            Flexible(
              child: Text(
                'Ruta: $_currentFilePath',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
          else
            Flexible(
              child: Text(
                'El contenido de los scripts se enviará en el ticket al servicio para guardarse en la BD.',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: isDark
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => _closeDialog(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              side: BorderSide(
                color: cs.outlineVariant.withValues(
                  alpha: isDark ? 0.5 : 0.8,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text(
              'Aplicar a Ticket',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: widget.themeColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
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
