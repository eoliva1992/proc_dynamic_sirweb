import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_monaco/flutter_monaco.dart';
import '../services/schema_service.dart';
import '../widgets/_editor_themes.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/app_toast.dart';

typedef _Hunk = ({int origStart, int origEnd, int modStart, int modEnd});

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

// ─────────────────────────────────────────────────────────────────────────────

class SchemaObjectDiffPage extends StatefulWidget {
  final String objectName;
  final String objectType; // PROCEDURE, FUNCTION, PACKAGE, TYPE
  final String sourceAmbiente;

  const SchemaObjectDiffPage({
    super.key,
    required this.objectName,
    required this.objectType,
    required this.sourceAmbiente,
  });

  @override
  State<SchemaObjectDiffPage> createState() => _SchemaObjectDiffPageState();
}

class _SchemaObjectDiffPageState extends State<SchemaObjectDiffPage> {
  late String _targetAmbiente;
  bool _loading = false;
  String? _sourceCode;
  String? _targetCode;
  String? _error;

  // For PACKAGE: store both spec and body to switch without reloading
  ({String spec, String? body})? _sourceData;
  ({String spec, String? body})? _targetData;
  String _part = 'BODY'; // 'SPEC' or 'BODY'

  bool get _isPackage => widget.objectType == 'PACKAGE';

  bool _compiling = false;
  List<({int line, int position, String text, String attribute})>
  _compilationErrors = [];

  bool _sideBySide = true;
  MonacoDiffController? _ctrl;
  late String _currentOriginal;
  final _history = <({String original, String modified})>[];

  @override
  void initState() {
    super.initState();
    _targetAmbiente = AmbienteSelector.ambientes.firstWhere(
      (a) => a != widget.sourceAmbiente,
    );
  }

  // Returns spec or body text depending on current _part selection
  String _extract(({String spec, String? body}) data) {
    if (_isPackage && _part == 'SPEC') return data.spec;
    if (data.body != null && data.body!.isNotEmpty) return data.body!;
    return data.spec;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _sourceCode = null;
      _targetCode = null;
      _compilationErrors = [];
    });
    try {
      final results = await Future.wait([
        SchemaService.instance.getObjectSource(
          widget.objectName,
          widget.objectType,
          ambiente: widget.sourceAmbiente,
        ),
        SchemaService.instance.getObjectSource(
          widget.objectName,
          widget.objectType,
          ambiente: _targetAmbiente,
        ),
      ]);
      if (mounted) {
        final src = _extract(results[0]);
        final tgt = _extract(results[1]);
        setState(() {
          _sourceData = results[0];
          _targetData = results[1];
          _sourceCode = src;
          _targetCode = tgt;
          _currentOriginal = src;
          _history.clear();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _compile() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    String code = _targetCode ?? '';
    try {
      code = await ctrl.getModifiedText();
    } catch (_) {}
    setState(() {
      _compiling = true;
      _compilationErrors = [];
    });
    try {
      final errors = await SchemaService.instance.compileObject(
        code,
        widget.objectName,
        widget.objectType,
        ambiente: _targetAmbiente,
      );
      if (!mounted) return;
      setState(() {
        _compiling = false;
        _compilationErrors = errors;
      });
      if (errors.isEmpty) {
        AppToast.success('Compilado correctamente en $_targetAmbiente');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _compiling = false);
      AppToast.error(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _switchPart(String part) async {
    if (_part == part || _sourceData == null) return;
    setState(() => _part = part);
    final src = _extract(_sourceData!);
    final tgt = _extract(_targetData!);
    setState(() {
      _sourceCode = src;
      _targetCode = tgt;
      _currentOriginal = src;
      _history.clear();
      _compilationErrors = [];
    });
    await _ctrl?.setTexts(original: src, modified: tgt);
  }

  Future<void> _toggleLayout() async {
    final next = !_sideBySide;
    setState(() => _sideBySide = next);
    await _ctrl?.updateDiffOptions(MonacoDiffOptions(renderSideBySide: next));
  }

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

  String get _objectTypeName => switch (widget.objectType) {
    'PACKAGE' => 'Paquete',
    'PROCEDURE' => 'Procedimiento',
    'FUNCTION' => 'Función',
    'TYPE' => 'Tipo',
    _ => widget.objectType,
  };

  String get _bodyNote => _isPackage ? ' (${_part.toLowerCase()})' : '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final srcColor = AmbienteSelector.colorForAmbiente(widget.sourceAmbiente);
    final tgtColor = AmbienteSelector.colorForAmbiente(_targetAmbiente);

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
                'SCHEMA DIFF',
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
              widget.objectName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                widget.objectType + _bodyNote,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_sourceCode != null) ...[
            // SPEC / BODY toggle — only for PACKAGE (which has both)
            if (_isPackage && (_sourceData?.body?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 28),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  segments: const [
                    ButtonSegment(value: 'SPEC', label: Text('Spec')),
                    ButtonSegment(value: 'BODY', label: Text('Body')),
                  ],
                  selected: {_part},
                  onSelectionChanged: (s) => _switchPart(s.first),
                ),
              ),
            Tooltip(
              message: 'Cambio anterior',
              child: IconButton(
                icon: const Icon(Icons.arrow_upward, size: 16),
                onPressed: () => _ctrl?.revealPreviousChange(),
              ),
            ),
            Tooltip(
              message: 'Siguiente cambio',
              child: IconButton(
                icon: const Icon(Icons.arrow_downward, size: 16),
                onPressed: () => _ctrl?.revealNextChange(),
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
                _sideBySide ? 'Dividida' : 'Lineal',
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: _toggleLayout,
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
                onPressed: _compiling ? null : _compile,
                icon: _compiling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.build_outlined, size: 14),
                label: Text(
                  'Compilar en $_targetAmbiente',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                    if (v != null) {
                      setState(() {
                        _targetAmbiente = v;
                        _sourceCode = null;
                        _targetCode = null;
                        _compilationErrors = [];
                      });
                    }
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
      body: _buildBody(isDark, cs, srcColor, tgtColor),
    );
  }

  Widget _buildBody(
    bool isDark,
    ColorScheme cs,
    Color srcColor,
    Color tgtColor,
  ) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0078D4)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 36, color: Colors.orange.shade400),
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (_sourceCode == null) {
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
            const SizedBox(height: 6),
            Text(
              _objectTypeName,
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _history.isEmpty ? () {} : _undo,
        SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
            _ctrl?.revealPreviousChange(),
        SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
            _ctrl?.revealNextChange(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            _applyOneToSource,
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            _applyOneToTarget,
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true, shift: true):
            _applyAllToSource,
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true, shift: true):
            _applyAllToTarget,
      },
      child: Focus(
        autofocus: false,
        child: Column(
          children: [
            _buildHeaders(isDark, cs, srcColor, tgtColor),
            Expanded(
              child: MonacoDiffEditor(
                original: _sourceCode!,
                modified: _targetCode!,
                language: const MonacoLanguage('sql'),
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
            if (_compilationErrors.isNotEmpty) _buildErrorsPanel(isDark, cs),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaders(
    bool isDark,
    ColorScheme cs,
    Color srcColor,
    Color tgtColor,
  ) {
    return Container(
      color: isDark ? cs.surfaceContainerHighest : cs.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: srcColor, width: 3),
                  right: BorderSide(color: cs.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  _ambBadge(widget.sourceAmbiente, srcColor, 'ORIGEN'),
                  const SizedBox(width: 8),
                  Text(
                    'Solo lectura',
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
          // Center: nav + per-hunk + all + undo
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
                      message: 'Cambio anterior  (Alt+↑)',
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
                      message: 'Aplicar 1 cambio: DESTINO → ORIGEN  (Alt+←)',
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
                        onPressed: _applyOneToSource,
                      ),
                    ),
                    Tooltip(
                      message: 'Copiar TODO: DESTINO → ORIGEN  (Alt+Shift+←)',
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
                        onPressed: _applyAllToSource,
                      ),
                    ),
                    Tooltip(
                      message: _history.isEmpty
                          ? 'Nada que deshacer'
                          : 'Deshacer última copia (${_history.length})  Ctrl+Z',
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.undo,
                              size: 12,
                              color: _history.isEmpty
                                  ? cs.onSurfaceVariant.withValues(alpha: 0.3)
                                  : Colors.amber.shade600,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 24,
                            ),
                            onPressed: _history.isEmpty ? null : _undo,
                          ),
                          if (_history.isNotEmpty)
                            Positioned(
                              top: 2,
                              right: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade600,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${_history.length}',
                                    style: const TextStyle(
                                      fontSize: 6,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: 'Copiar TODO: ORIGEN → DESTINO  (Alt+Shift+→)',
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
                        onPressed: _applyAllToTarget,
                      ),
                    ),
                    Tooltip(
                      message: 'Aplicar 1 cambio: ORIGEN → DESTINO  (Alt+→)',
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
                        onPressed: _applyOneToTarget,
                      ),
                    ),
                    Tooltip(
                      message: 'Siguiente cambio  (Alt+↓)',
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: tgtColor, width: 3)),
              ),
              child: Row(
                children: [
                  _ambBadge(_targetAmbiente, tgtColor, 'DESTINO'),
                  const SizedBox(width: 8),
                  Text(
                    'Editable · Compilar con el botón',
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
    );
  }

  Widget _buildErrorsPanel(bool isDark, ColorScheme cs) {
    final errColor = Colors.red.shade400;
    final warnColor = Colors.orange.shade400;
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFF0F0),
        border: Border(top: BorderSide(color: errColor.withValues(alpha: 0.4))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 13, color: errColor),
                const SizedBox(width: 6),
                Text(
                  '${_compilationErrors.length} error(es) de compilación',
                  style: TextStyle(
                    fontSize: 11,
                    color: errColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _compilationErrors = []),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              itemCount: _compilationErrors.length,
              itemBuilder: (_, i) {
                final e = _compilationErrors[i];
                final isErr = e.attribute == 'ERROR';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        alignment: Alignment.centerRight,
                        child: Text(
                          'L${e.line}',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Consolas',
                            color: isErr ? errColor : warnColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.text,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Consolas',
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _ambBadge(String ambiente, Color color, String role) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 0.8),
        ),
        child: Text(
          '$role — $ambiente',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    ],
  );
}
