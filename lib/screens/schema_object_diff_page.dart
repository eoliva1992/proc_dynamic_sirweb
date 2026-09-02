import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import '../services/backup_service.dart';
import '../services/schema_service.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/app_toast.dart';
import '../widgets/native_diff_viewer.dart';

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
  // ── Ambiente ───────────────────────────────────────────────────────────────
  late String _targetAmbiente;

  // ── Carga ──────────────────────────────────────────────────────────────────
  bool _loading = false;
  String? _sourceCode;
  String? _error;

  // ── Paquete (SPEC/BODY) ────────────────────────────────────────────────────
  ({String spec, String? body})? _sourceData;
  ({String spec, String? body})? _targetData;
  String _part = 'BODY';
  bool get _isPackage => widget.objectType == 'PACKAGE';

  // ── Compilación ────────────────────────────────────────────────────────────
  bool _compiling = false;
  List<({int line, int position, String text, String attribute})>
      _compilationErrors = [];

  // ── Vista ──────────────────────────────────────────────────────────────────
  bool _sideBySide = true;
  bool _showAllLines = true; // por defecto muestra el código completo

  // ── Sidebar (solo PACKAGE) ─────────────────────────────────────────────────
  String _sidebarFilter = '';
  bool _sidebarVisible = true;
  double _sidebarWidth = 210;
  final _sidebarListCtrl = ScrollController();
  int _sidebarActiveIdx = -1; // índice activo en _procItems
  List<({String name, String type, int lineNum, int lineEnd})> _procItems = [];

  // ── Foco en procedimiento ──────────────────────────────────────────────────
  /// Nombre del procedimiento enfocado. null = sin foco (vista completa).
  String? _focusedProcName;

  // ── Texto ──────────────────────────────────────────────────────────────────
  String _modifiedText = '';
  late String _currentOriginal;

  // ── Historial y controlador ────────────────────────────────────────────────
  final _diffCtrl = NativeDiffController();
  final _history = <({String original, String modified})>[];
  final _sidebarFilterCtrl = TextEditingController();

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _sidebarFilterCtrl.addListener(() {
      setState(() => _sidebarFilter = _sidebarFilterCtrl.text);
    });
    _targetAmbiente = AmbienteSelector.ambientes.firstWhere(
      (a) => a != widget.sourceAmbiente,
    );
    _diffCtrl.visibleOrigLine.addListener(_onVisibleLineChanged);
  }

  @override
  void dispose() {
    _diffCtrl.dispose();
    _sidebarFilterCtrl.dispose();
    _sidebarListCtrl.dispose();
    super.dispose();
  }

  /// Sincroniza el ítem activo del sidebar con la línea visible en el visor.
  void _onVisibleLineChanged() {
    if (!mounted || _procItems.isEmpty) return;
    final visLine = _diffCtrl.visibleOrigLine.value;
    var newIdx = -1;
    for (var i = _procItems.length - 1; i >= 0; i--) {
      if (_procItems[i].lineNum <= visLine) {
        newIdx = i;
        break;
      }
    }
    if (newIdx == _sidebarActiveIdx) return;
    _sidebarActiveIdx = newIdx;
    // Auto-scroll del sidebar al ítem activo
    if (newIdx >= 0 && _sidebarListCtrl.hasClients) {
      const itemH = 38.0;
      final off = newIdx * itemH;
      final vp = _sidebarListCtrl.position.viewportDimension;
      final cur = _sidebarListCtrl.offset;
      if (off < cur || off + itemH > cur + vp) {
        _sidebarListCtrl.animateTo(
          off.clamp(0.0, _sidebarListCtrl.position.maxScrollExtent),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }
    // Rebuild solo para el highlight
    if (mounted) setState(() {});
  }

  // ──────��──────────────────────────────────────────────────────────────────
  // Helpers de foco
  // ─────────────────────────────────────────────────────────────────────────

  /// Ítem del proc actualmente enfocado (null si sin foco).
  ({String name, String type, int lineNum, int lineEnd})? get _focusedProcItem =>
      _focusedProcName == null
          ? null
          : _procItems.where((p) => p.name == _focusedProcName).firstOrNull;

  /// Texto ORIGEN que el visor muestra (fragmento si hay foco).
  String get _viewOrig {
    final fp = _focusedProcItem;
    if (fp == null) return _currentOriginal;
    final lines = _currentOriginal.split('\n');
    final s = (fp.lineNum - 1).clamp(0, lines.length);
    final e = fp.lineEnd.clamp(s, lines.length);
    return lines.sublist(s, e).join('\n');
  }

  /// Texto DESTINO que el visor muestra (fragmento si hay foco).
  /// Usa los límites del procedimiento en _modifiedText (no los del origen).
  String get _viewMod {
    final fp = _focusedProcItem;
    if (fp == null) return _modifiedText;
    final bounds = _findProcBounds(fp.name, _modifiedText);
    if (bounds == null) return _modifiedText; // proc no encontrado en destino → vista completa
    final lines = _modifiedText.split('\n');
    final s = (bounds.lineNum - 1).clamp(0, lines.length);
    final e = bounds.lineEnd.clamp(s, lines.length);
    return lines.sublist(s, e).join('\n');
  }

  /// Offset para números de línea del visor cuando hay foco.
  int get _viewLineOffset => (_focusedProcItem?.lineNum ?? 1) - 1;

  /// Reconstruye DESTINO completo reemplazando el fragmento enfocado por [fragment].
  /// Usa los límites del procedimiento en _modifiedText para un corte preciso.
  String _spliceMod(String fragment) {
    final fp = _focusedProcItem;
    if (fp == null) return fragment;
    final bounds = _findProcBounds(fp.name, _modifiedText);
    if (bounds == null) return fragment; // no se puede empalmar, retornar tal cual
    final lines = _modifiedText.split('\n');
    final s = (bounds.lineNum - 1).clamp(0, lines.length);
    final e = bounds.lineEnd.clamp(s, lines.length);
    return [...lines.sublist(0, s), ...fragment.split('\n'), ...lines.sublist(e)].join('\n');
  }

  /// Reconstruye ORIGEN completo reemplazando el fragmento enfocado por [fragment].
  String _spliceOrig(String fragment) {
    final fp = _focusedProcItem;
    if (fp == null) return fragment;
    final lines = _currentOriginal.split('\n');
    final s = (fp.lineNum - 1).clamp(0, lines.length);
    final e = fp.lineEnd.clamp(s, lines.length);
    return [...lines.sublist(0, s), ...fragment.split('\n'), ...lines.sublist(e)].join('\n');
  }

  void _focusProc(String name) => setState(() {
        _focusedProcName = name;
        _compilationErrors = [];
      });

  void _clearFocus() => setState(() => _focusedProcName = null);

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _extract(({String spec, String? body}) data, {String? forPart}) {
    final p = forPart ?? _part;
    if (_isPackage && p == 'SPEC') return data.spec;
    if (data.body != null && data.body!.isNotEmpty) return data.body!;
    return data.spec;
  }

  String get _objectTypeName => switch (widget.objectType) {
        'PACKAGE' => 'Paquete',
        'PROCEDURE' => 'Procedimiento',
        'FUNCTION' => 'Función',
        'TYPE' => 'Tipo',
        _ => widget.objectType,
      };

  String get _bodyNote => _isPackage ? ' · ${_part.toLowerCase()}' : '';

  // ─────────────────────────────────────────────────────────────────────────
  // Carga / compilación
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _sourceCode = null;
      _compilationErrors = [];
    });
    try {
      final results = await Future.wait([
        SchemaService.instance.getObjectSource(
            widget.objectName, widget.objectType,
            ambiente: widget.sourceAmbiente),
        SchemaService.instance.getObjectSource(
            widget.objectName, widget.objectType,
            ambiente: _targetAmbiente),
      ]);
      if (mounted) {
        final src = _extract(results[0]);
        final tgt = _extract(results[1]);
        final procs = _parseProcFuncs(src);
        setState(() {
          _sourceData = results[0];
          _targetData = results[1];
          _sourceCode = src;
          _modifiedText = tgt;
          _currentOriginal = src;
          _history.clear();
          _loading = false;
          _sidebarFilterCtrl.clear();
          _sidebarFilter = '';
          _procItems = procs;
          _focusedProcName = null;
          _sidebarActiveIdx = procs.isNotEmpty ? 0 : -1; // primer ítem por defecto
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
    final code = _modifiedText;
    setState(() {
      _compiling = true;
      _compilationErrors = [];
    });
    try {
      final errors = await SchemaService.instance.compileObject(
          code, widget.objectName, widget.objectType,
          ambiente: _targetAmbiente);
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

  // ─────────────────────────────────────────────────────────────────────────
  // Backup
  // ─────────────────────────────────────────────────────────────────────────

  /// Exporta [text] al disco como backup .sql del objeto de esquema.
  /// [isSource] distingue el label del toast y el nombre del archivo.
  Future<void> _backup({required String text, required bool isSource}) async {
    final ambiente = isSource ? widget.sourceAmbiente : _targetAmbiente;
    final label = isSource ? 'Origen' : 'Destino';
    // Para PACKAGE indicamos la parte actual (SPEC / BODY)
    final part = _isPackage ? _part : null;
    try {
      final savedPath = await BackupService.exportarDdl(
        objectName: widget.objectName,
        objectType: widget.objectType,
        ambiente: ambiente,
        source: text,
        part: part,
      );
      if (savedPath != null) {
        AppToast.successWithAction(
          'Backup $label exportado correctamente',
          detail: savedPath,
          actionLabel: 'Abrir ubicación',
          onAction: () => BackupService.revealInExplorer(savedPath),
        );
      }
    } catch (e) {
      AppToast.error('Error al exportar backup: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Vista SPEC / BODY
  // ─────────────────────────────────────────────────────────────────────────

  void _switchPart(String part) {
    if (_part == part || _sourceData == null) return;
    // Pasar `forPart: part` para que _extract use el NUEVO part, no el actual
    final src = _extract(_sourceData!, forPart: part);
    final tgt = _extract(_targetData!, forPart: part);
    final procs = _parseProcFuncs(src);
    _sidebarFilterCtrl.clear();
    // Preservar el foco si el mismo proc/func existe en la nueva parte
    final preservedFocus = _focusedProcName != null &&
            procs.any((p) => p.name == _focusedProcName)
        ? _focusedProcName
        : null;
    setState(() {
      _part = part;
      _sourceCode = src;
      _modifiedText = tgt;
      _currentOriginal = src;
      _history.clear();
      _compilationErrors = [];
      _procItems = procs;
      _focusedProcName = preservedFocus;
      _sidebarFilter = '';
      _sidebarActiveIdx = preservedFocus != null
          ? procs.indexWhere((p) => p.name == preservedFocus)
          : (procs.isNotEmpty ? 0 : -1);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Navegación
  // ─────────────────────────────────────────────────────────────────────────

  void _nextChange() => _diffCtrl.nextChange();
  void _prevChange() => _diffCtrl.previousChange();

  // ─────────────────────────────────────────────────────────────────────────
  // Aplicar cambios — por HUNK
  // ─────────────────────────────────────────────────────────────────────────

  /// Aplica el hunk [idx] copiando ORIGEN → DESTINO.
  void _applyHunkToTarget(int idx) {
    final oFrag = _viewOrig;
    final mFrag = _viewMod;
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
      _modifiedText = _spliceMod(newFrag);
    });
  }

  /// Aplica el hunk [idx] copiando DESTINO → ORIGEN.
  void _applyHunkToSource(int idx) {
    final oFrag = _viewOrig;
    final mFrag = _viewMod;
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
      _currentOriginal = _spliceOrig(newFrag);
    });
  }

  void _applyCurrentHunkToTarget() => _applyHunkToTarget(_diffCtrl.currentHunk);
  void _applyCurrentHunkToSource() => _applyHunkToSource(_diffCtrl.currentHunk);

  void _applyAllToTarget() {
    final orig = _viewOrig;
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _modifiedText = _spliceMod(orig);
    });
  }

  void _applyAllToSource() {
    final mod = _viewMod;
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _currentOriginal = _spliceOrig(mod);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Aplicar cambios — por LÍNEA (callbacks del viewer)
  // ─────────────────────────────────────────────────────────────────────────

  /// Copia la línea [hunkRow] del hunk [hunkIdx] de ORIGEN → DESTINO.
  void _applyLineToTarget(int hunkIdx, int hunkRow) {
    final oFrag = _viewOrig;
    final mFrag = _viewMod;
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
      _modifiedText = _spliceMod(dL.join('\n'));
    });
  }

  /// Copia la línea [hunkRow] del hunk [hunkIdx] de DESTINO → ORIGEN.
  void _applyLineToSource(int hunkIdx, int hunkRow) {
    final oFrag = _viewOrig;
    final mFrag = _viewMod;
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
      _currentOriginal = _spliceOrig(oL.join('\n'));
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Undo
  // ─────────────────────────────────────────────────────────────────────────

  void _undo() {
    if (_history.isEmpty) return;
    final prev = _history.last;
    setState(() {
      _history.removeLast();
      _currentOriginal = prev.original;
      _modifiedText = prev.modified;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Editar origen / destino (reutilizable)
  // ─────────────────────────────────────────────────────────────────────────

  void _openEditDialog({required bool isSource}) {
    final color = isSource
        ? AmbienteSelector.colorForAmbiente(widget.sourceAmbiente)
        : AmbienteSelector.colorForAmbiente(_targetAmbiente);
    final label = isSource
        ? 'ORIGEN — ${widget.sourceAmbiente.toUpperCase()}'
        : 'DESTINO — ${_targetAmbiente.toUpperCase()}';
    final ec = TextEditingController(
        text: isSource ? _currentOriginal : _modifiedText);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Row(children: [
              Icon(Icons.edit_outlined, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Editar $label · ${widget.objectName}$_bodyNote',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: () {
                  setState(() {
                    if (isSource) {
                      _history.add((
                        original: _currentOriginal,
                        modified: _modifiedText
                      ));
                      _currentOriginal = ec.text;
                    } else {
                      _modifiedText = ec.text;
                    }
                  });
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Aplicar'),
              ),
            ]),
          ),
          Expanded(
            child: TextField(
              controller: ec,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                  fontFamily: 'Consolas', fontSize: 12, height: 1.45),
              decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(14)),
            ),
          ),
        ]),
      ),
    ).whenComplete(ec.dispose);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sidebar: parseo de PROCEDURE / FUNCTION en paquetes
  // ─────────────────────────────────────────────────────────────────────────

  static final _plsqlRe = RegExp(
    r'^\s*(PROCEDURE|FUNCTION)\s+([A-Za-z_][A-Za-z0-9_$#]*)',
    caseSensitive: false,
  );

  /// Parsea el código fuente y devuelve lista de (name, type, lineNum, lineEnd).
  /// [lineEnd] es el número de línea exclusivo del fin del procedimiento (0-based count).
  List<({String name, String type, int lineNum, int lineEnd})> _parseProcFuncs(String source) {
    final lines = source.split('\n');
    final raw = <({String name, String type, int lineNum})>[];
    final seen = <String>{};
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('--')) continue;
      final m = _plsqlRe.firstMatch(lines[i]);
      if (m == null) continue;
      final name = m.group(2)!.toUpperCase();
      final type = m.group(1)!.toUpperCase();
      if (!seen.contains(name)) {
        seen.add(name);
        raw.add((name: name, type: type, lineNum: i + 1));
      }
    }
    return List.generate(raw.length, (i) {
      final end = i + 1 < raw.length ? raw[i + 1].lineNum - 1 : lines.length;
      return (name: raw[i].name, type: raw[i].type, lineNum: raw[i].lineNum, lineEnd: end);
    });
  }

  /// Busca los límites de un procedimiento/función por nombre en [text].
  /// Parsea [text] de forma independiente para obtener rangos precisos.
  /// Retorna null si el nombre no se encuentra en el texto.
  ({int lineNum, int lineEnd})? _findProcBounds(String name, String text) {
    final items = _parseProcFuncs(text);
    final found = items.where((p) => p.name == name).firstOrNull;
    if (found == null) return null;
    return (lineNum: found.lineNum, lineEnd: found.lineEnd);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final srcColor = AmbienteSelector.colorForAmbiente(widget.sourceAmbiente);
    final tgtColor = AmbienteSelector.colorForAmbiente(_targetAmbiente);

    return Scaffold(
      appBar: _buildAppBar(cs),
      body: _buildBody(isDark, cs, srcColor, tgtColor),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(ColorScheme cs) {
    return AppBar(
      titleSpacing: 0,
      title: Row(children: [
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.shade400, width: 0.8),
          ),
          child: Text('SCHEMA DIFF',
              style: TextStyle(
                  color: Colors.blue.shade400,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
        ),
        const SizedBox(width: 8),
        Text(widget.objectName,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(3)),
          child: Text(widget.objectType + _bodyNote,
              style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
      actions: [
        // SPEC / BODY (solo PACKAGE con body)
        if (_isPackage && (_sourceData?.body?.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 28),
                  textStyle: const TextStyle(fontSize: 11)),
              segments: const [
                ButtonSegment(value: 'SPEC', label: Text('Spec')),
                ButtonSegment(value: 'BODY', label: Text('Body')),
              ],
              selected: {_part},
              onSelectionChanged: (s) => _switchPart(s.first),
            ),
          ),
        // Target dropdown
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('vs ', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            DropdownButton<String>(
              value: _targetAmbiente,
              isDense: true,
              underline: const SizedBox.shrink(),
              dropdownColor: cs.surfaceContainerHigh,
              items: AmbienteSelector.ambientes
                  .where((a) => a != widget.sourceAmbiente)
                  .map((a) => DropdownMenuItem(
                        value: a,
                        child: Text(a,
                            style: TextStyle(
                                color: AmbienteSelector.colorForAmbiente(a),
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _targetAmbiente = v;
                    _sourceCode = null;
                    _compilationErrors = [];
                  });
                }
              },
            ),
          ]),
        ),
        // Comparar
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: FilledButton.icon(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                : const Icon(Icons.compare_arrows, size: 14),
            label: const Text('Comparar', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody(bool isDark, ColorScheme cs, Color srcColor, Color tgtColor) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF0078D4)));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.info_outline, size: 36, color: Colors.orange.shade400),
          const SizedBox(height: 10),
          Text(_error!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
        ]),
      );
    }
    if (_sourceCode == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.compare_arrows,
              size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.35)),
          const SizedBox(height: 12),
          Text('Seleccioná el ambiente y presioná Comparar',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 4),
          Text(_objectTypeName,
              style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                  fontSize: 11)),
        ]),
      );
    }

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _history.isEmpty ? () {} : _undo,
        SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _prevChange,
        SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): _nextChange,
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _applyCurrentHunkToSource,
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): _applyCurrentHunkToTarget,
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true, shift: true): _applyAllToSource,
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true, shift: true): _applyAllToTarget,
      },
      child: Focus(
        autofocus: false,
        child: Column(children: [
          _buildToolbar(isDark, cs, srcColor, tgtColor),
          Expanded(
            child: Row(children: [
              // Sidebar de procedimientos/funciones (solo PACKAGE)
              if (_isPackage && _sidebarVisible)
                _buildSidebar(isDark, cs),
              // Visor principal
              Expanded(
                child: Column(children: [
                  Expanded(
                    child: NativeDiffViewer(
                      origText: _viewOrig,
                      modText: _viewMod,
                      sideBySide: _sideBySide,
                      showAllLines: _showAllLines,
                      lineOffset: _viewLineOffset,
                      controller: _diffCtrl,
                      onApplyLineToTarget: _applyLineToTarget,
                      onApplyLineToSource: _applyLineToSource,
                    ),
                  ),
                  if (_compilationErrors.isNotEmpty) _buildErrorsPanel(isDark, cs),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────────────

  Widget _buildToolbar(bool isDark, ColorScheme cs, Color srcColor, Color tgtColor) {
    final divColor = cs.outlineVariant;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
        border: Border(bottom: BorderSide(color: divColor)),
      ),
      child: Row(children: [
        // ── Lado izquierdo: ORIGEN ────────────────────────────────────────
        const SizedBox(width: 8),
        _ambBadge(widget.sourceAmbiente, srcColor, 'ORIGEN'),
        const SizedBox(width: 4),

        // ←← copia todo DESTINO→ORIGEN
        _tbBtn(
          tooltip: 'Copiar TODO: DESTINO→ORIGEN  (Alt+Shift+←)',
          icon: Icons.keyboard_double_arrow_left,
          color: srcColor,
          onTap: _applyAllToSource,
        ),

        // ← copia hunk actual DESTINO→ORIGEN
        _tbBtn(
          tooltip: 'Aplicar cambio actual: DESTINO→ORIGEN  (Alt+←)',
          icon: Icons.chevron_left,
          color: srcColor,
          size: 20,
          onTap: _applyCurrentHunkToSource,
        ),

        // ── Navegación central ────────────────────────────────────────────
        _vSep(divColor),
        _tbBtn(
          tooltip: 'Cambio anterior  (Alt+↑)',
          icon: Icons.keyboard_arrow_up,
          onTap: _prevChange,
        ),

        // Contador de hunks
        ListenableBuilder(
          listenable: _diffCtrl,
          builder: (_, __) {
            final tot = _diffCtrl.totalHunks;
            final cur = _diffCtrl.currentHunk;
            return Container(
              constraints: const BoxConstraints(minWidth: 52),
              alignment: Alignment.center,
              child: tot == 0
                  ? Text('✓ Sin cambios',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade500,
                          fontWeight: FontWeight.w600))
                  : Text('${cur + 1} / $tot',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600)),
            );
          },
        ),

        _tbBtn(
          tooltip: 'Siguiente cambio  (Alt+↓)',
          icon: Icons.keyboard_arrow_down,
          onTap: _nextChange,
        ),
        _vSep(divColor),

        // → copia hunk actual ORIGEN→DESTINO
        _tbBtn(
          tooltip: 'Aplicar cambio actual: ORIGEN→DESTINO  (Alt+→)',
          icon: Icons.chevron_right,
          color: tgtColor,
          size: 20,
          onTap: _applyCurrentHunkToTarget,
        ),

        // →→ copia todo ORIGEN→DESTINO
        _tbBtn(
          tooltip: 'Copiar TODO: ORIGEN→DESTINO  (Alt+Shift+→)',
          icon: Icons.keyboard_double_arrow_right,
          color: tgtColor,
          onTap: _applyAllToTarget,
        ),

        const SizedBox(width: 4),
        _ambBadge(_targetAmbiente, tgtColor, 'DESTINO'),

        // ── Separador principal ───────────────────────────────────────────
        const Spacer(),

        // Chip de foco activo (solo PACKAGE, cuando hay foco)
        if (_focusedProcName != null) ...[
          _vSep(divColor),
          Tooltip(
            message: 'Viendo solo: $_focusedProcName  –  Clic × para ver el paquete completo',
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              padding: const EdgeInsets.fromLTRB(7, 2, 4, 2),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.45), width: 0.8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.center_focus_strong, size: 11, color: cs.primary),
                const SizedBox(width: 4),
                Text(
                  _focusedProcName!,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 3),
                GestureDetector(
                  onTap: _clearFocus,
                  child: Icon(Icons.close, size: 12, color: cs.primary.withValues(alpha: 0.7)),
                ),
              ]),
            ),
          ),
        ],

        _vSep(divColor),

        // Toggle sidebar (solo PACKAGE)
        if (_isPackage) ...[
          Tooltip(
            message: _sidebarVisible ? 'Ocultar panel de navegación' : 'Mostrar panel de navegación',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => setState(() => _sidebarVisible = !_sidebarVisible),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Icon(
                  _sidebarVisible ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                  size: 14,
                  color: _sidebarVisible
                      ? Theme.of(context).colorScheme.primary
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          _vSep(divColor),
        ],

        // Solo diffs / Código completo
        Tooltip(
          message: _showAllLines ? 'Mostrar solo diffs' : 'Mostrar código completo',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _showAllLines = !_showAllLines),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: [
                Icon(
                  _showAllLines ? Icons.article_outlined : Icons.difference_outlined,
                  size: 14,
                  color: _showAllLines ? Colors.amber.shade600 : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _showAllLines ? 'Completo' : 'Solo diffs',
                  style: TextStyle(
                    fontSize: 11,
                    color: _showAllLines ? Colors.amber.shade600 : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ]),
            ),
          ),
        ),

        _vSep(divColor),

        // SBS / Unified
        Tooltip(
          message: _sideBySide ? 'Vista unificada' : 'Vista lado a lado',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _sideBySide = !_sideBySide),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: [
                Icon(
                  _sideBySide ? Icons.view_agenda_outlined : Icons.view_sidebar_outlined,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _sideBySide ? 'Dividida' : 'Unificada',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ]),
            ),
          ),
        ),

        _vSep(divColor),

        // Editar origen / destino — popup, oculto en modo foco
        if (_focusedProcName == null) ...[
          Tooltip(
            message: 'Editar código (Origen / Destino)',
            child: PopupMenuButton<String>(
              tooltip: '',
              icon: Icon(Icons.edit_outlined,
                  size: 15, color: cs.onSurfaceVariant),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'src',
                  child: Row(children: [
                    Icon(Icons.edit_note_outlined,
                        size: 15,
                        color: AmbienteSelector.colorForAmbiente(
                            widget.sourceAmbiente)),
                    const SizedBox(width: 8),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Editar Origen',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          Text(widget.sourceAmbiente.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AmbienteSelector.colorForAmbiente(
                                      widget.sourceAmbiente))),
                        ]),
                  ]),
                ),
                PopupMenuItem(
                  value: 'tgt',
                  child: Row(children: [
                    Icon(Icons.edit_outlined,
                        size: 15,
                        color: AmbienteSelector.colorForAmbiente(
                            _targetAmbiente)),
                    const SizedBox(width: 8),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Editar Destino',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          Text(_targetAmbiente.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AmbienteSelector.colorForAmbiente(
                                      _targetAmbiente))),
                        ]),
                  ]),
                ),
              ],
              onSelected: (v) =>
                  _openEditDialog(isSource: v == 'src'),
            ),
          ),
          _vSep(divColor),
        ],

        // Undo con badge
        Tooltip(
          message: _history.isEmpty
              ? 'Nada que deshacer'
              : 'Deshacer  Ctrl+Z  (${_history.length} operaciones)',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: _history.isEmpty ? null : _undo,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Stack(clipBehavior: Clip.none, children: [
                Icon(
                  Icons.undo,
                  size: 16,
                  color: _history.isEmpty
                      ? cs.onSurfaceVariant.withValues(alpha: 0.3)
                      : Colors.amber.shade600,
                ),
                if (_history.isNotEmpty)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                          color: Colors.amber.shade600,
                          shape: BoxShape.circle),
                      child: Center(
                        child: Text(
                          '${_history.length}',
                          style: const TextStyle(
                              fontSize: 7,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),

        _vSep(divColor),

        // Backup — menú con Origen y Destino (oculto en modo foco)
        if (_focusedProcName == null) ...[
          Tooltip(
            message: 'Backup del objeto (Origen / Destino)',
            child: PopupMenuButton<String>(
            tooltip: '',
            icon: Icon(Icons.save_alt_outlined,
                size: 15, color: cs.onSurfaceVariant),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'src',
                child: Row(children: [
                  Icon(Icons.download_outlined,
                      size: 15,
                      color: AmbienteSelector.colorForAmbiente(
                          widget.sourceAmbiente)),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Backup Origen',
                        style: const TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    Text(widget.sourceAmbiente.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            color: AmbienteSelector.colorForAmbiente(
                                widget.sourceAmbiente))),
                  ]),
                ]),
              ),
              PopupMenuItem(
                value: 'tgt',
                child: Row(children: [
                  Icon(Icons.download_outlined,
                      size: 15,
                      color: AmbienteSelector.colorForAmbiente(_targetAmbiente)),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Backup Destino',
                        style: const TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    Text(_targetAmbiente.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            color: AmbienteSelector.colorForAmbiente(
                                _targetAmbiente))),
                  ]),
                ]),
              ),
            ],
            onSelected: (v) {
              if (v == 'src') {
                _backup(text: _currentOriginal, isSource: true);
              } else {
                _backup(text: _modifiedText, isSource: false);
              }
            },
          ),
        ),
        ], // fin if _focusedProcName == null (backup)

        _vSep(divColor),

        // Compilar — oculto cuando hay foco en un procedimiento puntual
        if (_focusedProcName != null)
          Tooltip(
            message: 'Estás viendo solo "$_focusedProcName".\n'
                'Salí del foco (×) para compilar el destino completo.',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade400),
                const SizedBox(width: 5),
                Text(
                  'Salir del foco para compilar',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _clearFocus,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade400.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade400, width: 0.8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.zoom_out_map, size: 11, color: Colors.orange.shade400),
                      const SizedBox(width: 3),
                      Text('Ver todo',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange.shade400,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: tgtColor,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                textStyle: const TextStyle(fontSize: 11),
              ),
              onPressed: _compiling ? null : _compile,
              icon: _compiling
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                  : const Icon(Icons.build_outlined, size: 13),
              label: Text('Compilar $_targetAmbiente',
                  style: const TextStyle(fontSize: 11)),
            ),
          ),
        const SizedBox(width: 4),
      ]),
    );
  }

  // ── Helpers toolbar ────────────────────────────────────────────────────────

  Widget _tbBtn({
    required String tooltip,
    required IconData icon,
    Color? color,
    double size = 16,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Icon(icon,
              size: size,
              color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _vSep(Color color) => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: color,
      );

  // ── Menú contextual de procedimiento ─────────────────────────────────────

  void _showProcContextMenu(
    BuildContext ctx,
    Offset pos,
    ({String name, String type, int lineNum, int lineEnd}) item,
  ) async {
    final cs = Theme.of(ctx).colorScheme;
    final result = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'focus',
          child: Row(children: [
            Icon(Icons.center_focus_strong, size: 14, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Ver solo: ${item.name}', style: const TextStyle(fontSize: 12))),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'applyToTarget',
          child: Row(children: [
            Icon(Icons.arrow_forward, size: 14, color: Colors.green.shade600),
            const SizedBox(width: 8),
            const Expanded(child: Text('Aplicar cambios → Destino', style: TextStyle(fontSize: 12))),
          ]),
        ),
        PopupMenuItem(
          value: 'applyToSource',
          child: Row(children: [
            Icon(Icons.arrow_back, size: 14, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Expanded(child: Text('Aplicar cambios → Origen', style: TextStyle(fontSize: 12))),
          ]),
        ),
      ],
    );
    if (!mounted) return;
    if (result == 'focus') {
      _focusProc(item.name);
    } else if (result == 'applyToTarget') {
      _applyProcAllToTarget(item);
    } else if (result == 'applyToSource') {
      _applyProcAllToSource(item);
    }
  }

  /// Aplica TODOS los cambios del proc [item] de ORIGEN → DESTINO
  /// independientemente del foco activo.
  void _applyProcAllToTarget(({String name, String type, int lineNum, int lineEnd}) item) {
    final oLines = _currentOriginal.split('\n');
    final mLines = _modifiedText.split('\n');
    // Límites del lado ORIGEN (del item, ya parseados correctamente)
    final os = (item.lineNum - 1).clamp(0, oLines.length);
    final oEnd = item.lineEnd.clamp(os, oLines.length);
    // Límites del lado DESTINO: buscar el mismo procedimiento en _modifiedText
    final mBounds = _findProcBounds(item.name, _modifiedText);
    final ms = mBounds != null ? (mBounds.lineNum - 1).clamp(0, mLines.length) : os;
    final mEnd = mBounds != null ? mBounds.lineEnd.clamp(ms, mLines.length) : item.lineEnd.clamp(ms, mLines.length);
    final origFrag = oLines.sublist(os, oEnd);
    final newMod = [...mLines.sublist(0, ms), ...origFrag, ...mLines.sublist(mEnd)].join('\n');
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _modifiedText = newMod;
    });
  }

  /// Aplica TODOS los cambios del proc [item] de DESTINO → ORIGEN
  /// independientemente del foco activo.
  void _applyProcAllToSource(({String name, String type, int lineNum, int lineEnd}) item) {
    final oLines = _currentOriginal.split('\n');
    final mLines = _modifiedText.split('\n');
    // Límites del lado DESTINO: buscar el procedimiento en _modifiedText
    final mBounds = _findProcBounds(item.name, _modifiedText);
    final ms = mBounds != null ? (mBounds.lineNum - 1).clamp(0, mLines.length) : (item.lineNum - 1).clamp(0, mLines.length);
    final mEnd = mBounds != null ? mBounds.lineEnd.clamp(ms, mLines.length) : item.lineEnd.clamp(ms, mLines.length);
    // Límites del lado ORIGEN (del item, ya parseados correctamente)
    final os = (item.lineNum - 1).clamp(0, oLines.length);
    final oEnd = item.lineEnd.clamp(os, oLines.length);
    final modFrag = mLines.sublist(ms, mEnd);
    final newOrig = [...oLines.sublist(0, os), ...modFrag, ...oLines.sublist(oEnd)].join('\n');
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _currentOriginal = newOrig;
    });
  }

  // ── Sidebar navegación PACKAGE ─────────────────────────────────────────────

  Widget _buildSidebar(bool isDark, ColorScheme cs) {
    final q = _sidebarFilter.trim().toUpperCase();
    final items = q.isEmpty
        ? _procItems
        : _procItems.where((e) => e.name.contains(q) || e.type.contains(q)).toList();

    // Índice del ítem activo en la lista filtrada (cálculo seguro y limpio)
    int activeInFiltered = -1;
    if (_sidebarActiveIdx >= 0 && _sidebarActiveIdx < _procItems.length) {
      if (q.isEmpty) {
        activeInFiltered = _sidebarActiveIdx;
      } else {
        final activeName = _procItems[_sidebarActiveIdx].name;
        activeInFiltered = items.indexWhere((e) => e.name == activeName);
      }
    }

    return Stack(
      children: [
        // ── Contenido del sidebar ──────────────────────────────────────────
        SizedBox(
          width: _sidebarWidth,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
              border: Border(right: BorderSide(color: cs.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Encabezado
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: cs.outlineVariant)),
                  ),
                  child: Row(children: [
                    Icon(Icons.account_tree_outlined,
                        size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Estructura',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      '${_procItems.length}',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ]),
                ),
                // Filtro
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: TextField(
                    controller: _sidebarFilterCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Filtrar...',
                      hintStyle: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                      prefixIcon: Icon(Icons.search,
                          size: 14, color: cs.onSurfaceVariant),
                      suffixIcon: _sidebarFilter.isNotEmpty
                          ? GestureDetector(
                              onTap: _sidebarFilterCtrl.clear,
                              child: Icon(Icons.close,
                                  size: 13, color: cs.onSurfaceVariant),
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                    ),
                  ),
                ),
                // Lista
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'Sin resultados',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.5)),
                          ),
                        )
                      : ListView.builder(
                          controller: _sidebarListCtrl,
                          itemCount: items.length,
                          itemExtent: 38,
                          itemBuilder: (_, i) {
                            final item = items[i];
                            final isActive = i == activeInFiltered;
                            final isProc = item.type == 'PROCEDURE';
                            final badgeColor = isProc
                                ? Colors.blue.shade600
                                : Colors.purple.shade600;

                            return GestureDetector(
                              onSecondaryTapUp: (d) => _showProcContextMenu(
                                  context, d.globalPosition, item),
                              child: Material(
                              color: isActive
                                  ? (isDark
                                      ? cs.primary.withValues(alpha: 0.18)
                                      : cs.primary.withValues(alpha: 0.10))
                                  : Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  if (_focusedProcName != null &&
                                      _focusedProcName != item.name) {
                                    // Cambiar foco al proc tocado
                                    _focusProc(item.name);
                                  }
                                  _diffCtrl.scrollToOrigLine(item.lineNum);
                                },
                                child: Container(
                                  decoration: isActive
                                      ? BoxDecoration(
                                          border: Border(
                                            left: BorderSide(
                                              color: cs.primary,
                                              width: 3,
                                            ),
                                          ),
                                        )
                                      : null,
                                  padding: EdgeInsets.fromLTRB(
                                    isActive ? 7 : 10, 0, 8, 0),
                                  child: Row(
                                    children: [
                                      // Badge tipo
                                      Container(
                                        width: 18,
                                        height: 16,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: badgeColor
                                              .withValues(alpha: isActive ? 0.25 : 0.12),
                                          borderRadius:
                                              BorderRadius.circular(3),
                                          border: Border.all(
                                            color: badgeColor
                                                .withValues(alpha: 0.6),
                                            width: 0.7,
                                          ),
                                        ),
                                        child: Text(
                                          isProc ? 'P' : 'F',
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // Nombre
                                      Expanded(
                                        child: Text(
                                          item.name,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'Consolas',
                                            fontWeight: isActive
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isActive
                                                ? cs.primary
                                                : (isDark
                                                    ? Colors.white70
                                                    : Colors.black87),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      // Número de línea
                                      Text(
                                        'L${item.lineNum}',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontFamily: 'Consolas',
                                          color: isActive
                                              ? cs.primary
                                                  .withValues(alpha: 0.7)
                                              : cs.onSurfaceVariant
                                                  .withValues(alpha: 0.45),
                                        ),
                                      ),
                                    ],
                                  ),       // Row
                                ),         // Container
                              ),           // InkWell
                            ),             // Material
                          );               // GestureDetector
                          },
                        ),
                ),
              ],
            ),
          ),
        ),

        // ── Handle de redimensionado (borde derecho) ───────────────────────
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 6,
          child: _ResizeHandle(
            onDrag: (dx) => setState(() {
              _sidebarWidth = (_sidebarWidth + dx).clamp(140.0, 480.0);
            }),
            color: cs.primary,
          ),
        ),
      ],
    );
  }

  // ── Panel de errores ───────────────────────────────────────────────────────

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
            child: Row(children: [
              Icon(Icons.error_outline, size: 13, color: errColor),
              const SizedBox(width: 6),
              Text('${_compilationErrors.length} error(es) de compilación',
                  style: TextStyle(
                      fontSize: 11,
                      color: errColor,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _compilationErrors = []),
                child: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
              ),
            ]),
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
                        child: Text('L${e.line}',
                            style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'Consolas',
                                color: isErr ? errColor : warnColor,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(e.text,
                            style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'Consolas',
                                color: isDark ? Colors.white70 : Colors.black87)),
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

  // ── Badge de ambiente ──────────────────────────────────────────────────────

  Widget _ambBadge(String amb, Color color, String role) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 0.8),
        ),
        child: Text(
          '$role · $amb',
          style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4),
        ),
      );
}

// ── Widget handle de redimensionado ───────────────────────────────────────────

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.onDrag, required this.color});
  final void Function(double dx) onDrag;
  final Color color;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 6,
          color: _hovering
              ? widget.color.withValues(alpha: 0.45)
              : Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _hovering ? 2 : 1,
              color: _hovering
                  ? widget.color
                  : widget.color.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}
