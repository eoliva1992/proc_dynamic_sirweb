import 'package:flutter/material.dart';
import '../services/schema_service.dart';

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

enum _NK { section, table, colLoading, column, object, arg }

class _Node {
  final _NK kind;
  final String id;
  final String label;
  final String? detail; // dataType para column/arg; sectionKey para section
  final String? extra; // inOut para arg ("IN" | "OUT" | "IN/OUT")
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
  late final Future<SchemaMetadata> _schemaFuture;
  final _searchCtrl = TextEditingController();
  final _columns = <String, List<({String name, String dataType})>>{};
  final _loadingCols = <String>{};
  final _objectArgs =
      <String, List<({String name, String dataType, String inOut})>>{};
  final _loadingArgs = <String>{};
  final _expanded = <String, bool>{};
  final _expandedTables = <String, bool>{};
  final _expandedObjects = <String, bool>{};
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _schemaFuture = SchemaService.instance.getMetadata(
      ambiente: widget.ambiente,
    );
    _searchCtrl.addListener(
      () => setState(() => _filter = _searchCtrl.text.toLowerCase().trim()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadColumns(String table) async {
    if (_columns.containsKey(table) || _loadingCols.contains(table)) return;
    setState(() => _loadingCols.add(table));
    final cols = await SchemaService.instance.getColumns(
      table,
      ambiente: widget.ambiente,
    );
    if (mounted) {
      setState(() {
        _columns[table] = cols;
        _loadingCols.remove(table);
      });
    }
  }

  void _toggleSection(String key) =>
      setState(() => _expanded[key] = !(_expanded[key] ?? false));

  void _toggleTable(String table) {
    final nowOpen = !(_expandedTables[table] ?? false);
    setState(() => _expandedTables[table] = nowOpen);
    if (nowOpen) _loadColumns(table);
  }

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
      ambiente: widget.ambiente,
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
            for (final col in _columns[item]!) {
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
        } else if (isObjects) {
          nodes.add(
            _Node(
              kind: _NK.object,
              id: 'obj_${key}_$item',
              label: item,
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
            for (final arg in _objectArgs[item]!) {
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
            if (_objectArgs[item]!.isEmpty) {
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

    addSection(
      'tables',
      'Tablas',
      _filterStrings(schema.tables),
      Icons.table_chart_outlined,
      const Color(0xFF0078D4),
      isTables: true,
    );
    addSection(
      'views',
      'Vistas',
      _filterStrings(schema.views),
      Icons.visibility_outlined,
      const Color(0xFF107C10),
    );
    addSection(
      'procedures',
      'Procedimientos',
      _filterByType(schema.objects, 'PROCEDURE'),
      Icons.code_rounded,
      const Color(0xFFCA5010),
      isObjects: true,
    );
    addSection(
      'functions',
      'Funciones',
      _filterByType(schema.objects, 'FUNCTION'),
      Icons.functions_rounded,
      const Color(0xFF8764B8),
      isObjects: true,
    );
    addSection(
      'packages',
      'Paquetes',
      _filterByType(schema.objects, 'PACKAGE'),
      Icons.inventory_2_outlined,
      const Color(0xFFC19C00),
      isObjects: true,
    );

    return nodes;
  }

  List<String> _filterStrings(List<String> list) {
    if (_filter.isEmpty) return list;
    return list.where((s) => s.toLowerCase().contains(_filter)).toList();
  }

  List<String> _filterByType(
    List<({String name, String type})> objects,
    String type,
  ) {
    final typed = objects.where((o) => o.type == type);
    if (_filter.isEmpty) return typed.map((o) => o.name).toList();
    return typed
        .where((o) => o.name.toLowerCase().contains(_filter))
        .map((o) => o.name)
        .toList();
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
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
          ),
        ),
      ),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? const Color(0xFFD4D4D4) : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar tabla, vista, procedimiento…',
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
                    color: isDark ? const Color(0xFF888888) : Colors.black45,
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
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF0078D4), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    return FutureBuilder<SchemaMetadata>(
      future: _schemaFuture,
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
                  Icons.table_rows_outlined,
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
        final isObjOpen = _expandedObjects[node.label] ?? false;
        return InkWell(
          onTap: () => _toggleObject(node.label),
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
                if (_loadingArgs.contains(node.label))
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
