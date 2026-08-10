import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;
import '../services/schema_service.dart';
import '_editor_plsql_checker.dart';
import '_editor_plsql_completions.dart';
import '_editor_themes.dart';
import 'app_toast.dart';
import 'status_card.dart';

const kTypeColors = {
  'TABLE': Color(0xFF0078D4),
  'VIEW': Color(0xFF107C10),
  'PROCEDURE': Color(0xFFCA5010),
  'FUNCTION': Color(0xFF8764B8),
  'PACKAGE': Color(0xFFC19C00),
  'TYPE': Color(0xFF2E7D9E),
};

const kTypeIcons = {
  'TABLE': Icons.table_chart_outlined,
  'VIEW': Icons.visibility_outlined,
  'PROCEDURE': Icons.code_rounded,
  'FUNCTION': Icons.functions_rounded,
  'PACKAGE': Icons.inventory_2_outlined,
  'TYPE': Icons.data_object_outlined,
};

enum _ViewerCompileStatus { idle, compiling, ok, error }

// Shared across all editor instances — avoids re-reading the asset each time
String? _cachedAntlrJs;

class ObjectSourcePage extends StatefulWidget {
  final String name;
  final String objectType; // PROCEDURE | FUNCTION | PACKAGE | VIEW | TYPE
  final String ambiente;

  /// When true, renders content without a Scaffold (for embedding in a float window).
  final bool embedded;

  const ObjectSourcePage({
    super.key,
    required this.name,
    required this.objectType,
    required this.ambiente,
    this.embedded = false,
  });

  @override
  State<ObjectSourcePage> createState() => _ObjectSourcePageState();
}

class _ObjectSourcePageState extends State<ObjectSourcePage>
    with SingleTickerProviderStateMixin {
  TabController? _tabCtrl;
  ({String spec, String? body})? _data;
  Object? _error;

  // single shared controller — multi-doc for packages/types, single-doc for others
  fm.MonacoController? _specCtrl;
  String _specText = '';
  String _bodyText = '';
  int _specErrors = 0;
  int _bodyErrors = 0;

  _ViewerCompileStatus _compileStatus = _ViewerCompileStatus.idle;
  bool _minimap = true;
  bool _wordWrap = false;
  double _fontSize = 14;
  bool _showProblems = false;
  bool _showPackageNav = true;
  String? _activeSubprogram;
  List<PlSqlIssue> _specIssues = [];
  List<PlSqlIssue> _bodyIssues = [];
  List<PlSqlIssue> _specCompileIssues = [];
  List<PlSqlIssue> _bodyCompileIssues = [];
  List<({String name, String kind, int line})> _subprograms = [];
  List<({String name, String kind, int line})> _specSubprograms = [];
  final TextEditingController _navSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    SchemaService.instance
        .getObjectSource(
          widget.name,
          widget.objectType,
          ambiente: widget.ambiente,
        )
        .then((data) {
          if (!mounted) return;
          setState(() {
            _data = data;
            if (data.body != null) {
              _tabCtrl = TabController(length: 2, vsync: this);
            }
          });
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    _navSearchCtrl.dispose();
    super.dispose();
  }

  void _copyCurrentSource() {
    final text = (_tabCtrl?.index == 1 && _bodyText.isNotEmpty)
        ? _bodyText
        : _specText;
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    AppToast.info(
      'Fuente copiado al portapapeles',
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _compile() async {
    final isBody = _tabCtrl?.index == 1;
    final ctrl = _specCtrl; // shared controller handles both documents
    final text = isBody ? _bodyText : _specText;
    // PACKAGE BODY needs different objectType for USER_ERRORS query
    final objType = (isBody && widget.objectType == 'PACKAGE')
        ? 'PACKAGE BODY'
        : widget.objectType;

    if (text.isEmpty || ctrl == null) return;
    setState(() {
      _compileStatus = _ViewerCompileStatus.compiling;
      if (isBody) {
        _bodyCompileIssues = [];
      } else {
        _specCompileIssues = [];
      }
    });
    try {
      final errors = await SchemaService.instance.compileObject(
        text,
        widget.name,
        objType,
        ambiente: widget.ambiente,
      );
      await ctrl.document.clearMarkers(owner: 'oracle-compile');
      if (errors.isNotEmpty) {
        await ctrl.document.setMarkers([
          for (final e in errors)
            fm.MarkerData(
              range: fm.Range(
                startLine: e.line,
                startColumn: e.position,
                endLine: e.line,
                endColumn: e.position + 1,
              ),
              message: e.text,
              severity: e.attribute == 'ERROR'
                  ? fm.MarkerSeverity.error
                  : fm.MarkerSeverity.warning,
              source: 'Oracle',
            ),
        ], owner: 'oracle-compile');
      }
      final compileIssues = errors
          .map(
            (e) => PlSqlIssue(
              line: e.line,
              col: e.position,
              endCol: e.position + 1,
              message: e.text,
              severity: e.attribute == 'ERROR'
                  ? fm.MarkerSeverity.error
                  : fm.MarkerSeverity.warning,
              source: 'Oracle',
            ),
          )
          .toList();
      if (mounted) {
        setState(() {
          if (isBody) {
            _bodyCompileIssues = compileIssues;
          } else {
            _specCompileIssues = compileIssues;
          }
          _compileStatus = errors.isEmpty
              ? _ViewerCompileStatus.ok
              : _ViewerCompileStatus.error;
          if (errors.isNotEmpty) _showProblems = true;
        });
        if (errors.isEmpty) {
          AppToast.success('${widget.name} compilado exitosamente');
        } else {
          AppToast.error(
            '${widget.name}: ${errors.length} error(es) de compilación',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _compileStatus = _ViewerCompileStatus.error);
        AppToast.error('Error: $e');
      }
    }
  }

  void _triggerFind() {
    _specCtrl?.runJavaScript(
      'try{editor.getAction("actions.find").run();}catch(e){}',
    );
  }

  // Parses PROCEDURE/FUNCTION declarations with their 1-based line numbers.
  List<({String name, String kind, int line})> _parseSubprograms(String text) {
    final result = <({String name, String kind, int line})>[];
    final lines = text.split('\n');
    final re = RegExp(
      r'^\s*(PROCEDURE|FUNCTION)\s+(\w+)',
      caseSensitive: false,
    );
    for (var i = 0; i < lines.length; i++) {
      final m = re.firstMatch(lines[i]);
      if (m != null) {
        result.add((
          name: m.group(2)!,
          kind: m.group(1)!.toUpperCase(),
          line: i + 1,
        ));
      }
    }
    return result;
  }

  List<PlSqlIssue> get _allActiveIssues {
    final isBody = _tabCtrl?.index == 1;
    final syntax = isBody ? _bodyIssues : _specIssues;
    final compile = isBody ? _bodyCompileIssues : _specCompileIssues;
    return [...compile, ...syntax]..sort((a, b) => a.line.compareTo(b.line));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasTabs = _tabCtrl != null;
    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);
    final typeIcon = kTypeIcons[widget.objectType] ?? Icons.code_rounded;

    if (widget.embedded) return _buildEmbedded(isDark, hasTabs);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Icon(typeIcon, color: Colors.white, size: 20),
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Consolas',
                    ),
                  ),
                  Text(
                    _typeLabel(widget.objectType),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.ambiente,
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: typeColor,
        foregroundColor: Colors.white,
        bottom: hasTabs
            ? PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: ColoredBox(
                  color: isDark
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFFF5F7FA),
                  child: TabBar(
                    controller: _tabCtrl,
                    tabs: [
                      _TabWithBadge('Especificación', errorCount: _specErrors),
                      _TabWithBadge('Cuerpo', errorCount: _bodyErrors),
                    ],
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 13),
                    indicatorColor: typeColor,
                    labelColor: typeColor,
                    unselectedLabelColor: isDark
                        ? Colors.white54
                        : Colors.black54,
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          _buildViewToolbar(isDark),
          Expanded(
            child: Stack(
              children: [
                _buildBody(isDark),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _data == null ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: _data != null,
                      child: const StatusCard(message: 'Cargando fuente...'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildStatusBar(isDark),
          _buildProblemsPanel(isDark),
        ],
      ),
    );
  }

  // Embedded layout (no Scaffold) — used by the floating source window.
  Widget _buildEmbedded(bool isDark, bool hasTabs) {
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);
    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);
    return Column(
      children: [
        // Header with tabs and action buttons
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              if (hasTabs)
                Expanded(
                  child: TabBar(
                    controller: _tabCtrl,
                    tabs: [
                      _TabWithBadge(
                        'Especificación',
                        errorCount: _specErrors,
                        compact: true,
                      ),
                      _TabWithBadge(
                        'Cuerpo',
                        errorCount: _bodyErrors,
                        compact: true,
                      ),
                    ],
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 12),
                    indicatorColor: typeColor,
                    labelColor: typeColor,
                    unselectedLabelColor: isDark
                        ? Colors.white54
                        : Colors.black54,
                    indicatorSize: TabBarIndicatorSize.label,
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                )
              else
                const Spacer(),
              if (_data != null) ...[
                IconButton(
                  tooltip: 'Copiar fuente',
                  icon: const Icon(Icons.content_copy_outlined, size: 16),
                  onPressed: _copyCurrentSource,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  tooltip: 'Buscar (Ctrl+F)',
                  icon: const Icon(Icons.search_rounded, size: 16),
                  onPressed: _triggerFind,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                _buildCompileBtn(compact: true),
              ],
            ],
          ),
        ),
        _buildViewToolbar(isDark),
        Expanded(
          child: Stack(
            children: [
              _buildBody(isDark),
              Positioned(
                left: 12,
                bottom: 12,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _data == null ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: _data != null,
                    child: const StatusCard(message: 'Cargando fuente...'),
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildStatusBar(isDark),
        _buildProblemsPanel(isDark),
      ],
    );
  }

  Widget _buildBody(bool isDark) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(
                _error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_data == null) {
      return const SizedBox.expand();
    }

    if (_tabCtrl != null) {
      final editor = _MultiDocSourceEditor(
        spec: _data!.spec,
        body: _data!.body,
        isDark: isDark,
        ambiente: widget.ambiente,
        isPlSql: widget.objectType != 'VIEW',
        tabCtrl: _tabCtrl!,
        minimap: _minimap,
        wordWrap: _wordWrap,
        fontSize: _fontSize,
        onControllerReady: (c) => setState(() {
          _specCtrl = c;
          _specText = _data!.spec;
          _bodyText = _data!.body ?? '';
          _subprograms = _parseSubprograms(_data!.body ?? '');
          _specSubprograms = _parseSubprograms(_data!.spec);
        }),
        onSpecTextChanged: (t) {
          _specText = t;
          _specSubprograms = _parseSubprograms(t);
        },
        onBodyTextChanged: (t) {
          _bodyText = t;
          final parsed = _parseSubprograms(t);
          if (parsed.length != _subprograms.length) {
            setState(() => _subprograms = parsed);
          } else {
            _subprograms = parsed;
          }
        },
        onSpecErrorsChanged: (n) => setState(() => _specErrors = n),
        onBodyErrorsChanged: (n) => setState(() => _bodyErrors = n),
        onSpecIssuesChanged: (issues) => setState(() => _specIssues = issues),
        onBodyIssuesChanged: (issues) => setState(() => _bodyIssues = issues),
      );
      final showNav = _showPackageNav && _subprograms.isNotEmpty;
      return Row(
        children: [
          if (showNav) _buildPackageNav(isDark),
          Expanded(child: editor),
        ],
      );
    }

    return _MonacoSourceTab(
      source: _data!.spec,
      isDark: isDark,
      ambiente: widget.ambiente,
      isPlSql: widget.objectType != 'VIEW',
      minimap: _minimap,
      wordWrap: _wordWrap,
      fontSize: _fontSize,
      onControllerReady: (c) => setState(() {
        _specCtrl = c;
        _specText = _data!.spec;
      }),
      onTextChanged: (t) => _specText = t,
      onErrorCountChanged: (n) => setState(() => _specErrors = n),
      onIssuesChanged: (issues) => setState(() => _specIssues = issues),
    );
  }

  Widget _buildPackageNav(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);
    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);
    final query = _navSearchCtrl.text.toLowerCase();
    final filtered = query.isEmpty
        ? _subprograms
        : _subprograms
              .where((s) => s.name.toLowerCase().contains(query))
              .toList();

    void navigateTo(({String name, String kind, int line}) sub) {
      final onSpec = _tabCtrl == null || _tabCtrl!.index == 0;
      final targetLine = onSpec
          ? (_specSubprograms
                    .where(
                      (s) => s.name.toUpperCase() == sub.name.toUpperCase(),
                    )
                    .firstOrNull
                    ?.line ??
                sub.line)
          : sub.line;

      _specCtrl?.revealLine(targetLine, center: true);
      // Select the full declaration line so it's visually highlighted
      _specCtrl?.runJavaScript(
        'try{'
        'var m=editor.getModel();'
        'editor.setSelection({'
        'startLineNumber:$targetLine,startColumn:1,'
        'endLineNumber:$targetLine,endColumn:m.getLineMaxColumn($targetLine)'
        '});'
        '}catch(e){}',
      );
      setState(() => _activeSubprogram = sub.name);
    }

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1F22) : cs.surfaceContainerLow,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: isDark
                ? const Color(0xFF252526)
                : cs.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 13, color: typeColor),
                const SizedBox(width: 6),
                Text(
                  'Subprogramas',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${filtered.length}/${_subprograms.length}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _navSearchCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
                decoration: InputDecoration(
                  hintText: 'Filtrar…',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  suffixIcon: _navSearchCtrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _navSearchCtrl.clear();
                            setState(() {});
                          },
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 28,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF2D2D30)
                      : cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: cs.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: typeColor, width: 1.2),
                  ),
                ),
              ),
            ),
          ),
          // List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'Sin resultados',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final sub = filtered[i];
                      final isProcedure = sub.kind == 'PROCEDURE';
                      final kindColor = isProcedure
                          ? const Color(0xFFCA5010)
                          : const Color(0xFF8764B8);
                      final isActive = _activeSubprogram == sub.name;
                      return InkWell(
                        onTap: () => navigateTo(sub),
                        mouseCursor: SystemMouseCursors.click,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: isActive
                                ? kindColor.withValues(alpha: 0.12)
                                : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: isActive
                                    ? kindColor
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            isActive ? 6 : 8,
                            5,
                            8,
                            5,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 16,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: kindColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  isProcedure ? 'P' : 'F',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: kindColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Tooltip(
                                  message: sub.name,
                                  waitDuration: const Duration(
                                    milliseconds: 600,
                                  ),
                                  child: Text(
                                    sub.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'Consolas',
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              Text(
                                '${sub.line}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: isActive ? 0.8 : 0.5,
                                  ),
                                  fontFamily: 'Consolas',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToolbar(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);
    final issues = _allActiveIssues;
    final errCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.error)
        .length;
    final warnCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.warning)
        .length;
    final isPackage =
        widget.objectType == 'PACKAGE' || widget.objectType == 'TYPE';
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          // ── Vista ──────────────────────────────────────────────────────────
          if (isPackage)
            _ViewerToggleBtn(
              icon: Icons.account_tree_outlined,
              tooltip: 'Navegador de subprogramas',
              active: _showPackageNav,
              onPressed: () =>
                  setState(() => _showPackageNav = !_showPackageNav),
            ),
          _ViewerToggleBtn(
            icon: Icons.map_outlined,
            tooltip: 'Minimap',
            active: _minimap,
            onPressed: () {
              setState(() => _minimap = !_minimap);
              _specCtrl?.runJavaScript(
                'try{window.flutterMonaco.updateOptions({minimap:{enabled:$_minimap}});}catch(e){}',
              );
            },
          ),
          _ViewerToggleBtn(
            icon: Icons.wrap_text_rounded,
            tooltip: 'Ajustar líneas',
            active: _wordWrap,
            onPressed: () {
              setState(() => _wordWrap = !_wordWrap);
              final v = _wordWrap ? 'on' : 'off';
              _specCtrl?.runJavaScript(
                'try{window.flutterMonaco.updateOptions({wordWrap:"$v"});}catch(e){}',
              );
            },
          ),
          const SizedBox(width: 4),
          _buildFontSizePill(cs),
          const SizedBox(width: 4),
          SizedBox(
            height: 16,
            child: VerticalDivider(color: cs.outlineVariant, width: 10),
          ),
          // ── Acciones ───────────────────────────────────────────────────────
          _ViewerIconBtn(
            icon: Icons.search_rounded,
            tooltip: 'Buscar (Ctrl+F)',
            onPressed: _triggerFind,
          ),
          if (_data != null) ...[
            _ViewerIconBtn(
              icon: Icons.content_copy_outlined,
              tooltip: 'Copiar fuente',
              onPressed: _copyCurrentSource,
            ),
            SizedBox(
              height: 16,
              child: VerticalDivider(color: cs.outlineVariant, width: 10),
            ),
          ],
          const Spacer(),
          // ── Errores + Compilar ─────────────────────────────────────────────
          if (errCount > 0 || warnCount > 0)
            GestureDetector(
              onTap: () => setState(() => _showProblems = !_showProblems),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: errCount > 0
                      ? Colors.red.shade400.withValues(alpha: 0.12)
                      : Colors.orange.shade400.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (errCount > 0) ...[
                      Icon(
                        Icons.error_outline,
                        size: 13,
                        color: Colors.red.shade400,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$errCount',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade400,
                        ),
                      ),
                    ],
                    if (errCount > 0 && warnCount > 0) const SizedBox(width: 6),
                    if (warnCount > 0) ...[
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 13,
                        color: Colors.orange.shade400,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$warnCount',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_data != null) _buildCompileBtn(),
        ],
      ),
    );
  }

  Widget _buildFontSizePill(ColorScheme cs) {
    return Container(
      height: 22,
      decoration: BoxDecoration(
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.7),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _fontSize > 10
                ? () {
                    setState(() => _fontSize = (_fontSize - 2).clamp(10, 28));
                    _specCtrl?.runJavaScript(
                      'try{window.flutterMonaco.updateOptions({fontSize:${_fontSize.toInt()}});}catch(e){}',
                    );
                  }
                : null,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(11),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: Icon(
                Icons.remove,
                size: 12,
                color: _fontSize > 10
                    ? cs.onSurfaceVariant
                    : cs.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          Text(
            '${_fontSize.toInt()}',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          InkWell(
            onTap: _fontSize < 28
                ? () {
                    setState(() => _fontSize = (_fontSize + 2).clamp(10, 28));
                    _specCtrl?.runJavaScript(
                      'try{window.flutterMonaco.updateOptions({fontSize:${_fontSize.toInt()}});}catch(e){}',
                    );
                  }
                : null,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(11),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: Icon(
                Icons.add,
                size: 12,
                color: _fontSize < 28
                    ? cs.onSurfaceVariant
                    : cs.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompileBtn({bool compact = false}) {
    final size = compact ? 18.0 : 22.0;
    return switch (_compileStatus) {
      _ViewerCompileStatus.idle => IconButton(
        tooltip: 'Compilar',
        icon: Icon(Icons.play_arrow_rounded, size: size),
        onPressed: _compile,
        padding: compact ? EdgeInsets.zero : null,
        constraints: compact
            ? const BoxConstraints(minWidth: 32, minHeight: 32)
            : null,
        color: compact ? const Color(0xFF0078D4) : null,
      ),
      _ViewerCompileStatus.compiling => Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 12),
        child: SizedBox(
          width: compact ? 14 : 18,
          height: compact ? 14 : 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: compact ? const Color(0xFF0078D4) : Colors.white,
          ),
        ),
      ),
      _ViewerCompileStatus.ok => IconButton(
        tooltip: 'Compilado — compilar de nuevo',
        icon: Icon(
          Icons.check_circle_outline,
          size: size,
          color: const Color(0xFF4CAF50),
        ),
        onPressed: _compile,
        padding: compact ? EdgeInsets.zero : null,
        constraints: compact
            ? const BoxConstraints(minWidth: 32, minHeight: 32)
            : null,
      ),
      _ViewerCompileStatus.error => IconButton(
        tooltip: 'Compilación falló — compilar de nuevo',
        icon: Icon(Icons.error_outline, size: size, color: Colors.orange),
        onPressed: _compile,
        padding: compact ? EdgeInsets.zero : null,
        constraints: compact
            ? const BoxConstraints(minWidth: 32, minHeight: 32)
            : null,
      ),
    };
  }

  Widget _buildStatusBar(bool isDark) {
    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark
            ? typeColor.withValues(alpha: 0.1)
            : typeColor.withValues(alpha: 0.06),
        border: Border(top: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _typeLabel(widget.objectType).toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                color: typeColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.name,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Consolas',
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const Spacer(),
          Text(
            widget.ambiente,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'PL/SQL',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProblemsPanel(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final issues = _allActiveIssues;
    final errCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.error)
        .length;
    final warnCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.warning)
        .length;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.bottomCenter,
      child: _showProblems
          ? Container(
              height: 160,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : cs.surfaceContainerLow,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: Column(
                children: [
                  Container(
                    height: 28,
                    color: isDark
                        ? cs.surfaceContainerHigh
                        : cs.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.list_alt_rounded,
                          size: 13,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Problemas',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (errCount > 0)
                          _ProblemBadge(count: errCount, isError: true),
                        if (warnCount > 0) ...[
                          const SizedBox(width: 4),
                          _ProblemBadge(count: warnCount, isError: false),
                        ],
                        const Spacer(),
                        InkWell(
                          onTap: () => setState(() => _showProblems = false),
                          borderRadius: BorderRadius.circular(3),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: issues.isEmpty
                        ? Center(
                            child: Text(
                              'Sin problemas detectados',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: issues.length,
                            itemBuilder: (_, i) {
                              final issue = issues[i];
                              final isError =
                                  issue.severity == fm.MarkerSeverity.error;
                              return InkWell(
                                onTap: () => _specCtrl?.revealLine(
                                  issue.line,
                                  center: true,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isError
                                            ? Icons.error_outline
                                            : Icons.warning_amber_rounded,
                                        size: 14,
                                        color: isError
                                            ? Colors.red[400]
                                            : Colors.orange[400],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          issue.message,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontFamily: 'Consolas',
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.fade,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'L${issue.line}:${issue.col}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant,
                                          fontFamily: 'Consolas',
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                        child: Text(
                                          issue.source,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: issue.source == 'Oracle'
                                                ? Colors.orange[400]
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () {
                                          Clipboard.setData(
                                            ClipboardData(
                                              text:
                                                  '${issue.source} L${issue.line}:${issue.col} — ${issue.message}',
                                            ),
                                          );
                                          AppToast.info(
                                            'Copiado al portapapeles',
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(3),
                                        child: Padding(
                                          padding: const EdgeInsets.all(3),
                                          child: Icon(
                                            Icons.copy_rounded,
                                            size: 12,
                                            color: cs.onSurfaceVariant
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  static String _typeLabel(String type) => switch (type) {
    'PROCEDURE' => 'Procedimiento',
    'FUNCTION' => 'Función',
    'PACKAGE' => 'Paquete',
    'VIEW' => 'Vista',
    'TYPE' => 'Tipo',
    _ => type,
  };
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _TabWithBadge extends StatelessWidget {
  final String label;
  final int errorCount;
  final bool compact;
  const _TabWithBadge(this.label, {this.errorCount = 0, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (errorCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.shade400.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$errorCount',
                style: TextStyle(
                  fontSize: compact ? 9 : 10,
                  color: Colors.red.shade400,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ViewerToggleBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onPressed;
  const _ViewerToggleBtn({
    required this.icon,
    required this.tooltip,
    required this.active,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? cs.primaryContainer.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 15,
            color: active
                ? cs.primary
                : cs.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _ViewerIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const _ViewerIconBtn({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Icon(icon, size: 15, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ProblemBadge extends StatelessWidget {
  final int count;
  final bool isError;
  const _ProblemBadge({required this.count, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red[400]! : Colors.orange[400]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.warning_amber_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Keeps the Monaco editor alive when switching tabs so it doesn't reload.
// Handles ANTLR4 injection, schema completions and PL/SQL syntax checking.
class _MonacoSourceTab extends StatefulWidget {
  final String source;
  final bool isDark;
  final String ambiente;
  final bool isPlSql;
  final bool minimap;
  final bool wordWrap;
  final double fontSize;
  final void Function(fm.MonacoController ctrl)? onControllerReady;
  final void Function(String text)? onTextChanged;
  final void Function(int errorCount)? onErrorCountChanged;
  final void Function(List<PlSqlIssue> issues)? onIssuesChanged;

  const _MonacoSourceTab({
    required this.source,
    required this.isDark,
    required this.ambiente,
    required this.isPlSql,
    this.minimap = true,
    this.wordWrap = false,
    this.fontSize = 14,
    this.onControllerReady,
    this.onTextChanged,
    this.onErrorCountChanged,
    this.onIssuesChanged,
  });

  @override
  State<_MonacoSourceTab> createState() => _MonacoSourceTabState();
}

class _MonacoSourceTabState extends State<_MonacoSourceTab>
    with AutomaticKeepAliveClientMixin {
  fm.MonacoController? _ctrl;
  fm.MonacoCompletionRegistration? _kwReg;
  bool _antlrReady = false;
  bool _contentReady = false; // true once monacoSetValue has been called
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _kwReg?.dispose();
    editorThemeStore.removeListener(_onEditorThemeChanged);
    super.dispose();
  }

  void _onEditorThemeChanged() {
    _ctrl?.setTheme(editorThemeStore.monacoTheme);
  }

  Future<void> _onReady(fm.MonacoController ctrl) async {
    _ctrl = ctrl;
    widget.onControllerReady?.call(ctrl);
    editorThemeStore.addListener(_onEditorThemeChanged);

    // Push content first so the user sees text immediately
    if (widget.source.isNotEmpty) {
      await ctrl.runJavaScript('monacoSetValue(${jsonEncode(widget.source)})');
    }
    if (mounted) setState(() => _contentReady = true);

    // Background setup after content is visible
    await Future.wait([
      EditorThemeStore.defineAllThemes(ctrl),
      ctrl
          .registerStaticCompletions(
            id: 'plsql-source-kw',
            languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
            triggerCharacters: const [' ', '.', '('],
            items: plsqlCompletionItems,
          )
          .then((r) => _kwReg = r),
    ]);
    await ctrl.setTheme(editorThemeStore.monacoTheme);

    _loadSchema(ctrl);
    if (widget.isPlSql) _injectAntlr(ctrl);

    await ctrl.runJavaScript(
      'try { window.flutterMonaco.updateOptions({'
      '  acceptSuggestionOnEnter:"off", tabCompletion:"on"'
      '}); } catch(e) {}',
    );

    if (widget.isPlSql && widget.source.isNotEmpty) {
      _scheduleCheck(widget.source);
    }
  }

  Future<void> _loadSchema(fm.MonacoController ctrl) async {
    try {
      final schema = await SchemaService.instance.getMetadata(
        ambiente: widget.ambiente,
      );
      final payload = jsonEncode({
        'action': 'setCompletionSchema',
        'tables': schema.tables,
        'views': schema.views,
        'objects': schema.objects
            .map((o) => {'name': o.name, 'type': o.type})
            .toList(),
      });
      await ctrl.runJavaScript('monacoReceiveMessage($payload)');
    } catch (_) {}
  }

  Future<void> _injectAntlr(fm.MonacoController ctrl) async {
    try {
      _cachedAntlrJs ??= await rootBundle.loadString('assets/plsql_checker.js');
      await ctrl.runJavaScript(_cachedAntlrJs!);
      if (mounted) setState(() => _antlrReady = true);
    } catch (_) {}
  }

  void _scheduleCheck(String code) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 1200),
      () => _checkSyntax(code),
    );
  }

  Future<void> _checkSyntax(String code) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    List<PlSqlIssue> issues;
    if (_antlrReady && code.length < 40000) {
      try {
        final raw = await ctrl.evaluateJavaScript<String>(
          'try{__checkPlSql(_editor.getValue())}catch(e){null}',
        );
        issues = raw != null ? _parseAntlrResult(raw) : checkPlSqlSyntax(code);
      } catch (_) {
        issues = checkPlSqlSyntax(code);
      }
    } else {
      issues = checkPlSqlSyntax(code);
    }

    final errCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.error)
        .length;
    widget.onErrorCountChanged?.call(errCount);
    widget.onIssuesChanged?.call(issues);

    await ctrl.document.setMarkers([
      for (final e in issues)
        fm.MarkerData(
          range: fm.Range(
            startLine: e.line,
            startColumn: e.col,
            endLine: e.line,
            endColumn: e.endCol,
          ),
          message: e.message,
          severity: e.severity,
          source: 'PL/SQL',
        ),
    ], owner: 'plsql-checker');
  }

  List<PlSqlIssue> _parseAntlrResult(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return [
        for (final e in list)
          PlSqlIssue(
            line: (e['line'] as num).toInt(),
            col: (e['col'] as num).toInt(),
            endCol: (e['col'] as num).toInt() + 1,
            message: e['msg'] as String,
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.source.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        fm.MonacoEditor(
          initialText: '', // content pushed via monacoSetValue in onReady
          options: fm.EditorOptions(
            language: fm.MonacoLanguage.sql,
            theme: widget.isDark ? fm.MonacoTheme.vsDark : fm.MonacoTheme.vs,
            fontSize: widget.fontSize,
            minimap: fm.MonacoMinimapOptions(enabled: widget.minimap),
            lineNumbers: fm.MonacoLineNumbers.on,
            wordWrap: widget.wordWrap
                ? fm.MonacoWordWrap.on
                : fm.MonacoWordWrap.off,
            renderWhitespace: fm.RenderWhitespace.none,
            tabSize: 2,
          ),
          contentDebounce: const Duration(milliseconds: 300),
          onReady: _onReady,
          onContentChanged: (text) {
            widget.onTextChanged?.call(text);
            if (widget.isPlSql) _scheduleCheck(text);
          },
        ),
        if (!_contentReady)
          const Positioned(
            left: 12,
            bottom: 12,
            child: StatusCard(message: 'Cargando contenido...'),
          ),
      ],
    );
  }
}

// Single Monaco WebView with two documents — spec loads immediately, body after.
// Tab switching activates the corresponding document without recreating the WebView.
class _MultiDocSourceEditor extends StatefulWidget {
  final String spec;
  final String? body;
  final bool isDark;
  final String ambiente;
  final bool isPlSql;
  final TabController tabCtrl;
  final bool minimap;
  final bool wordWrap;
  final double fontSize;
  final void Function(fm.MonacoController)? onControllerReady;
  final void Function(String)? onSpecTextChanged;
  final void Function(String)? onBodyTextChanged;
  final void Function(int)? onSpecErrorsChanged;
  final void Function(int)? onBodyErrorsChanged;
  final void Function(List<PlSqlIssue>)? onSpecIssuesChanged;
  final void Function(List<PlSqlIssue>)? onBodyIssuesChanged;

  const _MultiDocSourceEditor({
    required this.spec,
    required this.body,
    required this.isDark,
    required this.ambiente,
    required this.isPlSql,
    required this.tabCtrl,
    this.minimap = true,
    this.wordWrap = false,
    this.fontSize = 14,
    this.onControllerReady,
    this.onSpecTextChanged,
    this.onBodyTextChanged,
    this.onSpecErrorsChanged,
    this.onBodyErrorsChanged,
    this.onSpecIssuesChanged,
    this.onBodyIssuesChanged,
  });

  @override
  State<_MultiDocSourceEditor> createState() => _MultiDocSourceEditorState();
}

class _MultiDocSourceEditorState extends State<_MultiDocSourceEditor> {
  fm.MonacoController? _ctrl;
  fm.MonacoDocument? _specDoc;
  fm.MonacoDocument? _bodyDoc;
  fm.MonacoCompletionRegistration? _kwReg;
  bool _antlrReady = false;
  bool _specReady = false;
  Timer? _debounce;
  bool _isBody = false;

  @override
  void initState() {
    super.initState();
    widget.tabCtrl.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.tabCtrl.removeListener(_onTabChanged);
    _debounce?.cancel();
    _kwReg?.dispose();
    editorThemeStore.removeListener(_onEditorThemeChanged2);
    super.dispose();
  }

  void _onEditorThemeChanged2() {
    _ctrl?.setTheme(editorThemeStore.monacoTheme);
  }

  void _onTabChanged() async {
    final wantsBody = widget.tabCtrl.index == 1;
    if (_isBody == wantsBody) return;
    _isBody = wantsBody;

    // Open the body document lazily on first switch to avoid blocking spec load
    if (wantsBody && _bodyDoc == null) {
      final ctrl = _ctrl;
      final body = widget.body;
      if (ctrl != null && body != null && body.isNotEmpty) {
        _bodyDoc = await ctrl.openDocument(
          text: body,
          language: fm.MonacoLanguage.sql,
          uri: Uri.parse('file:///source/body.sql'),
        );
        if (widget.isPlSql) _scheduleCheck(body, isBody: true);
      }
    }

    final doc = wantsBody ? _bodyDoc : _specDoc;
    if (doc != null) _ctrl?.activateDocument(doc);
  }

  Future<void> _onReady(fm.MonacoController ctrl) async {
    _ctrl = ctrl;
    widget.onControllerReady?.call(ctrl);
    editorThemeStore.addListener(_onEditorThemeChanged2);

    // Open spec FIRST so content is visible as fast as possible
    _specDoc = await ctrl.openDocument(
      text: widget.spec,
      language: fm.MonacoLanguage.sql,
      uri: Uri.parse('file:///source/spec.sql'),
    );
    await ctrl.activateDocument(_specDoc!);
    if (mounted) setState(() => _specReady = true);
    widget.onSpecTextChanged?.call(widget.spec);

    // Background setup after content is already visible
    await Future.wait([
      EditorThemeStore.defineAllThemes(ctrl),
      ctrl
          .registerStaticCompletions(
            id: 'plsql-multidoc-kw',
            languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
            triggerCharacters: const [' ', '.', '('],
            items: plsqlCompletionItems,
          )
          .then((r) => _kwReg = r),
    ]);
    await ctrl.setTheme(editorThemeStore.monacoTheme);

    _loadSchema(ctrl);
    if (widget.isPlSql) _injectAntlr(ctrl);

    await ctrl.runJavaScript(
      'try { window.flutterMonaco.updateOptions({'
      '  acceptSuggestionOnEnter:"off", tabCompletion:"on"'
      '}); } catch(e) {}',
    );

    if (widget.isPlSql && widget.spec.isNotEmpty) {
      _scheduleCheck(widget.spec, isBody: false);
    }

    // Notify parent with body text for subprogram parsing without opening the doc
    if (widget.body != null) widget.onBodyTextChanged?.call(widget.body!);
  }

  Future<void> _loadSchema(fm.MonacoController ctrl) async {
    try {
      final schema = await SchemaService.instance.getMetadata(
        ambiente: widget.ambiente,
      );
      final payload = jsonEncode({
        'action': 'setCompletionSchema',
        'tables': schema.tables,
        'views': schema.views,
        'objects': schema.objects
            .map((o) => {'name': o.name, 'type': o.type})
            .toList(),
      });
      await ctrl.runJavaScript('monacoReceiveMessage($payload)');
    } catch (_) {}
  }

  Future<void> _injectAntlr(fm.MonacoController ctrl) async {
    try {
      _cachedAntlrJs ??= await rootBundle.loadString('assets/plsql_checker.js');
      await ctrl.runJavaScript(_cachedAntlrJs!);
      if (mounted) setState(() => _antlrReady = true);
    } catch (_) {}
  }

  void _scheduleCheck(String code, {required bool isBody}) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 1200),
      () => _checkSyntax(code, isBody: isBody),
    );
  }

  Future<void> _checkSyntax(String code, {required bool isBody}) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    List<PlSqlIssue> issues;
    if (_antlrReady && code.length < 40000) {
      try {
        final raw = await ctrl.evaluateJavaScript<String>(
          'try{__checkPlSql(_editor.getValue())}catch(e){null}',
        );
        issues = raw != null ? _parseAntlrResult(raw) : checkPlSqlSyntax(code);
      } catch (_) {
        issues = checkPlSqlSyntax(code);
      }
    } else {
      issues = checkPlSqlSyntax(code);
    }

    final errCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.error)
        .length;
    if (isBody) {
      widget.onBodyErrorsChanged?.call(errCount);
      widget.onBodyIssuesChanged?.call(issues);
    } else {
      widget.onSpecErrorsChanged?.call(errCount);
      widget.onSpecIssuesChanged?.call(issues);
    }

    await ctrl.document.setMarkers([
      for (final e in issues)
        fm.MarkerData(
          range: fm.Range(
            startLine: e.line,
            startColumn: e.col,
            endLine: e.line,
            endColumn: e.endCol,
          ),
          message: e.message,
          severity: e.severity,
          source: 'PL/SQL',
        ),
    ], owner: 'plsql-checker');
  }

  List<PlSqlIssue> _parseAntlrResult(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return [
        for (final e in list)
          PlSqlIssue(
            line: (e['line'] as num).toInt(),
            col: (e['col'] as num).toInt(),
            endCol: (e['col'] as num).toInt() + 1,
            message: e['msg'] as String,
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        fm.MonacoEditor(
          initialText: '',
          options: fm.EditorOptions(
            language: fm.MonacoLanguage.sql,
            theme: editorThemeStore.monacoTheme,
            fontSize: widget.fontSize,
            minimap: fm.MonacoMinimapOptions(enabled: widget.minimap),
            lineNumbers: fm.MonacoLineNumbers.on,
            wordWrap: widget.wordWrap
                ? fm.MonacoWordWrap.on
                : fm.MonacoWordWrap.off,
            renderWhitespace: fm.RenderWhitespace.none,
            tabSize: 2,
          ),
          contentDebounce: const Duration(milliseconds: 300),
          onReady: _onReady,
          onContentChanged: (text) {
            if (_isBody) {
              widget.onBodyTextChanged?.call(text);
              if (widget.isPlSql) _scheduleCheck(text, isBody: true);
            } else {
              widget.onSpecTextChanged?.call(text);
              if (widget.isPlSql) _scheduleCheck(text, isBody: false);
            }
          },
        ),
        if (!_specReady)
          const Positioned(
            left: 12,
            bottom: 12,
            child: StatusCard(message: 'Cargando especificación...'),
          ),
      ],
    );
  }
}
