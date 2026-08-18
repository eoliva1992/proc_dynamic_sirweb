import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
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
// _cachedAntlrJs removed — validation now uses Oracle backend

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
  bool _backendChecking = false;
  bool _showPackageNav = true;
  String? _activeSubprogram;
  List<PlSqlIssue> _specIssues = [];
  List<PlSqlIssue> _bodyIssues = [];
  List<PlSqlIssue> _specCompileIssues = [];
  List<PlSqlIssue> _bodyCompileIssues = [];
  List<({String name, String kind, int line})> _subprograms = [];
  List<({String name, String kind, int line})> _specSubprograms = [];
  final TextEditingController _navSearchCtrl = TextEditingController();

  // Grants/owner from table DDL response — used in backup dialog for TABLE type
  String? _tableDdlGrants;
  String _tableDdlOwner = '';
  String _tableDdlCreateTable = '';
  String? _tableDdlComments;

  @override
  void initState() {
    super.initState();
    final isTable = widget.objectType == 'TABLE';
    final sourceFuture = isTable
        ? SchemaService.instance
              .getTableDdl(widget.name, ambiente: widget.ambiente)
              .then((ddl) {
                _tableDdlGrants = ddl.grants?.isNotEmpty == true
                    ? ddl.grants
                    : null;
                _tableDdlOwner = ddl.owner;
                _tableDdlCreateTable = ddl.createTable;
                _tableDdlComments = ddl.comments?.isNotEmpty == true
                    ? ddl.comments
                    : null;
                final parts = [
                  ddl.createTable,
                  if (ddl.comments != null && ddl.comments!.isNotEmpty)
                    ddl.comments!,
                ];
                return (spec: parts.join('\n\n'), body: null as String?);
              })
        : SchemaService.instance.getObjectSource(
            widget.name,
            widget.objectType,
            ambiente: widget.ambiente,
          );
    sourceFuture
        .then((data) {
          if (!mounted) return;
          setState(() {
            _data = data;
            // Only PACKAGE has a meaningful spec/body split
            if (data.body != null && widget.objectType == 'PACKAGE') {
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

  Future<void> _showBackupDialog() async {
    final isTable = widget.objectType == 'TABLE';

    var includeSpec = true;
    var includeBody = _bodyText.isNotEmpty;
    var includeTableComments = _tableDdlComments != null;
    var includeSynonym = false;
    var includeGrants = false;

    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final hasBody = _bodyText.isNotEmpty;
          final canSave =
              includeSpec ||
              (hasBody && includeBody) ||
              (isTable && includeTableComments) ||
              includeSynonym ||
              includeGrants;

          Widget checkRow(
            String label,
            bool value,
            bool enabled,
            ValueChanged<bool?> onChanged, {
            String? subtitle,
            IconData icon = Icons.check_box_outline_blank,
          }) {
            return InkWell(
              onTap: enabled ? () => onChanged(!value) : null,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: value,
                        onChanged: enabled ? onChanged : null,
                        activeColor: typeColor,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              color: enabled ? null : Colors.grey,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                                fontFamily: 'Consolas',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.download_outlined, size: 18, color: typeColor),
                const SizedBox(width: 8),
                const Text(
                  'Generar backup SQL',
                  style: TextStyle(fontSize: 15),
                ),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seleccioná qué incluir en el script',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  // ── Fuente ──────────────────────────────────────────────
                  Text(
                    'FUENTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: typeColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  checkRow(
                    isTable ? 'DDL de tabla' : 'Especificación',
                    includeSpec,
                    _specText.isNotEmpty,
                    (v) => setDlg(() => includeSpec = v ?? false),
                    subtitle: isTable
                        ? 'CREATE TABLE + Índices + Constraints'
                        : widget.objectType == 'PACKAGE'
                        ? 'CREATE OR REPLACE PACKAGE ...'
                        : null,
                  ),
                  if (isTable && _tableDdlComments != null)
                    checkRow(
                      'Comentarios',
                      includeTableComments,
                      true,
                      (v) => setDlg(() => includeTableComments = v ?? false),
                      subtitle: 'COMMENT ON TABLE ...',
                    ),
                  if (!isTable && hasBody)
                    checkRow(
                      'Cuerpo',
                      includeBody,
                      true,
                      (v) => setDlg(() => includeBody = v ?? false),
                      subtitle: 'CREATE OR REPLACE PACKAGE BODY ...',
                    ),
                  const SizedBox(height: 10),
                  // ── Adicional ────────────────────────────────────────────
                  Text(
                    'ADICIONAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: typeColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  checkRow(
                    'Grant',
                    includeGrants,
                    true,
                    (v) => setDlg(() => includeGrants = v ?? false),
                    subtitle: isTable && _tableDdlGrants != null
                        ? 'Grants del DDL de tabla'
                        : 'GRANT EXECUTE ON OWNER.NAME TO PUBLIC',
                  ),
                  checkRow(
                    'Sinónimo público',
                    includeSynonym,
                    true,
                    (v) => setDlg(() => includeSynonym = v ?? false),
                    subtitle:
                        'CREATE OR REPLACE PUBLIC SYNONYM NAME FOR OWNER.NAME',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: canSave
                    ? () {
                        Navigator.pop(ctx);
                        _saveBackup(
                          includeSpec: includeSpec,
                          includeBody: includeBody && hasBody,
                          includeTableComments: includeTableComments,
                          includeSynonyms: includeSynonym,
                          includeGrants: includeGrants,
                        );
                      }
                    : null,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Guardar .sql'),
                style: FilledButton.styleFrom(backgroundColor: typeColor),
              ),
            ],
          );
        },
      ),
    );
  }

  // Resolves the schema owner for this object from the cached metadata or table DDL.
  String _objectOwner() {
    if (_tableDdlOwner.isNotEmpty) return _tableDdlOwner;
    final cached = SchemaService.instance.getCached(ambiente: widget.ambiente);
    return cached?.objects
            .where((o) => o.name == widget.name.toUpperCase())
            .firstOrNull
            ?.owner ??
        '';
  }

  Future<void> _saveBackup({
    required bool includeSpec,
    required bool includeBody,
    bool includeTableComments = false,
    required bool includeSynonyms,
    required bool includeGrants,
  }) async {
    final parts = <String>[];
    final isTable = widget.objectType == 'TABLE';

    if (includeSpec) {
      // For TABLE use the raw createTable; for others use the full specText
      final source = isTable ? _tableDdlCreateTable : _specText;
      if (source.isNotEmpty) parts.add('$source\n/');
    }
    if (includeTableComments && _tableDdlComments != null) {
      parts.add('${_tableDdlComments!}\n/');
    }
    if (includeBody && _bodyText.isNotEmpty) {
      parts.add('$_bodyText\n/');
    }

    if (includeSynonyms || includeGrants) {
      final owner = _objectOwner();
      final ref = owner.isNotEmpty ? '$owner.${widget.name}' : widget.name;
      if (includeGrants) {
        // For TABLE, use pre-built grants from DDL response; for others generate
        if (widget.objectType == 'TABLE' && _tableDdlGrants != null) {
          parts.add('${_tableDdlGrants!}\n/');
        } else {
          parts.add('GRANT EXECUTE ON $ref TO PUBLIC;\n/');
        }
      }
      if (includeSynonyms) {
        parts.add(
          'CREATE OR REPLACE PUBLIC SYNONYM ${widget.name} FOR $ref;\n/',
        );
      }
    }

    if (parts.isEmpty) return;

    final script = parts.join('\n\n');
    final suggested =
        '${widget.name.toLowerCase()}_${widget.ambiente.toLowerCase()}.sql';

    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Guardar backup SQL',
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: ['sql'],
      );
      if (path == null) return;
      await File(path).writeAsString(script, flush: true);
      AppToast.success('Backup guardado: ${path.split(r"\\").last}');
    } catch (e) {
      AppToast.error('Error guardando backup: $e');
    }
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
                  tooltip: 'Generar backup SQL',
                  icon: const Icon(Icons.download_outlined, size: 16),
                  onPressed: _showBackupDialog,
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
        isPlSql: widget.objectType != 'VIEW' && widget.objectType != 'TABLE',
        objectType: widget.objectType,
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
        onBackendChecking: (v) => setState(() => _backendChecking = v),
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
      // For non-PACKAGE types, use body if spec is empty (some servers return body only)
      source: _data!.spec.isNotEmpty ? _data!.spec : (_data!.body ?? ''),
      isDark: isDark,
      ambiente: widget.ambiente,
      isPlSql: widget.objectType != 'VIEW' && widget.objectType != 'TABLE',
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
      onBackendChecking: (v) => setState(() => _backendChecking = v),
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
            _ViewerIconBtn(
              icon: Icons.download_outlined,
              tooltip: 'Generar backup SQL',
              onPressed: _showBackupDialog,
            ),
            SizedBox(
              height: 16,
              child: VerticalDivider(color: cs.outlineVariant, width: 10),
            ),
          ],
          const Spacer(),
          // ── Errores + Compilar ─────────────────────────────────────────────
          if (_backendChecking)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (errCount > 0 || warnCount > 0)
            Tooltip(
              message: _showProblems
                  ? 'Ocultar problemas'
                  : 'Mostrar problemas',
              waitDuration: const Duration(milliseconds: 400),
              child: GestureDetector(
                onTap: () => setState(() => _showProblems = !_showProblems),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: errCount > 0
                        ? Colors.red.shade400.withValues(alpha: 0.12)
                        : Colors.orange.shade400.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: errCount > 0
                          ? Colors.red.shade400.withValues(alpha: 0.4)
                          : Colors.orange.shade400.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
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
                      if (errCount > 0 && warnCount > 0)
                        const SizedBox(width: 6),
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
    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);
    final size = compact ? 18.0 : 22.0;
    return switch (_compileStatus) {
      _ViewerCompileStatus.idle when !compact => GestureDetector(
        onTap: _compile,
        child: Tooltip(
          message: 'Compilar (F5)',
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: typeColor.withValues(alpha: 0.35),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, size: 14, color: typeColor),
                const SizedBox(width: 4),
                Text(
                  'Compilar',
                  style: TextStyle(
                    fontSize: 11,
                    color: typeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      _ViewerCompileStatus.idle => IconButton(
        tooltip: 'Compilar',
        icon: Icon(Icons.play_arrow_rounded, size: size, color: typeColor),
        onPressed: _compile,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
      _ViewerCompileStatus.compiling => Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
        child: SizedBox(
          width: compact ? 14 : 18,
          height: compact ? 14 : 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: compact ? typeColor : typeColor,
          ),
        ),
      ),
      _ViewerCompileStatus.ok =>
        compact
            ? IconButton(
                tooltip: 'Compilado — compilar de nuevo',
                icon: Icon(
                  Icons.check_circle_outline,
                  size: size,
                  color: const Color(0xFF4CAF50),
                ),
                onPressed: _compile,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            : GestureDetector(
                onTap: _compile,
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.35),
                      width: 0.5,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: Color(0xFF4CAF50),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Compilado',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      _ViewerCompileStatus.error =>
        compact
            ? IconButton(
                tooltip: 'Compilación falló — compilar de nuevo',
                icon: Icon(
                  Icons.error_outline,
                  size: size,
                  color: Colors.orange,
                ),
                onPressed: _compile,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            : GestureDetector(
                onTap: _compile,
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.35),
                      width: 0.5,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 14, color: Colors.orange),
                      SizedBox(width: 4),
                      Text(
                        'Error — reintentar',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
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
              height: 200,
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
                        if (_backendChecking) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
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
                                            color: switch (issue.source) {
                                              'Oracle' || 'Oracle-DDL' =>
                                                Colors.orange[400],
                                              'PL/SQL' => cs.primary,
                                              _ => cs.onSurfaceVariant,
                                            },
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
  final void Function(bool checking)? onBackendChecking;

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
    this.onBackendChecking,
  });

  @override
  State<_MonacoSourceTab> createState() => _MonacoSourceTabState();
}

class _MonacoSourceTabState extends State<_MonacoSourceTab>
    with AutomaticKeepAliveClientMixin {
  fm.MonacoController? _ctrl;
  fm.MonacoCompletionRegistration? _kwReg;
  fm.MonacoCompletionRegistration? _schemaReg;
  bool _contentReady = false;
  Timer? _debounce;
  int _checkGen = 0;
  String _editorFullText = '';
  int? _fromExtractHash;
  Map<String, String> _fromExtractResult = {};

  static final _reDotPrefix = RegExp(r'(\w+)\.$');
  static final _reWordEnd = RegExp(r'(\w+)$');
  static final _reFromBlock = RegExp(
    r'FROM\s+([\s\S]*?)(?=\bWHERE\b|\bGROUP\b|\bORDER\b|\bHAVING\b|$)',
    caseSensitive: false,
  );
  static final _reAliasBlock = RegExp(
    r'\b(\w+)\s+(?:AS\s+)?(\w+)\b',
    caseSensitive: false,
  );
  static final _reFromSimple = RegExp(
    r'\bFROM\s+(\w+)(?:\s*,|\s*$|\s+(?:WHERE|GROUP|ORDER|HAVING|JOIN))',
    caseSensitive: false,
  );
  static final _reJoin = RegExp(
    r'\bJOIN\s+(\w+)(?:\s+AS\s+|\s+)(\w+)?',
    caseSensitive: false,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _kwReg?.dispose();
    _schemaReg?.dispose();
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

    // Push content directly via the document API (monacoSetValue is not available in flutter_monaco)
    if (widget.source.isNotEmpty) {
      await ctrl.document.setText(widget.source);
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
    _registerSchemaCompletions(ctrl);

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

  void _registerSchemaCompletions(fm.MonacoController ctrl) {
    _schemaReg?.dispose();
    _schemaReg = null;
    SchemaService.instance
        .getMetadata(ambiente: widget.ambiente)
        .then((schema) async {
          if (!mounted) return;
          _schemaReg = await ctrl.registerCompletions(
            id: 'source-tab-schema',
            languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
            triggerCharacters: ['.', ' '],
            provider: (request) async {
              final line = request.lineText ?? '';
              final trigger = request.triggerCharacter;
              final fullText = _editorFullText;
              if (trigger == '.' || line.endsWith('.')) {
                final dotMatch = _reDotPrefix.firstMatch(line);
                if (dotMatch != null) {
                  final realTable =
                      _extractFromTables(fullText)[dotMatch
                          .group(1)!
                          .toUpperCase()] ??
                      dotMatch.group(1)!.toUpperCase();
                  final cols = await SchemaService.instance.getColumns(
                    realTable,
                    ambiente: widget.ambiente,
                  );
                  return fm.CompletionList(
                    suggestions: cols
                        .map(
                          (c) => fm.CompletionItem(
                            label: c.name,
                            kind: fm.CompletionItemKind.field,
                            detail: '${c.dataType} · $realTable',
                            insertText: c.name,
                            sortText: '0${c.name}',
                          ),
                        )
                        .toList(),
                  );
                }
              }
              final upper = _wordBefore(line).toUpperCase();
              final suggestions = <fm.CompletionItem>[];
              for (final t in _extractFromTables(fullText).values.toSet()) {
                final cols =
                    schema.cachedColumns[t] ??
                    await SchemaService.instance.getColumns(
                      t,
                      ambiente: widget.ambiente,
                    );
                suggestions.addAll(
                  cols
                      .where((c) => upper.isEmpty || c.name.startsWith(upper))
                      .map(
                        (c) => fm.CompletionItem(
                          label: c.name,
                          kind: fm.CompletionItemKind.field,
                          detail: '${c.dataType} · $t',
                          sortText: '1${c.name}',
                        ),
                      ),
                );
              }
              suggestions.addAll(
                schema.tables
                    .where((t) => upper.isEmpty || t.startsWith(upper))
                    .map(
                      (t) => fm.CompletionItem(
                        label: t,
                        kind: fm.CompletionItemKind.classType,
                        detail: 'TABLE',
                        sortText: '2$t',
                      ),
                    ),
              );
              suggestions.addAll(
                schema.views
                    .where((v) => upper.isEmpty || v.startsWith(upper))
                    .map(
                      (v) => fm.CompletionItem(
                        label: v,
                        kind: fm.CompletionItemKind.interfaceType,
                        detail: 'VIEW',
                        sortText: '3$v',
                      ),
                    ),
              );
              suggestions.addAll(
                schema.objects
                    .where((o) => upper.isEmpty || o.name.startsWith(upper))
                    .map(
                      (o) => fm.CompletionItem(
                        label: o.name,
                        kind: o.type == 'FUNCTION'
                            ? fm.CompletionItemKind.functionType
                            : o.type == 'PACKAGE'
                            ? fm.CompletionItemKind.module
                            : fm.CompletionItemKind.method,
                        detail: o.type,
                        sortText: '4${o.name}',
                      ),
                    ),
              );
              return fm.CompletionList(
                suggestions: suggestions.take(50).toList(),
              );
            },
          );
        })
        .catchError((_) {});
  }

  Map<String, String> _extractFromTables(String sql) {
    final hash = sql.hashCode ^ sql.length;
    if (hash == _fromExtractHash) return _fromExtractResult;
    final result = <String, String>{};
    void add(String table, String? alias) {
      final t = table.toUpperCase();
      result[t] = t;
      if (alias != null && alias.isNotEmpty) result[alias.toUpperCase()] = t;
    }

    const reserved = {
      'ON',
      'WHERE',
      'SET',
      'AND',
      'OR',
      'JOIN',
      'LEFT',
      'RIGHT',
      'INNER',
      'OUTER',
      'FULL',
      'CROSS',
      'GROUP',
      'ORDER',
      'HAVING',
    };
    final fromBlock = _reFromBlock.firstMatch(sql)?.group(1) ?? '';
    for (final m in _reAliasBlock.allMatches(fromBlock)) {
      if (!reserved.contains(m.group(2)!.toUpperCase()))
        add(m.group(1)!, m.group(2));
    }
    for (final m in _reFromSimple.allMatches(sql)) {
      add(m.group(1)!, null);
    }
    for (final m in _reJoin.allMatches(sql)) {
      add(m.group(1)!, m.group(2));
    }
    _fromExtractHash = sql.hashCode ^ sql.length;
    _fromExtractResult = result;
    return result;
  }

  String _wordBefore(String line) =>
      _reWordEnd.firstMatch(line)?.group(1) ?? '';

  void _scheduleCheck(String code) {
    _debounce?.cancel();
    final gen = ++_checkGen;
    // Clear stale markers immediately so the editor doesn't show obsolete results
    _ctrl?.document.clearMarkers(owner: 'plsql-checker');
    widget.onErrorCountChanged?.call(0);
    widget.onIssuesChanged?.call([]);
    final ms = code.length > 15000 ? 3500 : 1200;
    _debounce = Timer(
      Duration(milliseconds: ms),
      () => _checkSyntax(code, gen),
    );
  }

  Future<void> _checkSyntax(String code, int gen) async {
    final ctrl = _ctrl;
    if (ctrl == null || code.isEmpty) return;
    widget.onBackendChecking?.call(true);
    try {
      final errors = await SchemaService.instance.validateSyntax(
        code,
        'PROCEDURE',
        ambiente: widget.ambiente,
      );
      if (!mounted || gen != _checkGen) return; // user typed again — discard
      final issues = errors
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
      widget.onErrorCountChanged?.call(
        issues.where((e) => e.severity == fm.MarkerSeverity.error).length,
      );
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
            source: 'Oracle',
          ),
      ], owner: 'plsql-checker');
    } finally {
      if (mounted) widget.onBackendChecking?.call(false);
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
          initialText: widget.source.isNotEmpty ? widget.source : '',
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
          contentDebounce: const Duration(milliseconds: 600),
          onReady: _onReady,
          onContentChanged: (text) {
            _editorFullText = text;
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
  final String objectType;
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
  final void Function(bool checking)? onBackendChecking;

  const _MultiDocSourceEditor({
    required this.spec,
    required this.body,
    required this.isDark,
    required this.ambiente,
    required this.isPlSql,
    required this.objectType,
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
    this.onBackendChecking,
  });

  @override
  State<_MultiDocSourceEditor> createState() => _MultiDocSourceEditorState();
}

class _MultiDocSourceEditorState extends State<_MultiDocSourceEditor> {
  fm.MonacoController? _ctrl;
  fm.MonacoDocument? _specDoc;
  fm.MonacoDocument? _bodyDoc;
  fm.MonacoCompletionRegistration? _kwReg;
  fm.MonacoCompletionRegistration? _schemaReg;
  bool _specReady = false;
  bool _bodyReady = false;
  Timer? _debounce;
  int _checkGen = 0;
  bool _isBody = false;
  String _currentSpecCode = '';
  String _currentBodyCode = '';
  int? _fromExtractHash;
  Map<String, String> _fromExtractResult = {};

  static final _reDotPrefix = RegExp(r'(\w+)\.$');
  static final _reWordEnd = RegExp(r'(\w+)$');
  static final _reFromBlock = RegExp(
    r'FROM\s+([\s\S]*?)(?=\bWHERE\b|\bGROUP\b|\bORDER\b|\bHAVING\b|$)',
    caseSensitive: false,
  );
  static final _reAliasBlock = RegExp(
    r'\b(\w+)\s+(?:AS\s+)?(\w+)\b',
    caseSensitive: false,
  );
  static final _reFromSimple = RegExp(
    r'\bFROM\s+(\w+)(?:\s*,|\s*$|\s+(?:WHERE|GROUP|ORDER|HAVING|JOIN))',
    caseSensitive: false,
  );
  static final _reJoin = RegExp(
    r'\bJOIN\s+(\w+)(?:\s+AS\s+|\s+)(\w+)?',
    caseSensitive: false,
  );

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
    _schemaReg?.dispose();
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

    if (wantsBody) {
      if (_bodyDoc != null) {
        _ctrl?.activateDocument(_bodyDoc!);
        if (widget.isPlSql && _currentBodyCode.isNotEmpty) {
          _scheduleCheck(_currentBodyCode, isBody: true);
        }
      }
      return;
    }

    final doc = _specDoc;
    if (doc != null) {
      _ctrl?.activateDocument(doc);
      if (widget.isPlSql && _currentSpecCode.isNotEmpty) {
        _scheduleCheck(_currentSpecCode, isBody: false);
      }
    }
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
    _registerSchemaCompletions(ctrl);

    await ctrl.runJavaScript(
      'try { window.flutterMonaco.updateOptions({'
      '  acceptSuggestionOnEnter:"off", tabCompletion:"on"'
      '}); } catch(e) {}',
    );

    if (widget.isPlSql && widget.spec.isNotEmpty) {
      _currentSpecCode = widget.spec;
      _scheduleCheck(widget.spec, isBody: false);
    }

    // Load body in background so it's ready before the user switches tabs
    final body = widget.body;
    if (body != null && body.isNotEmpty) {
      widget.onBodyTextChanged?.call(body);
      _openBodyInBackground(ctrl, body);
    }
  }

  Future<void> _openBodyInBackground(
    fm.MonacoController ctrl,
    String body,
  ) async {
    _bodyDoc = await ctrl.openDocument(
      text: body,
      language: fm.MonacoLanguage.sql,
      uri: Uri.parse('file:///source/body.sql'),
    );
    if (!mounted) return;
    if (mounted) setState(() => _bodyReady = true);
    _currentBodyCode = body;
    if (_isBody) _ctrl?.activateDocument(_bodyDoc!);
    if (widget.isPlSql) _scheduleCheck(body, isBody: true);
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

  void _registerSchemaCompletions(fm.MonacoController ctrl) {
    _schemaReg?.dispose();
    _schemaReg = null;
    SchemaService.instance
        .getMetadata(ambiente: widget.ambiente)
        .then((schema) async {
          if (!mounted) return;
          _schemaReg = await ctrl.registerCompletions(
            id: 'multi-doc-schema',
            languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
            triggerCharacters: ['.', ' '],
            provider: (request) async {
              final line = request.lineText ?? '';
              final trigger = request.triggerCharacter;
              final fullText = _isBody ? _currentBodyCode : _currentSpecCode;
              if (trigger == '.' || line.endsWith('.')) {
                final dotMatch = _reDotPrefix.firstMatch(line);
                if (dotMatch != null) {
                  final realTable =
                      _extractFromTables(fullText)[dotMatch
                          .group(1)!
                          .toUpperCase()] ??
                      dotMatch.group(1)!.toUpperCase();
                  final cols = await SchemaService.instance.getColumns(
                    realTable,
                    ambiente: widget.ambiente,
                  );
                  return fm.CompletionList(
                    suggestions: cols
                        .map(
                          (c) => fm.CompletionItem(
                            label: c.name,
                            kind: fm.CompletionItemKind.field,
                            detail: '${c.dataType} · $realTable',
                            insertText: c.name,
                            sortText: '0${c.name}',
                          ),
                        )
                        .toList(),
                  );
                }
              }
              final upper = _wordBefore(line).toUpperCase();
              final suggestions = <fm.CompletionItem>[];
              for (final t in _extractFromTables(fullText).values.toSet()) {
                final cols =
                    schema.cachedColumns[t] ??
                    await SchemaService.instance.getColumns(
                      t,
                      ambiente: widget.ambiente,
                    );
                suggestions.addAll(
                  cols
                      .where((c) => upper.isEmpty || c.name.startsWith(upper))
                      .map(
                        (c) => fm.CompletionItem(
                          label: c.name,
                          kind: fm.CompletionItemKind.field,
                          detail: '${c.dataType} · $t',
                          sortText: '1${c.name}',
                        ),
                      ),
                );
              }
              suggestions.addAll(
                schema.tables
                    .where((t) => upper.isEmpty || t.startsWith(upper))
                    .map(
                      (t) => fm.CompletionItem(
                        label: t,
                        kind: fm.CompletionItemKind.classType,
                        detail: 'TABLE',
                        sortText: '2$t',
                      ),
                    ),
              );
              suggestions.addAll(
                schema.views
                    .where((v) => upper.isEmpty || v.startsWith(upper))
                    .map(
                      (v) => fm.CompletionItem(
                        label: v,
                        kind: fm.CompletionItemKind.interfaceType,
                        detail: 'VIEW',
                        sortText: '3$v',
                      ),
                    ),
              );
              suggestions.addAll(
                schema.objects
                    .where((o) => upper.isEmpty || o.name.startsWith(upper))
                    .map(
                      (o) => fm.CompletionItem(
                        label: o.name,
                        kind: o.type == 'FUNCTION'
                            ? fm.CompletionItemKind.functionType
                            : o.type == 'PACKAGE'
                            ? fm.CompletionItemKind.module
                            : fm.CompletionItemKind.method,
                        detail: o.type,
                        sortText: '4${o.name}',
                      ),
                    ),
              );
              return fm.CompletionList(
                suggestions: suggestions.take(50).toList(),
              );
            },
          );
        })
        .catchError((_) {});
  }

  Map<String, String> _extractFromTables(String sql) {
    final hash = sql.hashCode ^ sql.length;
    if (hash == _fromExtractHash) return _fromExtractResult;
    final result = <String, String>{};
    void add(String table, String? alias) {
      final t = table.toUpperCase();
      result[t] = t;
      if (alias != null && alias.isNotEmpty) result[alias.toUpperCase()] = t;
    }

    const reserved = {
      'ON',
      'WHERE',
      'SET',
      'AND',
      'OR',
      'JOIN',
      'LEFT',
      'RIGHT',
      'INNER',
      'OUTER',
      'FULL',
      'CROSS',
      'GROUP',
      'ORDER',
      'HAVING',
    };
    final fromBlock = _reFromBlock.firstMatch(sql)?.group(1) ?? '';
    for (final m in _reAliasBlock.allMatches(fromBlock)) {
      if (!reserved.contains(m.group(2)!.toUpperCase()))
        add(m.group(1)!, m.group(2));
    }
    for (final m in _reFromSimple.allMatches(sql)) {
      add(m.group(1)!, null);
    }
    for (final m in _reJoin.allMatches(sql)) {
      add(m.group(1)!, m.group(2));
    }
    _fromExtractHash = sql.hashCode ^ sql.length;
    _fromExtractResult = result;
    return result;
  }

  String _wordBefore(String line) =>
      _reWordEnd.firstMatch(line)?.group(1) ?? '';

  // Debounce scales with size — larger files need more idle time before validation fires
  void _scheduleCheck(String code, {required bool isBody}) {
    _debounce?.cancel();
    final gen = ++_checkGen;
    // Clear stale markers immediately so the editor doesn't show obsolete results
    final doc = isBody ? _bodyDoc : _specDoc;
    doc?.clearMarkers(owner: 'plsql-checker');
    if (isBody) {
      widget.onBodyErrorsChanged?.call(0);
      widget.onBodyIssuesChanged?.call([]);
    } else {
      widget.onSpecErrorsChanged?.call(0);
      widget.onSpecIssuesChanged?.call([]);
    }
    final ms = code.length > 15000 ? 3500 : 1200;
    _debounce = Timer(
      Duration(milliseconds: ms),
      () => _checkSyntax(code, gen, isBody: isBody),
    );
  }

  Future<void> _checkSyntax(
    String code,
    int gen, {
    required bool isBody,
  }) async {
    final ctrl = _ctrl;
    if (ctrl == null || code.isEmpty) return;
    widget.onBackendChecking?.call(true);
    try {
      // PACKAGE BODY requires a different objectType for the backend validator
      final objType = (isBody && widget.objectType == 'PACKAGE')
          ? 'PACKAGE BODY'
          : widget.objectType;
      final errors = await SchemaService.instance.validateSyntax(
        code,
        objType,
        ambiente: widget.ambiente,
      );
      if (!mounted || gen != _checkGen) return; // user typed again — discard
      final doc = isBody ? _bodyDoc : _specDoc;
      if (doc == null) return;
      final issues = errors
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
      await doc.setMarkers([
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
            source: 'Oracle',
          ),
      ], owner: 'plsql-checker');
    } finally {
      if (mounted) widget.onBackendChecking?.call(false);
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
          contentDebounce: const Duration(milliseconds: 600),
          onReady: _onReady,
          onContentChanged: (text) {
            if (_isBody) {
              _currentBodyCode = text;
              widget.onBodyTextChanged?.call(text);
              if (widget.isPlSql) _scheduleCheck(text, isBody: true);
            } else {
              _currentSpecCode = text;
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
        if (_isBody && !_bodyReady)
          const Positioned(
            left: 12,
            bottom: 12,
            child: StatusCard(message: 'Cargando cuerpo...'),
          ),
      ],
    );
  }
}
