import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import '../models/procedimiento.dart';
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

/// Full-screen page for comparing a procedure's code across two environments.
class EnvDiffPage extends StatefulWidget {
  final Procedimiento sourceProc;
  final String sourceAmbiente;
  final String cdUsuario;
  final String? currentSourceCode;

  const EnvDiffPage({
    super.key,
    required this.sourceProc,
    required this.sourceAmbiente,
    required this.cdUsuario,
    this.currentSourceCode,
  });

  @override
  State<EnvDiffPage> createState() => _EnvDiffPageState();
}

class _EnvDiffPageState extends State<EnvDiffPage> {
  late String _targetAmbiente;
  bool _loading = false;
  String? _error;
  String? _targetCode;

  @override
  void initState() {
    super.initState();
    // Default target: first ambiente that is not the source
    _targetAmbiente = AmbienteSelector.ambientes.firstWhere(
      (a) => a != widget.sourceAmbiente,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _targetCode = null;
    });
    try {
      final proc = await SirwebService().obtenerProcedimiento(
        widget.sourceProc.cdProcedimiento,
        ambiente: _targetAmbiente,
      );
      setState(() {
        _targetCode = proc.deTexto;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$_targetAmbiente: procedimiento no encontrado';
        _loading = false;
      });
    }
  }

  String get _language =>
      widget.sourceProc.inConfiguracion == 'J' ? 'javascript' : 'sql';

  String get _sourceCode =>
      widget.currentSourceCode ?? widget.sourceProc.deTexto;

  Future<void> _saveToAmbiente(String ambiente, String code) async {
    final result = await TransferService.transfer(
      cdProcedimiento: widget.sourceProc.cdProcedimiento,
      sourceCode: code,
      inConfiguracion: widget.sourceProc.inConfiguracion,
      cdUsuario: widget.cdUsuario,
      targetAmbiente: ambiente,
    );
    if (!mounted) return;
    if (result.success) {
      AppToast.success(result.message);
    } else {
      AppToast.error(result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.shade400, width: 0.8),
              ),
              child: Text(
                'COMPARACIÓN',
                style: TextStyle(
                  color: Colors.blue.shade400,
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
            _ambienteBadge(widget.sourceAmbiente),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.compare_arrows, size: 16),
            ),
            _ambienteBadge(_targetAmbiente),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                const Text('Comparar con:', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _targetAmbiente,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: cs.surfaceContainerHigh,
                  items: AmbienteSelector.ambientes
                      .where((a) => a != widget.sourceAmbiente)
                      .map(
                        (a) => DropdownMenuItem(
                          value: a,
                          child: Text(
                            a,
                            style: TextStyle(
                              color: AmbienteSelector.colorForAmbiente(a),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _targetAmbiente = v);
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.compare_arrows, size: 14),
                  label: const Text('Comparar', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
      body: _buildBody(isDark, cs),
    );
  }

  Widget _buildBody(bool isDark, ColorScheme cs) {
    if (!_loading && _targetCode == null && _error == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.compare_arrows,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Seleccioná el ambiente y presioná Comparar',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 36, color: Colors.orange.shade400),
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: cs.onSurface, fontSize: 13)),
          ],
        ),
      );
    }

    if (_targetCode != null) {
      // ORIGEN on left, DESTINO on right — bidirectional comparison
      return _InlineDiff(
        title:
            '${widget.sourceProc.cdProcedimiento}: ${widget.sourceAmbiente} ↔ $_targetAmbiente',
        original: _sourceCode,
        modified: _targetCode!,
        language: _language,
        sourceAmbiente: widget.sourceAmbiente,
        targetAmbiente: _targetAmbiente,
        onSaveOriginal: () =>
            _saveToAmbiente(widget.sourceAmbiente, _sourceCode),
        onSaveModified: (code) => _saveToAmbiente(_targetAmbiente, code),
      );
    }

    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF0078D4)),
    );
  }

  Widget _ambienteBadge(String a) {
    final color = AmbienteSelector.colorForAmbiente(a);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        a,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// Inline Monaco diff (not a dialog — fills available space)
class _InlineDiff extends StatefulWidget {
  final String title;
  final String original;
  final String modified;
  final String language;
  final String sourceAmbiente;
  final String targetAmbiente;
  final Future<void> Function()? onSaveOriginal;
  final Future<void> Function(String code)? onSaveModified;

  const _InlineDiff({
    required this.title,
    required this.original,
    required this.modified,
    required this.language,
    required this.sourceAmbiente,
    required this.targetAmbiente,
    this.onSaveOriginal,
    this.onSaveModified,
  });

  @override
  State<_InlineDiff> createState() => _InlineDiffState();
}

class _InlineDiffState extends State<_InlineDiff> {
  bool _sideBySide = true;
  bool _savingOriginal = false;
  bool _savingModified = false;
  MonacoDiffController? _ctrl;

  // Tracks the current ORIGEN (left) text after programmatic changes
  late String _currentOriginal;
  final _history = <({String original, String modified})>[];

  @override
  void initState() {
    super.initState();
    _currentOriginal = widget.original;
  }

  Future<void> _toggleLayout() async {
    final next = !_sideBySide;
    setState(() => _sideBySide = next);
    await _ctrl?.updateDiffOptions(MonacoDiffOptions(renderSideBySide: next));
  }

  Future<void> _handleSaveOriginal() async {
    setState(() => _savingOriginal = true);
    try {
      await widget.onSaveOriginal?.call();
    } finally {
      if (mounted) setState(() => _savingOriginal = false);
    }
  }

  Future<void> _handleSaveModified() async {
    if (_ctrl == null) return;
    setState(() => _savingModified = true);
    try {
      final code = await _ctrl!.getModifiedText();
      await widget.onSaveModified?.call(code);
    } finally {
      if (mounted) setState(() => _savingModified = false);
    }
  }

  // Apply the first remaining hunk from ORIGEN to DESTINO
  Future<void> _applyOneToModified() async {
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
  Future<void> _applyOneToOriginal() async {
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
  Future<void> _applyAllToModified() async {
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
  Future<void> _applyAllToOriginal() async {
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final srcColor = AmbienteSelector.colorForAmbiente(widget.sourceAmbiente);
    final tgtColor = AmbienteSelector.colorForAmbiente(widget.targetAmbiente);
    return Column(
      children: [
        Container(
          height: 36,
          color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Text(
                widget.title,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              if (widget.onSaveOriginal != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    foregroundColor: srcColor,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _savingOriginal ? null : _handleSaveOriginal,
                  icon: _savingOriginal
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: srcColor,
                          ),
                        )
                      : const Icon(Icons.save_outlined, size: 13),
                  label: Text('Guardar ${widget.sourceAmbiente}'),
                ),
              if (widget.onSaveModified != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    foregroundColor: tgtColor,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _savingModified ? null : _handleSaveModified,
                  icon: _savingModified
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: tgtColor,
                          ),
                        )
                      : const Icon(Icons.save_outlined, size: 13),
                  label: Text('Guardar ${widget.targetAmbiente}'),
                ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  textStyle: const TextStyle(fontSize: 11),
                ),
                icon: Icon(
                  _sideBySide
                      ? Icons.view_agenda_outlined
                      : Icons.view_sidebar_outlined,
                  size: 14,
                ),
                label: Text(_sideBySide ? 'Vista dividida' : 'Vista lineal'),
                onPressed: _toggleLayout,
              ),
            ],
          ),
        ),
        // Column labels with bidirectional copy buttons
        Container(
          color: isDark ? cs.surfaceContainerHighest : cs.surfaceContainerLow,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: srcColor, width: 3),
                      right: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                  child: Text(
                    'ORIGEN \u2014 ${widget.sourceAmbiente}',
                    style: TextStyle(
                      color: srcColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
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
                            onPressed: () => _ctrl?.revealPreviousChange(),
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
                            onPressed: _applyOneToOriginal,
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
                            onPressed: _applyAllToOriginal,
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
                            onPressed: _history.isEmpty ? null : _undo,
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
                            onPressed: _applyAllToModified,
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
                            onPressed: _applyOneToModified,
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
                            onPressed: () => _ctrl?.revealNextChange(),
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
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: tgtColor, width: 3)),
                  ),
                  child: Text(
                    'DESTINO \u2014 ${widget.targetAmbiente}',
                    style: TextStyle(
                      color: tgtColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: MonacoDiffEditor(
            original: widget.original,
            modified: widget.modified,
            language: MonacoLanguage(widget.language),
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
}
