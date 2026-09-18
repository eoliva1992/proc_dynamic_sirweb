import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;

import '../widgets/constellation_background.dart';
import '../widgets/floating_window.dart';
import '../widgets/native_diff_viewer.dart';

void showPasteDiff(
  BuildContext context, {
  String initialSource = '',
  String initialTarget = '',
}) {
  showFloatingWindow(
    context,
    (close) => PasteDiffPage(
      onClose: close,
      initialSource: initialSource,
      initialTarget: initialTarget,
    ),
  );
}

class PasteDiffPage extends StatefulWidget {
  final VoidCallback? onClose;
  final String initialSource;
  final String initialTarget;

  const PasteDiffPage({
    super.key,
    this.onClose,
    this.initialSource = '',
    this.initialTarget = '',
  });

  @override
  State<PasteDiffPage> createState() => _PasteDiffPageState();
}

class _PasteDiffPageState extends State<PasteDiffPage> {
  late String _sourceText = widget.initialSource;
  late String _targetText = widget.initialTarget;
  fm.MonacoController? _sourceCtrl;
  fm.MonacoController? _targetCtrl;
  final _diffController = NativeDiffController();
  final _history = <({String source, String target})>[];

  bool _sideBySide = true;
  bool _showAllLines = true;
  bool _editorsCollapsed = false;
  bool _maximized = false;
  bool _minimized = false;
  int? _slot;
  Offset _position = Offset.zero;
  double? _winW;
  double? _winH;
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;
  Duration _anim = Duration.zero;

  static const double _kMinW = 640;
  static const double _kHeaderH = 44;

  @override
  void dispose() {
    FloatingWindowSlots.release(_slot);
    // MonacoEditor gestiona el ciclo de vida de su propio controller.
    _sourceCtrl = null;
    _targetCtrl = null;
    _diffController.dispose();
    super.dispose();
  }

  void _toggleEditorsCollapsed() {
    setState(() => _editorsCollapsed = !_editorsCollapsed);
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

  String get _source => _sourceText;
  String get _target => _targetText;

  bool get _hasChanges => _source != _target;

  void _rememberState() {
    final previous = _history.isEmpty ? null : _history.last;
    if (previous?.source == _source && previous?.target == _target) return;
    _history.add((source: _source, target: _target));
  }

  void _setTexts(String source, String target) {
    _sourceCtrl?.document.setText(source);
    _targetCtrl?.document.setText(target);
    setState(() {
      _sourceText = source;
      _targetText = target;
    });
  }

  void _undo() {
    if (_history.isEmpty) return;
    final previous = _history.removeLast();
    _setTexts(previous.source, previous.target);
  }

  void _swapSides() {
    _rememberState();
    _setTexts(_target, _source);
  }

  Future<void> _applyAllToTarget() async {
    if (_source == _target) return;
    if (!await _confirmReplace('destino')) return;
    _rememberState();
    _setTexts(_source, _source);
  }

  Future<void> _applyAllToSource() async {
    if (_source == _target) return;
    if (!await _confirmReplace('origen')) return;
    _rememberState();
    _setTexts(_target, _target);
  }

  Future<bool> _confirmReplace(String side) async {
    final result = await showFloatingDialog<bool>(
      context,
      (context, close) => AlertDialog(
        title: Text('Reemplazar todo el $side'),
        content: Text(
          'Se sobrescribirá todo el contenido del $side con el otro panel. '
          'Podrás deshacer la operación con Ctrl+Z.',
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => close(true),
            child: const Text('Reemplazar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _applyLineToTarget(int hunkIndex, int hunkRow) {
    final hunks = computeHunks(_source, _target);
    if (hunkIndex >= hunks.length) return;
    final hunk = hunks[hunkIndex];
    final sourceLines = _source.split('\n');
    final targetLines = _target.split('\n');
    final sourceCount = hunk.origEnd - hunk.origStart;
    final targetCount = hunk.modEnd - hunk.modStart;
    if (hunkRow >= sourceCount && hunkRow >= targetCount) return;

    _rememberState();
    if (hunkRow < sourceCount && hunkRow < targetCount) {
      targetLines[hunk.modStart + hunkRow] =
          sourceLines[hunk.origStart + hunkRow];
    } else if (hunkRow < sourceCount) {
      targetLines.insert(
        hunk.modStart + targetCount,
        sourceLines[hunk.origStart + hunkRow],
      );
    } else {
      targetLines.removeAt(hunk.modStart + hunkRow - sourceCount);
    }
    _setTexts(_source, targetLines.join('\n'));
  }

  void _applyLineToSource(int hunkIndex, int hunkRow) {
    final hunks = computeHunks(_source, _target);
    if (hunkIndex >= hunks.length) return;
    final hunk = hunks[hunkIndex];
    final sourceLines = _source.split('\n');
    final targetLines = _target.split('\n');
    final sourceCount = hunk.origEnd - hunk.origStart;
    final targetCount = hunk.modEnd - hunk.modStart;
    if (hunkRow >= sourceCount && hunkRow >= targetCount) return;

    _rememberState();
    if (hunkRow < sourceCount && hunkRow < targetCount) {
      sourceLines[hunk.origStart + hunkRow] =
          targetLines[hunk.modStart + hunkRow];
    } else if (hunkRow < targetCount) {
      sourceLines.insert(
        hunk.origStart + sourceCount,
        targetLines[hunk.modStart + hunkRow],
      );
    } else {
      sourceLines.removeAt(hunk.origStart + hunkRow - targetCount);
    }
    _setTexts(sourceLines.join('\n'), _target);
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copiado al portapapeles')));
  }

  Future<void> _save(String text, String fileName, String label) async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Guardar $label',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['sql', 'txt', 'diff'],
    );
    if (path == null) return;
    await File(path).writeAsString(text, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label guardado en $path')));
  }

  Future<void> _showOutputMenu() async {
    final result = await showModalBottomSheet<_OutputAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: const Text('Guardar texto destino'),
              onTap: () => Navigator.pop(context, _OutputAction.saveTarget),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copiar texto destino'),
              onTap: () => Navigator.pop(context, _OutputAction.copyTarget),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt_outlined),
              title: const Text('Guardar diff unificado'),
              onTap: () => Navigator.pop(context, _OutputAction.saveDiff),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_outlined),
              title: const Text('Copiar diff unificado'),
              onTap: () => Navigator.pop(context, _OutputAction.copyDiff),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    final diff = _unifiedDiff(_source, _target);
    switch (result) {
      case _OutputAction.saveTarget:
        await _save(_target, 'diff_destino.sql', 'texto destino');
      case _OutputAction.copyTarget:
        await _copy(_target, 'Texto destino');
      case _OutputAction.saveDiff:
        await _save(diff, 'diff_unificado.diff', 'diff unificado');
      case _OutputAction.copyDiff:
        await _copy(diff, 'Diff unificado');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final gripColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.18,
    );

    // Ventana contenida por defecto (nunca a pantalla completa).
    if (_maximized) {
      _winW = (size.width - 48).clamp(320.0, size.width);
      _winH = (size.height - 48).clamp(280.0, size.height);
    } else {
      _winW ??= (size.width * 0.85).clamp(_kMinW, 1400.0);
      _winH ??= (size.height * 0.82).clamp(480.0, 900.0);
    }
    // Nunca más grande que la pantalla (evita clamps invertidos al posicionar).
    if (_winW! > size.width) _winW = size.width;
    if (_winH! > size.height) _winH = size.height;

    // Geometría efectiva: minimizada ocupa solo la barra de título.
    final double w, h, left, top;
    if (_minimized) {
      w = FloatingWindowSlots.barW;
      h = FloatingWindowSlots.barH;
      final (l, t) = FloatingWindowSlots.offsetFor(_slot ?? 0, size);
      left = l;
      top = t;
    } else {
      w = _winW!;
      h = _winH!;
      left = ((size.width - w) / 2 + _position.dx).clamp(
        0.0,
        (size.width - w).clamp(0.0, double.infinity),
      );
      top = ((size.height - h) / 2 + _position.dy).clamp(
        0.0,
        (size.height - h).clamp(0.0, double.infinity),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
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
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(
                      _maximized ? 6 : (_minimized ? 8 : 12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.5 : 0.18,
                        ),
                        blurRadius: _minimized ? 16 : 40,
                        offset: Offset(0, _minimized ? 4 : 16),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  // El contenido se mantiene SIEMPRE montado con el tamaño de
                  // la ventana restaurada: al minimizar sólo se recorta.
                  child: OverflowBox(
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
                                Expanded(child: _buildBody()),
                              ],
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            width: w,
                            child: _buildHeader(isDark, cs),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Resize: borde derecho ─────────────────────────────────────
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 5,
                top: top + 44,
                width: 10,
                height: (h - 54).clamp(0.0, double.infinity),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(
                        _kMinW,
                        size.width - 40,
                      );
                    }),
                  ),
                ),
              ),

            // ── Resize: borde inferior ────────────────────────────────────
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
                        size.height - 40,
                      );
                    }),
                  ),
                ),
              ),

            // ── Resize: esquina inferior derecha (grip) ───────────────────
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
                        _kMinW,
                        size.width - 40,
                      );
                      _winH = (_winH! + d.delta.dy).clamp(
                        360.0,
                        size.height - 40,
                      );
                    }),
                    child: CustomPaint(painter: WindowGripPainter(gripColor)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Barra de título (arrastrable) ──────────────────────────────────────────

  Widget _buildHeader(bool isDark, ColorScheme cs) {
    final divColor = cs.outlineVariant;
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
          height: _kHeaderH,
          padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF262626), Color(0xFF212121)]
                  : const [Color(0xFFF7F9FC), Color(0xFFF0F3F8)],
            ),
            border: _minimized
                ? null
                : Border(bottom: BorderSide(color: divColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _minimized ? _toggleMinimized : _toggleMaximized,
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          Icons.compare_arrows,
                          size: 16,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!_minimized) ...[
                        const Text(
                          'Diff pegado',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildHeaderBadge('ORIGEN ↔ DESTINO', cs.primary),
                      ],
                    ],
                  ),
                ),
              ),
              WindowButton.titleBar(
                icon: _minimized
                    ? Icons.expand_less_rounded
                    : Icons.remove_rounded,
                tooltip: _minimized ? 'Restaurar' : 'Minimizar',
                onTap: _toggleMinimized,
              ),
              WindowButton.titleBar(
                icon: _maximized
                    ? Icons.close_fullscreen_rounded
                    : Icons.open_in_full_rounded,
                tooltip: _maximized
                    ? 'Restaurar tamaño  (F11)'
                    : 'Maximizar  (F11)',
                size: 13,
                onTap: () {
                  if (_minimized) {
                    _toggleMinimized();
                  } else {
                    _toggleMaximized();
                  }
                },
              ),
              WindowButton.titleBar(
                icon: Icons.close_rounded,
                tooltip: 'Cerrar  (Esc)',
                isClose: true,
                size: 16,
                onTap: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Barra de acciones (deshacer, intercambiar, guardar/copiar) ────────────

  Widget _buildActionsBar() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divColor = cs.outlineVariant;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151A21) : const Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: divColor.withValues(alpha: 0.55)),
          bottom: BorderSide(color: divColor),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Deshacer',
            onPressed: _history.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Intercambiar origen y destino',
            onPressed: _swapSides,
            icon: const Icon(Icons.swap_horiz, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Guardar o copiar resultado',
            onPressed: _showOutputMenu,
            icon: const Icon(Icons.output_outlined, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          const Spacer(),
          Text(
            _hasChanges ? 'Hay diferencias' : 'Sin cambios',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildActionsBar(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 900;
              return Column(
                children: [
                  if (_editorsCollapsed)
                    _buildCollapsedEditorsBar()
                  else
                    Expanded(
                      flex: narrow ? 5 : 4,
                      child: _buildEditors(narrow),
                    ),
                  const Divider(height: 1),
                  Expanded(flex: narrow ? 6 : 5, child: _buildViewer()),
                ],
              );
            },
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  Widget _buildCollapsedEditorsBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 12, right: 4),
      color: cs.surfaceContainerLow,
      child: Row(
        children: [
          Icon(Icons.code_rounded, size: 17, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            'Fuentes ocultas',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            'Origen y destino',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          IconButton(
            tooltip: 'Mostrar fuentes',
            onPressed: _toggleEditorsCollapsed,
            icon: const Icon(Icons.expand_more_rounded, size: 20),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  void _close() {
    FloatingWindowSlots.release(_slot);
    _slot = null;
    final close = widget.onClose;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Widget _buildHeaderBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: .4,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          FilledButton.tonalIcon(
            onPressed: _hasChanges ? _applyAllToSource : null,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Aplicar todo al origen'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: _hasChanges ? _applyAllToTarget : null,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Aplicar todo al destino'),
          ),
          const Spacer(),
          Text(_hasChanges ? 'Hay diferencias' : 'Sin cambios'),
        ],
      ),
    );
  }

  Widget _buildEditors(bool narrow) {
    final cs = Theme.of(context).colorScheme;
    final panels = [
      _buildEditor(
        title: 'Origen',
        initialText: _sourceText,
        isSource: true,
        color: Colors.blue,
      ),
      _buildEditor(
        title: 'Destino',
        initialText: _targetText,
        isSource: false,
        color: Colors.orange,
      ),
    ];
    return Column(
      children: [
        SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                Icon(Icons.code_rounded, size: 17, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Fuentes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Ocultar fuentes',
                  onPressed: _toggleEditorsCollapsed,
                  icon: const Icon(Icons.expand_less_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: narrow
                ? Column(
                    children: [
                      Expanded(child: panels[0]),
                      const SizedBox(height: 8),
                      Expanded(child: panels[1]),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: panels[0]),
                      const SizedBox(width: 12),
                      Expanded(child: panels[1]),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditor({
    required String title,
    required String initialText,
    required bool isSource,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      key: ValueKey('${title.toLowerCase()}-editor-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: fm.MonacoEditor(
              initialText: initialText,
              options: fm.EditorOptions(
                language: fm.MonacoLanguage.sql,
                theme: isDark ? fm.MonacoTheme.vsDark : fm.MonacoTheme.vs,
                fontSize: 13,
                minimap: const fm.MonacoMinimapOptions(enabled: false),
                lineNumbers: fm.MonacoLineNumbers.on,
                wordWrap: fm.MonacoWordWrap.on,
                // Necesario para que el buscador nativo (Ctrl+F) reciba clicks
                // dentro del WebView2 embebido.
                extra: const {'fixedOverflowWidgets': true},
              ),
              contentDebounce: const Duration(milliseconds: 300),
              onReady: (ctrl) {
                if (isSource) {
                  _sourceCtrl = ctrl;
                } else {
                  _targetCtrl = ctrl;
                }
              },
              onContentChanged: (text) => setState(() {
                if (isSource) {
                  _sourceText = text;
                } else {
                  _targetText = text;
                }
              }),
              onError: (e, _) => debugPrint('Monaco error ($title): $e'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildViewer() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Text(
                'Comparación',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Lado a lado')),
                  ButtonSegment(value: false, label: Text('Unificada')),
                ],
                selected: {_sideBySide},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onSelectionChanged: (values) =>
                    setState(() => _sideBySide = values.first),
              ),
              const SizedBox(width: 6),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Completo')),
                  ButtonSegment(value: false, label: Text('Solo diffs')),
                ],
                selected: {_showAllLines},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onSelectionChanged: (values) =>
                    setState(() => _showAllLines = values.first),
              ),
              const Spacer(),
              Text(
                '${_source.split('\n').length} / ${_target.split('\n').length} líneas',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        Expanded(
          child: NativeDiffViewer(
            origText: _source,
            modText: _target,
            sideBySide: _sideBySide,
            showAllLines: _showAllLines,
            controller: _diffController,
            searchQuery: '',
            onApplyLineToTarget: _applyLineToTarget,
            onApplyLineToSource: _applyLineToSource,
          ),
        ),
      ],
    );
  }
}

enum _OutputAction { saveTarget, copyTarget, saveDiff, copyDiff }

String _unifiedDiff(String source, String target) {
  final sourceLines = source.split('\n');
  final targetLines = target.split('\n');
  final result = <String>['--- origen', '+++ destino'];
  var sourceIndex = 0;
  var targetIndex = 0;
  while (sourceIndex < sourceLines.length || targetIndex < targetLines.length) {
    if (sourceIndex < sourceLines.length &&
        targetIndex < targetLines.length &&
        sourceLines[sourceIndex] == targetLines[targetIndex]) {
      result.add(' ${sourceLines[sourceIndex]}');
      sourceIndex++;
      targetIndex++;
    } else {
      if (sourceIndex < sourceLines.length)
        result.add('-${sourceLines[sourceIndex++]}');
      if (targetIndex < targetLines.length)
        result.add('+${targetLines[targetIndex++]}');
    }
  }
  return '${result.join('\n')}\n';
}
