/// Native Flutter diff viewer.
///
/// Características:
/// – [itemExtent] fijo → scroll O(1) en archivos de 100 k+ líneas.
/// – Modo side-by-side con scroll sincronizado O modo unificado.
/// – Highlight intra-línea char-level para líneas modificadas.
/// – Secciones no modificadas colapsables (toca para expandir).
/// – [showAllLines] para alternar entre "solo diffs" y "código completo".
/// – Callbacks por línea para aplicar cambios bidireccionales.
library;

import 'dart:math' as math;

import 'package:diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════════════
// Public API
// ════════════════════════════════════════════════════════════════════════════

typedef DiffHunk = ({int origStart, int origEnd, int modStart, int modEnd});

/// Calcula hunks de diferencias a nivel de línea usando Unicode encoding.
List<DiffHunk> computeHunks(String orig, String mod) {
  if (orig == mod) return [];
  final oL = orig.split('\n');
  final mL = mod.split('\n');
  final idx = <String, int>{};
  int code(String s) => idx.putIfAbsent(s, () {
    final n = idx.length + 1;
    return n < 0xD800 ? n : n + 0x800;
  });
  final enc1 = String.fromCharCodes(oL.map(code));
  final enc2 = String.fromCharCodes(mL.map(code));
  final ds = dmp.diff(enc1, enc2, checklines: false, timeout: 0);
  final hunks = <DiffHunk>[];
  var o = 0, m = 0;
  for (final d in ds) {
    final n = d.text.length;
    if (d.operation == dmp.DIFF_EQUAL) {
      o += n;
      m += n;
    } else if (d.operation == dmp.DIFF_DELETE) {
      if (hunks.isNotEmpty &&
          hunks.last.origEnd == o &&
          hunks.last.modEnd == m) {
        final h = hunks.removeLast();
        o += n;
        hunks.add((
          origStart: h.origStart,
          origEnd: o,
          modStart: h.modStart,
          modEnd: m,
        ));
      } else {
        final s = o;
        o += n;
        hunks.add((origStart: s, origEnd: o, modStart: m, modEnd: m));
      }
    } else {
      if (hunks.isNotEmpty &&
          hunks.last.origEnd == o &&
          hunks.last.modEnd == m) {
        final h = hunks.removeLast();
        m += n;
        hunks.add((
          origStart: h.origStart,
          origEnd: o,
          modStart: h.modStart,
          modEnd: m,
        ));
      } else {
        final s = m;
        m += n;
        hunks.add((origStart: o, origEnd: o, modStart: s, modEnd: m));
      }
    }
  }
  return hunks;
}

/// Controla la navegación entre hunks del [NativeDiffViewer].
class NativeDiffController extends ChangeNotifier {
  int _cur = -1;
  int _tot = 0;

  int get currentHunk => _cur;
  int get totalHunks => _tot;
  bool get hasNext => _tot > 0 && _cur < _tot - 1;
  bool get hasPrev => _cur > 0;

  /// true = la próxima notificación debe hacer scroll al hunk actual.
  bool _scrollOnNotify = false;
  bool get scrollOnNotify => _scrollOnNotify;

  /// Línea de orig actualmente visible en el visor (1-based).
  /// Actualizada automáticamente al scrollear; escucharla con [ValueListenableBuilder].
  final visibleOrigLine = ValueNotifier<int>(1);

  /// Línea de orig (1-based) a la que scrollear. null = sin solicitud pendiente.
  int? _lineScrollRequest;
  int? get lineScrollRequest => _lineScrollRequest;

  void _init(int total) {
    _tot = total;
    _cur = total > 0 ? 0 : -1;
    _scrollOnNotify = false;
    notifyListeners();
  }

  void nextChange() {
    if (!hasNext) return;
    _cur++;
    _scrollOnNotify = true;
    notifyListeners();
  }

  void previousChange() {
    if (!hasPrev) return;
    _cur--;
    _scrollOnNotify = true;
    notifyListeners();
  }

  /// Solicita al viewer que scrollee hasta la línea [lineNum] (1-based, lado ORIGEN).
  void scrollToOrigLine(int lineNum) {
    _lineScrollRequest = lineNum;
    _scrollOnNotify = false;
    notifyListeners();
  }

  @override
  void dispose() {
    visibleOrigLine.dispose();
    super.dispose();
  }
}

/// Visor de diffs nativo, performante, con soporte para líneas individuales.
class NativeDiffViewer extends StatefulWidget {
  const NativeDiffViewer({
    super.key,
    required this.origText,
    required this.modText,
    required this.sideBySide,
    this.controller,
    this.showAllLines = false,
    this.lineOffset = 0,
    this.onApplyLineToTarget,
    this.onApplyLineToSource,
  });

  final String origText;
  final String modText;
  final bool sideBySide;
  final NativeDiffController? controller;

  /// false = colapsa líneas sin cambios (solo muestra diffs + contexto).
  /// true  = muestra el código fuente completo.
  final bool showAllLines;

  /// Offset sumado a todos los números de línea mostrados en el gutter.
  /// Útil cuando se pasa un fragmento: poner lineOffset = lineStart (0-based)
  /// para que los números reflejen la posición real en el archivo completo.
  final int lineOffset;

  /// Llamado cuando el usuario toca "→" en una fila del panel izquierdo.
  /// Parámetros: (hunkIdx, hunkRow) — posición 0-based dentro del hunk.
  final void Function(int hunkIdx, int hunkRow)? onApplyLineToTarget;

  /// Llamado cuando el usuario toca "←" en una fila del panel derecho.
  final void Function(int hunkIdx, int hunkRow)? onApplyLineToSource;

  @override
  State<NativeDiffViewer> createState() => _NativeDiffViewerState();
}

// ════════════════════════════════════════════════════════════════════════════
// Modelo interno
// ════════════════════════════════════════════════════════════════════════════

enum _K { equal, changed, collapsed }

class _SbsRow {
  const _SbsRow({
    required this.kind,
    this.left,
    this.right,
    this.leftNum,
    this.rightNum,
    this.hunkIdx = -1,
    this.hunkRow = -1,
    this.colCount = 0,
    this.colOrig = -1,
    this.colMod = -1,
  });
  final _K kind;
  final String? left;
  final String? right;
  final int? leftNum;
  final int? rightNum;
  final int hunkIdx;
  final int hunkRow; // posición 0-based dentro del hunk
  final int colCount;
  final int colOrig;
  final int colMod;
}

class _URow {
  const _URow({
    required this.kind,
    this.text,
    this.origNum,
    this.modNum,
    this.isAdded = false,
    this.hunkIdx = -1,
    this.colCount = 0,
    this.colOrig = -1,
    this.colMod = -1,
  });
  final _K kind;
  final String? text;
  final int? origNum;
  final int? modNum;
  final bool isAdded;
  final int hunkIdx;
  final int colCount;
  final int colOrig;
  final int colMod;
}

// ════════════════════════════════════════════════════════════════════════════
// Constructores de filas
// ════════════════════════════════════════════════════════════════════════════

const _kCtx = 4;

List<_SbsRow> _buildSbs(
  List<String> orig,
  List<String> mod,
  List<DiffHunk> hunks,
  Set<int> expanded,
  bool showAll,
  int lineOffset,
) {
  final rows = <_SbsRow>[];
  var oPos = 0, mPos = 0;

  void addEq(int oS, int mS, int count, bool isFirst, bool isLast) {
    if (count <= 0) return;
    final head = isFirst ? 0 : _kCtx;
    final tail = isLast ? 0 : _kCtx;
    final col = count - head - tail;
    if (showAll || hunks.isEmpty || col <= 0 || expanded.contains(oS + head)) {
      for (var i = 0; i < count; i++) {
        rows.add(
          _SbsRow(
            kind: _K.equal,
            left: orig[oS + i],
            right: mod[mS + i],
            leftNum: oS + i + 1 + lineOffset,
            rightNum: mS + i + 1 + lineOffset,
          ),
        );
      }
      return;
    }
    for (var i = 0; i < head; i++) {
      rows.add(
        _SbsRow(
          kind: _K.equal,
          left: orig[oS + i],
          right: mod[mS + i],
          leftNum: oS + i + 1 + lineOffset,
          rightNum: mS + i + 1 + lineOffset,
        ),
      );
    }
    rows.add(
      _SbsRow(
        kind: _K.collapsed,
        colCount: col,
        colOrig: oS + head,
        colMod: mS + head,
      ),
    );
    for (var i = count - tail; i < count; i++) {
      rows.add(
        _SbsRow(
          kind: _K.equal,
          left: orig[oS + i],
          right: mod[mS + i],
          leftNum: oS + i + 1 + lineOffset,
          rightNum: mS + i + 1 + lineOffset,
        ),
      );
    }
  }

  for (var hi = 0; hi < hunks.length; hi++) {
    final h = hunks[hi];
    addEq(oPos, mPos, h.origStart - oPos, hi == 0, false);
    final oC = h.origEnd - h.origStart;
    final mC = h.modEnd - h.modStart;
    for (var i = 0; i < math.max(oC, mC); i++) {
      rows.add(
        _SbsRow(
          kind: _K.changed,
          left: i < oC ? orig[h.origStart + i] : null,
          right: i < mC ? mod[h.modStart + i] : null,
          leftNum: i < oC ? h.origStart + i + 1 + lineOffset : null,
          rightNum: i < mC ? h.modStart + i + 1 + lineOffset : null,
          hunkIdx: hi,
          hunkRow: i,
        ),
      );
    }
    oPos = h.origEnd;
    mPos = h.modEnd;
  }
  addEq(oPos, mPos, orig.length - oPos, hunks.isEmpty, true);
  return rows;
}

List<_URow> _buildUnified(
  List<String> orig,
  List<String> mod,
  List<DiffHunk> hunks,
  Set<int> expanded,
  bool showAll,
  int lineOffset,
) {
  final rows = <_URow>[];
  var oPos = 0, mPos = 0;

  void addEq(int oS, int mS, int count, bool isFirst, bool isLast) {
    if (count <= 0) return;
    final head = isFirst ? 0 : _kCtx;
    final tail = isLast ? 0 : _kCtx;
    final col = count - head - tail;
    if (showAll || hunks.isEmpty || col <= 0 || expanded.contains(oS + head)) {
      for (var i = 0; i < count; i++) {
        rows.add(
          _URow(
            kind: _K.equal,
            text: orig[oS + i],
            origNum: oS + i + 1 + lineOffset,
            modNum: mS + i + 1 + lineOffset,
          ),
        );
      }
      return;
    }
    for (var i = 0; i < head; i++) {
      rows.add(
        _URow(
          kind: _K.equal,
          text: orig[oS + i],
          origNum: oS + i + 1 + lineOffset,
          modNum: mS + i + 1 + lineOffset,
        ),
      );
    }
    rows.add(
      _URow(
        kind: _K.collapsed,
        colCount: col,
        colOrig: oS + head,
        colMod: mS + head,
      ),
    );
    for (var i = count - tail; i < count; i++) {
      rows.add(
        _URow(
          kind: _K.equal,
          text: orig[oS + i],
          origNum: oS + i + 1 + lineOffset,
          modNum: mS + i + 1 + lineOffset,
        ),
      );
    }
  }

  for (var hi = 0; hi < hunks.length; hi++) {
    final h = hunks[hi];
    addEq(oPos, mPos, h.origStart - oPos, hi == 0, false);
    for (var i = h.origStart; i < h.origEnd; i++) {
      rows.add(
        _URow(
          kind: _K.changed,
          text: orig[i],
          origNum: i + 1 + lineOffset,
          hunkIdx: hi,
        ),
      );
    }
    for (var i = h.modStart; i < h.modEnd; i++) {
      rows.add(
        _URow(
          kind: _K.changed,
          text: mod[i],
          modNum: i + 1 + lineOffset,
          hunkIdx: hi,
          isAdded: true,
        ),
      );
    }
    oPos = h.origEnd;
    mPos = h.modEnd;
  }
  addEq(oPos, mPos, orig.length - oPos, hunks.isEmpty, true);
  return rows;
}

// ════════════════════════════════════════════════════════════════════════════
// State
// ════════════════════════════════════════════════════════════════════════════

const double _kLineH = 22;
const _kFont = TextStyle(fontFamily: 'Consolas', fontSize: 12, height: 1.1);

class _NativeDiffViewerState extends State<NativeDiffViewer> {
  late List<String> _oLines, _mLines;
  late List<DiffHunk> _hunks;
  late List<_SbsRow> _sbs;
  late List<_URow> _unified;
  late List<int> _sbsHunkRow;
  late List<int> _uHunkRow;
  final _expanded = <int>{};
  final _lCtrl = ScrollController();
  final _rCtrl = ScrollController();
  final _uCtrl = ScrollController();
  bool _syncLock = false;

  @override
  void initState() {
    super.initState();
    _lCtrl.addListener(_syncR);
    _lCtrl.addListener(_reportVisibleLineSbs);
    _rCtrl.addListener(_syncL);
    _uCtrl.addListener(_reportVisibleLineUnified);
    _fullRebuild();
    widget.controller?.addListener(_onCtrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller?._init(_hunks.length);
    });
  }

  /// Notifica al controlador qué línea de ORIGEN es visible (SBS, panel izq).
  void _reportVisibleLineSbs() {
    final ctrl = widget.controller;
    if (ctrl == null || !_lCtrl.hasClients || _sbs.isEmpty) return;
    final rowIdx = (_lCtrl.offset / _kLineH).floor().clamp(0, _sbs.length - 1);
    for (var i = rowIdx; i >= 0; i--) {
      final ln = _sbs[i].leftNum;
      if (ln != null) {
        ctrl.visibleOrigLine.value = ln;
        return;
      }
    }
  }

  /// Notifica al controlador qué línea de ORIGEN es visible (unified).
  void _reportVisibleLineUnified() {
    final ctrl = widget.controller;
    if (ctrl == null || !_uCtrl.hasClients || _unified.isEmpty) return;
    final rowIdx = (_uCtrl.offset / _kLineH).floor().clamp(
      0,
      _unified.length - 1,
    );
    for (var i = rowIdx; i >= 0; i--) {
      final ln = _unified[i].origNum;
      if (ln != null) {
        ctrl.visibleOrigLine.value = ln;
        return;
      }
    }
  }

  void _syncR() {
    if (_syncLock || !_rCtrl.hasClients || !_lCtrl.hasClients) return;
    _syncLock = true;
    _rCtrl.jumpTo(_lCtrl.offset.clamp(0.0, _rCtrl.position.maxScrollExtent));
    _syncLock = false;
  }

  void _syncL() {
    if (_syncLock || !_lCtrl.hasClients || !_rCtrl.hasClients) return;
    _syncLock = true;
    _lCtrl.jumpTo(_rCtrl.offset.clamp(0.0, _lCtrl.position.maxScrollExtent));
    _syncLock = false;
  }

  void _onCtrl() {
    if (!mounted) return;
    // ¿Solicitud de scroll a línea específica?
    final lineReq = widget.controller?.lineScrollRequest;
    if (lineReq != null) {
      widget.controller!._lineScrollRequest = null;
      _scrollToOrigLineInView(lineReq);
    }
    setState(() {});
    // Scroll a hunk solo en navegación explícita (next/previous).
    if (widget.controller?._scrollOnNotify == true) {
      widget.controller!._scrollOnNotify = false;
      _scrollToCurrentHunk();
    }
  }

  /// Scrollea al primer row que tiene [origLineNum] en el lado izquierdo (SBS)
  /// o como número de línea orig (unified).
  void _scrollToOrigLineInView(int origLineNum) {
    if (widget.sideBySide) {
      for (var i = 0; i < _sbs.length; i++) {
        if (_sbs[i].leftNum == origLineNum || _sbs[i].rightNum == origLineNum) {
          final off = i * _kLineH;
          _goto(_lCtrl, off);
          _goto(_rCtrl, off);
          return;
        }
      }
    } else {
      for (var i = 0; i < _unified.length; i++) {
        if (_unified[i].origNum == origLineNum) {
          _goto(_uCtrl, i * _kLineH);
          return;
        }
      }
    }
  }

  void _scrollToCurrentHunk() {
    final hi = widget.controller?.currentHunk ?? -1;
    if (hi < 0) return;
    if (widget.sideBySide) {
      if (hi < _sbsHunkRow.length && _sbsHunkRow[hi] >= 0) {
        final off = _sbsHunkRow[hi] * _kLineH;
        _goto(_lCtrl, off);
        _goto(_rCtrl, off);
      }
    } else {
      if (hi < _uHunkRow.length && _uHunkRow[hi] >= 0) {
        _goto(_uCtrl, _uHunkRow[hi] * _kLineH);
      }
    }
  }

  void _goto(ScrollController c, double off) {
    if (!c.hasClients) return;
    c.animateTo(
      off.clamp(0.0, c.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _fullRebuild() {
    _oLines = widget.origText.split('\n');
    _mLines = widget.modText.split('\n');
    _hunks = computeHunks(widget.origText, widget.modText);
    _rowsRebuild();
  }

  void _rowsRebuild() {
    _sbs = _buildSbs(
      _oLines,
      _mLines,
      _hunks,
      _expanded,
      widget.showAllLines,
      widget.lineOffset,
    );
    _unified = _buildUnified(
      _oLines,
      _mLines,
      _hunks,
      _expanded,
      widget.showAllLines,
      widget.lineOffset,
    );
    _sbsHunkRow = List.filled(_hunks.length, -1);
    for (var i = 0; i < _sbs.length; i++) {
      final hi = _sbs[i].hunkIdx;
      if (hi >= 0 && _sbsHunkRow[hi] == -1) _sbsHunkRow[hi] = i;
    }
    _uHunkRow = List.filled(_hunks.length, -1);
    for (var i = 0; i < _unified.length; i++) {
      final hi = _unified[i].hunkIdx;
      if (hi >= 0 && _uHunkRow[hi] == -1) _uHunkRow[hi] = i;
    }
  }

  void _expand(int colOrig) {
    _expanded.add(colOrig);
    setState(_rowsRebuild);
  }

  @override
  void didUpdateWidget(NativeDiffViewer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onCtrl);
      widget.controller?.addListener(_onCtrl);
    }
    if (old.origText != widget.origText || old.modText != widget.modText) {
      _expanded.clear();
      setState(_fullRebuild);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller?._init(_hunks.length);
      });
    } else if (old.sideBySide != widget.sideBySide ||
        old.showAllLines != widget.showAllLines ||
        old.lineOffset != widget.lineOffset) {
      setState(_rowsRebuild);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onCtrl);
    _lCtrl.dispose();
    _rCtrl.dispose();
    _uCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cur = widget.controller?.currentHunk ?? -1;
    return widget.sideBySide
        ? _buildSbs2(dark, cur)
        : _buildUnified2(dark, cur);
  }

  // ── Side-by-side ───────────────────────────────────────────────────────────

  Widget _buildSbs2(bool dark, int cur) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: _panel(dark, cur, isLeft: true)),
      Container(
        width: 1,
        color: dark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE),
      ),
      Expanded(child: _panel(dark, cur, isLeft: false)),
    ],
  );

  Widget _panel(bool dark, int cur, {required bool isLeft}) => ListView.builder(
    controller: isLeft ? _lCtrl : _rCtrl,
    itemCount: _sbs.length,
    itemExtent: _kLineH,
    itemBuilder: (_, i) => _sbsCell(_sbs[i], isLeft, dark, cur),
  );

  Widget _sbsCell(_SbsRow row, bool isLeft, bool dark, int cur) {
    if (row.kind == _K.collapsed)
      return _collapsedCell(row.colCount, row.colOrig, dark);

    final text = isLeft ? row.left : row.right;
    final num = isLeft ? row.leftNum : row.rightNum;
    final isChanged = row.kind == _K.changed;
    final isCurrent = isChanged && row.hunkIdx == cur;
    final hasSide = text != null;

    Color? bg;
    Color lnBg;
    if (isChanged) {
      if (isLeft) {
        bg = hasSide
            ? (dark ? const Color(0xFF3D1C1C) : const Color(0xFFFFEBEB))
            : (dark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA));
        lnBg = hasSide
            ? (dark ? const Color(0xFF5C2020) : const Color(0xFFFFD0D0))
            : (dark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA));
      } else {
        bg = hasSide
            ? (dark ? const Color(0xFF1C3D1C) : const Color(0xFFEBFFEB))
            : (dark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA));
        lnBg = hasSide
            ? (dark ? const Color(0xFF205C20) : const Color(0xFFD0FFD0))
            : (dark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA));
      }
    } else {
      bg = null;
      lnBg = dark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
    }

    final showBtn =
        isChanged &&
        hasSide &&
        (isLeft
            ? widget.onApplyLineToTarget != null
            : widget.onApplyLineToSource != null);

    // Botón dentro del gutter: nunca solapa el scrollbar ni el contenido.
    // Left panel → botón verde "→" en el borde derecho del gutter.
    // Right panel → botón naranja "←" en el borde derecho del gutter.
    final lnNumStyle = TextStyle(
      fontFamily: 'Consolas',
      fontSize: 10,
      height: 1.0,
      color: dark ? const Color(0xFF6E7681) : const Color(0xFF6E7781),
    );

    Widget gutter = Container(
      width: 44,
      color: lnBg,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                num != null ? '$num' : '',
                textAlign: TextAlign.right,
                style: lnNumStyle,
              ),
            ),
          ),
          if (showBtn)
            GestureDetector(
              onTap: () => isLeft
                  ? widget.onApplyLineToTarget!(row.hunkIdx, row.hunkRow)
                  : widget.onApplyLineToSource!(row.hunkIdx, row.hunkRow),
              child: Container(
                width: 13,
                height: double.infinity,
                color: (isLeft ? Colors.green.shade700 : Colors.orange.shade700)
                    .withValues(alpha: 0.85),
                child: Icon(
                  isLeft ? Icons.arrow_forward : Icons.arrow_back,
                  size: 9,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: isCurrent
            ? Border(
                left: BorderSide(
                  color: Colors.blue.shade400,
                  width: isLeft ? 3 : 0,
                ),
                right: BorderSide(
                  color: Colors.blue.shade400,
                  width: isLeft ? 0 : 3,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          gutter,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: text != null
                  ? _lineContent(
                      text: text,
                      other: isLeft ? row.right : row.left,
                      showLeft: isLeft,
                      isChanged: isChanged,
                      dark: dark,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Unified ────────────────────────────────────────────────────────────────

  Widget _buildUnified2(bool dark, int cur) => ListView.builder(
    controller: _uCtrl,
    itemCount: _unified.length,
    itemExtent: _kLineH,
    itemBuilder: (_, i) => _uCell(_unified[i], dark, cur),
  );

  Widget _uCell(_URow row, bool dark, int cur) {
    if (row.kind == _K.collapsed)
      return _collapsedCell(row.colCount, row.colOrig, dark);

    final isCurrent = row.hunkIdx >= 0 && row.hunkIdx == cur;
    final isChanged = row.kind == _K.changed;
    Color? bg;
    Color lnBg;
    String sign;
    Color signColor;

    if (isChanged) {
      if (row.isAdded) {
        bg = dark ? const Color(0xFF1C3D1C) : const Color(0xFFEBFFEB);
        lnBg = dark ? const Color(0xFF205C20) : const Color(0xFFD0FFD0);
        sign = '+';
        signColor = dark ? Colors.green.shade400 : Colors.green.shade700;
      } else {
        bg = dark ? const Color(0xFF3D1C1C) : const Color(0xFFFFEBEB);
        lnBg = dark ? const Color(0xFF5C2020) : const Color(0xFFFFD0D0);
        sign = '−';
        signColor = dark ? Colors.red.shade400 : Colors.red.shade700;
      }
    } else {
      bg = null;
      lnBg = dark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
      sign = ' ';
      signColor = Colors.transparent;
    }

    final lnC = dark ? const Color(0xFF6E7681) : const Color(0xFF6E7781);
    final lnStyle = TextStyle(
      fontFamily: 'Consolas',
      fontSize: 10,
      height: 1.0,
      color: lnC,
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: isCurrent
            ? Border(left: BorderSide(color: Colors.blue.shade400, width: 3))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            alignment: Alignment.centerRight,
            color: lnBg,
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              row.origNum != null ? '${row.origNum}' : '',
              style: lnStyle,
            ),
          ),
          Container(
            width: 36,
            alignment: Alignment.centerRight,
            color: lnBg,
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              row.modNum != null ? '${row.modNum}' : '',
              style: lnStyle,
            ),
          ),
          SizedBox(
            width: 16,
            child: Text(
              sign,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                height: 1.0,
                color: signColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                row.text ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _kFont.copyWith(
                  color: dark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Collapsed ──────────────────────────────────────────────────────────────

  Widget _collapsedCell(int count, int colOrig, bool dark) {
    final bg = dark ? const Color(0xFF21262D) : const Color(0xFFF1F8FF);
    final fg = dark ? const Color(0xFF8B949E) : const Color(0xFF57606A);
    return GestureDetector(
      onTap: () => _expand(colOrig),
      child: Container(
        color: bg,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.unfold_more, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              '$count líneas sin cambios — toca para expandir',
              style: TextStyle(
                fontSize: 11,
                color: fg,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Intra-line char diff ───────────────────────────────────────────────────

  Widget _lineContent({
    required String text,
    required String? other,
    required bool showLeft,
    required bool isChanged,
    required bool dark,
  }) {
    final base = _kFont.copyWith(color: dark ? Colors.white70 : Colors.black87);
    if (!isChanged || other == null || text.length + other.length > 600) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    final left = showLeft ? text : other;
    final right = showLeft ? other : text;
    final ds = dmp.diff(left, right, timeout: 0.5);
    final spans = <InlineSpan>[];
    for (final d in ds) {
      if (d.operation == dmp.DIFF_EQUAL) {
        spans.add(TextSpan(text: d.text, style: base));
      } else if (showLeft && d.operation == dmp.DIFF_DELETE) {
        spans.add(
          TextSpan(
            text: d.text,
            style: base.copyWith(
              backgroundColor: dark
                  ? const Color(0xFF7A2020)
                  : const Color(0xFFFFAAAF),
              color: dark ? Colors.red.shade200 : Colors.red.shade900,
            ),
          ),
        );
      } else if (!showLeft && d.operation == dmp.DIFF_INSERT) {
        spans.add(
          TextSpan(
            text: d.text,
            style: base.copyWith(
              backgroundColor: dark
                  ? const Color(0xFF207A20)
                  : const Color(0xFFAAFFAA),
              color: dark ? Colors.green.shade200 : Colors.green.shade900,
            ),
          ),
        );
      }
    }
    if (spans.isEmpty)
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    return RichText(
      text: TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
