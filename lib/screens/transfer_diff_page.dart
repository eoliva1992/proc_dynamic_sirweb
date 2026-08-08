import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import '../models/procedimiento.dart';
import '../services/backup_service.dart';
import '../services/sirweb_service.dart';
import '../services/transfer_service.dart';
import '../widgets/_editor_themes.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/app_toast.dart';

typedef _Hunk = ({int origStart, int origEnd, int modStart, int modEnd});

// LCS-based line diff; returns contiguous change blocks between orig and mod
List<_Hunk> _computeHunks(String orig, String mod) {
  final a = orig.split('\n');
  final b = mod.split('\n');
  final n = a.length;
  final m = b.length;
  final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final matches = <(int, int)>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      matches.add((i, j));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  final hunks = <_Hunk>[];
  var po = -1, pm = -1;
  for (final (mi, mj) in [...matches, (n, m)]) {
    if (mi > po + 1 || mj > pm + 1) {
      hunks.add((origStart: po + 1, origEnd: mi, modStart: pm + 1, modEnd: mj));
    }
    po = mi;
    pm = mj;
  }
  return hunks;
}

class TransferDiffPage extends StatefulWidget {
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
  State<TransferDiffPage> createState() => _TransferDiffPageState();
}

class _TransferDiffPageState extends State<TransferDiffPage> {
  bool _loadingTarget = true;
  String _targetCode = '';
  bool _targetExists = false;
  bool _transferring = false;
  bool _savingSource = false;
  bool _savingTarget = false;
  bool _sideBySide = true;
  MonacoDiffController? _ctrl;

  // Tracks the current ORIGEN (left) text after programmatic changes
  late String _currentOriginal;
  final _history = <({String original, String modified})>[];

  @override
  void initState() {
    super.initState();
    _currentOriginal = widget.sourceCode;
    unawaited(_loadTarget());
  }

  Future<void> _loadTarget() async {
    try {
      final proc = await SirwebService().obtenerProcedimiento(
        widget.sourceProc.cdProcedimiento,
        ambiente: widget.targetAmbiente,
      );
      if (mounted) {
        setState(() {
          _targetCode = proc.deTexto;
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

  Future<void> _backup() async {
    if (!_targetExists) {
      AppToast.info(
        'El procedimiento no existe en ${widget.targetAmbiente} — no hay nada que respaldar',
      );
      return;
    }
    final backupProc = widget.sourceProc.copyWith(deTexto: _targetCode);
    final saved = await BackupService.exportar(
      backupProc,
      widget.targetAmbiente,
      widget.cdUsuario,
    );
    if (saved && mounted) AppToast.success('Backup guardado correctamente');
  }

  Future<void> _saveToSource() async {
    setState(() => _savingSource = true);
    final result = await TransferService.transfer(
      cdProcedimiento: widget.sourceProc.cdProcedimiento,
      sourceCode: widget.sourceCode,
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

  // Apply the first remaining hunk from ORIGEN to DESTINO
  Future<void> _applyOneToTarget() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final destino = await ctrl.getModifiedText();
    final hunks = _computeHunks(_currentOriginal, destino);
    if (hunks.isEmpty) return;
    final h = hunks.first;
    final oLines = _currentOriginal.split('\n');
    final dLines = destino.split('\n');
    final newDest = [
      ...dLines.sublist(0, h.modStart),
      ...oLines.sublist(h.origStart, h.origEnd),
      ...dLines.sublist(h.modEnd),
    ].join('\n');
    setState(
      () => _history.add((original: _currentOriginal, modified: destino)),
    );
    await ctrl.setTexts(original: _currentOriginal, modified: newDest);
  }

  // Apply the first remaining hunk from DESTINO to ORIGEN
  Future<void> _applyOneToSource() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final destino = await ctrl.getModifiedText();
    final hunks = _computeHunks(_currentOriginal, destino);
    if (hunks.isEmpty) return;
    final h = hunks.first;
    final oLines = _currentOriginal.split('\n');
    final dLines = destino.split('\n');
    final newOrig = [
      ...oLines.sublist(0, h.origStart),
      ...dLines.sublist(h.modStart, h.modEnd),
      ...oLines.sublist(h.origEnd),
    ].join('\n');
    setState(() {
      _history.add((original: _currentOriginal, modified: destino));
      _currentOriginal = newOrig;
    });
    await ctrl.setTexts(original: newOrig, modified: destino);
  }

  // Overwrites DESTINO (right) with current ORIGEN (left) content
  Future<void> _applyAllToTarget() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final currentModified = await ctrl.getModifiedText();
    setState(
      () =>
          _history.add((original: _currentOriginal, modified: currentModified)),
    );
    await ctrl.setTexts(original: _currentOriginal, modified: _currentOriginal);
  }

  // Overwrites ORIGEN (left) with current DESTINO (right) content
  Future<void> _applyAllToSource() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final code = await ctrl.getModifiedText();
    setState(() {
      _history.add((original: _currentOriginal, modified: code));
      _currentOriginal = code;
    });
    await ctrl.setTexts(original: code, modified: code);
  }

  Future<void> _undo() async {
    if (_history.isEmpty) return;
    final prev = _history.last;
    setState(() {
      _history.removeLast();
      _currentOriginal = prev.original;
    });
    await _ctrl?.setTexts(original: prev.original, modified: prev.modified);
  }

  Future<void> _saveToTarget() async {
    String codeToSave = _targetCode;
    if (_ctrl != null) {
      try {
        codeToSave = await _ctrl!.getModifiedText();
      } catch (_) {
        codeToSave = _targetCode;
      }
    }
    setState(() => _savingTarget = true);
    final result = await TransferService.transfer(
      cdProcedimiento: widget.sourceProc.cdProcedimiento,
      sourceCode: codeToSave,
      inConfiguracion: widget.sourceProc.inConfiguracion,
      cdUsuario: widget.cdUsuario,
      targetAmbiente: widget.targetAmbiente,
    );
    if (!mounted) return;
    setState(() => _savingTarget = false);
    if (result.success) {
      AppToast.success(result.message);
    } else {
      AppToast.error(result.message);
    }
  }

  Future<void> _confirmAndTransfer() async {
    // Read current content from the editable modified pane (DESTINO right side after cherry-picking)
    String codeToTransfer = _targetCode;
    if (_ctrl != null) {
      try {
        codeToTransfer = await _ctrl!.getModifiedText();
      } catch (_) {
        codeToTransfer = _targetCode;
      }
    }

    if (!mounted) return;

    final tgtColor = AmbienteSelector.colorForAmbiente(widget.targetAmbiente);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.send_rounded, size: 18, color: tgtColor),
            const SizedBox(width: 8),
            const Text('Confirmar transferencia'),
          ],
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
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: tgtColor),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Transferir a ${widget.targetAmbiente}'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _transferring = true);
    final result = await TransferService.transfer(
      cdProcedimiento: widget.sourceProc.cdProcedimiento,
      sourceCode: codeToTransfer,
      inConfiguracion: widget.sourceProc.inConfiguracion,
      cdUsuario: widget.cdUsuario,
      targetAmbiente: widget.targetAmbiente,
    );
    if (!mounted) return;
    setState(() => _transferring = false);

    if (result.success) {
      AppToast.success(result.message);
      Navigator.of(context).pop();
    } else {
      AppToast.error(result.message);
    }
  }

  Future<void> _toggleLayout() async {
    final next = !_sideBySide;
    setState(() => _sideBySide = next);
    await _ctrl?.updateDiffOptions(MonacoDiffOptions(renderSideBySide: next));
  }

  String get _language =>
      widget.sourceProc.inConfiguracion == 'J' ? 'javascript' : 'sql';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final srcColor = AmbienteSelector.colorForAmbiente(widget.sourceAmbiente);
    final tgtColor = AmbienteSelector.colorForAmbiente(widget.targetAmbiente);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.shade700, width: 0.8),
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
            Text(
              widget.sourceProc.cdProcedimiento,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            _badge(widget.sourceAmbiente, srcColor, 'ORIGEN'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.compare_arrows, size: 14),
            ),
            _badge(widget.targetAmbiente, tgtColor, 'DESTINO'),
          ],
        ),
        actions: [
          // Navigate between changes
          Tooltip(
            message: 'Cambio anterior',
            child: IconButton(
              icon: const Icon(Icons.arrow_upward, size: 16),
              onPressed: _loadingTarget
                  ? null
                  : () => _ctrl?.revealPreviousChange(),
            ),
          ),
          Tooltip(
            message: 'Siguiente cambio',
            child: IconButton(
              icon: const Icon(Icons.arrow_downward, size: 16),
              onPressed: _loadingTarget
                  ? null
                  : () => _ctrl?.revealNextChange(),
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: _loadingTarget ? null : _backup,
            icon: const Icon(Icons.save_alt, size: 14),
            label: const Text('Backup destino', style: TextStyle(fontSize: 12)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
              ),
              onPressed: (_loadingTarget || _savingSource)
                  ? null
                  : _saveToSource,
              icon: _savingSource
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : const Icon(Icons.save_outlined, size: 14),
              label: Text(
                'Guardar en ${widget.sourceAmbiente}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                foregroundColor: tgtColor,
              ),
              onPressed: (_loadingTarget || _savingTarget)
                  ? null
                  : _saveToTarget,
              icon: _savingTarget
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: tgtColor,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 14),
              label: Text(
                'Guardar en ${widget.targetAmbiente}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
            icon: Icon(
              _sideBySide
                  ? Icons.view_agenda_outlined
                  : Icons.view_sidebar_outlined,
              size: 14,
            ),
            label: Text(
              _sideBySide ? 'Vista dividida' : 'Vista lineal',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: _loadingTarget ? null : _toggleLayout,
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: tgtColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
              ),
              onPressed: (_loadingTarget || _transferring)
                  ? null
                  : _confirmAndTransfer,
              icon: _transferring
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 14),
              label: Text(
                'Transferir a ${widget.targetAmbiente}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: _loadingTarget
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0078D4)),
            )
          : _buildDiff(isDark, cs, srcColor, tgtColor),
    );
  }

  Widget _buildDiff(
    bool isDark,
    ColorScheme cs,
    Color srcColor,
    Color tgtColor,
  ) {
    return Column(
      children: [
        // Column headers — make it unambiguous which side is which
        Container(
          color: isDark ? cs.surfaceContainerHighest : cs.surfaceContainerLow,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: srcColor, width: 3),
                      right: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: srcColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: srcColor, width: 0.8),
                        ),
                        child: Text(
                          'ORIGEN — ${widget.sourceAmbiente}',
                          style: TextStyle(
                            color: srcColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Código fuente (editable)',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Navigation + per-hunk + all + undo
              Container(
                width: 140,
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    vertical: BorderSide(color: cs.outlineVariant),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Tooltip(
                          message: 'Cambio anterior',
                          child: IconButton(
                            icon: Icon(
                              Icons.arrow_upward,
                              size: 12,
                              color: cs.onSurfaceVariant,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 24,
                            ),
                            onPressed: _loadingTarget
                                ? null
                                : () => _ctrl?.revealPreviousChange(),
                          ),
                        ),
                        Tooltip(
                          message: 'Aplicar 1 cambio: DESTINO → ORIGEN',
                          child: IconButton(
                            icon: Icon(
                              Icons.chevron_left,
                              size: 18,
                              color: srcColor,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 24,
                            ),
                            onPressed: _loadingTarget
                                ? null
                                : _applyOneToSource,
                          ),
                        ),
                        Tooltip(
                          message: 'Copiar TODO: DESTINO → ORIGEN',
                          child: IconButton(
                            icon: Icon(
                              Icons.keyboard_double_arrow_left,
                              size: 14,
                              color: srcColor,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 24,
                            ),
                            onPressed: _loadingTarget
                                ? null
                                : _applyAllToSource,
                          ),
                        ),
                        Tooltip(
                          message: 'Deshacer última copia',
                          child: IconButton(
                            icon: Icon(
                              Icons.undo,
                              size: 12,
                              color: _history.isEmpty
                                  ? cs.onSurfaceVariant.withValues(alpha: 0.3)
                                  : cs.onSurfaceVariant,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 24,
                            ),
                            onPressed: (_loadingTarget || _history.isEmpty)
                                ? null
                                : _undo,
                          ),
                        ),
                        Tooltip(
                          message: 'Copiar TODO: ORIGEN → DESTINO',
                          child: IconButton(
                            icon: Icon(
                              Icons.keyboard_double_arrow_right,
                              size: 14,
                              color: tgtColor,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 24,
                            ),
                            onPressed: _loadingTarget
                                ? null
                                : _applyAllToTarget,
                          ),
                        ),
                        Tooltip(
                          message: 'Aplicar 1 cambio: ORIGEN → DESTINO',
                          child: IconButton(
                            icon: Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: tgtColor,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 24,
                            ),
                            onPressed: _loadingTarget
                                ? null
                                : _applyOneToTarget,
                          ),
                        ),
                        Tooltip(
                          message: 'Siguiente cambio',
                          child: IconButton(
                            icon: Icon(
                              Icons.arrow_downward,
                              size: 12,
                              color: cs.onSurfaceVariant,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 24,
                            ),
                            onPressed: _loadingTarget
                                ? null
                                : () => _ctrl?.revealNextChange(),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '< > = 1 cambio  ·  << >> = todos',
                      style: TextStyle(
                        fontSize: 8,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: tgtColor, width: 3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tgtColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: tgtColor, width: 0.8),
                        ),
                        child: Text(
                          'DESTINO — ${widget.targetAmbiente}',
                          style: TextStyle(
                            color: tgtColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _targetExists
                            ? 'Estado actual (editable)'
                            : 'No existe — se creará',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: MonacoDiffEditor(
            // original = left = ORIGEN code
            original: widget.sourceCode,
            // modified = right = DESTINO current code (editable, cherry-pick target)
            modified: _targetCode,
            language: MonacoLanguage(_language),
            diffOptions: MonacoDiffOptions(
              renderSideBySide: _sideBySide,
              ignoreTrimWhitespace: false,
              originalEditable: true,
              renderMarginRevertIcon: true,
            ),
            options: EditorOptions(
              theme: editorThemeStore.monacoTheme,
              fontSize: 13,
              minimap: const MonacoMinimapOptions(enabled: false),
              lineNumbers: MonacoLineNumbers.on,
              wordWrap: MonacoWordWrap.off,
              readOnly: false,
            ),
            onReady: (ctrl) => _ctrl = ctrl,
          ),
        ),
      ],
    );
  }

  Widget _badge(String label, Color color, String role) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 0.8),
        ),
        child: Text(
          '$role: $label',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ],
  );
}
