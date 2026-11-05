import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

import '../../models/plantilla.dart';
import '../../services/editor_cursor_store.dart';
import '../../services/plantilla_service.dart';
import '../_editor_themes.dart';
import '../app_toast.dart';
import '../floating_window.dart';

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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descripcionCtrl;
  late String _categoria;
  late bool _isActive;

  MonacoController? _editorCtrl;
  bool _editorReady = false;
  bool _isSaving = false;
  String _currentCode = '';

  Offset _position = Offset.zero;
  double? _winW = 900;
  double? _winH = 650;
  bool _maximized = false;
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
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    editorThemeStore.removeListener(_onThemeChanged);
    editorCursorStore.removeListener(_onCursorChanged);
    FloatingWindowSlots.release(_slot);
    super.dispose();
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
    });
    final nuevoLang =
        _categoria == Plantilla.catProcDinamico &&
            _currentCode.contains('function')
        ? MonacoLanguage.javascript
        : MonacoLanguage.sql;
    _editorCtrl?.document.setLanguage(nuevoLang);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      final code = _editorCtrl != null
          ? await _editorCtrl!.document.getText()
          : _currentCode;
      final p =
          (widget.initialPlantilla ??
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
              );

      final saved = await PlantillaService.instance.save(p);
      AppToast.info('Plantilla guardada correctamente');
      widget.onSaved?.call(saved);
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

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222A),
        title: const Text(
          'Eliminar Plantilla',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '¿Estás seguro de eliminar la plantilla "${p.nombre}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _isSaving = true);
    try {
      final ok = await PlantillaService.instance.delete(p);
      if (ok) {
        AppToast.info('Plantilla eliminada');
        widget.onDeleted?.call();
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

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final w = _maximized
        ? screenSize.width
        : (_winW ?? 900).clamp(600.0, screenSize.width);
    final h = _maximized
        ? screenSize.height
        : (_winH ?? 650).clamp(450.0, screenSize.height);

    return Positioned(
      left: _maximized ? 0 : (screenSize.width - w) / 2 + _position.dx,
      top: _maximized ? 0 : (screenSize.height - h) / 2 + _position.dy,
      width: w,
      height: h,
      child: AnimatedContainer(
        duration: _anim,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: const Color(0xFF141820),
          borderRadius: BorderRadius.circular(_maximized ? 0 : 12),
          border: Border.all(color: const Color(0xFF2C3240), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 30,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_maximized ? 0 : 11),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  _guardar,
              const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
              const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
            },
            child: Focus(
              autofocus: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildMetadataFields(),
                            const SizedBox(height: 12),
                            _buildHelpBanner(),
                            const SizedBox(height: 10),
                            Expanded(child: _buildEditor()),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final esEdicion = widget.initialPlantilla != null;
    return GestureDetector(
      onPanUpdate: _maximized
          ? null
          : (d) => setState(() {
              _anim = Duration.zero;
              _position += d.delta;
            }),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          color: Color(0xFF1B202C),
          border: Border(bottom: BorderSide(color: Color(0xFF2C3240))),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF0078D4).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.bookmark_add_rounded,
                color: Color(0xFF4FC3F7),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              esEdicion
                  ? 'Editar Plantilla de Código'
                  : 'Nueva Plantilla de Código',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                _maximized
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
              ),
              color: Colors.white70,
              iconSize: 18,
              tooltip: 'Maximizar (F11)',
              onPressed: _toggleMaximized,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              color: Colors.white70,
              iconSize: 18,
              tooltip: 'Cerrar (Esc)',
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataFields() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nombre
        Expanded(
          flex: 4,
          child: TextFormField(
            controller: _nombreCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Nombre de la plantilla *',
              labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF1B202C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF333B4D)),
              ),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
        ),
        const SizedBox(width: 12),
        // Categoría
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: _categoria,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            dropdownColor: const Color(0xFF1B202C),
            decoration: InputDecoration(
              labelText: 'Categoría de Objeto *',
              labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF1B202C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF333B4D)),
              ),
            ),
            items: Plantilla.categoriasValidas.map((cat) {
              return DropdownMenuItem(
                value: cat,
                child: Text(cat, style: const TextStyle(fontSize: 12)),
              );
            }).toList(),
            onChanged: _onCategoriaChanged,
          ),
        ),
        const SizedBox(width: 12),
        // Descripción
        Expanded(
          flex: 5,
          child: TextFormField(
            controller: _descripcionCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Descripción / Propósito',
              labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF1B202C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF333B4D)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHelpBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0078D4).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFF0078D4).withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF64B5F6), size: 15),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tokens reemplazables automáticamente al instanciar: '
              '{NOMBRE_PROC} (o {NOMBRE}), {USUARIO}, {FECHA}',
              style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    final lang =
        _categoria == Plantilla.catProcDinamico &&
            _currentCode.contains('function')
        ? MonacoLanguage.javascript
        : MonacoLanguage.sql;

    if (!_editorReady) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2C3240)),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF0078D4),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2C3240)),
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
        onContentChanged: (text) => _currentCode = text,
      ),
    );
  }

  Widget _buildFooter() {
    final esEdicion =
        widget.initialPlantilla != null && widget.initialPlantilla!.isPersisted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF181C26),
        border: Border(top: BorderSide(color: Color(0xFF2C3240))),
      ),
      child: Row(
        children: [
          if (esEdicion)
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
          const Text(
            'Ctrl+S: Guardar  •  Esc: Cancelar',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(width: 16),
          OutlinedButton(
            onPressed: widget.onClose,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0xFF3A4254)),
            ),
            child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 16),
            label: Text(
              _isSaving ? 'Guardando...' : 'Guardar Plantilla',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0078D4),
              foregroundColor: Colors.white,
            ),
            onPressed: _isSaving ? null : _guardar,
          ),
        ],
      ),
    );
  }
}
