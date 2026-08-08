import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/schema_service.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/object_source_page.dart';
import '../widgets/schema_object_details_sheet.dart';
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ObjectSourcePage(
          name: name,
          objectType: objectType,
          ambiente: _currentAmbiente,
        ),
      ),
    );
  }

  static String _oracleType(String? detail) => switch (detail) {
    'procedure' => 'PROCEDURE',
    'function' => 'FUNCTION',
    'package' => 'PACKAGE',
    'type' => 'TYPE',
    _ => 'PROCEDURE',
  };

  void _toggleSection(String key) =>
      setState(() => _expanded[key] = !(_expanded[key] ?? false));

  void _toggleTable(String table) {
    final nowOpen = !(_expandedTables[table] ?? false);
    setState(() => _expandedTables[table] = nowOpen);
    if (nowOpen) _loadColumns(table);
  }

  void _toggleType(String typeName) {
    final nowOpen = !(_expandedTypes[typeName] ?? false);
    setState(() => _expandedTypes[typeName] = nowOpen);
    if (nowOpen) _loadTypeAttrs(typeName);
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
    if (nowOpen) _loadPackageSubprogs(name);
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
    if (nowOpen) _loadObjectArgs(name);
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
    final width = (size.width * 0.85).clamp(400.0, 640.0);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          height: size.height * 0.75,
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
                  widget.ambiente,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
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
          const SizedBox(width: 10),
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
        final nodes = _buildNodes(snap.data!);
        if (nodes.isEmpty) {
          return Center(
            child: Text(
              _filter.isNotEmpty
                  ? 'Sin resultados para "$_filter"'
                  : 'Sin datos disponibles',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          );
        }
        // Solo renderiza los items visibles en pantalla.
        return ListView.builder(
          itemCount: nodes.length,
          itemBuilder: (_, i) => _buildNodeWidget(nodes[i], isDark),
        );
      },
    );
  }

  Widget _buildNodeWidget(_Node node, bool isDark) {
    final textColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final subColor = isDark ? const Color(0xFF888888) : Colors.black45;
    final rowBg = isDark ? const Color(0xFF252526) : const Color(0xFFF8F8F8);
    final colBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFAFAFA);

    switch (node.kind) {
      case _NK.section:
        final key = node.detail!;
        final isOpen = _filter.isNotEmpty || (_expanded[key] ?? false);
        return InkWell(
          onTap: _filter.isNotEmpty ? null : () => _toggleSection(key),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Icon(node.icon, size: 16, color: node.color),
                const SizedBox(width: 8),
                Text(
                  node.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: node.color,
                  ),
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
        );

      case _NK.table:
        final isOpen = _expandedTables[node.label] ?? false;
        return InkWell(
          onTap: () => _toggleTable(node.label),
          child: Container(
            color: rowBg,
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
                  child: Text(
                    node.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if ((node.owner ?? '').isNotEmpty)
                  _ownerBadge(node.owner!, subColor),
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
                if (node.detail == 'view') ...[
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
                ],
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
                    child: Icon(Icons.info_outline, size: 13, color: subColor),
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
        return Container(
          color: colBg,
          padding: const EdgeInsets.fromLTRB(64, 5, 16, 5),
          child: Row(
            children: [
              Icon(Icons.view_column_outlined, size: 12, color: subColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.label,
                  style: TextStyle(fontSize: 11.5, color: textColor),
                ),
              ),
              Text(
                node.detail ?? '',
                style: TextStyle(
                  fontSize: 11,
                  color: subColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
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
        return InkWell(
          onTap: () => isPkg
              ? _togglePackage(node.label)
              : isTyp
              ? _toggleType(node.label)
              : _toggleObject(node.label),
          child: Container(
            color: rowBg,
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
                  child: Text(
                    node.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if ((node.owner ?? '').isNotEmpty)
                  _ownerBadge(node.owner!, subColor),
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
                  const SizedBox(width: 2),
                ],
                InkWell(
                  onTap: () =>
                      _openSource(node.label, _oracleType(node.detail)),
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
                    child: Icon(Icons.info_outline, size: 13, color: subColor),
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
        );

      case _NK.subprogram:
        // id = 'sp_PKG::PROC'
        final spKey = node.id.substring(3);
        final isSpOpen = _expandedSubprogs[spKey] ?? false;
        final isFunc = node.detail == 'FUNCTION';
        return InkWell(
          onTap: () => _toggleSubprog(spKey),
          child: Container(
            color: rowBg,
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
                  child: Text(
                    node.label,
                    style: TextStyle(fontSize: 11.5, color: textColor),
                  ),
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
                      size: 12,
                      color: _copiedNodes.contains(node.id)
                          ? Colors.green
                          : subColor,
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
        return Container(
          color: colBg,
          padding: const EdgeInsets.fromLTRB(64, 5, 16, 5),
          child: Row(
            children: [
              if (inOut.isNotEmpty) ...[
                Container(
                  width: 32,
                  alignment: Alignment.centerLeft,
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
              if (node.detail != null)
                Text(
                  node.detail!,
                  style: TextStyle(
                    fontSize: 11,
                    color: subColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
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
