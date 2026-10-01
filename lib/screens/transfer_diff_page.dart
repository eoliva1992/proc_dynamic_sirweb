import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/procedimiento.dart';
import '../services/backup_service.dart';
import '../services/sirweb_service.dart';
import '../services/transfer_service.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/app_toast.dart';
import '../widgets/constellation_background.dart';
import '../widgets/floating_window.dart';
import '../widgets/native_diff_viewer.dart';

/// Abre una ventana flotante con el diff de transferencia entre dos ambientes.
///
/// Comparte los mismos controles de edición, navegación y visualización que
/// `ProcedureDiffWindow` y `SchemaObjectDiffPage`:
/// - Navegación entre hunks (`Alt+↑` / `Alt+↓`)
/// - Aplicar cambio actual: origen → destino (`Alt+→`) o destino → origen (`Alt+←`)
/// - Copiar TODO: origen → destino (`Alt+Shift+→`) o destino → origen (`Alt+Shift+←`)
/// - Aplicar líneas individuales mediante botones directos en el gutter
/// - Edición directa en línea (`editableSide` / `onEditLine`)
/// - Búsqueda de texto con conteo y navegación interactiva
/// - Deshacer (`Ctrl+Z`) con historial
/// - Acciones de transferencia: Backup destino, Guardar origen, Guardar destino y Transferir
/// - Ventana flotante arrastrable, redimensionable y minimizable.
VoidCallback showTransferDiff(
  BuildContext context, {
  required Procedimiento sourceProc,
  required String sourceCode,
  required String sourceAmbiente,
  required String targetAmbiente,
  required String cdUsuario,
  VoidCallback? onTransferred,
}) {
  return showFloatingWindow(
    context,
    (close) => TransferDiffWindow(
      sourceProc: sourceProc,
      sourceCode: sourceCode,
      sourceAmbiente: sourceAmbiente,
      targetAmbiente: targetAmbiente,
      cdUsuario: cdUsuario,
      onTransferred: onTransferred,
      onClose: close,
    ),
  );
}

class TransferDiffPage extends StatelessWidget {
  final Procedimiento sourceProc;
  final String sourceCode;
  final String sourceAmbiente;
  final String targetAmbiente;
  final String cdUsuario;

  const TransferDiffPage({
    super.key,
    required this.sourceProc,
    required this.sourceCode,
    required this.sourceAmbiente,
    required this.targetAmbiente,
    required this.cdUsuario,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TransferDiffWindow(
        sourceProc: sourceProc,
        sourceCode: sourceCode,
        sourceAmbiente: sourceAmbiente,
        targetAmbiente: targetAmbiente,
        cdUsuario: cdUsuario,
        onClose: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class TransferDiffWindow extends StatefulWidget {
  final Procedimiento sourceProc;
  final String sourceCode;
  final String sourceAmbiente;
  final String targetAmbiente;
  final String cdUsuario;
  final VoidCallback? onTransferred;
  final VoidCallback? onClose;

  const TransferDiffWindow({
    super.key,
    required this.sourceProc,
    required this.sourceCode,
    required this.sourceAmbiente,
    required this.targetAmbiente,
    required this.cdUsuario,
    this.onTransferred,
    this.onClose,
  });

  @override
  State<TransferDiffWindow> createState() => _TransferDiffWindowState();
}

class _TransferDiffWindowState extends State<TransferDiffWindow> {
  static const _kPrefSideBySide = 'diff_side_by_side';
  static const _kPrefShowAllLines = 'diff_show_all_lines';

  static const double _kMinW = 750;
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
  late String _currentOriginal; // ORIGEN
  late String _targetCode; // DESTINO
  bool _loadingTarget = true;
  bool _targetExists = false;
  bool _transferring = false;
  bool _savingSource = false;
  bool _savingTarget = false;

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

  String get _language =>
      widget.sourceProc.inConfiguracion == 'J' ? 'javascript' : 'sql';

  /// Conteo de líneas agregadas/eliminadas.
  ({int added, int removed}) get _stats {
    if (_currentOriginal == _targetCode) return (added: 0, removed: 0);
    var added = 0, removed = 0;
    for (final h in computeHunks(_currentOriginal, _targetCode)) {
      removed += h.origEnd - h.origStart;
      added += h.modEnd - h.modStart;
    }
    return (added: added, removed: removed);
  }

  @override
  void initState() {
    super.initState();
    _currentOriginal = _normalize(widget.sourceCode);
    _targetCode = '';
    _loadPrefs();
    unawaited(_loadTarget());
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

  // ── Carga y persistencia ──────────────────────────────────────────────────

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

  Future<void> _loadTarget() async {
    try {
      final proc = await SirwebService().obtenerProcedimiento(
        widget.sourceProc.cdProcedimiento,
        ambiente: widget.targetAmbiente,
      );
      if (mounted) {
        setState(() {
          _targetCode = _normalize(proc.deTexto);
          _targetExists = true;
          _loadingTarget = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _targetCode = '';
          _targetExists = false;
          _loadingTarget = false;
        });
      }
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

  // ── Acciones de Edición / Hunks ───────────────────────────────────────────

  void _applyHunkToTarget(int idx) {
    final oFrag = _currentOriginal;
    final mFrag = _targetCode;
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
      _history.add((original: _currentOriginal, modified: _targetCode));
      _targetCode = newFrag;
    });
  }

  void _applyHunkToSource(int idx) {
    final oFrag = _currentOriginal;
    final mFrag = _targetCode;
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
      _history.add((original: _currentOriginal, modified: _targetCode));
      _currentOriginal = newFrag;
    });
  }

  void _applyCurrentHunkToTarget() => _applyHunkToTarget(_diffCtrl.currentHunk);
  void _applyCurrentHunkToSource() => _applyHunkToSource(_diffCtrl.currentHunk);

  void _applyAllToTarget() {
    setState(() {
      _history.add((original: _currentOriginal, modified: _targetCode));
      _targetCode = _currentOriginal;
    });
  }

  void _applyAllToSource() {
    setState(() {
      _history.add((original: _currentOriginal, modified: _targetCode));
      _currentOriginal = _targetCode;
    });
  }

  Future<void> _confirmReplace({required bool towardsTarget}) async {
    final direction = towardsTarget ? 'ORIGEN → DESTINO' : 'DESTINO → ORIGEN';
    final destination = towardsTarget
        ? 'el DESTINO (${widget.targetAmbiente})'
        : 'el ORIGEN (${widget.sourceAmbiente})';
    final source = towardsTarget
        ? 'el ORIGEN (${widget.sourceAmbiente})'
        : 'el DESTINO (${widget.targetAmbiente})';

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
    final mFrag = _targetCode;
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
      _history.add((original: _currentOriginal, modified: _targetCode));
      _targetCode = dL.join('\n');
    });
  }

  void _applyLineToSource(int hunkIdx, int hunkRow) {
    final oFrag = _currentOriginal;
    final mFrag = _targetCode;
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
      _history.add((original: _currentOriginal, modified: _targetCode));
      _currentOriginal = oL.join('\n');
    });
  }

  // ── Undo ─────────────────────────────────────────────────────────────────

  void _undo() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    setState(() {
      _currentOriginal = prev.original;
      _targetCode = prev.modified;
    });
  }

  // ── Edición en línea ─────────────────────────────────────────────────────

  void _setEditSide(bool isSource) {
    setState(() {
      _editSide = isSource ? DiffEditSide.source : DiffEditSide.target;
    });
  }

  void _stopEditing() => setState(() => _editSide = DiffEditSide.none);

  void _editLine(bool isSource, int lineNumber, String value) {
    final lines = (isSource ? _currentOriginal : _targetCode).split('\n');
    final lineIndex = lineNumber - 1;
    if (lineIndex < 0 ||
        lineIndex >= lines.length ||
        lines[lineIndex] == value) {
      return;
    }
    setState(() {
      _history.add((original: _currentOriginal, modified: _targetCode));
      lines[lineIndex] = value;
      if (isSource) {
        _currentOriginal = lines.join('\n');
      } else {
        _targetCode = lines.join('\n');
      }
    });
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
    for (final entry in _targetCode.split('\n').asMap().entries) {
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
          _jumpToMatch(matches[0]);
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
    _jumpToMatch(matches[_searchIndex]);
  }

  void _jumpToMatch(({bool isSource, int line}) match) {
    _diffCtrl.scrollToOrigLine(match.line);
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('$label copiado al portapapeles'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Operaciones de Transferencia / Backup ─────────────────────────────────

  Future<void> _backup() async {
    if (!_targetExists) {
      AppToast.info(
        'El procedimiento no existe en ${widget.targetAmbiente} — no hay nada que respaldar',
      );
      return;
    }
    final backupProc = widget.sourceProc.copyWith(deTexto: _targetCode);
    final savedPath = await BackupService.exportar(
      backupProc,
      widget.targetAmbiente,
      widget.cdUsuario,
    );
    if (savedPath != null && mounted) {
      AppToast.successWithAction(
        'Backup guardado correctamente',
        detail: savedPath,
        actionLabel: 'Abrir ubicación',
        onAction: () => BackupService.revealInExplorer(savedPath),
      );
    }
  }

  Future<void> _saveToSource() async {
    setState(() => _savingSource = true);
    final result = await TransferService.transfer(
      cdProcedimiento: widget.sourceProc.cdProcedimiento,
      sourceCode: _currentOriginal,
      inConfiguracion: widget.sourceProc.inConfiguracion,
      cdUsuario: widget.cdUsuario,
      targetAmbiente: widget.sourceAmbiente,
    );
    if (!mounted) return;
    setState(() => _savingSource = false);
    if (result.success) {
      AppToast.success(result.message);
    } else {
      AppToast.error(result.message);
    }
  }

  Future<void> _saveToTarget() async {
    setState(() => _savingTarget = true);
    final result = await TransferService.transfer(
      cdProcedimiento: widget.sourceProc.cdProcedimiento,
      sourceCode: _targetCode,
      inConfiguracion: widget.sourceProc.inConfiguracion,
      cdUsuario: widget.cdUsuario,
      targetAmbiente: widget.targetAmbiente,
    );
    if (!mounted) return;
    setState(() => _savingTarget = false);
    if (result.success) {
      _targetExists = true;
      AppToast.success(result.message);
    } else {
      AppToast.error(result.message);
    }
  }

  Future<void> _confirmAndTransfer() async {
    final tgtColor = AmbienteSelector.colorForAmbiente(widget.targetAmbiente);
    final confirmed = await showFloatingDialog<bool>(
      context,
      (dialogContext, close) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        title: ConstellationDialogTitle(
          lineColor: tgtColor.withValues(alpha: 0.35),
          child: Row(
            children: [
              Icon(Icons.send_rounded, size: 18, color: tgtColor),
              const SizedBox(width: 8),
              const Text('Confirmar transferencia'),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_targetExists ? 'Se actualizará' : 'Se creará'} '
              '${widget.sourceProc.cdProcedimiento} en ${widget.targetAmbiente}.',
            ),
            if (_targetExists) ...[
              const SizedBox(height: 6),
              Text(
                'El código actual en ${widget.targetAmbiente} será reemplazado.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: tgtColor),
            onPressed: () => close(true),
            child: Text('Transferir a ${widget.targetAmbiente}'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _transferring = true);
    final result = await TransferService.transfer(
      cdProcedimiento: widget.sourceProc.cdProcedimiento,
      sourceCode: _targetCode,
      inConfiguracion: widget.sourceProc.inConfiguracion,
      cdUsuario: widget.cdUsuario,
      targetAmbiente: widget.targetAmbiente,
    );
    if (!mounted) return;
    setState(() => _transferring = false);

    if (result.success) {
      _targetExists = true;
      AppToast.success(result.message);
      widget.onTransferred?.call();
      _close();
    } else {
      AppToast.error(result.message);
    }
  }

  // ── Layout y Render ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);

    final srcColor = AmbienteSelector.colorForAmbiente(widget.sourceAmbiente);
    final tgtColor = AmbienteSelector.colorForAmbiente(widget.targetAmbiente);

    if (_maximized) {
      _winW = (size.width - 48).clamp(320.0, size.width);
      _winH = (size.height - 48).clamp(280.0, size.height);
    } else {
      _winW ??= (size.width * 0.88).clamp(_kMinW, 1400.0);
      _winH ??= (size.height * 0.88).clamp(420.0, 950.0);
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
      },
      child: Stack(
        children: [
          // Barrier para click-outside cuando no está maximizado ni minimizado
          if (!_maximized && !_minimized)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  // No cierra abruptamente para evitar perder ediciones en transferencia
                },
              ),
            ),

          AnimatedPositioned(
            duration: _anim,
            curve: Curves.easeOutCubic,
            left: left,
            top: top,
            width: w,
            height: h,
            onEnd: () => setState(() => _anim = Duration.zero),
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E222B)
                      : const Color(0xFFFAFBFC),
                  borderRadius: _maximized
                      ? BorderRadius.zero
                      : BorderRadius.circular(10),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(
                      alpha: isDark ? 0.4 : 0.8,
                    ),
                    width: 1,
                  ),
                  boxShadow: _minimized
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.45 : 0.22,
                            ),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
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
                                child: _loadingTarget
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: tgtColor,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'Cargando versión de ${widget.targetAmbiente}…',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : NativeDiffViewer(
                                        origText: _currentOriginal,
                                        modText: _targetCode,
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
                          child: _buildHeader(isDark, cs, srcColor, tgtColor),
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
                    _winW = (_winW! + d.delta.dx).clamp(_kMinW, size.width);
                  }),
                ),
              ),
            ),
            Positioned(
              left: left + 10,
              top: top + h - 5,
              width: (w - 20).clamp(0.0, double.infinity),
              height: 10,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) => setState(() {
                    _anim = Duration.zero;
                    _winH = (_winH! + d.delta.dy).clamp(320.0, size.height);
                  }),
                ),
              ),
            ),
            Positioned(
              left: left + w - 16,
              top: top + h - 16,
              width: 16,
              height: 16,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) => setState(() {
                    _anim = Duration.zero;
                    _winW = (_winW! + d.delta.dx).clamp(_kMinW, size.width);
                    _winH = (_winH! + d.delta.dy).clamp(320.0, size.height);
                  }),
                  child: CustomPaint(
                    painter: WindowGripPainter(
                      cs.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Encabezado / Título de Ventana Flotante ────────────────────────────────

  Widget _buildHeader(
    bool isDark,
    ColorScheme cs,
    Color srcColor,
    Color tgtColor,
  ) {
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
            final compact = constraints.maxWidth < 620;
            return ConstellationHeader(
              height: _kHeaderH,
              lineColor: isDark
                  ? Colors.orange.withValues(alpha: 0.25)
                  : Colors.orange.withValues(alpha: 0.15),
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
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.orange.shade700,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                'TRANSFERENCIA',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
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
                              widget.sourceProc.cdProcedimiento,
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
                              _language.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _badge(widget.sourceAmbiente, srcColor, 'ORIGEN'),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.arrow_forward_rounded, size: 13),
                          ),
                          _badge(widget.targetAmbiente, tgtColor, 'DESTINO'),
                        ],
                      ),
                    ),
                  ),

                  // Botón de acción rápida: Transferir a destino
                  if (!_minimized) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: tgtColor,
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
                      onPressed: (_loadingTarget || _transferring)
                          ? null
                          : _confirmAndTransfer,
                      icon: _transferring
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 13),
                      label: Text('Transferir a ${widget.targetAmbiente}'),
                    ),
                    const SizedBox(width: 6),
                  ],

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

                // ── Lado izquierdo: ORIGEN ─────────────────────────────────
                _roleBadge(
                  role: 'ORIGEN',
                  detail: widget.sourceAmbiente,
                  color: srcColor,
                ),
                const SizedBox(width: 4),

                // ←← copia todo DESTINO → ORIGEN
                _tbBtn(
                  tooltip: 'Copiar TODO: DESTINO → ORIGEN  (Alt+Shift+←)',
                  icon: Icons.keyboard_double_arrow_left,
                  color: srcColor,
                  onTap: _applyAllToSource,
                ),

                // ← copia hunk actual DESTINO → ORIGEN
                _tbBtn(
                  tooltip: 'Aplicar cambio actual: DESTINO → ORIGEN  (Alt+←)',
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

                // → copia hunk actual ORIGEN → DESTINO
                _tbBtn(
                  tooltip: 'Aplicar cambio actual: ORIGEN → DESTINO  (Alt+→)',
                  icon: Icons.chevron_right,
                  color: tgtColor,
                  size: 20,
                  onTap: _applyCurrentHunkToTarget,
                ),

                // →→ copia todo ORIGEN → DESTINO
                _tbBtn(
                  tooltip: 'Copiar TODO: ORIGEN → DESTINO  (Alt+Shift+→)',
                  icon: Icons.keyboard_double_arrow_right,
                  color: tgtColor,
                  onTap: _applyAllToTarget,
                ),

                const SizedBox(width: 4),

                // ── Lado derecho: DESTINO ──────────────────────────────────
                _roleBadge(
                  role: 'DESTINO',
                  detail: widget.targetAmbiente,
                  color: tgtColor,
                ),

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

                // Editar Origen / Destino
                _srcTgtMenu(
                  cs,
                  tooltip: 'Editar código (Origen / Destino)',
                  icon: Icons.edit_outlined,
                  srcIcon: Icons.edit_note_outlined,
                  tgtIcon: Icons.edit_outlined,
                  srcLabel: 'Editar Origen',
                  tgtLabel: 'Editar Destino',
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
                  message: 'Copiar código (origen / destino)',
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
                        ? _copy(_currentOriginal, 'Código de origen')
                        : _copy(_targetCode, 'Código de destino'),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'orig',
                        child: Text(
                          'Copiar origen (${widget.sourceAmbiente})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'mod',
                        child: Text(
                          'Copiar destino (${widget.targetAmbiente})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                // Acciones de transferencia extras
                _vSep(divColor),
                Tooltip(
                  message:
                      'Guardar copia de seguridad del código actual en destino',
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    onPressed: _loadingTarget ? null : _backup,
                    icon: const Icon(Icons.save_alt, size: 14),
                    label: const Text(
                      'Backup destino',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),

                Tooltip(
                  message: 'Guardar cambios directamente en el ambiente origen',
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    onPressed: (_loadingTarget || _savingSource)
                        ? null
                        : _saveToSource,
                    icon: _savingSource
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : const Icon(Icons.save_outlined, size: 14),
                    label: Text(
                      'Guardar en ${widget.sourceAmbiente}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),

                Tooltip(
                  message:
                      'Guardar cambios directamente en el ambiente destino',
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      foregroundColor: tgtColor,
                    ),
                    onPressed: (_loadingTarget || _savingTarget)
                        ? null
                        : _saveToTarget,
                    icon: _savingTarget
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: tgtColor,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 14),
                    label: Text(
                      'Guardar en ${widget.targetAmbiente}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),

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
          child: const Text('Completo: Origen → Destino'),
        ),
        MenuItemButton(
          onPressed: () => _confirmReplace(towardsTarget: false),
          leadingIcon: const Icon(Icons.keyboard_double_arrow_left, size: 15),
          child: const Text('Completo: Destino → Origen'),
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
                'ORIGEN (${widget.sourceAmbiente})',
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
                'DESTINO (${widget.targetAmbiente})',
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
                Icon(
                  icon,
                  size: 14,
                  color: _editSide == DiffEditSide.none
                      ? cs.onSurfaceVariant
                      : _editSide == DiffEditSide.source
                      ? Colors.blue.shade700
                      : Colors.teal.shade700,
                ),
                const SizedBox(width: 4),
                Text(
                  _editSide == DiffEditSide.none
                      ? 'Editar'
                      : _editSide == DiffEditSide.source
                      ? 'Editando Origen'
                      : 'Editando Destino',
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
              hintText: 'Buscar en diff…',
              hintStyle: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              prefixIcon: const Icon(Icons.search, size: 14),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 26,
                minHeight: 26,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 12),
                      splashRadius: 10,
                      onPressed: () => _setSearchQuery(''),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 20,
                minHeight: 20,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          constraints: const BoxConstraints(minWidth: 44),
          alignment: Alignment.center,
          child: Text(
            count == 0 ? '0/0' : '$position/$count',
            style: TextStyle(
              fontSize: 10,
              color: count == 0 ? cs.outline : cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _tbBtn(
          tooltip: 'Coincidencia anterior  (Shift+Enter)',
          icon: Icons.keyboard_arrow_up,
          size: 16,
          onTap: count == 0 ? null : () => _moveSearch(-1),
        ),
        _tbBtn(
          tooltip: 'Siguiente coincidencia  (Enter)',
          icon: Icons.keyboard_arrow_down,
          size: 16,
          onTap: count == 0 ? null : () => _moveSearch(1),
        ),
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
          color: Colors.green.shade600,
          fontWeight: FontWeight.w500,
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
              color: Colors.green.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (s.added > 0 && s.removed > 0) const SizedBox(width: 4),
        if (s.removed > 0)
          Text(
            '-${s.removed}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.red.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _tbBtn({
    required String tooltip,
    required IconData icon,
    VoidCallback? onTap,
    Color? color,
    double size = 18,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color, String role) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
    ),
    child: Text(
      '$role: $label',
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
    ),
  );

  Widget _vSep(Color color) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    width: 1,
    height: 18,
    color: color,
  );
}
