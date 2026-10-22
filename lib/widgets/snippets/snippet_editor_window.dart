import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;

import '../../models/snippet.dart';
import '../../services/snippet_service.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart';

/// Abre una ventana flotante independiente para la creación o edición de un Snippet.
///
/// La ventana es arrastrable, redimensionable, minimizable y cuenta con un editor
/// Monaco integrado para el cuerpo del código.
void showSnippetEditorWindow(
  BuildContext context, {
  Snippet? initialSnippet,
  void Function(Snippet saved)? onSaved,
  VoidCallback? onDeleted,
}) {
  showFloatingWindow(
    context,
    (close) => _SnippetEditorWindow(
      initialSnippet: initialSnippet,
      onClose: close,
      onSaved: onSaved,
      onDeleted: onDeleted,
    ),
  );
}

typedef LangMeta = ({
  String label,
  IconData icon,
  Color color,
  String monacoLang,
});

const Map<String, LangMeta> kSnippetLanguages = {
  'any': (
    label: 'Cualquier lenguaje',
    icon: Icons.all_inclusive_rounded,
    color: Color(0xFF8E8E93),
    monacoLang: 'plaintext',
  ),
  'sql': (
    label: 'SQL / PL·SQL',
    icon: Icons.storage_rounded,
    color: Color(0xFF0078D4),
    monacoLang: 'sql',
  ),
  'javascript': (
    label: 'JavaScript',
    icon: Icons.javascript_rounded,
    color: Color(0xFFD9A407),
    monacoLang: 'javascript',
  ),
  'yaml': (
    label: 'YAML (.yaml)',
    icon: Icons.data_object_rounded,
    color: Color(0xFFCB171E),
    monacoLang: 'yaml',
  ),
};

class _SnippetEditorWindow extends StatefulWidget {
  final Snippet? initialSnippet;
  final VoidCallback onClose;
  final void Function(Snippet saved)? onSaved;
  final VoidCallback? onDeleted;

  const _SnippetEditorWindow({
    this.initialSnippet,
    required this.onClose,
    this.onSaved,
    this.onDeleted,
  });

  @override
  State<_SnippetEditorWindow> createState() => _SnippetEditorWindowState();
}

class _SnippetEditorWindowState extends State<_SnippetEditorWindow> {
  static const double _kHeaderH = 50;

  Offset _position = Offset.zero;
  double? _winW;
  double? _winH;
  bool _minimized = false;
  int? _slot;
  bool _maximized = false;
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;
  Duration _anim = Duration.zero;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _prefixCtrl;
  late final TextEditingController _descCtrl;
  final FocusNode _nameFocus = FocusNode();

  late String _language;
  String _currentBody = '';
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final init = widget.initialSnippet;
    _nameCtrl = TextEditingController(text: init?.name ?? '');
    _prefixCtrl = TextEditingController(text: init?.prefix ?? '');
    _descCtrl = TextEditingController(text: init?.description ?? '');
    _language = init?.language ?? 'any';
    _currentBody = init?.body ?? '';

    for (final c in [_nameCtrl, _prefixCtrl, _descCtrl]) {
      c.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _prefixCtrl, _descCtrl]) {
      c.removeListener(_markDirty);
      c.dispose();
    }
    _nameFocus.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  void _onBodyChanged(String value) {
    _currentBody = value;
    _markDirty();
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
        _maximized = false;
        _winW = _restoreW;
        _winH = _restoreH;
        _position = _restorePos;
      } else {
        _restoreW = _winW;
        _restoreH = _winH;
        _restorePos = _position;
        _position = Offset.zero;
        _maximized = true;
      }
    });
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: const Text(
          'Tienes modificaciones en el snippet. ¿Deseas descartarlas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _close() async {
    if (!await _confirmDiscardIfDirty()) return;
    FloatingWindowSlots.release(_slot);
    _slot = null;
    widget.onClose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppToast.warning('Revisa los campos obligatorios');
      return;
    }
    final bodyText = _currentBody.trim();
    if (bodyText.isEmpty) {
      AppToast.warning('El cuerpo del snippet no puede estar vacío');
      return;
    }

    final base = widget.initialSnippet;
    final isNew = base == null || !base.isPersisted;

    final snippet = Snippet(
      id: base?.id ?? '',
      name: _nameCtrl.text.trim(),
      prefix: _prefixCtrl.text.trim(),
      body: _currentBody,
      description: _descCtrl.text.trim(),
      language: _language,
      ownerUser: isNew ? SnippetService.currentUser : base.ownerUser,
      isActive: true,
      version: base?.version ?? 0,
    );

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final saved = await SnippetService.instance.save(snippet);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      AppToast.success(isNew ? 'Snippet registrado' : 'Snippet actualizado');
      widget.onSaved?.call(saved);
      widget.onClose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      AppToast.error('No se pudo guardar el snippet');
    }
  }

  Future<void> _delete() async {
    final current = widget.initialSnippet;
    if (current == null || !current.isPersisted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar snippet'),
        content: Text(
          '¿Estás seguro de eliminar "${current.name.isNotEmpty ? current.name : current.prefix}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await SnippetService.instance.delete(current);
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.success('Snippet eliminado');
      widget.onDeleted?.call();
      widget.onClose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      AppToast.error('No se pudo eliminar el snippet');
    }
  }

  String _formatSnippetDate(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'hace un momento';
    if (diff.inHours < 1) return 'hace ${diff.inMinutes}m';
    if (diff.inDays < 1) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  Widget _buildAuditBadge({
    required IconData icon,
    required String label,
    required String user,
    String? extra,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
          Text(
            user.isNotEmpty ? user : '—',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'Consolas',
              color: cs.onSurface,
            ),
          ),
          if (extra != null && extra.isNotEmpty) ...[
            Text(
              ' ($extra)',
              style: TextStyle(
                fontSize: 9.5,
                color: cs.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : cs.surface;
    final divColor = isDark ? const Color(0xFF333333) : cs.outlineVariant;
    final screen = MediaQuery.sizeOf(context);

    if (_maximized) {
      _winW = (screen.width - 32).clamp(420.0, screen.width);
      _winH = (screen.height - 32).clamp(360.0, screen.height);
    } else {
      _winW ??= 780.0;
      _winH ??= 600.0;
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
      left = ((screen.width - w) / 2 + _position.dx).clamp(
        0.0,
        (screen.width - w).clamp(0.0, double.infinity),
      );
      top = ((screen.height - h) / 2 + _position.dy).clamp(
        0.0,
        (screen.height - h).clamp(0.0, double.infinity),
      );
    }

    final isNew =
        widget.initialSnippet == null || !widget.initialSnippet!.isPersisted;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (!_saving) unawaited(_save());
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_maximized) {
            _toggleMaximized();
          } else {
            unawaited(_close());
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
                      _maximized ? 6 : (_minimized ? 8 : 12),
                    ),
                    border: Border.all(color: divColor, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: _minimized ? 16 : 28,
                        offset: Offset(0, _minimized ? 4 : 10),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _minimized
                      ? MinimizedWindowCard(
                          title: _nameCtrl.text.trim().isEmpty
                              ? 'Editor de Snippet'
                              : _nameCtrl.text.trim(),
                          icon: Icons.edit_note_rounded,
                          accentColor: Colors.amber.shade700,
                          badge: 'SNIPPET',
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
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Column(
                                    children: [
                                      const SizedBox(height: _kHeaderH),
                                      if (_error != null)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          color: Colors.orange.withValues(
                                            alpha: 0.13,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.warning_amber_rounded,
                                                size: 14,
                                                color: Colors.orange[800],
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _error!,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.orange[800],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Expanded(child: _buildForm(cs, divColor)),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  width: w,
                                  child: _buildHeader(cs, divColor, isNew),
                                ),
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
                top: top + 50,
                width: 10,
                height: (h - 60).clamp(0.0, double.infinity),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(
                        520.0,
                        screen.width - 40,
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
                        360.0,
                        screen.height - 40,
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
                        520.0,
                        screen.width - 40,
                      );
                      _winH = (_winH! + d.delta.dy).clamp(
                        360.0,
                        screen.height - 40,
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

  Widget _buildHeader(ColorScheme cs, Color divColor, bool isNew) {
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
          height: _minimized ? FloatingWindowSlots.barH : _kHeaderH,
          padding: const EdgeInsets.only(left: 16, right: 10),
          lineColor: cs.primary.withValues(alpha: 0.32),
          decoration: BoxDecoration(
            border: _minimized
                ? null
                : Border(bottom: BorderSide(color: divColor, width: 0.5)),
          ),
          child: Row(
            children: [
              titleArea(
                Container(
                  width: _minimized ? 22 : 28,
                  height: _minimized ? 22 : 28,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    isNew
                        ? Icons.add_circle_outline_rounded
                        : Icons.code_rounded,
                    size: _minimized ? 13 : 16,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: titleArea(
                  _minimized
                      ? Text(
                          isNew ? 'Nuevo Snippet' : 'Editor de Snippet',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  isNew ? 'Nuevo Snippet' : 'Editar Snippet',
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
                                      color: Colors.amber.withValues(
                                        alpha: 0.18,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'sin guardar',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.amber[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              isNew
                                  ? 'Crea un fragmento reutilizable con soporte de tab-stops'
                                  : (_nameCtrl.text.isNotEmpty
                                        ? _nameCtrl.text
                                        : _prefixCtrl.text),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (!_minimized &&
                  widget.initialSnippet?.isPersisted == true) ...[
                if (widget.initialSnippet!.ownerUser.isNotEmpty)
                  _buildAuditBadge(
                    icon: Icons.person_outline_rounded,
                    label: 'Registrado',
                    user: widget.initialSnippet!.ownerUser,
                    cs: cs,
                  ),
                if ((widget.initialSnippet!.modifiedBy != null &&
                        widget.initialSnippet!.modifiedBy!.isNotEmpty) ||
                    widget.initialSnippet!.updatedAt != null) ...[
                  const SizedBox(width: 6),
                  _buildAuditBadge(
                    icon: Icons.edit_note_rounded,
                    label: 'Actualizado',
                    user:
                        (widget.initialSnippet!.modifiedBy != null &&
                            widget.initialSnippet!.modifiedBy!.isNotEmpty)
                        ? widget.initialSnippet!.modifiedBy!
                        : widget.initialSnippet!.ownerUser,
                    extra: _formatSnippetDate(widget.initialSnippet!.updatedAt),
                    cs: cs,
                  ),
                ],
                const SizedBox(width: 10),
              ],
              _WindowIconButton(
                icon: _minimized
                    ? Icons.expand_less_rounded
                    : Icons.remove_rounded,
                tooltip: _minimized ? 'Restaurar' : 'Minimizar',
                onTap: _toggleMinimized,
              ),
              const SizedBox(width: 2),
              _WindowIconButton(
                icon: _maximized
                    ? Icons.close_fullscreen_rounded
                    : Icons.open_in_full_rounded,
                tooltip: _maximized
                    ? 'Restaurar tamaño (F11)'
                    : 'Maximizar (F11)',
                onTap: () {
                  if (_minimized) {
                    _toggleMinimized();
                  } else {
                    _toggleMaximized();
                  }
                },
              ),
              const SizedBox(width: 2),
              _WindowIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Cerrar (Esc)',
                danger: true,
                onTap: () => unawaited(_close()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ColorScheme cs, Color divColor) {
    final labelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      color: cs.onSurfaceVariant,
    );

    InputDecoration deco({String? hint}) => InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 12,
        color: cs.onSurfaceVariant.withValues(alpha: 0.45),
      ),
      errorStyle: const TextStyle(fontSize: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: cs.primary, width: 1),
      ),
    );

    final langMeta = kSnippetLanguages[_language] ?? kSnippetLanguages['any']!;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('NOMBRE DEL SNIPPET', style: labelStyle),
                          const SizedBox(height: 5),
                          TextFormField(
                            controller: _nameCtrl,
                            focusNode: _nameFocus,
                            decoration: deco(hint: 'Ej: SELECT dinámico'),
                            style: const TextStyle(fontSize: 12),
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Obligatorio'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PREFIX / TRIGGER', style: labelStyle),
                          const SizedBox(height: 5),
                          TextFormField(
                            controller: _prefixCtrl,
                            decoration: deco(hint: 'Ej: seldin'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'Consolas',
                              fontWeight: FontWeight.w600,
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'Obligatorio';
                              if (t.contains(' ')) return 'Sin espacios';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LENGUAJE', style: labelStyle),
                          const SizedBox(height: 5),
                          MenuAnchor(
                            alignmentOffset: const Offset(0, 4),
                            menuChildren: [
                              for (final e in kSnippetLanguages.entries)
                                MenuItemButton(
                                  leadingIcon: Icon(
                                    e.value.icon,
                                    size: 14,
                                    color: e.value.color,
                                  ),
                                  trailingIcon: e.key == _language
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 14,
                                          color: cs.primary,
                                        )
                                      : null,
                                  onPressed: () {
                                    setState(() => _language = e.key);
                                    _markDirty();
                                  },
                                  child: Text(
                                    e.value.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: e.key == _language
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                            ],
                            builder: (context, menuCtrl, _) {
                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  if (menuCtrl.isOpen) {
                                    menuCtrl.close();
                                  } else {
                                    menuCtrl.open();
                                  }
                                },
                                child: InputDecorator(
                                  decoration: deco(),
                                  isEmpty: false,
                                  child: Row(
                                    children: [
                                      Icon(
                                        langMeta.icon,
                                        size: 13,
                                        color: langMeta.color,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          langMeta.label,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        size: 18,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DESCRIPCIÓN (OPCIONAL)', style: labelStyle),
                          const SizedBox(height: 5),
                          TextFormField(
                            controller: _descCtrl,
                            decoration: deco(
                              hint:
                                  'Breve explicación que se muestra en el menú autocompletar',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text('CUERPO DE CÓDIGO (MONACO EDITOR)', style: labelStyle),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    r'${1:placeholder}  ·  $0 cursor final',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontFamily: 'Consolas',
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${langMeta.monacoLang.toUpperCase()} MODE',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: langMeta.color,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: divColor, width: 0.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: fm.MonacoEditor(
                key: ValueKey(
                  'monaco_snippet_editor_${widget.initialSnippet?.id}_$_language',
                ),
                initialText: _currentBody,
                options: fm.EditorOptions(
                  language: switch (langMeta.monacoLang) {
                    'sql' => fm.MonacoLanguage.sql,
                    'javascript' => fm.MonacoLanguage.javascript,
                    'yaml' => fm.MonacoLanguage.yaml,
                    _ => fm.MonacoLanguage.plaintext,
                  },
                  theme: Theme.of(context).brightness == Brightness.dark
                      ? fm.MonacoTheme.vsDark
                      : fm.MonacoTheme.vs,
                  fontSize: 12,
                  minimap: const fm.MonacoMinimapOptions(enabled: false),
                  lineNumbers: fm.MonacoLineNumbers.on,
                  tabSize: 2,
                  automaticLayout: true,
                ),
                onContentChanged: (val) {
                  _onBodyChanged(val);
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
              border: Border(top: BorderSide(color: divColor, width: 0.5)),
            ),
            child: Row(
              children: [
                if (widget.initialSnippet?.isPersisted == true)
                  TextButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 15,
                      color: cs.error,
                    ),
                    label: Text(
                      'Eliminar',
                      style: TextStyle(fontSize: 12, color: cs.error),
                    ),
                  ),
                const Spacer(),
                Text(
                  'Ctrl+S guardar · Esc cerrar',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(width: 12),
                if (_dirty)
                  TextButton(
                    onPressed: _saving ? null : () => unawaited(_close()),
                    child: const Text(
                      'Descartar',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.save_outlined, size: 15),
                  label: Text(
                    widget.initialSnippet?.isPersisted == true
                        ? 'Guardar cambios'
                        : 'Registrar snippet',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  const _WindowIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  @override
  State<_WindowIconButton> createState() => _WindowIconButtonState();
}

class _WindowIconButtonState extends State<_WindowIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = widget.danger
        ? (_hover ? Colors.red[600] : cs.onSurfaceVariant)
        : (_hover ? cs.primary : cs.onSurfaceVariant);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hover
                  ? (widget.danger
                        ? Colors.red.withValues(alpha: 0.12)
                        : cs.surfaceContainerHighest)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 15, color: fg),
          ),
        ),
      ),
    );
  }
}
