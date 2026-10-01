import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constellation_background.dart';
import 'floating_window.dart';
import 'native_diff_viewer.dart';

/// Abre una ventana flotante con el diff de un procedimiento dinámico.
///
/// Comparte los mismos controles de edición y capacidades que `SchemaObjectDiffPage`:
/// - Navegación entre hunks (`Alt+↑` / `Alt+↓`)
/// - Aplicar cambio actual: origen → destino (`Alt+→`) o destino → origen (`Alt+←`)
/// - Copiar TODO: origen → destino (`Alt+Shift+→`) o destino → origen (`Alt+Shift+←`)
/// - Aplicar líneas individuales mediante botones directos en el gutter
/// - Edición directa en línea (`editableSide` / `onEditLine`)
/// - Búsqueda de texto con conteo y navegación interactiva
/// - Deshacer (`Ctrl+Z`) con historial
/// - Sincronización opcional de vuelta al editor Monaco mediante [onApplyToEditor]
/// - Ventana flotante arrastrable, redimensionable y minimizable.
VoidCallback showProcedureDiff(
  BuildContext context, {
  required String title,
  required String original,
  required String modified,
  required String language, // 'sql' | 'javascript'
  String? procId,
  String? ambiente,
  ValueChanged<String>? onApplyToEditor,
}) {
  return showFloatingWindow(
    context,
    (close) => ProcedureDiffWindow(
      title: title,
      original: original,
      modified: modified,
      language: language,
      procId: procId,
      ambiente: ambiente,
      onApplyToEditor: onApplyToEditor,
      onClose: close,
    ),
  );
}

class ProcedureDiffWindow extends StatefulWidget {
  final String title;
  final String original;
  final String modified;
  final String language;
  final String? procId;
  final String? ambiente;
  final ValueChanged<String>? onApplyToEditor;
  final VoidCallback? onClose;

  const ProcedureDiffWindow({
    super.key,
    required this.title,
    required this.original,
    required this.modified,
    required this.language,
    this.procId,
    this.ambiente,
    this.onApplyToEditor,
    this.onClose,
  });

  @override
  State<ProcedureDiffWindow> createState() => _ProcedureDiffWindowState();
}

class _ProcedureDiffWindowState extends State<ProcedureDiffWindow> {
  static const _kPrefSideBySide = 'diff_side_by_side';
  static const _kPrefShowAllLines = 'diff_show_all_lines';

  static const double _kMinW = 720;
  static const double _kHeaderH = 44;

  bool _sideBySide = false;
  bool _showAllLines = true;

  double? _winW;
  double? _winH;
  Offset _position = Offset.zero;
  bool _maximized = false;
  bool _minimized = false;
  int? _slot;
  Duration _anim = Duration.zero;

  final _diffCtrl = NativeDiffController();

  // ── Textos mutables normalizados ──────────────────────────────────────────
  late String _initialModified;
  late String _currentOriginal;
  late String _modifiedText;

  // Historial de deshacer
  final _history = <({String original, String modified})>[];

  // Edición directa
  DiffEditSide _editSide = DiffEditSide.none;

  // Búsqueda
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  int _searchIndex = 0;

  static String _normalize(String s) =>
      s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  /// Conteo de líneas agregadas/eliminadas.
  ({int added, int removed}) get _stats {
    if (_currentOriginal == _modifiedText) return (added: 0, removed: 0);
    var added = 0, removed = 0;
    for (final h in computeHunks(_currentOriginal, _modifiedText)) {
      removed += h.origEnd - h.origStart;
      added += h.modEnd - h.modStart;
    }
    return (added: added, removed: removed);
  }

  @override
  void initState() {
    super.initState();
    _currentOriginal = _normalize(widget.original);
    _modifiedText = _normalize(widget.modified);
    _initialModified = _modifiedText;
    _loadPrefs();
  }

  @override
  void dispose() {
    if (_slot != null) {
      FloatingWindowSlots.release(_slot!);
    }
    _diffCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── Persistencia ─────────────────────────────────────────────────────────

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final sideBySide = prefs.getBool(_kPrefSideBySide);
      final showAllLines = prefs.getBool(_kPrefShowAllLines);
      if (sideBySide == null && showAllLines == null) return;
      setState(() {
        _sideBySide = sideBySide ?? _sideBySide;
        _showAllLines = showAllLines ?? _showAllLines;
      });
    } catch (_) {
      // Sin storage disponible
    }
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefSideBySide, _sideBySide);
      await prefs.setBool(_kPrefShowAllLines, _showAllLines);
    } catch (_) {
      // Best effort
    }
  }

  void _toggleShowAllLines() {
    setState(() => _showAllLines = !_showAllLines);
    _savePrefs();
  }

  void _toggleSideBySide() {
    setState(() => _sideBySide = !_sideBySide);
    _savePrefs();
  }

  void _nextChange() => _diffCtrl.nextChange();
  void _prevChange() => _diffCtrl.previousChange();

  void _toggleMaximized() {
    setState(() {
      _anim = const Duration(milliseconds: 200);
      if (_maximized) {
        _maximized = false;
        // Restaurar a dimensiones por defecto
        _winW = null;
        _winH = null;
      } else {
        _maximized = true;
        if (_minimized) {
          FloatingWindowSlots.release(_slot!);
          _slot = null;
          _minimized = false;
        }
        _position = Offset.zero;
      }
    });
  }

  void _toggleMinimized() {
    setState(() {
      _anim = const Duration(milliseconds: 200);
      _minimized = !_minimized;
      if (_minimized) {
        _maximized = false;
        _slot = FloatingWindowSlots.take();
      } else {
        FloatingWindowSlots.release(_slot!);
        _slot = null;
      }
    });
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ── Acciones de edición / Reemplazo ───────────────────────────────────────

  void _applyHunkToTarget(int idx) {
    final oFrag = _currentOriginal;
    final mFrag = _modifiedText;
    final hunks = computeHunks(oFrag, mFrag);
    if (idx < 0 || idx >= hunks.length) return;
    final h = hunks[idx];
    final oL = oFrag.split('\n');
    final dL = mFrag.split('\n');
    final newFrag = [
      ...dL.sublist(0, h.modStart),
      ...oL.sublist(h.origStart, h.origEnd),
      ...dL.sublist(h.modEnd),
    ].join('\n');
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _modifiedText = newFrag;
    });
    _notifyEditorChanged();
  }

  void _applyHunkToSource(int idx) {
    final oFrag = _currentOriginal;
    final mFrag = _modifiedText;
    final hunks = computeHunks(oFrag, mFrag);
    if (idx < 0 || idx >= hunks.length) return;
    final h = hunks[idx];
    final oL = oFrag.split('\n');
    final dL = mFrag.split('\n');
    final newFrag = [
      ...oL.sublist(0, h.origStart),
      ...dL.sublist(h.modStart, h.modEnd),
      ...oL.sublist(h.origEnd),
    ].join('\n');
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _currentOriginal = newFrag;
    });
  }

  void _applyCurrentHunkToTarget() => _applyHunkToTarget(_diffCtrl.currentHunk);
  void _applyCurrentHunkToSource() => _applyHunkToSource(_diffCtrl.currentHunk);

  void _applyAllToTarget() {
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _modifiedText = _currentOriginal;
    });
    _notifyEditorChanged();
  }

  void _applyAllToSource() {
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _currentOriginal = _modifiedText;
    });
  }

  Future<void> _confirmReplace({required bool towardsTarget}) async {
    final direction = towardsTarget ? 'GUARDADO → EDITOR' : 'EDITOR → GUARDADO';
    final destination = towardsTarget ? 'el EDITOR' : 'la versión GUARDADA';
    final source = towardsTarget ? 'la versión GUARDADA' : 'el EDITOR';

    final confirmed = await showFloatingDialog<bool>(
      context,
      (dialogContext, close) => AlertDialog(
        title: const Text('Confirmar reemplazo'),
        content: Text(
          'Se reemplazará todo el contenido de $destination con $source ($direction).\n\n'
          'El cambio podrá deshacerse con Ctrl+Z.',
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
    if (confirmed != true || !mounted) return;

    if (towardsTarget) {
      _applyAllToTarget();
    } else {
      _applyAllToSource();
    }
  }

  // ── Aplicar por línea en Gutter ──────────────────────────────────────────

  void _applyLineToTarget(int hunkIdx, int hunkRow) {
    final oFrag = _currentOriginal;
    final mFrag = _modifiedText;
    final hunks = computeHunks(oFrag, mFrag);
    if (hunkIdx >= hunks.length) return;
    final h = hunks[hunkIdx];
    final oC = h.origEnd - h.origStart;
    final mC = h.modEnd - h.modStart;
    final hasO = hunkRow < oC;
    final hasM = hunkRow < mC;
    final oL = oFrag.split('\n');
    final dL = List<String>.from(mFrag.split('\n'));

    if (hasO && hasM) {
      dL[h.modStart + hunkRow] = oL[h.origStart + hunkRow];
    } else if (hasO && !hasM) {
      final at = (h.modEnd + (hunkRow - mC)).clamp(0, dL.length);
      dL.insert(at, oL[h.origStart + hunkRow]);
    } else if (!hasO && hasM) {
      final ri = h.modStart + hunkRow;
      if (ri >= 0 && ri < dL.length) dL.removeAt(ri);
    }

    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _modifiedText = dL.join('\n');
    });
    _notifyEditorChanged();
  }

  void _applyLineToSource(int hunkIdx, int hunkRow) {
    final oFrag = _currentOriginal;
    final mFrag = _modifiedText;
    final hunks = computeHunks(oFrag, mFrag);
    if (hunkIdx >= hunks.length) return;
    final h = hunks[hunkIdx];
    final oC = h.origEnd - h.origStart;
    final mC = h.modEnd - h.modStart;
    final hasO = hunkRow < oC;
    final hasM = hunkRow < mC;
    final oL = List<String>.from(oFrag.split('\n'));
    final dL = mFrag.split('\n');

    if (hasO && hasM) {
      oL[h.origStart + hunkRow] = dL[h.modStart + hunkRow];
    } else if (hasO && !hasM) {
      final ri = h.origStart + hunkRow;
      if (ri >= 0 && ri < oL.length) oL.removeAt(ri);
    } else if (!hasO && hasM) {
      final at = (h.origEnd + (hunkRow - oC)).clamp(0, oL.length);
      oL.insert(at, dL[h.modStart + hunkRow]);
    }

    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _currentOriginal = oL.join('\n');
    });
  }

  // ── Undo ─────────────────────────────────────────────────────────────────

  void _undo() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    setState(() {
      _currentOriginal = prev.original;
      _modifiedText = prev.modified;
    });
    _notifyEditorChanged();
  }

  // ── Edición en línea ─────────────────────────────────────────────────────

  void _setEditSide(bool isSource) {
    setState(() {
      _editSide = isSource ? DiffEditSide.source : DiffEditSide.target;
    });
  }

  void _stopEditing() => setState(() => _editSide = DiffEditSide.none);

  void _editLine(bool isSource, int lineNumber, String value) {
    final lines = (isSource ? _currentOriginal : _modifiedText).split('\n');
    final lineIndex = lineNumber - 1;
    if (lineIndex < 0 ||
        lineIndex >= lines.length ||
        lines[lineIndex] == value) {
      return;
    }
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      lines[lineIndex] = value;
      if (isSource) {
        _currentOriginal = lines.join('\n');
      } else {
        _modifiedText = lines.join('\n');
      }
    });
    if (!isSource) {
      _notifyEditorChanged();
    }
  }

  bool get _targetModified => _modifiedText != _initialModified;

  void _syncToEditor() {
    widget.onApplyToEditor?.call(_modifiedText);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Código sincronizado con el editor'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _notifyEditorChanged() {
    widget.onApplyToEditor?.call(_modifiedText);
  }

  // ── Búsqueda ─────────────────────────────────────────────────────────────

  List<({bool isSource, int line})> get _searchMatches {
    final q = _searchQuery.trim().toUpperCase();
    if (q.isEmpty) return const [];
    final matches = <({bool isSource, int line})>[];
    for (final entry in _currentOriginal.split('\n').asMap().entries) {
      if (entry.value.toUpperCase().contains(q)) {
        matches.add((isSource: true, line: entry.key + 1));
      }
    }
    for (final entry in _modifiedText.split('\n').asMap().entries) {
      if (entry.value.toUpperCase().contains(q)) {
        matches.add((isSource: false, line: entry.key + 1));
      }
    }
    return matches;
  }

  void _setSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
      _searchIndex = 0;
    });
    if (value.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _searchQuery != value) return;
        final matches = _searchMatches;
        if (matches.isNotEmpty) {
          _diffCtrl.scrollToOrigLine(matches.first.line);
        }
      });
    }
  }

  void _moveSearch(int delta) {
    final matches = _searchMatches;
    if (matches.isEmpty) return;
    setState(() {
      _searchIndex = (_searchIndex + delta) % matches.length;
      if (_searchIndex < 0) _searchIndex += matches.length;
    });
    _diffCtrl.scrollToOrigLine(matches[_searchIndex].line);
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('$label copiado al portapapeles'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build Principal ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final gripColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.18,
    );

    final srcColor = Colors.blue.shade700;
    final tgtColor = Colors.teal.shade700;

    if (_maximized) {
      _winW = (size.width - 48).clamp(320.0, size.width);
      _winH = (size.height - 48).clamp(280.0, size.height);
    } else {
      _winW ??= (size.width * 0.85).clamp(_kMinW, 1400.0);
      _winH ??= (size.height * 0.85).clamp(420.0, 950.0);
    }
    if (_winW! > size.width) _winW = size.width;
    if (_winH! > size.height) _winH = size.height;

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
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
            _prevChange,
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
            _nextChange,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            _applyCurrentHunkToTarget,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            _applyCurrentHunkToSource,
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          alt: true,
          shift: true,
        ): _applyAllToTarget,
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          alt: true,
          shift: true,
        ): _applyAllToSource,
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
                                _buildToolbar(isDark, cs, srcColor, tgtColor),
                                Expanded(
                                  child: NativeDiffViewer(
                                    origText: _currentOriginal,
                                    modText: _modifiedText,
                                    sideBySide: _sideBySide,
                                    showAllLines: _showAllLines,
                                    controller: _diffCtrl,
                                    onApplyLineToTarget: _applyLineToTarget,
                                    onApplyLineToSource: _applyLineToSource,
                                    searchQuery: _searchQuery,
                                    editableSide: _editSide,
                                    onEditLine: _editLine,
                                  ),
                                ),
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

            // Resize handles
            if (!_maximized && !_minimized) ...[
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
          ],
        ),
      ),
    );
  }

  // ── Header (Arrastrable) ─────────────────────────────────────────────────

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            return ConstellationHeader(
              height: _kHeaderH,
              padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF161B22)
                    : const Color(0xFFF6F8FA),
                border: _minimized
                    ? null
                    : Border(bottom: BorderSide(color: divColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _minimized
                          ? _toggleMinimized
                          : _toggleMaximized,
                      child: Row(
                        children: [
                          if (!compact && !_minimized) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.indigo.shade400,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                'PROCEDURE DIFF',
                                style: TextStyle(
                                  color: Colors.indigo.shade400,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              widget.language.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_targetModified &&
                              widget.onApplyToEditor != null) ...[
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: _syncToEditor,
                              icon: const Icon(Icons.sync_rounded, size: 14),
                              label: const Text('Aplicar al editor'),
                            ),
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
                    tooltip: _maximized ? 'Restaurar tamaño' : 'Maximizar',
                    onTap: _toggleMaximized,
                  ),
                  WindowButton.titleBar(
                    icon: Icons.close_rounded,
                    tooltip: 'Cerrar',
                    onTap: _close,
                    isClose: true,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Toolbar con Controles de Edición ──────────────────────────────────────

  Widget _buildToolbar(
    bool isDark,
    ColorScheme cs,
    Color srcColor,
    Color tgtColor,
  ) {
    final divColor = cs.outlineVariant;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151A21) : const Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: divColor)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth - 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 8),

                // ── Lado izquierdo: GUARDADO ───────────────────────────────
                _roleBadge(
                  role: 'GUARDADO',
                  detail: widget.ambiente ?? 'BD',
                  color: srcColor,
                ),
                const SizedBox(width: 4),

                // ←← copia todo EDITOR → GUARDADO
                _tbBtn(
                  tooltip: 'Copiar TODO: EDITOR → GUARDADO  (Alt+Shift+←)',
                  icon: Icons.keyboard_double_arrow_left,
                  color: srcColor,
                  onTap: _applyAllToSource,
                ),

                // ← copia hunk actual EDITOR → GUARDADO
                _tbBtn(
                  tooltip: 'Aplicar cambio actual: EDITOR → GUARDADO  (Alt+←)',
                  icon: Icons.chevron_left,
                  color: srcColor,
                  size: 20,
                  onTap: _applyCurrentHunkToSource,
                ),

                // ── Navegación central ─────────────────────────────────────
                _vSep(divColor),
                _tbBtn(
                  tooltip: 'Cambio anterior  (Alt+↑)',
                  icon: Icons.keyboard_arrow_up,
                  onTap: _prevChange,
                ),

                // Contador de hunks
                ListenableBuilder(
                  listenable: _diffCtrl,
                  builder: (_, _) {
                    final tot = _diffCtrl.totalHunks;
                    final cur = _diffCtrl.currentHunk;
                    return Container(
                      constraints: const BoxConstraints(
                        minWidth: 52,
                        minHeight: 26,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.22),
                        ),
                      ),
                      child: tot == 0
                          ? Text(
                              '✓ Sin cambios',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade500,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : Text(
                              '${cur + 1} / $tot',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    );
                  },
                ),

                _tbBtn(
                  tooltip: 'Siguiente cambio  (Alt+↓)',
                  icon: Icons.keyboard_arrow_down,
                  onTap: _nextChange,
                ),
                _vSep(divColor),

                // → copia hunk actual GUARDADO → EDITOR
                _tbBtn(
                  tooltip: 'Aplicar cambio actual: GUARDADO → EDITOR  (Alt+→)',
                  icon: Icons.chevron_right,
                  color: tgtColor,
                  size: 20,
                  onTap: _applyCurrentHunkToTarget,
                ),

                // →→ copia todo GUARDADO → EDITOR
                _tbBtn(
                  tooltip: 'Copiar TODO: GUARDADO → EDITOR  (Alt+Shift+→)',
                  icon: Icons.keyboard_double_arrow_right,
                  color: tgtColor,
                  onTap: _applyAllToTarget,
                ),

                const SizedBox(width: 4),

                // ── Lado derecho: EDITOR ───────────────────────────────────
                _roleBadge(role: 'EDITOR', detail: 'ACTUAL', color: tgtColor),

                _vSep(divColor),
                _replaceMenu(cs),

                const SizedBox(width: 8),
                _vSep(divColor),
                _buildStatsWidget(),
                _vSep(divColor),

                // Solo diffs / Completo
                Tooltip(
                  message: _showAllLines
                      ? 'Mostrar solo diffs'
                      : 'Mostrar código completo',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: _toggleShowAllLines,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _showAllLines
                                ? Icons.article_outlined
                                : Icons.difference_outlined,
                            size: 14,
                            color: _showAllLines
                                ? Colors.amber.shade600
                                : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showAllLines ? 'Completo' : 'Solo diffs',
                            style: TextStyle(
                              fontSize: 11,
                              color: _showAllLines
                                  ? Colors.amber.shade600
                                  : cs.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _vSep(divColor),

                // Vista Dividida / Unificada
                Tooltip(
                  message: _sideBySide
                      ? 'Vista unificada'
                      : 'Vista lado a lado',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: _toggleSideBySide,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _sideBySide
                                ? Icons.view_agenda_outlined
                                : Icons.view_sidebar_outlined,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _sideBySide ? 'Dividida' : 'Unificada',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _vSep(divColor),

                // Búsqueda
                _buildSearchControl(cs),
                _vSep(divColor),

                // Editar Guardado / Editor
                _srcTgtMenu(
                  cs,
                  tooltip: 'Editar código (Guardado / Editor)',
                  icon: Icons.edit_outlined,
                  srcIcon: Icons.edit_note_outlined,
                  tgtIcon: Icons.edit_outlined,
                  srcLabel: 'Editar Guardado',
                  tgtLabel: 'Editar Editor',
                  onSelected: _setEditSide,
                ),
                if (_editSide != DiffEditSide.none) ...[
                  Text(
                    'Enter para confirmar',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Salir del modo edición',
                    child: IconButton(
                      onPressed: _stopEditing,
                      icon: const Icon(Icons.check, size: 15),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
                _vSep(divColor),

                // Undo
                Tooltip(
                  message: _history.isEmpty
                      ? 'Nada que deshacer'
                      : 'Deshacer  Ctrl+Z  (${_history.length} operaciones)',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: _history.isEmpty ? null : _undo,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.undo,
                            size: 14,
                            color: _history.isEmpty ? cs.outline : cs.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Deshacer',
                            style: TextStyle(
                              fontSize: 11,
                              color: _history.isEmpty ? cs.outline : cs.primary,
                            ),
                          ),
                          if (_history.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_history.length}',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                _vSep(divColor),

                // Copiar código
                Tooltip(
                  message: 'Copiar código (guardado / editor)',
                  child: PopupMenuButton<String>(
                    tooltip: '',
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: cs.onSurfaceVariant,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    onSelected: (v) => v == 'orig'
                        ? _copy(_currentOriginal, 'Código guardado')
                        : _copy(_modifiedText, 'Código del editor'),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'orig',
                        child: Text(
                          'Copiar versión guardada',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'mod',
                        child: Text(
                          'Copiar versión actual (editor)',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                if (widget.onApplyToEditor != null) ...[
                  _vSep(divColor),
                  Tooltip(
                    message:
                        'Sincronizar cambios aplicados al editor de código',
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      onPressed: _syncToEditor,
                      icon: const Icon(Icons.sync_alt, size: 14),
                      label: const Text(
                        'Aplicar al editor',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],

                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Sub-componentes ───────────────────────────────────────────────────────

  Widget _roleBadge({
    required String role,
    required String detail,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            role,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($detail)',
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _replaceMenu(ColorScheme cs) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        MenuItemButton(
          onPressed: () => _confirmReplace(towardsTarget: true),
          leadingIcon: const Icon(Icons.keyboard_double_arrow_right, size: 15),
          child: const Text('Completo: Guardado → Editor'),
        ),
        MenuItemButton(
          onPressed: () => _confirmReplace(towardsTarget: false),
          leadingIcon: const Icon(Icons.keyboard_double_arrow_left, size: 15),
          child: const Text('Completo: Editor → Guardado'),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Reemplazar contenido completo',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Icon(Icons.find_replace_rounded, size: 15, color: cs.error),
          ),
        ),
      ),
    );
  }

  Widget _srcTgtMenu(
    ColorScheme cs, {
    required String tooltip,
    required IconData icon,
    required IconData srcIcon,
    required IconData tgtIcon,
    required String srcLabel,
    required String tgtLabel,
    required void Function(bool isSource) onSelected,
  }) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        MenuItemButton(
          onPressed: () => onSelected(true),
          leadingIcon: Icon(srcIcon, size: 15, color: Colors.blue.shade700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                srcLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'GUARDADO',
                style: TextStyle(fontSize: 10, color: Colors.blue.shade700),
              ),
            ],
          ),
        ),
        MenuItemButton(
          onPressed: () => onSelected(false),
          leadingIcon: Icon(tgtIcon, size: 15, color: Colors.teal.shade700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tgtLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'EDITOR',
                style: TextStyle(fontSize: 10, color: Colors.teal.shade700),
              ),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  _editSide == DiffEditSide.none
                      ? 'Editar'
                      : _editSide == DiffEditSide.source
                      ? 'Editando Guardado'
                      : 'Editando Editor',
                  style: TextStyle(
                    fontSize: 11,
                    color: _editSide == DiffEditSide.none
                        ? cs.onSurfaceVariant
                        : _editSide == DiffEditSide.source
                        ? Colors.blue.shade700
                        : Colors.teal.shade700,
                    fontWeight: _editSide == DiffEditSide.none
                        ? FontWeight.normal
                        : FontWeight.w600,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchControl(ColorScheme cs) {
    final matches = _searchMatches;
    final count = matches.length;
    final position = count == 0 ? 0 : _searchIndex + 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 170,
          height: 30,
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocusNode,
            onChanged: _setSearchQuery,
            onEditingComplete: () {
              _moveSearch(1);
              _searchFocusNode.requestFocus();
            },
            style: const TextStyle(fontSize: 11),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar en comparar',
              hintStyle: const TextStyle(fontSize: 11),
              prefixIcon: const Icon(Icons.search, size: 15),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchCtrl.clear();
                        _setSearchQuery('');
                      },
                      icon: const Icon(Icons.close, size: 14),
                      visualDensity: VisualDensity.compact,
                    ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 7),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_searchQuery.trim().isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            '$position/$count',
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          IconButton(
            tooltip: 'Coincidencia anterior',
            onPressed: count == 0 ? null : () => _moveSearch(-1),
            icon: const Icon(Icons.keyboard_arrow_up, size: 16),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Siguiente coincidencia',
            onPressed: count == 0 ? null : () => _moveSearch(1),
            icon: const Icon(Icons.keyboard_arrow_down, size: 16),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }

  Widget _buildStatsWidget() {
    final s = _stats;
    if (s.added == 0 && s.removed == 0) {
      return Text(
        'sin cambios',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade600,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s.added > 0)
          Text(
            '+${s.added}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.green.shade500,
              fontWeight: FontWeight.w600,
              fontFamily: 'Consolas',
            ),
          ),
        if (s.removed > 0) ...[
          const SizedBox(width: 4),
          Text(
            '-${s.removed}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.red.shade400,
              fontWeight: FontWeight.w600,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ],
    );
  }

  Widget _vSep(Color c) => Container(
    width: 1,
    height: 18,
    color: c,
    margin: const EdgeInsets.symmetric(horizontal: 2),
  );

  Widget _tbBtn({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    double size = 16,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Icon(
            icon,
            size: size,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
