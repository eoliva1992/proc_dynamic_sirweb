import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/schema_service.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/schema_object_details_sheet.dart';
import '../widgets/source_float_window.dart';
import '../screens/schema_object_diff_page.dart';

/// Abre el explorador de esquema con fondo semi-transparente.
Future<void> showSchemaBrowser(
  BuildContext context, {
  required String ambiente,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'schema-browser',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (ctx, _, _) => _SchemaBrowserModal(ambiente: ambiente),
  );
}

// --- Tipos de nodo para la lista plana virtualizada ---

enum _NK {
  section,
  table,
  colLoading,
  column,
  object,
  arg,
  subprogram,
  childSearch,
}

class _Node {
  final _NK kind;
  final String id;
  final String label;
  final String? detail; // dataType para column/arg; sectionKey para section
  final String? extra; // inOut para arg
  final String? owner; // dueño Oracle del objeto
  final IconData icon;
  final Color color;
  final int? count;

  const _Node({
    required this.kind,
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.detail,
    this.extra,
    this.owner,
    this.count,
  });
}

class _SchemaBrowserModal extends StatefulWidget {
  final String ambiente;
  const _SchemaBrowserModal({required this.ambiente});

  @override
  State<_SchemaBrowserModal> createState() => _SchemaBrowserModalState();
}

class _SchemaBrowserModalState extends State<_SchemaBrowserModal> {
  // Per-ambiente schema futures — evita recargar al volver a un ambiente ya cargado.
  final _schemaFutures = <String, Future<SchemaMetadata>>{};
  late String _currentAmbiente;
  bool _wasRefreshing = false; // detecta cuando el refresh de fondo completa
  final _searchCtrl = TextEditingController();
  final _columns = <String, List<({String name, String dataType})>>{};
  final _loadingCols = <String>{};
  final _objectArgs =
      <String, List<({String name, String dataType, String inOut})>>{};
  final _loadingArgs = <String>{};
  final _packageSubprogs =
      <
        String,
        List<
          ({
            String name,
            String kind,
            List<({String name, String dataType, String inOut})> arguments,
          })
        >
      >{};
  final _loadingPackages = <String>{};
  final _typeAttrs = <String, List<({String name, String dataType})>>{};
  final _loadingTypeAttrs = <String>{};
  final _copiedNodes =
      <String>{}; // ids con copia reciente para feedback visual
  final _expanded = <String, bool>{};
  final _expandedTables = <String, bool>{};
  final _expandedObjects = <String, bool>{};
  final _expandedSubprogs = <String, bool>{};
  final _expandedTypes = <String, bool>{};
  // key = parent node id (e.g. 'tbl_TABLE'), only shown when !hasFilter && children > 10
  final _childSearch = <String, String>{};
  final _childSearchCtrls = <String, TextEditingController>{};
  final _childSearchDebounces = <String, Timer>{};
  String _filter = '';
  _Node? _selectedNode;
  String? _hoveredNodeId;
  double _treeWidth = 340.0;
  final _treeFocusNode = FocusNode();
  int _focusedIndex = -1;

  @override
  void initState() {
    super.initState();
    _currentAmbiente = widget.ambiente;
    _schemaFutures[_currentAmbiente] = SchemaService.instance.getMetadata(
      ambiente: _currentAmbiente,
    );
    _searchCtrl.addListener(
      () => setState(() => _filter = _searchCtrl.text.toLowerCase().trim()),
    );
    SchemaService.instance.status.addListener(_onSchemaStatus);
  }

  void _onSchemaStatus() {
    final s = SchemaService.instance.status.value;
    if (s == SchemaLoadStatus.refreshing) {
      _wasRefreshing = true;
    } else if (s == SchemaLoadStatus.ready && _wasRefreshing) {
      _wasRefreshing = false;
      // El refresh de fondo terminó — actualizar el future con los datos frescos.
      final fresh = SchemaService.instance.getCached(
        ambiente: _currentAmbiente,
      );
      if (fresh != null && mounted) {
        setState(() => _schemaFutures[_currentAmbiente] = Future.value(fresh));
      }
    }
  }

  @override
  void dispose() {
    SchemaService.instance.status.removeListener(_onSchemaStatus);
    _searchCtrl.dispose();
    _treeFocusNode.dispose();
    for (final c in _childSearchCtrls.values) {
      c.dispose();
    }
    for (final t in _childSearchDebounces.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _changeAmbiente(String newAmbiente) {
    if (newAmbiente == _currentAmbiente) return;
    _schemaFutures.putIfAbsent(
      newAmbiente,
      () => SchemaService.instance.getMetadata(ambiente: newAmbiente),
    );
    setState(() {
      _currentAmbiente = newAmbiente;
      // Limpiar caches locales — los datos son por ambiente
      _columns.clear();
      _loadingCols.clear();
      _objectArgs.clear();
      _loadingArgs.clear();
      _packageSubprogs.clear();
      _loadingPackages.clear();
      _typeAttrs.clear();
      _loadingTypeAttrs.clear();
      _expandedTables.clear();
      _expandedObjects.clear();
      _expandedSubprogs.clear();
      _expandedTypes.clear();
      _copiedNodes.clear();
      for (final c in _childSearchCtrls.values) {
        c.dispose();
      }
      _childSearchCtrls.clear();
      _childSearch.clear();
    });
  }

  Future<void> _loadColumns(String table) async {
    if (_columns.containsKey(table) || _loadingCols.contains(table)) return;
    setState(() => _loadingCols.add(table));
    // Look up the actual owner so ALL_TAB_COLUMNS can be queried for cross-schema tables
    final schema = SchemaService.instance.getCached(ambiente: _currentAmbiente);
    final owner = schema?.tableOwners[table] ?? schema?.viewOwners[table];
    final cols = await SchemaService.instance.getColumns(
      table,
      owner: owner,
      ambiente: _currentAmbiente,
    );
    if (mounted) {
      setState(() {
        _columns[table] = cols;
        _loadingCols.remove(table);
      });
    }
  }

  // Genera un SELECT con las columnas cargadas (tabla o vista).
  String _buildSelectBlock(String name) {
    final cols = _columns[name];
    if (cols == null || cols.isEmpty) {
      return 'SELECT *\nFROM $name';
    }
    final colLines = cols.map((c) => '  ${c.name}').join(',\n');
    return 'SELECT\n$colLines\nFROM $name';
  }

  // Genera un bloque PL/SQL de ejemplo para procedimientos y funciones.
  String _buildPlSqlBlock({
    required String callName,
    required bool isFunction,
    required List<({String name, String dataType, String inOut})>? args,
  }) {
    final returnArg = isFunction
        ? args?.where((a) => a.name == '(RETURN)').firstOrNull
        : null;
    final params = args?.where((a) => a.name != '(RETURN)').toList();

    String callExpr;
    if (params == null) {
      callExpr = '$callName(\n    /* parámetros */';
      callExpr += '\n  )';
    } else if (params.isEmpty) {
      callExpr = '$callName()';
    } else {
      final lines = params.map((p) => '    ${p.name} => /*valor*/').join(',\n');
      callExpr = '$callName(\n$lines\n  )';
    }

    // Si hay parámetro de salida de error, agregar condición de control post-llamada.
    final errorParam = params
        ?.where((p) => p.name.contains('ERROR') && p.inOut.contains('OUT'))
        .firstOrNull;
    final errorCheck = errorParam != null
        ? '\n  IF ${errorParam.name} IS NOT NULL THEN\n    RETURN;\n  END IF;'
        : '';

    if (isFunction) {
      final ret = returnArg?.dataType ?? 'TIPO_RETORNO';
      return 'DECLARE\n  v_result $ret;\nBEGIN\n  v_result := $callExpr;$errorCheck\nEXCEPTION\n  WHEN OTHERS THEN\n    NULL;\nEND;';
    }
    return 'BEGIN\n  $callExpr;$errorCheck\nEXCEPTION\n  WHEN OTHERS THEN\n    NULL;\nEND;';
  }

  // Genera la declaración de variable para tipos Oracle (sin bloque lógico).
  String _buildTypeBlock({
    required String typeName,
    required List<({String name, String dataType})>? attrs,
  }) {
    final isCollection =
        attrs != null && attrs.length == 1 && attrs[0].name.contains('OF');
    if (isCollection) {
      final elemType = attrs[0].dataType;
      return ' v_coll $typeName := $typeName(); -- $elemType';
    }
    if (attrs == null || attrs.isEmpty) {
      return ' v_obj $typeName;';
    }
    final lines = attrs.map((a) => '    ${a.name} => /*valor*/').join(',\n');
    return ' v_obj $typeName := $typeName(\n$lines\n  );';
  }

  Future<void> _copyNode(_Node node) async {
    final String template;

    if (node.kind == _NK.object && node.detail == 'procedure') {
      if (!_objectArgs.containsKey(node.label)) {
        await _loadObjectArgs(node.label);
      }
      template = _buildPlSqlBlock(
        callName: node.label,
        isFunction: false,
        args: _objectArgs[node.label],
      );
    } else if (node.kind == _NK.object && node.detail == 'function') {
      if (!_objectArgs.containsKey(node.label)) {
        await _loadObjectArgs(node.label);
      }
      template = _buildPlSqlBlock(
        callName: node.label,
        isFunction: true,
        args: _objectArgs[node.label],
      );
    } else if (node.kind == _NK.subprogram) {
      final spKey = node.id.substring(3);
      final sepIdx = spKey.indexOf('::');
      final pkgName = sepIdx >= 0 ? spKey.substring(0, sepIdx) : spKey;
      final procName = sepIdx >= 0 ? spKey.substring(sepIdx + 2) : '';
      if (!_packageSubprogs.containsKey(pkgName)) {
        await _loadPackageSubprogs(pkgName);
      }
      final subs = _packageSubprogs[pkgName] ?? [];
      final sp = subs.where((s) => s.name == procName).firstOrNull;
      template = _buildPlSqlBlock(
        callName: '$pkgName.$procName',
        isFunction: sp?.kind == 'FUNCTION',
        args: sp?.arguments,
      );
    } else if (node.kind == _NK.table) {
      template = _buildSelectBlock(node.label);
    } else if (node.kind == _NK.object && node.detail == 'type') {
      if (!_typeAttrs.containsKey(node.label)) await _loadTypeAttrs(node.label);
      template = _buildTypeBlock(
        typeName: node.label,
        attrs: _typeAttrs[node.label],
      );
    } else {
      return;
    }

    if (!mounted) return;
    Clipboard.setData(ClipboardData(text: template));
    setState(() => _copiedNodes.add(node.id));
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedNodes.remove(node.id));
    });
  }

  void _openSource(String name, String objectType) {
    openSourceWindow(
      context,
      name: name,
      objectType: objectType,
      ambiente: _currentAmbiente,
    );
  }

  static String _oracleType(String? detail) => switch (detail) {
    'procedure' => 'PROCEDURE',
    'function' => 'FUNCTION',
    'package' => 'PACKAGE',
    'type' => 'TYPE',
    _ => 'PROCEDURE',
  };

  bool get _hasAnyExpanded =>
      _expanded.values.any((v) => v) ||
      _expandedTables.values.any((v) => v) ||
      _expandedObjects.values.any((v) => v) ||
      _expandedTypes.values.any((v) => v);

  void _collapseAll() {
    setState(() {
      _expanded.clear();
      _expandedTables.clear();
      _expandedObjects.clear();
      _expandedSubprogs.clear();
      _expandedTypes.clear();
      for (final t in _childSearchDebounces.values) t.cancel();
      _childSearchDebounces.clear();
      for (final c in _childSearchCtrls.values) c.dispose();
      _childSearchCtrls.clear();
      _childSearch.clear();
    });
  }

  void _cleanChildSearch(String parentKey) {
    _childSearchDebounces[parentKey]?.cancel();
    _childSearchDebounces.remove(parentKey);
    _childSearchCtrls[parentKey]?.dispose();
    _childSearchCtrls.remove(parentKey);
    _childSearch.remove(parentKey);
  }

  void _refreshSchema() {
    setState(() {
      _schemaFutures[_currentAmbiente] = SchemaService.instance.refreshAmbiente(
        _currentAmbiente,
      );
    });
  }

  void _toggleSection(String key) =>
      setState(() => _expanded[key] = !(_expanded[key] ?? false));

  void _toggleTable(String table) {
    final nowOpen = !(_expandedTables[table] ?? false);
    setState(() => _expandedTables[table] = nowOpen);
    if (nowOpen) {
      _loadColumns(table);
    } else {
      _cleanChildSearch('tbl_$table');
    }
  }

  void _toggleType(String typeName) {
    final nowOpen = !(_expandedTypes[typeName] ?? false);
    setState(() => _expandedTypes[typeName] = nowOpen);
    if (nowOpen) {
      _loadTypeAttrs(typeName);
    } else {
      _cleanChildSearch('typ_$typeName');
    }
  }

  Future<void> _loadTypeAttrs(String typeName) async {
    if (_typeAttrs.containsKey(typeName) ||
        _loadingTypeAttrs.contains(typeName)) {
      return;
    }
    setState(() => _loadingTypeAttrs.add(typeName));
    final attrs = await SchemaService.instance.getTypeAttributes(
      typeName,
      ambiente: _currentAmbiente,
    );
    if (mounted) {
      setState(() {
        _typeAttrs[typeName] = attrs;
        _loadingTypeAttrs.remove(typeName);
      });
    }
  }

  void _togglePackage(String name) {
    final nowOpen = !(_expandedObjects[name] ?? false);
    setState(() => _expandedObjects[name] = nowOpen);
    if (nowOpen) {
      _loadPackageSubprogs(name);
    } else {
      _cleanChildSearch('pkg_$name');
    }
  }

  Future<void> _loadPackageSubprogs(String packageName) async {
    if (_packageSubprogs.containsKey(packageName) ||
        _loadingPackages.contains(packageName)) {
      return;
    }
    setState(() => _loadingPackages.add(packageName));
    final subs = await SchemaService.instance.getPackageSubprograms(
      packageName,
      ambiente: _currentAmbiente,
    );
    if (mounted) {
      setState(() {
        _packageSubprogs[packageName] = subs;
        _loadingPackages.remove(packageName);
      });
    }
  }

  void _toggleSubprog(String spKey) => setState(
    () => _expandedSubprogs[spKey] = !(_expandedSubprogs[spKey] ?? false),
  );

  void _toggleObject(String name) {
    final nowOpen = !(_expandedObjects[name] ?? false);
    setState(() => _expandedObjects[name] = nowOpen);
    if (nowOpen) {
      _loadObjectArgs(name);
    } else {
      // parentKey puede ser obj_procedures_name o obj_functions_name
      _cleanChildSearch('obj_procedures_$name');
      _cleanChildSearch('obj_functions_$name');
    }
  }

  Future<void> _loadObjectArgs(String objectName) async {
    if (_objectArgs.containsKey(objectName) ||
        _loadingArgs.contains(objectName)) {
      return;
    }
    setState(() => _loadingArgs.add(objectName));
    final args = await SchemaService.instance.getObjectArguments(
      objectName,
      ambiente: _currentAmbiente,
    );
    if (mounted) {
      setState(() {
        _objectArgs[objectName] = args;
        _loadingArgs.remove(objectName);
      });
    }
  }

  // Construye la lista plana de nodos visibles en O(n), sin instanciar widgets.
  List<_Node> _buildNodes(SchemaMetadata schema) {
    final hasFilter = _filter.isNotEmpty;
    final nodes = <_Node>[];

    void addSection(
      String key,
      String title,
      List<String> items,
      IconData icon,
      Color color, {
      bool isTables = false,
      bool isObjects = false,
      bool isPackages = false,
      bool isTypes = false,
      Map<String, String> ownerLookup = const {},
    }) {
      if (items.isEmpty) return;
      final isOpen = hasFilter || (_expanded[key] ?? false);
      nodes.add(
        _Node(
          kind: _NK.section,
          id: 'sec_$key',
          label: title,
          detail: key,
          icon: icon,
          color: color,
          count: items.length,
        ),
      );
      if (!isOpen) return;
      for (final item in items) {
        if (isTables) {
          nodes.add(
            _Node(
              kind: _NK.table,
              id: 'tbl_$item',
              label: item,
              detail: key == 'views' ? 'view' : null,
              owner: ownerLookup[item],
              icon: icon,
              color: color,
            ),
          );
          if (!(_expandedTables[item] ?? false)) continue;
          if (_loadingCols.contains(item)) {
            nodes.add(
              _Node(
                kind: _NK.colLoading,
                id: 'cll_$item',
                label: item,
                icon: Icons.view_column_outlined,
                color: color,
              ),
            );
          } else if (_columns[item] != null) {
            final cols = _columns[item]!;
            final parentKey = 'tbl_$item';
            final showChildSearch = cols.length > 10;
            if (showChildSearch) {
              nodes.add(
                _Node(
                  kind: _NK.childSearch,
                  id: 'csearch_$parentKey',
                  label: parentKey,
                  icon: Icons.search,
                  color: color,
                ),
              );
            }
            final cf = showChildSearch ? (_childSearch[parentKey] ?? '') : '';
            for (final col in cols.where(
              (c) => cf.isEmpty || c.name.toLowerCase().contains(cf),
            )) {
              nodes.add(
                _Node(
                  kind: _NK.column,
                  id: 'col_${item}_${col.name}',
                  label: col.name,
                  detail: col.dataType,
                  icon: Icons.view_column_outlined,
                  color: color,
                ),
              );
            }
          }
        } else if (isPackages) {
          // Parsear sintaxis "PKG.PROC" del filtro
          final dotIdx = _filter.indexOf('.');
          final hasDotSyntax = hasFilter && dotIdx >= 0;
          final procPart = hasDotSyntax ? _filter.substring(dotIdx + 1) : '';

          final subs = _packageSubprogs[item];
          // Auto-expandir si hay coincidencia en un subprograma cargado
          final subMatchesPlain =
              hasFilter &&
              !hasDotSyntax &&
              subs != null &&
              subs.any((sp) => sp.name.toLowerCase().contains(_filter));
          final autoExpand =
              subMatchesPlain || (hasDotSyntax && procPart.isNotEmpty);

          // Nivel 1: paquete
          nodes.add(
            _Node(
              kind: _NK.object,
              id: 'pkg_$item',
              label: item,
              detail: 'package',
              owner: ownerLookup[item],
              icon: icon,
              color: color,
            ),
          );
          if (!(_expandedObjects[item] ?? false) && !autoExpand) continue;

          if (_loadingPackages.contains(item)) {
            nodes.add(
              _Node(
                kind: _NK.colLoading,
                id: 'pkgll_$item',
                label: item,
                icon: icon,
                color: color,
              ),
            );
          } else if (subs != null) {
            // Filtrar subprogramas visibles según el tipo de búsqueda
            final visibleSubs = !hasFilter
                ? subs
                : hasDotSyntax
                ? (procPart.isEmpty
                      ? subs
                      : subs
                            .where(
                              (sp) => sp.name.toLowerCase().contains(procPart),
                            )
                            .toList())
                : (item.toLowerCase().contains(_filter)
                      ? subs // el paquete mismo coincide → mostrar todos
                      : subs
                            .where(
                              (sp) => sp.name.toLowerCase().contains(_filter),
                            )
                            .toList());

            final parentKey = 'pkg_$item';
            final showChildSearch = subs.length > 10;
            if (showChildSearch) {
              nodes.add(
                _Node(
                  kind: _NK.childSearch,
                  id: 'csearch_$parentKey',
                  label: parentKey,
                  icon: Icons.search,
                  color: color,
                ),
              );
            }
            final cf = showChildSearch ? (_childSearch[parentKey] ?? '') : '';
            final displaySubs = cf.isEmpty
                ? visibleSubs
                : visibleSubs
                      .where((sp) => sp.name.toLowerCase().contains(cf))
                      .toList();

            if (displaySubs.isEmpty) {
              nodes.add(
                _Node(
                  kind: _NK.arg,
                  id: 'pkgempty_$item',
                  label: '(sin subprogramas)',
                  icon: icon,
                  color: color,
                ),
              );
            } else {
              for (final sp in displaySubs) {
                final spKey = '$item::${sp.name}';
                final isFunc = sp.kind == 'FUNCTION';
                // Nivel 2: subprograma
                nodes.add(
                  _Node(
                    kind: _NK.subprogram,
                    id: 'sp_$spKey',
                    label: sp.name,
                    detail: sp.kind,
                    icon: isFunc ? Icons.functions_rounded : Icons.code_rounded,
                    color: isFunc
                        ? const Color(0xFF8764B8)
                        : const Color(0xFFCA5010),
                  ),
                );
                if (!(_expandedSubprogs[spKey] ?? false)) continue;
                if (sp.arguments.isEmpty) {
                  nodes.add(
                    _Node(
                      kind: _NK.arg,
                      id: 'spempty_$spKey',
                      label: '(sin parámetros)',
                      icon: icon,
                      color: color,
                    ),
                  );
                } else {
                  // Nivel 3: argumento
                  for (final arg in sp.arguments) {
                    nodes.add(
                      _Node(
                        kind: _NK.arg,
                        id: 'sparg_${spKey}_${arg.name}',
                        label: arg.name,
                        detail: arg.dataType,
                        extra: arg.inOut,
                        icon: icon,
                        color: color,
                      ),
                    );
                  }
                }
              }
            }
          }
        } else if (isTypes) {
          // Type — expandible para ver atributos (vacío para tipos colección)
          nodes.add(
            _Node(
              kind: _NK.object,
              id: 'typ_$item',
              label: item,
              detail: 'type',
              owner: ownerLookup[item],
              icon: icon,
              color: color,
            ),
          );
          if (!(_expandedTypes[item] ?? false)) continue;
          if (_loadingTypeAttrs.contains(item)) {
            nodes.add(
              _Node(
                kind: _NK.colLoading,
                id: 'typll_$item',
                label: item,
                icon: icon,
                color: color,
              ),
            );
          } else if (_typeAttrs[item] != null) {
            if (_typeAttrs[item]!.isEmpty) {
              nodes.add(
                _Node(
                  kind: _NK.arg,
                  id: 'typempty_$item',
                  label: '(sin atributos)',
                  icon: icon,
                  color: color,
                ),
              );
            } else {
              final parentKey = 'typ_$item';
              final attrs = _typeAttrs[item]!;
              final showChildSearch = attrs.length > 10;
              if (showChildSearch) {
                nodes.add(
                  _Node(
                    kind: _NK.childSearch,
                    id: 'csearch_$parentKey',
                    label: parentKey,
                    icon: Icons.search,
                    color: color,
                  ),
                );
              }
              final cf = showChildSearch ? (_childSearch[parentKey] ?? '') : '';
              for (final attr in attrs.where(
                (a) => cf.isEmpty || a.name.toLowerCase().contains(cf),
              )) {
                nodes.add(
                  _Node(
                    kind: _NK.column,
                    id: 'typattr_${item}_${attr.name}',
                    label: attr.name,
                    detail: attr.dataType,
                    icon: Icons.view_column_outlined,
                    color: color,
                  ),
                );
              }
            }
          }
        } else if (isObjects) {
          nodes.add(
            _Node(
              kind: _NK.object,
              id: 'obj_${key}_$item',
              label: item,
              detail: key == 'functions' ? 'function' : 'procedure',
              owner: ownerLookup[item],
              icon: icon,
              color: color,
            ),
          );
          if (!(_expandedObjects[item] ?? false)) continue;
          if (_loadingArgs.contains(item)) {
            nodes.add(
              _Node(
                kind: _NK.colLoading,
                id: 'all_$item',
                label: item,
                icon: icon,
                color: color,
              ),
            );
          } else if (_objectArgs[item] != null) {
            final parentKey = 'obj_${key}_$item';
            final args = _objectArgs[item]!;
            final showChildSearch = args.length > 10;
            if (showChildSearch) {
              nodes.add(
                _Node(
                  kind: _NK.childSearch,
                  id: 'csearch_$parentKey',
                  label: parentKey,
                  icon: Icons.search,
                  color: color,
                ),
              );
            }
            final cf = showChildSearch ? (_childSearch[parentKey] ?? '') : '';
            for (final arg in args.where(
              (a) => cf.isEmpty || a.name.toLowerCase().contains(cf),
            )) {
              nodes.add(
                _Node(
                  kind: _NK.arg,
                  id: 'arg_${item}_${arg.name}',
                  label: arg.name,
                  detail: arg.dataType,
                  extra: arg.inOut,
                  icon: icon,
                  color: color,
                ),
              );
            }
            if (args.isEmpty) {
              nodes.add(
                _Node(
                  kind: _NK.arg,
                  id: 'arg_${item}_empty',
                  label: '(sin parámetros)',
                  icon: icon,
                  color: color,
                ),
              );
            }
          }
        } else {
          nodes.add(
            _Node(
              kind: _NK.object,
              id: 'obj_${key}_$item',
              label: item,
              icon: icon,
              color: color,
            ),
          );
        }
      }
    }

    // Pre-build per-type owner lookup maps
    Map<String, String> ownersByType(String type) => {
      for (final o in schema.objects.where((x) => x.type == type))
        o.name: o.owner,
    };

    addSection(
      'tables',
      'Tablas',
      _filterStrings(schema.tables),
      Icons.table_chart_outlined,
      const Color(0xFF0078D4),
      isTables: true,
      ownerLookup: schema.tableOwners,
    );
    addSection(
      'views',
      'Vistas',
      _filterStrings(schema.views),
      Icons.visibility_outlined,
      const Color(0xFF107C10),
      isTables: true,
      ownerLookup: schema.viewOwners,
    );
    addSection(
      'procedures',
      'Procedimientos',
      _filterByType(schema.objects, 'PROCEDURE'),
      Icons.code_rounded,
      const Color(0xFFCA5010),
      isObjects: true,
      ownerLookup: ownersByType('PROCEDURE'),
    );
    addSection(
      'functions',
      'Funciones',
      _filterByType(schema.objects, 'FUNCTION'),
      Icons.functions_rounded,
      const Color(0xFF8764B8),
      isObjects: true,
      ownerLookup: ownersByType('FUNCTION'),
    );
    addSection(
      'packages',
      'Paquetes',
      _filterPackages(schema.objects),
      Icons.inventory_2_outlined,
      const Color(0xFFC19C00),
      isPackages: true,
      ownerLookup: ownersByType('PACKAGE'),
    );
    addSection(
      'types',
      'Types',
      _filterByType(schema.objects, 'TYPE'),
      Icons.data_object_outlined,
      const Color(0xFF2E7D9E),
      isTypes: true,
      ownerLookup: ownersByType('TYPE'),
    );

    return nodes;
  }

  List<String> _filterStrings(List<String> list) {
    if (_filter.isEmpty) return list;
    return list.where((s) => s.toLowerCase().contains(_filter)).toList();
  }

  List<String> _filterByType(
    List<({String name, String type, String owner})> objects,
    String type,
  ) {
    final typed = objects.where((o) => o.type == type);
    if (_filter.isEmpty) return typed.map((o) => o.name).toList();
    return typed
        .where((o) => o.name.toLowerCase().contains(_filter))
        .map((o) => o.name)
        .toList();
  }

  /// Filtra paquetes: soporta sintaxis "PKG.PROC" y busca en subprogramas ya cargados.
  List<String> _filterPackages(
    List<({String name, String type, String owner})> objects,
  ) {
    final packages = objects
        .where((o) => o.type == 'PACKAGE')
        .map((o) => o.name)
        .toList();
    if (_filter.isEmpty) return packages;
    final dotIdx = _filter.indexOf('.');
    if (dotIdx >= 0) {
      // Sintaxis "PKG." o "PKG.PROC" — filtrar por la parte del paquete
      final pkgPart = _filter.substring(0, dotIdx);
      if (pkgPart.isEmpty) return packages;
      return packages.where((p) => p.toLowerCase().contains(pkgPart)).toList();
    }
    // Búsqueda plana: coincidir por nombre del paquete O por subprograma ya cargado
    return packages.where((p) {
      if (p.toLowerCase().contains(_filter)) return true;
      final subs = _packageSubprogs[p];
      return subs != null &&
          subs.any((sp) => sp.name.toLowerCase().contains(_filter));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final width = (size.width * 0.90).clamp(500.0, 1000.0);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          height: size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E1E1E).withValues(alpha: 0.97)
                : Colors.white.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                _buildHeader(isDark),
                _buildSearchBar(isDark),
                Expanded(child: _buildBody(isDark)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0078D4), Color(0xFF005A9E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.storage_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Explorador de Esquema',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _currentAmbiente,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _refreshSchema,
            icon: const Icon(
              Icons.refresh_rounded,
              color: Colors.white70,
              size: 20,
            ),
            tooltip: 'Recargar esquema',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFFD4D4D4) : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar tabla, vista, PKG.PROC…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF666666) : Colors.black38,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: isDark ? const Color(0xFF666666) : Colors.black38,
                ),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: 16,
                          color: isDark
                              ? const Color(0xFF888888)
                              : Colors.black45,
                        ),
                        onPressed: _searchCtrl.clear,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF2D2D2D) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFDDE2EA),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: Color(0xFF0078D4),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          if (_hasAnyExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                onPressed: _collapseAll,
                icon: Icon(
                  Icons.unfold_less_rounded,
                  size: 18,
                  color: isDark ? const Color(0xFF888888) : Colors.black45,
                ),
                tooltip: 'Colapsar todo',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          const SizedBox(width: 6),
          AmbienteSelector(value: _currentAmbiente, onChanged: _changeAmbiente),
        ],
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    return FutureBuilder<SchemaMetadata>(
      future: _schemaFutures[_currentAmbiente],
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF0078D4),
              strokeWidth: 2,
            ),
          );
        }
        if (snap.hasError && !snap.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 32, color: Colors.red.shade400),
                const SizedBox(height: 8),
                Text(
                  'No se pudo cargar el esquema',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          );
        }
        final schema = snap.data!;
        final nodes = _buildNodes(schema);
        return Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: _treeWidth, child: _buildTree(nodes, isDark)),
                  GestureDetector(
                    onHorizontalDragUpdate: (d) => setState(() {
                      _treeWidth = (_treeWidth + d.delta.dx).clamp(
                        220.0,
                        550.0,
                      );
                    }),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: Container(
                        width: 5,
                        color: isDark
                            ? const Color(0xFF3A3A3A)
                            : const Color(0xFFDDE2EA),
                      ),
                    ),
                  ),
                  Expanded(child: _buildDetailPanel(schema, isDark)),
                ],
              ),
            ),
            _buildStatusBar(schema, isDark),
          ],
        );
      },
    );
  }

  Widget _buildTree(List<_Node> nodes, bool isDark) {
    final subColor = isDark ? const Color(0xFF888888) : Colors.black45;
    if (nodes.isEmpty) {
      return Center(
        child: Text(
          _filter.isNotEmpty
              ? 'Sin resultados para "$_filter"'
              : 'Sin datos disponibles',
          style: TextStyle(fontSize: 13, color: subColor),
        ),
      );
    }
    return Focus(
      focusNode: _treeFocusNode,
      autofocus: true,
      onKeyEvent: (_, event) => _onKeyEvent(event, nodes),
      child: RepaintBoundary(
        child: ListView.builder(
          itemCount: nodes.length,
          itemBuilder: (_, i) => _buildNodeWidget(nodes[i], isDark, index: i),
        ),
      ),
    );
  }

  Widget _buildDetailPanel(SchemaMetadata schema, bool isDark) {
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final subColor = isDark ? const Color(0xFF888888) : Colors.black45;
    final selected = _selectedNode;
    if (selected == null) {
      return Container(
        color: bg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 40, color: subColor),
              const SizedBox(height: 12),
              Text(
                'Seleccioná un objeto del árbol',
                style: TextStyle(fontSize: 13, color: subColor),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      color: bg,
      child: switch (selected.kind) {
        _NK.section => _buildSectionDetail(selected, schema, isDark),
        _NK.table => _buildTableDetail(selected, isDark),
        _NK.object when selected.detail == 'package' => _buildPackageDetail(
          selected,
          isDark,
        ),
        _NK.object => _buildObjectDetail(selected, isDark),
        _NK.subprogram => _buildSubprogramDetail(selected, isDark),
        _NK.column || _NK.arg => _buildColumnArgDetail(selected, isDark),
        _ => const SizedBox.shrink(),
      },
    );
  }

  // ── Detail panel helpers ────────────────────────────────────────────────

  Widget _detailHeader(_Node node, bool isDark) {
    final textColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final subColor = isDark ? const Color(0xFF888888) : Colors.black45;
    final headerBg = isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 9),
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(node.icon, size: 14, color: node.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              node.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
                fontFamily: 'Consolas',
              ),
            ),
          ),
          if (node.detail != null &&
              node.detail != 'view' &&
              node.detail != 'type')
            _typeBadgeStr(node.detail!, isDark),
          if ((node.owner ?? '').isNotEmpty) ...[
            const SizedBox(width: 6),
            _ownerBadge(node.owner!, subColor),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionDetail(_Node node, SchemaMetadata schema, bool isDark) {
    final textColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final subColor = isDark ? const Color(0xFF888888) : Colors.black45;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(node.icon, size: 20, color: node.color),
              const SizedBox(width: 10),
              Text(
                node.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 8),
              _badge(node.count!, node.color),
            ],
          ),
          const SizedBox(height: 10),
          Text(switch (node.detail) {
            'tables' =>
              'Tablas del esquema Oracle. Seleccioná una para ver sus columnas.',
            'views' =>
              'Vistas del esquema. Seleccioná una para ver sus columnas.',
            'procedures' =>
              'Procedimientos almacenados. Seleccioná uno para ver sus parámetros.',
            'functions' =>
              'Funciones Oracle. Seleccioná una para ver sus parámetros.',
            'packages' =>
              'Paquetes Oracle con procedimientos y funciones agrupadas.',
            'types' => 'Tipos de datos definidos por el usuario.',
            _ => '',
          }, style: TextStyle(fontSize: 12, color: subColor)),
        ],
      ),
    );
  }

  Widget _buildTableDetail(_Node node, bool isDark) {
    final subColor = isDark ? const Color(0xFF888888) : Colors.black45;
    if (!_columns.containsKey(node.label) &&
        !_loadingCols.contains(node.label)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadColumns(node.label);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailHeader(node, isDark),
        Expanded(
          child: _loadingCols.contains(node.label)
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF0078D4),
                    strokeWidth: 2,
                  ),
                )
              : _columns[node.label] == null
              ? Center(
                  child: Text(
                    'Sin columnas disponibles',
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                )
              : _buildColumnsTable(_columns[node.label]!, isDark),
        ),
      ],
    );
  }

  Widget _buildObjectDetail(_Node node, bool isDark) {
    final subColor = isDark ? const Color(0xFF888888) : Colors.black45;
    if (!_objectArgs.containsKey(node.label) &&
        !_loadingArgs.contains(node.label)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadObjectArgs(node.label);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailHeader(node, isDark),
        Expanded(
          child: _loadingArgs.contains(node.label)
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF0078D4),
                    strokeWidth: 2,
                  ),
                )
              : _objectArgs[node.label] == null
              ? Center(
                  child: Text(
                    'Sin argumentos',
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                )
              : _buildArgsTable(_objectArgs[node.label]!, isDark),
        ),
      ],
    );
  }

  Widget _buildPackageDetail(_Node node, bool isDark) {
    final textColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final subColor = isDark ? const Color(0xFF888888) : Colors.black45;
    final rowAlt = isDark ? const Color(0xFF252526) : const Color(0xFFF8F8F8);
    if (!_packageSubprogs.containsKey(node.label) &&
        !_loadingPackages.contains(node.label)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPackageSubprogs(node.label);
      });
    }
    final subs = _packageSubprogs[node.label];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailHeader(node, isDark),
        Expanded(
          child: _loadingPackages.contains(node.label)
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF0078D4),
                    strokeWidth: 2,
                  ),
                )
              : subs == null
              ? Center(
                  child: Text(
                    'Sin subprogramas',
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  itemCount: subs.length,
                  itemBuilder: (_, i) {
                    final sp = subs[i];
                    final isFunc = sp.kind == 'FUNCTION';
                    final accent = isFunc
                        ? const Color(0xFF8764B8)
                        : const Color(0xFFCA5010);
                    return Container(
                      color: i.isOdd ? rowAlt : null,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Row(
                        children: [
                          Icon(
                            isFunc
                                ? Icons.functions_rounded
                                : Icons.code_rounded,
                            size: 13,
                            color: accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sp.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: textColor,
                                fontFamily: 'Consolas',
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isFunc ? 'FN' : 'PR',
                              style: TextStyle(
                                fontSize: 9,
                                color: accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${sp.arguments.where((a) => a.name != "(RETURN)").length}p',
                            style: TextStyle(fontSize: 10, color: subColor),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSubprogramDetail(_Node node, bool isDark) {
    final spKey = node.id.substring(3);
    final sepIdx = spKey.indexOf('::');
    final pkgName = sepIdx >= 0 ? spKey.substring(0, sepIdx) : spKey;
    final procName = sepIdx >= 0 ? spKey.substring(sepIdx + 2) : '';
    final subs = _packageSubprogs[pkgName];
    final sp = subs?.where((s) => s.name == procName).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailHeader(
          _Node(
            kind: _NK.subprogram,
            id: node.id,
            label: '$pkgName.$procName',
            icon: node.icon,
            color: node.color,
            detail: node.detail,
          ),
          isDark,
        ),
        Expanded(
          child: sp == null
              ? const SizedBox.shrink()
              : _buildArgsTable(sp.arguments, isDark),
        ),
      ],
    );
  }

  Widget _buildColumnArgDetail(_Node node, bool isDark) {
    final textColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final subColor = isDark ? const Color(0xFF888888) : Colors.black45;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            node.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
              fontFamily: 'Consolas',
            ),
          ),
          const SizedBox(height: 10),
          if (node.detail != null) ...[
            Row(
              children: [
                Text('Tipo: ', style: TextStyle(fontSize: 12, color: subColor)),
                const SizedBox(width: 4),
                _typeBadgeStr(node.detail!, isDark),
              ],
            ),
          ],
          if (node.extra != null) ...[
            const SizedBox(height: 6),
            Text(
              'Dirección: ${node.extra}',
              style: TextStyle(fontSize: 12, color: subColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColumnsTable(
    List<({String name, String dataType})> cols,
    bool isDark,
  ) {
    final textColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final rowAlt = isDark ? const Color(0xFF252526) : const Color(0xFFF8F8F8);
    return ListView.builder(
      itemCount: cols.length,
      itemBuilder: (_, i) {
        final col = cols[i];
        return Container(
          color: i.isOdd ? rowAlt : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  col.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor,
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
              _typeBadgeStr(col.dataType, isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArgsTable(
    List<({String name, String dataType, String inOut})> args,
    bool isDark,
  ) {
    final textColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final rowAlt = isDark ? const Color(0xFF252526) : const Color(0xFFF8F8F8);
    return ListView.builder(
      itemCount: args.length,
      itemBuilder: (_, i) {
        final arg = args[i];
        if (arg.name == '(RETURN)') {
          return Container(
            color: i.isOdd ? rowAlt : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Row(
              children: [
                const Text(
                  'RETURN',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF0078D4),
                  ),
                ),
                const Spacer(),
                _typeBadgeStr(arg.dataType, isDark),
              ],
            ),
          );
        }
        final dirColor = switch (arg.inOut) {
          'IN' => const Color(0xFF0078D4),
          'OUT' => const Color(0xFFCA5010),
          _ => const Color(0xFF107C10),
        };
        return Container(
          color: i.isOdd ? rowAlt : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  arg.inOut,
                  style: TextStyle(
                    fontSize: 9,
                    color: dirColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  arg.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor,
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
              _typeBadgeStr(arg.dataType, isDark),
            ],
          ),
        );
      },
    );
  }

  // ── Status bar ──────────────────────────────────────────────────────────

  Widget _buildStatusBar(SchemaMetadata schema, bool isDark) {
    final bg = isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF0F0F0);
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);
    final procCount = schema.objects
        .where((o) => o.type == 'PROCEDURE' || o.type == 'FUNCTION')
        .length;
    final pkgCount = schema.objects.where((o) => o.type == 'PACKAGE').length;
    return ValueListenableBuilder<SchemaLoadStatus>(
      valueListenable: SchemaService.instance.status,
      builder: (_, status, _) {
        final isRefreshing =
            status == SchemaLoadStatus.refreshing ||
            status == SchemaLoadStatus.loadingServer;
        return Container(
          height: 26,
          decoration: BoxDecoration(
            color: bg,
            border: Border(top: BorderSide(color: border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _statusChip(
                Icons.table_chart_outlined,
                '${schema.tables.length}',
                const Color(0xFF0078D4),
                isDark,
              ),
              const SizedBox(width: 10),
              _statusChip(
                Icons.visibility_outlined,
                '${schema.views.length}',
                const Color(0xFF107C10),
                isDark,
              ),
              const SizedBox(width: 10),
              _statusChip(
                Icons.code_rounded,
                '$procCount',
                const Color(0xFFCA5010),
                isDark,
              ),
              const SizedBox(width: 10),
              _statusChip(
                Icons.inventory_2_outlined,
                '$pkgCount',
                const Color(0xFFC19C00),
                isDark,
              ),
              const Spacer(),
              if (isRefreshing) ...[
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Color(0xFF0078D4),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                isRefreshing ? 'Actualizando…' : _currentAmbiente,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? const Color(0xFF888888) : Colors.black45,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusChip(IconData icon, String label, Color color, bool isDark) {
    final text = isDark ? const Color(0xFF888888) : Colors.black45;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color.withValues(alpha: 0.7)),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10, color: text)),
      ],
    );
  }

  // ── Keyboard navigation ──────────────────────────────────────────────────

  KeyEventResult _onKeyEvent(KeyEvent event, List<_Node> nodes) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _focusedIndex = (_focusedIndex + 1).clamp(0, nodes.length - 1);
        _selectedNode = nodes[_focusedIndex];
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _focusedIndex = (_focusedIndex - 1).clamp(0, nodes.length - 1);
        _selectedNode = nodes[_focusedIndex];
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      if (_focusedIndex >= 0 && _focusedIndex < nodes.length) {
        _activateNode(nodes[_focusedIndex]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f5) {
      _refreshSchema();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _activateNode(_Node node) {
    switch (node.kind) {
      case _NK.section:
        if (node.detail != null) _toggleSection(node.detail!);
      case _NK.table:
        _toggleTable(node.label);
      case _NK.object:
        if (node.detail == 'package') {
          _togglePackage(node.label);
        } else if (node.detail == 'type') {
          _toggleType(node.label);
        } else {
          _toggleObject(node.label);
        }
      case _NK.subprogram:
        _toggleSubprog(node.id.substring(3));
      default:
        break;
    }
    setState(() => _selectedNode = node);
  }

  // ── Visual helpers ───────────────────────────────────────────────────────

  static Color _typeColor(String dt) {
    final t = dt.toUpperCase();
    if (t.contains('NUMBER') ||
        t.contains('INTEGER') ||
        t.contains('FLOAT') ||
        t.contains('DECIMAL') ||
        t.contains('NUMERIC')) {
      return const Color(0xFF0078D4);
    }
    if (t.contains('VARCHAR') || t.contains('CHAR') || t.contains('NCHAR')) {
      return const Color(0xFF107C10);
    }
    if (t.contains('DATE') ||
        t.contains('TIMESTAMP') ||
        t.contains('INTERVAL')) {
      return const Color(0xFFCA5010);
    }
    if (t.contains('CLOB') ||
        t.contains('BLOB') ||
        t.contains('XML') ||
        t.contains('RAW') ||
        t.contains('BINARY')) {
      return const Color(0xFF8764B8);
    }
    if (t.contains('BOOL') ||
        t.contains('PLS_INTEGER') ||
        t.contains('BINARY_INTEGER')) {
      return const Color(0xFF2E7D9E);
    }
    return const Color(0xFF888888);
  }

  Widget _typeBadgeStr(String dt, bool isDark) {
    if (dt.isEmpty) return const SizedBox.shrink();
    final color = _typeColor(dt);
    final label = dt.length > 14 ? '${dt.substring(0, 14)}…' : dt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w600,
          fontFamily: 'Consolas',
        ),
      ),
    );
  }

  Widget _highlight(
    String text,
    Color baseColor, {
    double fontSize = 12.0,
    FontWeight weight = FontWeight.normal,
    String? fontFamily,
  }) {
    if (_filter.isEmpty) {
      return Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          color: baseColor,
          fontWeight: weight,
          fontFamily: fontFamily,
        ),
      );
    }
    final lower = text.toLowerCase();
    final idx = lower.indexOf(_filter);
    if (idx == -1) {
      return Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          color: baseColor,
          fontWeight: weight,
          fontFamily: fontFamily,
        ),
      );
    }
    final end = idx + _filter.length;
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          color: baseColor,
          fontWeight: weight,
          fontFamily: fontFamily,
        ),
        children: [
          if (idx > 0) TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, end),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              backgroundColor: const Color(0xFF0078D4).withValues(alpha: 0.18),
              color: const Color(0xFF0078D4),
            ),
          ),
          if (end < text.length) TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }

  Widget _buildNodeWidget(_Node node, bool isDark, {int index = -1}) {
    final textColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final subColor = isDark ? const Color(0xFF888888) : Colors.black45;
    final rowBg = isDark ? const Color(0xFF252526) : const Color(0xFFF8F8F8);
    final colBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFAFAFA);
    final isSelected = _selectedNode?.id == node.id;
    final isFocused = index == _focusedIndex && index >= 0;
    final isHovered = _hoveredNodeId == node.id;

    Color? selectionBg(Color accent) {
      if (isSelected) return accent.withValues(alpha: 0.08);
      if (isFocused) return accent.withValues(alpha: 0.05);
      if (isHovered) return rowBg;
      return null;
    }

    switch (node.kind) {
      case _NK.section:
        final key = node.detail!;
        final isOpen = _filter.isNotEmpty || (_expanded[key] ?? false);
        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredNodeId = node.id),
          onExit: (_) => setState(() => _hoveredNodeId = null),
          child: InkWell(
            onTap: () {
              if (_filter.isEmpty) _toggleSection(key);
              setState(() {
                _selectedNode = node;
                _focusedIndex = index;
              });
            },
            child: Container(
              color: selectionBg(node.color),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Icon(node.icon, size: 16, color: node.color),
                  const SizedBox(width: 8),
                  _highlight(
                    node.label,
                    node.color,
                    fontSize: 13,
                    weight: FontWeight.w600,
                  ),
                  const SizedBox(width: 8),
                  _badge(node.count!, node.color),
                  const Spacer(),
                  if (_filter.isEmpty)
                    Icon(
                      isOpen ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: subColor,
                    ),
                ],
              ),
            ),
          ),
        );

      case _NK.table:
        final isOpen = _expandedTables[node.label] ?? false;
        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredNodeId = node.id),
          onExit: (_) => setState(() => _hoveredNodeId = null),
          child: InkWell(
            onTap: () {
              _toggleTable(node.label);
              setState(() {
                _selectedNode = node;
                _focusedIndex = index;
              });
            },
            child: Container(
              color: selectionBg(node.color) ?? (isHovered ? rowBg : null),
              padding: const EdgeInsets.fromLTRB(40, 7, 16, 7),
              child: Row(
                children: [
                  Icon(
                    node.icon,
                    size: 13,
                    color: node.color.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _highlight(
                      node.label,
                      textColor,
                      fontSize: 12,
                      weight: FontWeight.w500,
                    ),
                  ),
                  if ((node.owner ?? '').isNotEmpty)
                    _ownerBadge(node.owner!, subColor),
                  AnimatedOpacity(
                    opacity: isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _copyNode(node),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              _copiedNodes.contains(node.id)
                                  ? Icons.check_rounded
                                  : Icons.content_copy_outlined,
                              size: 13,
                              color: _copiedNodes.contains(node.id)
                                  ? Colors.green
                                  : subColor,
                            ),
                          ),
                        ),
                        if (node.detail == 'view')
                          InkWell(
                            onTap: () => _openSource(node.label, 'VIEW'),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.integration_instructions_outlined,
                                size: 13,
                                color: subColor,
                              ),
                            ),
                          ),
                        InkWell(
                          onTap: () => showObjectDetails(
                            context,
                            name: node.label,
                            type: node.detail == 'view' ? 'VIEW' : 'TABLE',
                            ambiente: _currentAmbiente,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.info_outline,
                              size: 13,
                              color: subColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  if (_loadingCols.contains(node.label))
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFF0078D4),
                      ),
                    )
                  else
                    Icon(
                      isOpen ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                      color: subColor,
                    ),
                ],
              ),
            ),
          ),
        );

      case _NK.colLoading:
        return Container(
          color: colBg,
          padding: const EdgeInsets.fromLTRB(64, 8, 16, 8),
          child: const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Color(0xFF0078D4),
            ),
          ),
        );

      case _NK.column:
        return InkWell(
          onTap: () => setState(() {
            _selectedNode = node;
            _focusedIndex = index;
          }),
          child: Container(
            color: isSelected
                ? const Color(0xFF0078D4).withValues(alpha: 0.07)
                : colBg,
            padding: const EdgeInsets.fromLTRB(64, 5, 16, 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    node.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: textColor,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ),
                if (node.detail != null) _typeBadgeStr(node.detail!, isDark),
              ],
            ),
          ),
        );

      case _NK.object:
        final isPkg = node.detail == 'package';
        final isTyp = node.detail == 'type';
        final isObjOpen = isTyp
            ? (_expandedTypes[node.label] ?? false)
            : (_expandedObjects[node.label] ?? false);
        final isObjLoading = isPkg
            ? _loadingPackages.contains(node.label)
            : isTyp
            ? _loadingTypeAttrs.contains(node.label)
            : _loadingArgs.contains(node.label);
        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredNodeId = node.id),
          onExit: (_) => setState(() => _hoveredNodeId = null),
          child: InkWell(
            onTap: () {
              if (isPkg) {
                _togglePackage(node.label);
              } else if (isTyp) {
                _toggleType(node.label);
              } else {
                _toggleObject(node.label);
              }
              setState(() {
                _selectedNode = node;
                _focusedIndex = index;
              });
            },
            child: Container(
              color: selectionBg(node.color),
              padding: const EdgeInsets.fromLTRB(40, 7, 16, 7),
              child: Row(
                children: [
                  Icon(
                    node.icon,
                    size: 13,
                    color: node.color.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _highlight(
                      node.label,
                      textColor,
                      fontSize: 12,
                      weight: FontWeight.w500,
                    ),
                  ),
                  if ((node.owner ?? '').isNotEmpty)
                    _ownerBadge(node.owner!, subColor),
                  AnimatedOpacity(
                    opacity: isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 4),
                        if (!isPkg) ...[
                          InkWell(
                            onTap: () => _copyNode(node),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                _copiedNodes.contains(node.id)
                                    ? Icons.check_rounded
                                    : Icons.content_copy_outlined,
                                size: 13,
                                color: _copiedNodes.contains(node.id)
                                    ? Colors.green
                                    : subColor,
                              ),
                            ),
                          ),
                        ],
                        InkWell(
                          onTap: () =>
                              _openSource(node.label, _oracleType(node.detail)),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Tooltip(
                              message: 'Ver fuente',
                              child: Icon(
                                Icons.integration_instructions_outlined,
                                size: 13,
                                color: subColor,
                              ),
                            ),
                          ),
                        ),
                        if (!isPkg) ...[
                          InkWell(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SchemaObjectDiffPage(
                                  objectName: node.label,
                                  objectType: _oracleType(node.detail),
                                  sourceAmbiente: _currentAmbiente,
                                ),
                              ),
                            ),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.compare_arrows,
                                size: 13,
                                color: subColor,
                              ),
                            ),
                          ),
                        ],
                        InkWell(
                          onTap: () => showObjectDetails(
                            context,
                            name: node.label,
                            type: _oracleType(node.detail),
                            ambiente: _currentAmbiente,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.info_outline,
                              size: 13,
                              color: subColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  if (isObjLoading)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFF0078D4),
                      ),
                    )
                  else
                    Icon(
                      isObjOpen ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                      color: subColor,
                    ),
                ],
              ),
            ),
          ),
        );

      case _NK.subprogram:
        final spKey = node.id.substring(3);
        final isSpOpen = _expandedSubprogs[spKey] ?? false;
        final isFunc = node.detail == 'FUNCTION';
        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredNodeId = node.id),
          onExit: (_) => setState(() => _hoveredNodeId = null),
          child: InkWell(
            onTap: () {
              _toggleSubprog(spKey);
              setState(() {
                _selectedNode = node;
                _focusedIndex = index;
              });
            },
            child: Container(
              color: selectionBg(node.color),
              padding: const EdgeInsets.fromLTRB(56, 6, 16, 6),
              child: Row(
                children: [
                  Icon(
                    node.icon,
                    size: 12,
                    color: node.color.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _highlight(node.label, textColor, fontSize: 11.5),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: node.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isFunc ? 'FN' : 'PR',
                      style: TextStyle(
                        fontSize: 9,
                        color: node.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: InkWell(
                      onTap: () => _copyNode(node),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _copiedNodes.contains(node.id)
                              ? Icons.check_rounded
                              : Icons.content_copy_outlined,
                          size: 12,
                          color: _copiedNodes.contains(node.id)
                              ? Colors.green
                              : subColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    isSpOpen ? Icons.expand_less : Icons.expand_more,
                    size: 13,
                    color: subColor,
                  ),
                ],
              ),
            ),
          ),
        );

      case _NK.childSearch:
        final key = node.label;
        final ctrl = _childSearchCtrls.putIfAbsent(key, () {
          final c = TextEditingController(text: _childSearch[key] ?? '');
          c.addListener(() {
            final t = c.text.toLowerCase();
            if (_childSearch[key] == t) return;
            _childSearchDebounces[key]?.cancel();
            _childSearchDebounces[key] = Timer(
              const Duration(milliseconds: 300),
              () {
                if (mounted) setState(() => _childSearch[key] = t);
              },
            );
          });
          return c;
        });
        return Container(
          color: colBg,
          padding: const EdgeInsets.fromLTRB(52, 4, 16, 4),
          child: TextField(
            controller: ctrl,
            autofocus: false,
            style: TextStyle(fontSize: 12, color: textColor),
            decoration: InputDecoration(
              hintText: 'Buscar...',
              hintStyle: TextStyle(fontSize: 12, color: subColor),
              prefixIcon: Icon(Icons.search, size: 14, color: subColor),
              suffixIcon: ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 12, color: subColor),
                      onPressed: ctrl.clear,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF2D2D2D) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF3A3A3A)
                      : const Color(0xFFDDE2EA),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(
                  color: Color(0xFF0078D4),
                  width: 1.5,
                ),
              ),
            ),
          ),
        );

      case _NK.arg:
        final inOut = node.extra ?? '';
        final dirColor = switch (inOut) {
          'IN' => const Color(0xFF0078D4),
          'OUT' => const Color(0xFFCA5010),
          _ => subColor,
        };
        return InkWell(
          onTap: () => setState(() {
            _selectedNode = node;
            _focusedIndex = index;
          }),
          child: Container(
            color: isSelected
                ? const Color(0xFF0078D4).withValues(alpha: 0.07)
                : colBg,
            padding: const EdgeInsets.fromLTRB(64, 5, 16, 5),
            child: Row(
              children: [
                if (inOut.isNotEmpty) ...[
                  SizedBox(
                    width: 32,
                    child: Text(
                      inOut,
                      style: TextStyle(
                        fontSize: 9,
                        color: dirColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                ] else
                  const SizedBox(width: 34),
                Expanded(
                  child: Text(
                    node.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: node.detail == null ? subColor : textColor,
                      fontStyle: node.detail == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
                if (node.detail != null) _typeBadgeStr(node.detail!, isDark),
              ],
            ),
          ),
        );
    }
  }

  Widget _ownerBadge(String owner, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: textColor.withValues(alpha: 0.20),
          width: 0.5,
        ),
      ),
      child: Text(
        owner,
        style: TextStyle(
          fontSize: 9,
          color: textColor.withValues(alpha: 0.75),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _badge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
