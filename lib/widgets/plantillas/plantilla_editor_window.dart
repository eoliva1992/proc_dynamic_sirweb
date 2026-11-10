import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

import '../../models/plantilla.dart';
import '../../services/editor_cursor_store.dart';
import '../../services/plantilla_service.dart';
import '../_editor_themes.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart';

class _CategoriaMetadata {
  final String code;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const _CategoriaMetadata({
    required this.code,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

const List<_CategoriaMetadata> _kCategoriasMetadata = [
  _CategoriaMetadata(
    code: 'PROCEDIMIENTO_DINAMICO',
    title: 'Procedimiento Dinámico',
    description: 'Regla de negocio, validación o cálculo del motor SirWeb',
    icon: Icons.flash_on_rounded,
    color: Color(0xFF0078D4),
  ),
  _CategoriaMetadata(
    code: 'PROCEDURE',
    title: 'Stored Procedure',
    description: 'Procedimiento almacenado estándar PL/SQL de base de datos',
    icon: Icons.terminal_rounded,
    color: Color(0xFF107C41),
  ),
  _CategoriaMetadata(
    code: 'FUNCTION',
    title: 'Función PL/SQL',
    description: 'Función con valor de retorno (escalar o compuesto)',
    icon: Icons.functions_rounded,
    color: Color(0xFF5C2D91),
  ),
  _CategoriaMetadata(
    code: 'PACKAGE',
    title: 'Package (Spec)',
    description: 'Especificación de paquete PL/SQL con signaturas públicas',
    icon: Icons.folder_zip_rounded,
    color: Color(0xFFB4A0FF),
  ),
  _CategoriaMetadata(
    code: 'PACKAGE_BODY',
    title: 'Package Body',
    description: 'Implementación y cuerpo de paquete PL/SQL',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFFE81123),
  ),
  _CategoriaMetadata(
    code: 'TRIGGER',
    title: 'Trigger',
    description: 'Disparador automático asociado a eventos de tabla (DML)',
    icon: Icons.bolt_rounded,
    color: Color(0xFFFF8C00),
  ),
  _CategoriaMetadata(
    code: 'TYPE',
    title: 'Type (Objeto)',
    description: 'Tipo de dato objeto Oracle compuesto o estructurado',
    icon: Icons.category_rounded,
    color: Color(0xFF0288D1),
  ),
  _CategoriaMetadata(
    code: 'OTRO',
    title: 'Otro / Script / Bloque',
    description: 'Bloque anónimo, script utilitario, migración o DDL libre',
    icon: Icons.code_rounded,
    color: Color(0xFF888888),
  ),
];

_CategoriaMetadata _categoriaMetaFor(String code) {
  final normalized = code.trim().toUpperCase();
  for (final meta in _kCategoriasMetadata) {
    if (meta.code.toUpperCase() == normalized) {
      return meta;
    }
  }
  return _CategoriaMetadata(
    code: code,
    title: code,
    description: 'Plantilla de código personalizada',
    icon: Icons.code_rounded,
    color: const Color(0xFF0078D4),
  );
}

/// Abre una ventana flotante para crear o editar una Plantilla de Código.
void showPlantillaEditorWindow(
  BuildContext context, {
  Plantilla? initialPlantilla,
  String? defaultCategoria,
  void Function(Plantilla saved)? onSaved,
  VoidCallback? onDeleted,
}) {
  showFloatingWindow(
    context,
    (close) => _PlantillaEditorWindow(
      initialPlantilla: initialPlantilla,
      defaultCategoria: defaultCategoria,
      onClose: close,
      onSaved: onSaved,
      onDeleted: onDeleted,
    ),
  );
}

class _PlantillaEditorWindow extends StatefulWidget {
  final Plantilla? initialPlantilla;
  final String? defaultCategoria;
  final VoidCallback onClose;
  final void Function(Plantilla saved)? onSaved;
  final VoidCallback? onDeleted;

  const _PlantillaEditorWindow({
    this.initialPlantilla,
    this.defaultCategoria,
    required this.onClose,
    this.onSaved,
    this.onDeleted,
  });

  @override
  State<_PlantillaEditorWindow> createState() => _PlantillaEditorWindowState();
}

class _PlantillaEditorWindowState extends State<_PlantillaEditorWindow> {
  static const double _kHeaderH = 50.0;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descripcionCtrl;
  late String _categoria;
  late bool _isActive;

  MonacoController? _editorCtrl;
  bool _editorReady = false;
  bool _isSaving = false;
  String _currentCode = '';
  bool _dirty = false;

  Offset _position = Offset.zero;
  double? _winW = 920;
  double? _winH = 680;
  bool _maximized = false;
  bool _minimized = false;
  int? _slot;
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;
  Duration _anim = Duration.zero;

  @override
  void initState() {
    super.initState();
    final p = widget.initialPlantilla;
    _nombreCtrl = TextEditingController(text: p?.nombre ?? '');
    _descripcionCtrl = TextEditingController(text: p?.descripcion ?? '');
    _categoria =
        p?.categoria ?? widget.defaultCategoria ?? Plantilla.catProcDinamico;
    _isActive = p?.isActive ?? true;
    _currentCode = p?.contenido ?? _codigoInicialPorCategoria(_categoria);

    _nombreCtrl.addListener(_onFieldChanged);
    _descripcionCtrl.addListener(_onFieldChanged);

    editorThemeStore.addListener(_onThemeChanged);
    editorCursorStore.addListener(_onCursorChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _editorReady = true);
      });
    });
  }

  @override
  void dispose() {
    _nombreCtrl.removeListener(_onFieldChanged);
    _descripcionCtrl.removeListener(_onFieldChanged);
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    editorThemeStore.removeListener(_onThemeChanged);
    editorCursorStore.removeListener(_onCursorChanged);
    FloatingWindowSlots.release(_slot);
    super.dispose();
  }

  void _onFieldChanged() {
    final hasChanges = _hasUnsavedChanges;
    if (hasChanges != _dirty && mounted) {
      setState(() => _dirty = hasChanges);
    }
  }

  bool get _hasUnsavedChanges {
    final base = widget.initialPlantilla;
    if (base == null) {
      return _nombreCtrl.text.trim().isNotEmpty ||
          _descripcionCtrl.text.trim().isNotEmpty ||
          _currentCode != _codigoInicialPorCategoria(_categoria);
    }
    return _nombreCtrl.text.trim() != base.nombre ||
        _categoria != base.categoria ||
        _descripcionCtrl.text.trim() != (base.descripcion ?? '') ||
        _isActive != base.isActive ||
        _currentCode != base.contenido;
  }

  void _onThemeChanged() {
    _editorCtrl?.setTheme(editorThemeStore.monacoTheme);
  }

  void _onCursorChanged() {
    _editorCtrl?.updateOptions(
      EditorOptions(cursorStyle: editorCursorStore.cursorStyle),
    );
  }

  String _codigoInicialPorCategoria(String cat) {
    final seed = PlantillaService.plantillasPorDefecto().firstWhere(
      (s) => s.categoria.toUpperCase() == cat.toUpperCase(),
      orElse: () => PlantillaService.plantillasPorDefecto().first,
    );
    return seed.contenido;
  }

  void _onCategoriaChanged(String? newCat) {
    if (newCat == null || newCat == _categoria) return;
    setState(() {
      _categoria = newCat;
      _onFieldChanged();
    });
    final nuevoLang =
        _categoria == Plantilla.catProcDinamico &&
            _currentCode.contains('function')
        ? MonacoLanguage.javascript
        : MonacoLanguage.sql;
    _editorCtrl?.document.setLanguage(nuevoLang);
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showFloatingDialog<bool>(
      context,
      (ctx, close) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 420,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E22) : cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.6),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstellationHeader(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onDark: true,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.amber.shade800,
                        Color.lerp(Colors.amber.shade800, Colors.black, 0.4)!,
                      ],
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Cambios sin guardar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Text(
                    'Tienes modificaciones pendientes en la plantilla. ¿Deseas descartarlas y cerrar?',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => close(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Seguir editando',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () => close(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Descartar',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      final code = _editorCtrl != null
          ? await _editorCtrl!.document.getText()
          : _currentCode;
      final base = widget.initialPlantilla;
      final isNew =
          base == null || !base.isPersisted || base.id.startsWith('seed-');

      final p =
          (base ??
                  Plantilla(
                    id: '',
                    nombre: '',
                    categoria: _categoria,
                    contenido: '',
                  ))
              .copyWith(
                nombre: _nombreCtrl.text.trim(),
                categoria: _categoria,
                descripcion: _descripcionCtrl.text.trim().isEmpty
                    ? null
                    : _descripcionCtrl.text.trim(),
                contenido: code,
                isActive: _isActive,
                modifiedBy: PlantillaService.currentUser,
              );

      final saved = await PlantillaService.instance.save(p);
      AppToast.success(
        isNew
            ? 'Plantilla creada correctamente'
            : 'Plantilla actualizada correctamente',
      );
      _dirty = false;
      widget.onSaved?.call(saved);
      FloatingWindowSlots.release(_slot);
      _slot = null;
      widget.onClose();
    } catch (e) {
      AppToast.error('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _eliminar() async {
    final p = widget.initialPlantilla;
    if (p == null || !p.isPersisted) {
      widget.onClose();
      return;
    }

    final currentUser = PlantillaService.currentUser;
    if (!p.esPropietario(currentUser)) {
      AppToast.warning(
        'Solo el autor (${p.ownerUser.isNotEmpty ? p.ownerUser : "creador"}) puede eliminar esta plantilla',
      );
      return;
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmar = await showFloatingDialog<bool>(
      context,
      (ctx, close) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 420,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E22) : cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.6),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstellationHeader(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onDark: true,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.red.shade800,
                        Color.lerp(Colors.red.shade800, Colors.black, 0.4)!,
                      ],
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Eliminar Plantilla',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Text(
                    '¿Estás seguro de eliminar la plantilla "${p.nombre}"?',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => close(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
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
                      FilledButton(
                        onPressed: () => close(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Eliminar',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmar != true) return;

    setState(() => _isSaving = true);
    try {
      final ok = await PlantillaService.instance.delete(p);
      if (ok) {
        AppToast.success('Plantilla eliminada correctamente');
        widget.onDeleted?.call();
        FloatingWindowSlots.release(_slot);
        _slot = null;
        widget.onClose();
      } else {
        AppToast.error('No se pudo eliminar la plantilla');
      }
    } catch (e) {
      AppToast.error('Error al eliminar: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
      }
    });
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
        _restoreW = _winW;
        _restoreH = _winH;
        _restorePos = _position;
        _position = Offset.zero;
        _maximized = true;
      }
    });
  }

  Future<void> _close() async {
    if (!await _confirmDiscardIfDirty()) return;
    FloatingWindowSlots.release(_slot);
    _slot = null;
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.sizeOf(context);

    if (_maximized) {
      _winW = (screenSize.width - 32).clamp(600.0, screenSize.width);
      _winH = (screenSize.height - 32).clamp(450.0, screenSize.height);
    } else {
      _winW ??= 920.0;
      _winH ??= 680.0;
    }

    if (_winW! > screenSize.width) _winW = screenSize.width;
    if (_winH! > screenSize.height) _winH = screenSize.height;

    final double w, h, left, top;
    if (_minimized) {
      w = FloatingWindowSlots.barW;
      h = FloatingWindowSlots.barH;
      final (l, t) = FloatingWindowSlots.offsetFor(_slot ?? 0, screenSize);
      left = l;
      top = t;
    } else {
      w = _winW!;
      h = _winH!;
      left = ((screenSize.width - w) / 2 + _position.dx).clamp(
        0.0,
        (screenSize.width - w).clamp(0.0, double.infinity),
      );
      top = ((screenSize.height - h) / 2 + _position.dy).clamp(
        0.0,
        (screenSize.height - h).clamp(0.0, double.infinity),
      );
    }

    final divColor = isDark ? const Color(0xFF333333) : cs.outlineVariant;
    final bg = isDark ? const Color(0xFF1E1E1E) : cs.surface;
    final esEdicion = widget.initialPlantilla != null;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _guardar,
        const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_maximized) {
            _toggleMaximized();
          } else {
            _close();
          }
        },
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
                      _maximized ? 6 : (_minimized ? 8 : 14),
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
                          alpha: _minimized ? 0.38 : (isDark ? 0.45 : 0.15),
                        ),
                        blurRadius: _minimized ? 16 : 28,
                        offset: Offset(0, _minimized ? 4 : 10),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _minimized
                      ? MinimizedWindowCard(
                          title: _nombreCtrl.text.trim().isEmpty
                              ? (esEdicion
                                    ? 'Editar Plantilla'
                                    : 'Nueva Plantilla')
                              : _nombreCtrl.text.trim(),
                          icon: Icons.bookmark_add_rounded,
                          accentColor: const Color(0xFF0078D4),
                          badge: 'PLANTILLA',
                          badgeColor: const Color(0xFF0078D4),
                          onRestore: _toggleMinimized,
                          onClose: _close,
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildHeader(cs, divColor, esEdicion),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      14,
                                      16,
                                      12,
                                    ),
                                    child: Form(
                                      key: _formKey,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _buildMetadataFields(
                                            cs,
                                            divColor,
                                            isDark,
                                          ),
                                          const SizedBox(height: 10),
                                          _buildHelpBanner(cs, isDark),
                                          const SizedBox(height: 10),
                                          Expanded(
                                            child: _buildEditor(
                                              cs,
                                              divColor,
                                              isDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                _buildFooter(cs, divColor, esEdicion),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
            // Resize handler: borde derecho
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 5,
                top: top + 52,
                width: 10,
                height: (h - 62).clamp(0.0, double.infinity),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(
                        600.0,
                        screenSize.width - 40,
                      );
                    }),
                  ),
                ),
              ),
            // Resize handler: borde inferior
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
                        450.0,
                        screenSize.height - 40,
                      );
                    }),
                  ),
                ),
              ),
            // Resize grip
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 18,
                top: top + h - 18,
                width: 20,
                height: 20,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(
                        600.0,
                        screenSize.width - 40,
                      );
                      _winH = (_winH! + d.delta.dy).clamp(
                        450.0,
                        screenSize.height - 40,
                      );
                    }),
                    child: CustomPaint(
                      painter: WindowGripPainter(
                        (isDark ? Colors.white : Colors.black).withValues(
                          alpha: 0.18,
                        ),
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

  Widget _buildHeader(ColorScheme cs, Color divColor, bool esEdicion) {
    Widget titleArea(Widget child) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _toggleMaximized,
      child: child,
    );

    return MouseRegion(
      cursor: _maximized ? SystemMouseCursors.basic : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _maximized
            ? null
            : (d) => setState(() {
                _anim = Duration.zero;
                _position += d.delta;
              }),
        child: ConstellationHeader(
          height: _kHeaderH,
          padding: const EdgeInsets.only(left: 16, right: 10),
          lineColor: cs.primary.withValues(alpha: 0.32),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
          ),
          child: Row(
            children: [
              titleArea(
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    esEdicion
                        ? Icons.bookmark_added_rounded
                        : Icons.bookmark_add_rounded,
                    size: 16,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: titleArea(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            esEdicion
                                ? 'Editar Plantilla de Código'
                                : 'Nueva Plantilla de Código',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          if (_dirty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.amber.shade700.withValues(
                                    alpha: 0.4,
                                  ),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                'Modificado',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _nombreCtrl.text.trim().isNotEmpty
                            ? _nombreCtrl.text.trim()
                            : 'Define la estructura, parámetros y categoría para SirWeb / Oracle',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_rounded, size: 18),
                color: cs.onSurfaceVariant,
                tooltip: 'Minimizar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: _toggleMinimized,
              ),
              IconButton(
                icon: Icon(
                  _maximized
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  size: 18,
                ),
                color: cs.onSurfaceVariant,
                tooltip: 'Maximizar (F11)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: _toggleMaximized,
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: cs.onSurfaceVariant,
                tooltip: 'Cerrar (Esc)',
                hoverColor: Colors.red.withValues(alpha: 0.12),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataFields(ColorScheme cs, Color divColor, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nombre
        Expanded(
          flex: 4,
          child: TextFormField(
            controller: _nombreCtrl,
            style: TextStyle(color: cs.onSurface, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Nombre de la plantilla *',
              hintText: 'Ej: Procedimiento Dinámico Estándar',
              labelStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                fontSize: 12,
              ),
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                fontSize: 12,
              ),
              isDense: true,
              filled: true,
              fillColor: isDark
                  ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                  : cs.surfaceContainerLowest,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: divColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: divColor.withValues(alpha: isDark ? 0.45 : 0.7),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.primary, width: 1.8),
              ),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
        ),
        const SizedBox(width: 12),
        // Categoría (Selector moderno con MenuAnchor)
        Expanded(flex: 4, child: _buildCategoriaSelector(cs, divColor, isDark)),
        const SizedBox(width: 12),
        // Descripción
        Expanded(
          flex: 5,
          child: TextFormField(
            controller: _descripcionCtrl,
            style: TextStyle(color: cs.onSurface, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Descripción / Propósito',
              hintText: 'Breve explicación de la plantilla y sus casos de uso',
              labelStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                fontSize: 12,
              ),
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                fontSize: 12,
              ),
              isDense: true,
              filled: true,
              fillColor: isDark
                  ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                  : cs.surfaceContainerLowest,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: divColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: divColor.withValues(alpha: isDark ? 0.45 : 0.7),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.primary, width: 1.8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoriaSelector(ColorScheme cs, Color divColor, bool isDark) {
    final selectedMeta = _categoriaMetaFor(_categoria);

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          isDark ? const Color(0xFF222226) : cs.surface,
        ),
        elevation: const WidgetStatePropertyAll(14),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: divColor, width: 0.8),
          ),
        ),
      ),
      menuChildren: _kCategoriasMetadata.map((catMeta) {
        final isSelected =
            catMeta.code.toUpperCase() == _categoria.toUpperCase();

        return MenuItemButton(
          onPressed: () => _onCategoriaChanged(catMeta.code),
          style: MenuItemButton.styleFrom(
            backgroundColor: isSelected
                ? catMeta.color.withValues(alpha: 0.12)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          leadingIcon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: catMeta.color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(catMeta.icon, color: catMeta.color, size: 16),
          ),
          trailingIcon: isSelected
              ? Icon(Icons.check_rounded, color: catMeta.color, size: 18)
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      catMeta.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: isSelected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: catMeta.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        catMeta.code,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: catMeta.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  catMeta.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
      builder: (context, controller, child) {
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Categoría de Objeto *',
              labelStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                fontSize: 12,
              ),
              isDense: true,
              filled: true,
              fillColor: isDark
                  ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                  : cs.surfaceContainerLowest,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 7.0,
                horizontal: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: divColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: controller.isOpen
                      ? cs.primary
                      : divColor.withValues(alpha: isDark ? 0.45 : 0.7),
                  width: controller.isOpen ? 1.8 : 1.0,
                ),
              ),
              suffixIcon: Icon(
                controller.isOpen
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 20,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: selectedMeta.color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    selectedMeta.icon,
                    color: selectedMeta.color,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selectedMeta.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHelpBanner(ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.primary.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: cs.primary, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r'Placeholders interactivos: ${0:usuario} · ${1:nombre_proc} · ${2:fecha} · ${3:placeholder} · $0 cursor final',
              style: TextStyle(
                color: isDark ? const Color(0xFF90CAF9) : cs.primary,
                fontSize: 11,
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(ColorScheme cs, Color divColor, bool isDark) {
    final lang =
        _categoria == Plantilla.catProcDinamico &&
            _currentCode.contains('function')
        ? MonacoLanguage.javascript
        : MonacoLanguage.sql;

    if (!_editorReady) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: divColor, width: 0.8),
        ),
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: divColor, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: MonacoEditor(
        initialText: _currentCode,
        options: EditorOptions(
          language: lang,
          theme: editorThemeStore.monacoTheme,
          fontSize: 13,
          cursorStyle: editorCursorStore.cursorStyle,
          lineNumbers: MonacoLineNumbers.on,
          minimap: const MonacoMinimapOptions(enabled: false),
          wordWrap: MonacoWordWrap.off,
          tabSize: 2,
        ),
        onReady: (ctrl) async {
          _editorCtrl = ctrl;
          await EditorThemeStore.defineAllThemes(ctrl);
          await ctrl.setTheme(editorThemeStore.monacoTheme);
        },
        onContentChanged: (text) {
          _currentCode = text;
          _onFieldChanged();
        },
      ),
    );
  }

  Widget _buildFooter(ColorScheme cs, Color divColor, bool esEdicion) {
    final esAutor =
        widget.initialPlantilla != null &&
        widget.initialPlantilla!.isPersisted &&
        widget.initialPlantilla!.esPropietario(PlantillaService.currentUser);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        border: Border(top: BorderSide(color: divColor, width: 0.5)),
      ),
      child: Row(
        children: [
          if (esAutor)
            TextButton.icon(
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: Colors.redAccent,
              ),
              label: const Text(
                'Eliminar',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
              onPressed: _isSaving ? null : _eliminar,
            ),
          const Spacer(),
          Text(
            'Ctrl+S: Guardar  •  Esc: Salir',
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 14),
          OutlinedButton(
            onPressed: _close,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Cancelar', style: TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(
              _isSaving ? 'Guardando...' : 'Guardar Plantilla',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _isSaving ? null : _guardar,
          ),
        ],
      ),
    );
  }
}
