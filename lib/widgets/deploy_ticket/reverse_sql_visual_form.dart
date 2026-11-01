import 'package:flutter/material.dart';
import '../../models/reverse_sql_config.dart';

/// Formulario visual estructurado para configurar tablas de extracción YAML (Reverse SQL).
class ReverseSqlVisualForm extends StatefulWidget {
  final ReverseSqlConfig config;
  final ValueChanged<ReverseSqlConfig> onChanged;

  const ReverseSqlVisualForm({
    super.key,
    required this.config,
    required this.onChanged,
  });

  @override
  State<ReverseSqlVisualForm> createState() => _ReverseSqlVisualFormState();
}

class _ReverseSqlVisualFormState extends State<ReverseSqlVisualForm> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  // Mapa para controlar la expansión individual de cada tabla por su índice.
  // Cuando se pulsa "Expandir todo" o "Colapsar todo", actualiza este mapa.
  final Map<int, bool> _expandedMap = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _addTable() {
    final updated = List<ReverseSqlTableConfig>.from(widget.config.tables)
      ..add(
        const ReverseSqlTableConfig(
          dml: ReverseSqlDml.merge,
          name: '',
          pkAdd: true,
        ),
      );
    // La nueva tabla creada la abrimos automáticamente para que el usuario pueda editarla de inmediato
    _expandedMap[updated.length - 1] = true;
    widget.onChanged(widget.config.copyWith(tables: updated));
  }

  void _removeTable(int index) {
    if (index < 0 || index >= widget.config.tables.length) return;
    final updated = List<ReverseSqlTableConfig>.from(widget.config.tables)
      ..removeAt(index);

    // Ajustar el mapa de expansión desplazando los índices superiores
    final newExpanded = <int, bool>{};
    for (var i = 0; i < widget.config.tables.length; i++) {
      if (i == index) continue;
      final targetIdx = i > index ? i - 1 : i;
      if (_expandedMap.containsKey(i)) {
        newExpanded[targetIdx] = _expandedMap[i]!;
      }
    }
    _expandedMap
      ..clear()
      ..addAll(newExpanded);

    widget.onChanged(widget.config.copyWith(tables: updated));
  }

  void _duplicateTable(int index) {
    if (index < 0 || index >= widget.config.tables.length) return;
    final item = widget.config.tables[index];
    final copy = item.copyWith(
      name: item.name.isNotEmpty ? '${item.name}_copy' : '',
    );
    final updated = List<ReverseSqlTableConfig>.from(widget.config.tables)
      ..insert(index + 1, copy);

    // Desplazar mapa de expansión
    final newExpanded = <int, bool>{};
    for (var i = 0; i < widget.config.tables.length; i++) {
      final targetIdx = i >= index + 1 ? i + 1 : i;
      if (_expandedMap.containsKey(i)) {
        newExpanded[targetIdx] = _expandedMap[i]!;
      }
    }
    newExpanded[index + 1] = false;
    _expandedMap
      ..clear()
      ..addAll(newExpanded);

    widget.onChanged(widget.config.copyWith(tables: updated));
  }

  void _moveTableUp(int index) {
    if (index <= 0 || index >= widget.config.tables.length) return;
    final expCurrent = _expandedMap[index] ?? false;
    final expAbove = _expandedMap[index - 1] ?? false;
    _expandedMap[index - 1] = expCurrent;
    _expandedMap[index] = expAbove;

    widget.onChanged(widget.config.moveTableUp(index));
  }

  void _moveTableDown(int index) {
    if (index < 0 || index >= widget.config.tables.length - 1) return;
    final expCurrent = _expandedMap[index] ?? false;
    final expBelow = _expandedMap[index + 1] ?? false;
    _expandedMap[index + 1] = expCurrent;
    _expandedMap[index] = expBelow;

    widget.onChanged(widget.config.moveTableDown(index));
  }

  void _onReorder(int oldIndex, int newIndex) {
    final prevExpanded = Map<int, bool>.from(_expandedMap);
    final newConfig = widget.config.reorderTable(oldIndex, newIndex);

    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }

    final newExpanded = <int, bool>{};
    final indices = List.generate(widget.config.tables.length, (i) => i);
    final movedItem = indices.removeAt(oldIndex);
    indices.insert(targetIndex, movedItem);

    for (var i = 0; i < indices.length; i++) {
      final oldIdx = indices[i];
      if (prevExpanded.containsKey(oldIdx)) {
        newExpanded[i] = prevExpanded[oldIdx]!;
      }
    }

    _expandedMap
      ..clear()
      ..addAll(newExpanded);

    widget.onChanged(newConfig);
  }

  void _updateTable(int index, ReverseSqlTableConfig updatedItem) {
    final updated = List<ReverseSqlTableConfig>.from(widget.config.tables);
    updated[index] = updatedItem;
    widget.onChanged(widget.config.copyWith(tables: updated));
  }

  void _setAllExpanded(bool expand) {
    setState(() {
      for (var i = 0; i < widget.config.tables.length; i++) {
        _expandedMap[i] = expand;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.config.tables.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.table_chart_outlined,
                size: 56,
                color: cs.outlineVariant,
              ),
              const SizedBox(height: 14),
              const Text(
                'No hay tablas configuradas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Agrega una tabla para configurar el DML, columnas y filtros de extracción.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar Primera Tabla'),
                onPressed: _addTable,
              ),
            ],
          ),
        ),
      );
    }

    // Filtrar índices de tablas según la búsqueda
    final query = _searchQuery.trim().toLowerCase();
    final matchingIndices = <int>[];
    for (var i = 0; i < widget.config.tables.length; i++) {
      final t = widget.config.tables[i];
      if (query.isEmpty ||
          t.name.toLowerCase().contains(query) ||
          t.dml.value.toLowerCase().contains(query) ||
          (t.columns?.toLowerCase().contains(query) ?? false)) {
        matchingIndices.add(i);
      }
    }

    final searchFill = isDark ? const Color(0xFF16181D) : Colors.white;
    final searchBorder = isDark
        ? const Color(0xFF33353F)
        : Colors.grey.shade300;

    return Column(
      children: [
        // Barra superior con contador, buscador y controles globales
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              // Buscador de tablas
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Buscar por tabla o DML...',
                      hintStyle: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 16),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              tooltip: 'Limpiar búsqueda',
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: searchFill,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: searchBorder, width: 0.8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: searchBorder, width: 0.8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: cs.primary, width: 1.2),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Botones globales de Expandir todo y Colapsar todo
              Tooltip(
                message: 'Expandir todas las tablas',
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: BorderSide(color: searchBorder, width: 0.8),
                  ),
                  icon: const Icon(Icons.unfold_more_rounded, size: 15),
                  label: const Text(
                    'Expandir todo',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _setAllExpanded(true),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Colapsar todas las tablas',
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: BorderSide(color: searchBorder, width: 0.8),
                  ),
                  icon: const Icon(Icons.unfold_less_rounded, size: 15),
                  label: const Text(
                    'Colapsar todo',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _setAllExpanded(false),
                ),
              ),
              const SizedBox(width: 6),

              // Botón Agregar Tabla
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Agregar Tabla',
                  style: TextStyle(fontSize: 11.5),
                ),
                onPressed: _addTable,
              ),
            ],
          ),
        ),

        // Subtítulo con contador de tablas
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Row(
            children: [
              Text(
                query.isEmpty
                    ? 'Tablas configuradas (${widget.config.tables.length})'
                    : 'Mostrando ${matchingIndices.length} de ${widget.config.tables.length} tablas',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),

        // Lista de tarjetas o estado vacío de búsqueda
        Expanded(
          child: matchingIndices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 44,
                          color: cs.outlineVariant,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No se encontraron tablas para "$_searchQuery"',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          icon: const Icon(Icons.clear, size: 14),
                          label: const Text('Limpiar búsqueda'),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: matchingIndices.length,
                  // ignore: deprecated_member_use
                  onReorder: (oldIdx, newIdx) {
                    if (query.isNotEmpty) {
                      // Si hay un filtro de búsqueda activo, convertimos al índice original de la tabla
                      final originalOld = matchingIndices[oldIdx];
                      var effectiveNew = newIdx;
                      if (effectiveNew > oldIdx) effectiveNew -= 1;
                      final originalTarget =
                          effectiveNew < matchingIndices.length
                          ? matchingIndices[effectiveNew]
                          : widget.config.tables.length - 1;
                      _onReorder(
                        originalOld,
                        originalTarget > originalOld
                            ? originalTarget + 1
                            : originalTarget,
                      );
                    } else {
                      _onReorder(oldIdx, newIdx);
                    }
                  },
                  itemBuilder: (context, i) {
                    final originalIdx = matchingIndices[i];
                    final table = widget.config.tables[originalIdx];
                    final isExpanded = _expandedMap[originalIdx] ?? false;

                    return Padding(
                      key: ValueKey('table_$originalIdx'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TableCard(
                        index: originalIdx,
                        itemPosition: i,
                        totalCount: widget.config.tables.length,
                        table: table,
                        isDark: isDark,
                        initiallyExpanded: isExpanded,
                        onToggleExpanded: (exp) {
                          setState(() {
                            _expandedMap[originalIdx] = exp;
                          });
                        },
                        onChanged: (updated) =>
                            _updateTable(originalIdx, updated),
                        onDelete: () => _removeTable(originalIdx),
                        onDuplicate: () => _duplicateTable(originalIdx),
                        onMoveUp: originalIdx > 0
                            ? () => _moveTableUp(originalIdx)
                            : null,
                        onMoveDown:
                            originalIdx < widget.config.tables.length - 1
                            ? () => _moveTableDown(originalIdx)
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TableCard extends StatefulWidget {
  final int index;
  final int itemPosition;
  final int totalCount;
  final ReverseSqlTableConfig table;
  final bool isDark;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onToggleExpanded;
  final ValueChanged<ReverseSqlTableConfig> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _TableCard({
    required this.index,
    required this.itemPosition,
    required this.totalCount,
    required this.table,
    required this.isDark,
    this.initiallyExpanded = false,
    this.onToggleExpanded,
    required this.onChanged,
    required this.onDelete,
    required this.onDuplicate,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  State<_TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<_TableCard> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _colsCtrl;
  late final TextEditingController _sqlCtrl;
  late final TextEditingController _ignorePkCtrl;
  late final TextEditingController _orderByCtrl;
  late final TextEditingController _limitCtrl;
  late bool _expanded;
  int _activeTabIndex =
      0; // 0: Filtros e IN/NOT IN, 1: Subconsultas y SQL, 2: Orden y Límite

  // Estados de expansión/colapso para secciones internas de los tabs
  bool _filtersExpanded = true;
  bool _insExpanded = true;
  bool _notInsExpanded = true;
  bool _existsExpanded = true;
  bool _sqlExpanded = true;

  // Lista mutable de filtros para desacoplar el estado de edición interactivo
  // del Map de la entidad y evitar que borrar la clave destruya la fila.
  late List<_FilterItem> _filterItems;
  int _nextFilterId = 1;

  // Lista mutable de operadores IN (ins)
  late List<_FilterItem> _insItems;
  int _nextInsId = 1;

  // Lista mutable de operadores NOT IN (not_ins)
  late List<_FilterItem> _notInsItems;
  int _nextNotInsId = 1;

  // Lista mutable de condiciones EXISTS
  late List<_FilterItem> _existsItems;
  int _nextExistsId = 1;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _nameCtrl = TextEditingController(text: widget.table.name);
    _colsCtrl = TextEditingController(text: widget.table.columns ?? '');
    _sqlCtrl = TextEditingController(text: widget.table.sql ?? '');
    _ignorePkCtrl = TextEditingController(text: widget.table.ignorePk ?? '');
    _orderByCtrl = TextEditingController(text: widget.table.orderBy ?? '');
    _limitCtrl = TextEditingController(
      text: widget.table.limit != null ? widget.table.limit.toString() : '',
    );

    _filterItems = widget.table.filters.entries.map((e) {
      return _FilterItem(id: _nextFilterId++, key: e.key, value: e.value);
    }).toList();

    _insItems = widget.table.ins.entries.map((e) {
      return _FilterItem(id: _nextInsId++, key: e.key, value: e.value);
    }).toList();

    _notInsItems = widget.table.notIns.entries.map((e) {
      return _FilterItem(id: _nextNotInsId++, key: e.key, value: e.value);
    }).toList();

    var exId = 1;
    _existsItems = widget.table.exists.map((e) {
      return _FilterItem(
        id: _nextExistsId++,
        key: 'EXISTS ${exId++}',
        value: e,
      );
    }).toList();
  }

  @override
  void didUpdateWidget(_TableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      _expanded = widget.initiallyExpanded;
    }
    if (widget.table.name != _nameCtrl.text) {
      _nameCtrl.text = widget.table.name;
    }
    if ((widget.table.columns ?? '') != _colsCtrl.text) {
      _colsCtrl.text = widget.table.columns ?? '';
    }
    if ((widget.table.sql ?? '') != _sqlCtrl.text) {
      _sqlCtrl.text = widget.table.sql ?? '';
    }
    if ((widget.table.ignorePk ?? '') != _ignorePkCtrl.text) {
      _ignorePkCtrl.text = widget.table.ignorePk ?? '';
    }
    if ((widget.table.orderBy ?? '') != _orderByCtrl.text) {
      _orderByCtrl.text = widget.table.orderBy ?? '';
    }
    final currentLimitText = widget.table.limit != null
        ? widget.table.limit.toString()
        : '';
    if (currentLimitText != _limitCtrl.text) {
      _limitCtrl.text = currentLimitText;
    }

    // Si los filtros cambiaron externamente (por ej. carga de archivo YAML o reseteo),
    // resincronizar si la cantidad o contenido de claves es distinta.
    final currentFiltersMap = _buildFiltersMap(filterEmptyKeys: false);
    if (!_mapsEqual(currentFiltersMap, widget.table.filters)) {
      _filterItems = widget.table.filters.entries.map((e) {
        return _FilterItem(id: _nextFilterId++, key: e.key, value: e.value);
      }).toList();
    }

    final currentInsMap = _buildInsMap(filterEmptyKeys: false);
    if (!_mapsEqual(currentInsMap, widget.table.ins)) {
      _insItems = widget.table.ins.entries.map((e) {
        return _FilterItem(id: _nextInsId++, key: e.key, value: e.value);
      }).toList();
    }

    final currentNotInsMap = _buildNotInsMap(filterEmptyKeys: false);
    if (!_mapsEqual(currentNotInsMap, widget.table.notIns)) {
      _notInsItems = widget.table.notIns.entries.map((e) {
        return _FilterItem(id: _nextNotInsId++, key: e.key, value: e.value);
      }).toList();
    }

    final currentExistsList = _buildExistsList(filterEmpty: false);
    if (!_listsEqual(currentExistsList, widget.table.exists)) {
      var exId = 1;
      _existsItems = widget.table.exists.map((e) {
        return _FilterItem(
          id: _nextExistsId++,
          key: 'EXISTS ${exId++}',
          value: e,
        );
      }).toList();
    }
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  Map<String, String> _buildFiltersMap({bool filterEmptyKeys = true}) {
    final map = <String, String>{};
    for (final item in _filterItems) {
      final k = item.key.trim();
      if (!filterEmptyKeys || k.isNotEmpty) {
        map[k] = item.value;
      }
    }
    return map;
  }

  Map<String, String> _buildInsMap({bool filterEmptyKeys = true}) {
    final map = <String, String>{};
    for (final item in _insItems) {
      final k = item.key.trim();
      if (!filterEmptyKeys || k.isNotEmpty) {
        map[k] = item.value;
      }
    }
    return map;
  }

  Map<String, String> _buildNotInsMap({bool filterEmptyKeys = true}) {
    final map = <String, String>{};
    for (final item in _notInsItems) {
      final k = item.key.trim();
      if (!filterEmptyKeys || k.isNotEmpty) {
        map[k] = item.value;
      }
    }
    return map;
  }

  List<String> _buildExistsList({bool filterEmpty = true}) {
    final list = <String>[];
    for (final item in _existsItems) {
      final v = item.value.trim();
      if (!filterEmpty || v.isNotEmpty) {
        list.add(item.value);
      }
    }
    return list;
  }

  void _notifyFiltersChanged() {
    widget.onChanged(
      widget.table.copyWith(filters: _buildFiltersMap(filterEmptyKeys: false)),
    );
  }

  void _notifyInsChanged() {
    widget.onChanged(
      widget.table.copyWith(ins: _buildInsMap(filterEmptyKeys: false)),
    );
  }

  void _notifyNotInsChanged() {
    widget.onChanged(
      widget.table.copyWith(notIns: _buildNotInsMap(filterEmptyKeys: false)),
    );
  }

  void _notifyExistsChanged() {
    widget.onChanged(
      widget.table.copyWith(exists: _buildExistsList(filterEmpty: false)),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _colsCtrl.dispose();
    _sqlCtrl.dispose();
    _ignorePkCtrl.dispose();
    _orderByCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Widget _buildSubTabButton({
    required int index,
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    final isSelected = _activeTabIndex == index;
    final activeBg = widget.isDark ? const Color(0xFF262831) : Colors.white;
    final inactiveText = widget.isDark ? Colors.white60 : Colors.black54;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          setState(() {
            _activeTabIndex = index;
          });
        },
        child: Container(
          height: 30,
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? color : inactiveText),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? (widget.isDark ? Colors.white : Colors.black87)
                        : inactiveText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.2)
                        : (widget.isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.06)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : inactiveText,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _dmlColor(ReverseSqlDml dml) {
    switch (dml) {
      case ReverseSqlDml.merge:
        return Colors.blue.shade600;
      case ReverseSqlDml.insert:
        return Colors.green.shade600;
      case ReverseSqlDml.update:
        return Colors.orange.shade700;
      case ReverseSqlDml.delete:
        return Colors.red.shade600;
    }
  }

  void _addFilterRow() {
    setState(() {
      _filtersExpanded = true;
      _filterItems.add(
        _FilterItem(
          id: _nextFilterId++,
          key: 'campo_${_filterItems.length + 1}',
          value: "= 'VALOR'",
        ),
      );
    });
    _notifyFiltersChanged();
  }

  void _removeFilter(int id) {
    setState(() {
      _filterItems.removeWhere((item) => item.id == id);
    });
    _notifyFiltersChanged();
  }

  void _updateFilter(int id, String newKey, String newValue) {
    final idx = _filterItems.indexWhere((item) => item.id == id);
    if (idx != -1) {
      _filterItems[idx].key = newKey;
      _filterItems[idx].value = newValue;
      _notifyFiltersChanged();
    }
  }

  void _addInsRow() {
    setState(() {
      _insExpanded = true;
      _insItems.add(
        _FilterItem(
          id: _nextInsId++,
          key: 'campo_${_insItems.length + 1}',
          value: '1, 2, 3, 4',
        ),
      );
    });
    _notifyInsChanged();
  }

  void _removeIns(int id) {
    setState(() {
      _insItems.removeWhere((item) => item.id == id);
    });
    _notifyInsChanged();
  }

  void _updateIns(int id, String newKey, String newValue) {
    final idx = _insItems.indexWhere((item) => item.id == id);
    if (idx != -1) {
      _insItems[idx].key = newKey;
      _insItems[idx].value = newValue;
      _notifyInsChanged();
    }
  }

  void _addNotInsRow() {
    setState(() {
      _notInsExpanded = true;
      _notInsItems.add(
        _FilterItem(
          id: _nextNotInsId++,
          key: 'campo_${_notInsItems.length + 1}',
          value: '1, 2, 3, 4',
        ),
      );
    });
    _notifyNotInsChanged();
  }

  void _removeNotIns(int id) {
    setState(() {
      _notInsItems.removeWhere((item) => item.id == id);
    });
    _notifyNotInsChanged();
  }

  void _updateNotIns(int id, String newKey, String newValue) {
    final idx = _notInsItems.indexWhere((item) => item.id == id);
    if (idx != -1) {
      _notInsItems[idx].key = newKey;
      _notInsItems[idx].value = newValue;
      _notifyNotInsChanged();
    }
  }

  void _addExistsRow() {
    setState(() {
      _existsExpanded = true;
      _existsItems.add(
        _FilterItem(
          id: _nextExistsId++,
          key: 'EXISTS ${_existsItems.length + 1}',
          value:
              'SELECT 1 FROM otra_tabla WHERE campo = ${widget.table.name.isEmpty ? 'tabla' : widget.table.name}.campo',
        ),
      );
    });
    _notifyExistsChanged();
  }

  void _removeExists(int id) {
    setState(() {
      _existsItems.removeWhere((item) => item.id == id);
    });
    _notifyExistsChanged();
  }

  void _updateExists(int id, String newValue) {
    final idx = _existsItems.indexWhere((item) => item.id == id);
    if (idx != -1) {
      _existsItems[idx].value = newValue;
      _notifyExistsChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dmlColor = _dmlColor(widget.table.dml);

    final cardBg = widget.isDark
        ? const Color(0xFF22242B)
        : const Color(0xFFFAFAFC);
    final borderColor = widget.isDark
        ? const Color(0xFF33353F)
        : Colors.grey.shade300;
    final inputFill = widget.isDark ? const Color(0xFF16181D) : Colors.white;

    OutlineInputBorder makeInputBorder({Color? color, double width = 1.0}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color ?? borderColor, width: width),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera de la tarjeta
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(10),
              bottom: Radius.circular(_expanded ? 0 : 10),
            ),
            onTap: () {
              final next = !_expanded;
              setState(() => _expanded = next);
              widget.onToggleExpanded?.call(next);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // Agarrador Drag & Drop
                  ReorderableDragStartListener(
                    index: widget.itemPosition,
                    child: Tooltip(
                      message: 'Arrastrar para reordenar posición de ejecución',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            size: 18,
                            color: widget.isDark
                                ? Colors.white38
                                : Colors.black38,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Badge numérico de orden de ejecución (#1, #2, etc.)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? const Color(0xFF16181D)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: widget.isDark
                            ? const Color(0xFF33353F)
                            : Colors.grey.shade300,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '#${widget.index + 1}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: widget.isDark
                            ? Colors.white70
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),

                  // Badge de Operación DML
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: dmlColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: dmlColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      widget.table.dml.value.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: dmlColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.table.name.isNotEmpty
                          ? widget.table.name
                          : '(Nombre de tabla pendiente)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontStyle: widget.table.name.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: widget.table.name.isEmpty ? Colors.grey : null,
                      ),
                    ),
                  ),

                  // Botones de Mover Arriba / Abajo
                  IconButton(
                    tooltip: widget.onMoveUp != null
                        ? 'Mover hacia arriba (ejecutar antes)'
                        : 'Ya está en la primera posición',
                    icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onMoveUp,
                  ),
                  IconButton(
                    tooltip: widget.onMoveDown != null
                        ? 'Mover hacia abajo (ejecutar después)'
                        : 'Ya está en la última posición',
                    icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onMoveDown,
                  ),

                  IconButton(
                    tooltip: 'Duplicar configuración',
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onDuplicate,
                  ),
                  IconButton(
                    tooltip: 'Eliminar tabla',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: Colors.redAccent,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onDelete,
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            Divider(height: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // DML y Nombre de Tabla
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Selector de Operación DML
                      SizedBox(
                        width: 160,
                        height: 34,
                        child: DropdownButtonFormField<ReverseSqlDml>(
                          initialValue: widget.table.dml,
                          isDense: true,
                          alignment: AlignmentDirectional.centerStart,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: widget.isDark
                                ? Colors.white
                                : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Operación DML',
                            labelStyle: const TextStyle(fontSize: 11),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            prefixIcon: Icon(
                              Icons.sync_alt_rounded,
                              size: 15,
                              color: dmlColor,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 30,
                              minHeight: 34,
                            ),
                            filled: true,
                            fillColor: inputFill,
                            contentPadding: const EdgeInsets.fromLTRB(
                              0,
                              7,
                              8,
                              7,
                            ),
                            border: makeInputBorder(),
                            enabledBorder: makeInputBorder(),
                            focusedBorder: makeInputBorder(
                              color: dmlColor,
                              width: 1.2,
                            ),
                          ),
                          items: ReverseSqlDml.values.map((d) {
                            return DropdownMenuItem(
                              value: d,
                              child: Text(
                                d.value.toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _dmlColor(d),
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              widget.onChanged(widget.table.copyWith(dml: val));
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Nombre de la tabla
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _nameCtrl,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Consolas, monospace',
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'Nombre de Tabla (name) *',
                              labelStyle: const TextStyle(fontSize: 11),
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              hintText: 'Ej. productobiendato, cotizacion',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: widget.isDark
                                    ? Colors.white38
                                    : Colors.black38,
                              ),
                              prefixIcon: const Icon(
                                Icons.table_chart_outlined,
                                size: 15,
                                color: Colors.blueAccent,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 34,
                              ),
                              filled: true,
                              fillColor: inputFill,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: makeInputBorder(),
                              enabledBorder: makeInputBorder(),
                              focusedBorder: makeInputBorder(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.2,
                              ),
                            ),
                            onChanged: (val) => widget.onChanged(
                              widget.table.copyWith(name: val.trim()),
                            ),
                          ),
                        ),
                      ),
                      // Checkbox pk_add compacto al lado
                      if (widget.table.dml != ReverseSqlDml.delete) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message:
                              'Completar Primary Key automáticamente en la consulta de exportación',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => widget.onChanged(
                              widget.table.copyWith(
                                pkAdd: !(widget.table.pkAdd ?? true),
                              ),
                            ),
                            child: Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: (widget.table.pkAdd ?? true)
                                    ? Theme.of(context).colorScheme.primary
                                          .withValues(alpha: 0.1)
                                    : inputFill,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: (widget.table.pkAdd ?? true)
                                      ? Theme.of(context).colorScheme.primary
                                            .withValues(alpha: 0.4)
                                      : borderColor,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: Checkbox(
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                      value: widget.table.pkAdd ?? true,
                                      onChanged: (val) => widget.onChanged(
                                        widget.table.copyWith(pkAdd: val),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'pk_add',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Consolas, monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Nota informativa según DML
                  if (widget.table.dml == ReverseSqlDml.delete)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Operación DELETE: los filtros definen las condiciones WHERE para la eliminación. Las columnas y llaves primarias no aplican.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (widget.table.dml == ReverseSqlDml.merge)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: Colors.blueAccent,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'En MERGE, puedes especificar las columnas a actualizar si el registro ya existe en destino.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.blueAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Barra de sub-pestañas internas compactas
                  Container(
                    margin: const EdgeInsets.only(top: 2, bottom: 12),
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? const Color(0xFF16181D)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        _buildSubTabButton(
                          index: 0,
                          icon: Icons.filter_alt_rounded,
                          label: 'Filtros & Valores',
                          count:
                              _filterItems.length +
                              _insItems.length +
                              _notInsItems.length,
                          color: Colors.blueAccent,
                        ),
                        const SizedBox(width: 4),
                        _buildSubTabButton(
                          index: 1,
                          icon: Icons.code_rounded,
                          label: 'SQL & Subconsultas',
                          count:
                              _existsItems.length +
                              ((widget.table.sql != null &&
                                      widget.table.sql!.trim().isNotEmpty)
                                  ? 1
                                  : 0),
                          color: Colors.purpleAccent,
                        ),
                        const SizedBox(width: 4),
                        _buildSubTabButton(
                          index: 2,
                          icon: Icons.sort_rounded,
                          label: 'Orden & Límite',
                          count:
                              ((widget.table.orderBy != null &&
                                      widget.table.orderBy!.trim().isNotEmpty)
                                  ? 1
                                  : 0) +
                              (widget.table.limit != null ? 1 : 0),
                          color: Colors.teal,
                        ),
                      ],
                    ),
                  ),

                  // Contenido de la pestaña activa
                  if (_activeTabIndex == 0) ...[
                    // PESTAÑA 0: Filtros WHERE/AND, IN y NOT IN
                    // --- SECCIÓN 1: Filtros de Extracción ---
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () =>
                          setState(() => _filtersExpanded = !_filtersExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _filtersExpanded
                                  ? Icons.expand_more_rounded
                                  : Icons.chevron_right_rounded,
                              size: 18,
                              color: Colors.blueAccent,
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.filter_alt_outlined,
                              size: 15,
                              color: Colors.blueAccent,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Filtros de Extracción (filters):',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                            if (_filterItems.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_filterItems.length}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            PopupMenuButton<String>(
                              tooltip: 'Insertar filtro común',
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.flash_on_rounded,
                                size: 16,
                                color: Colors.amber,
                              ),
                              onSelected: (template) {
                                setState(() {
                                  _filtersExpanded = true;
                                  _filterItems.add(
                                    _FilterItem(
                                      id: _nextFilterId++,
                                      key: 'campo_${_filterItems.length + 1}',
                                      value: template,
                                    ),
                                  );
                                });
                                _notifyFiltersChanged();
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'IS NULL',
                                  child: Text(
                                    'IS NULL',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'IS NOT NULL',
                                  child: Text(
                                    'IS NOT NULL',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: "BETWEEN 'VAL_DESDE' AND 'VAL_HASTA'",
                                  child: Text(
                                    'BETWEEN ... AND ...',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: "LIKE '%PATRON%'",
                                  child: Text(
                                    'LIKE %...%',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text(
                                'Agregar Filtro',
                                style: TextStyle(fontSize: 11),
                              ),
                              onPressed: _addFilterRow,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    if (_filtersExpanded) ...[
                      if (_filterItems.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.black12
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Sin filtros (extraerá toda la tabla o según SQL)',
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      else
                        ..._filterItems.map((item) {
                          return Padding(
                            key: ValueKey('filter_${item.id}'),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _FilterRow(
                              filterKey: item.key,
                              filterValue: item.value,
                              isDark: widget.isDark,
                              onUpdate: (k, v) => _updateFilter(item.id, k, v),
                              onDelete: () => _removeFilter(item.id),
                            ),
                          );
                        }),
                    ],

                    const SizedBox(height: 10),

                    // --- SECCIÓN 2: Cláusula IN (ins) ---
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _insExpanded = !_insExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _insExpanded
                                  ? Icons.expand_more_rounded
                                  : Icons.chevron_right_rounded,
                              size: 18,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.format_list_bulleted_rounded,
                              size: 15,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Valores IN (ins):',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                            if (_insItems.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_insItems.length}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '(WHERE col IN (...))',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.isDark
                                      ? Colors.white38
                                      : Colors.black45,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text(
                                'Agregar IN',
                                style: TextStyle(fontSize: 11),
                              ),
                              onPressed: _addInsRow,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    if (_insExpanded) ...[
                      if (_insItems.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.black12
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Sin cláusulas IN configuradas',
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      else
                        ..._insItems.map((item) {
                          return Padding(
                            key: ValueKey('ins_${item.id}'),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _FilterRow(
                              filterKey: item.key,
                              filterValue: item.value,
                              isDark: widget.isDark,
                              hintValue: '1, 2, 3, 4 ó \'A\', \'B\'',
                              labelValue:
                                  'Lista de valores (separados por coma)',
                              valueIcon: Icons.checklist_rounded,
                              valueAccentColor: Colors.teal,
                              onUpdate: (k, v) => _updateIns(item.id, k, v),
                              onDelete: () => _removeIns(item.id),
                            ),
                          );
                        }),
                    ],

                    const SizedBox(height: 10),

                    // --- SECCIÓN 3: Cláusula NOT IN (not_ins) ---
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () =>
                          setState(() => _notInsExpanded = !_notInsExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _notInsExpanded
                                  ? Icons.expand_more_rounded
                                  : Icons.chevron_right_rounded,
                              size: 18,
                              color: Colors.deepOrangeAccent,
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.do_not_disturb_on_outlined,
                              size: 15,
                              color: Colors.deepOrangeAccent,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Valores NOT IN (not_ins):',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                            if (_notInsItems.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.deepOrangeAccent.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_notInsItems.length}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepOrangeAccent,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '(WHERE col NOT IN (...))',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.isDark
                                      ? Colors.white38
                                      : Colors.black45,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text(
                                'Agregar NOT IN',
                                style: TextStyle(fontSize: 11),
                              ),
                              onPressed: _addNotInsRow,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    if (_notInsExpanded) ...[
                      if (_notInsItems.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.black12
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Sin cláusulas NOT IN configuradas',
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      else
                        ..._notInsItems.map((item) {
                          return Padding(
                            key: ValueKey('not_ins_${item.id}'),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _FilterRow(
                              filterKey: item.key,
                              filterValue: item.value,
                              isDark: widget.isDark,
                              hintValue: '1, 2, 3, 4 ó \'A\', \'B\'',
                              labelValue: 'Lista de valores excluidos',
                              valueIcon: Icons.block_flipped,
                              valueAccentColor: Colors.deepOrangeAccent,
                              onUpdate: (k, v) => _updateNotIns(item.id, k, v),
                              onDelete: () => _removeNotIns(item.id),
                            ),
                          );
                        }),
                    ],
                  ] else if (_activeTabIndex == 1) ...[
                    // PESTAÑA 1: SQL & Subconsultas (EXISTS, SQL verbatim, Columns, Ignore PK)
                    // --- SECCIÓN 1: Subconsultas EXISTS (exists) ---
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () =>
                          setState(() => _existsExpanded = !_existsExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _existsExpanded
                                  ? Icons.expand_more_rounded
                                  : Icons.chevron_right_rounded,
                              size: 18,
                              color: Colors.purpleAccent,
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.data_object_rounded,
                              size: 15,
                              color: Colors.purpleAccent,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Subconsultas EXISTS:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                            if (_existsItems.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purpleAccent.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_existsItems.length}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purpleAccent,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '(WHERE EXISTS (SELECT 1 ...))',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.isDark
                                      ? Colors.white38
                                      : Colors.black45,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text(
                                'Agregar EXISTS',
                                style: TextStyle(fontSize: 11),
                              ),
                              onPressed: _addExistsRow,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    if (_existsExpanded) ...[
                      if (_existsItems.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.black12
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Sin subconsultas EXISTS configuradas',
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      else
                        ..._existsItems.map((item) {
                          return Padding(
                            key: ValueKey('exists_${item.id}'),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      controller: TextEditingController(
                                        text: item.value,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'Consolas, monospace',
                                      ),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText:
                                            'SELECT 1 FROM otra_tabla WHERE...',
                                        hintStyle: TextStyle(
                                          fontSize: 11,
                                          color: widget.isDark
                                              ? Colors.white24
                                              : Colors.black26,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.code_rounded,
                                          size: 15,
                                          color: Colors.purpleAccent,
                                        ),
                                        filled: true,
                                        fillColor: inputFill,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 8,
                                            ),
                                        border: makeInputBorder(),
                                        enabledBorder: makeInputBorder(),
                                        focusedBorder: makeInputBorder(
                                          color: Colors.purpleAccent,
                                          width: 1.5,
                                        ),
                                      ),
                                      onChanged: (v) =>
                                          _updateExists(item.id, v),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                  ),
                                  color: Colors.redAccent,
                                  splashRadius: 16,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  tooltip: 'Eliminar subconsulta',
                                  onPressed: () => _removeExists(item.id),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],

                    const SizedBox(height: 10),

                    // --- SECCIÓN 2: SQL Personalizado & Columnas ---
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _sqlExpanded = !_sqlExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _sqlExpanded
                                  ? Icons.expand_more_rounded
                                  : Icons.chevron_right_rounded,
                              size: 18,
                              color: Colors.indigoAccent,
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.tune_rounded,
                              size: 15,
                              color: Colors.indigoAccent,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'SQL Directo, Ignorar PK & Columnas:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                            if ((widget.table.sql != null &&
                                    widget.table.sql!.trim().isNotEmpty) ||
                                (widget.table.columns != null &&
                                    widget.table.columns!.trim().isNotEmpty) ||
                                (widget.table.ignorePk != null &&
                                    widget.table.ignorePk!
                                        .trim()
                                        .isNotEmpty)) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.indigoAccent.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Activo',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigoAccent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    if (_sqlExpanded) ...[
                      // SQL personalizado & Ignore PK
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 34,
                              child: TextField(
                                controller: _sqlCtrl,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Consolas, monospace',
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: 'SQL Personalizado (sql)',
                                  labelStyle: const TextStyle(fontSize: 11),
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  hintText:
                                      'Query sin saltos de línea (opcional)',
                                  hintStyle: TextStyle(
                                    fontSize: 11,
                                    color: widget.isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.code_rounded,
                                    size: 15,
                                    color: Colors.indigoAccent,
                                  ),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 34,
                                  ),
                                  filled: true,
                                  fillColor: inputFill,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: makeInputBorder(),
                                  enabledBorder: makeInputBorder(),
                                  focusedBorder: makeInputBorder(
                                    color: Colors.indigoAccent,
                                    width: 1.2,
                                  ),
                                ),
                                onChanged: (val) => widget.onChanged(
                                  widget.table.copyWith(sql: val.trim()),
                                ),
                              ),
                            ),
                          ),
                          if (widget.table.dml != ReverseSqlDml.delete) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 34,
                                child: TextField(
                                  controller: _ignorePkCtrl,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'Consolas, monospace',
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: 'Ignorar PK (ignore_pk)',
                                    labelStyle: const TextStyle(fontSize: 11),
                                    floatingLabelBehavior:
                                        FloatingLabelBehavior.always,
                                    hintText: 'Ej. cd_campo1, cd_campo2',
                                    hintStyle: TextStyle(
                                      fontSize: 11,
                                      color: widget.isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.vpn_key_off_outlined,
                                      size: 15,
                                      color: Colors.deepOrangeAccent,
                                    ),
                                    prefixIconConstraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 34,
                                    ),
                                    filled: true,
                                    fillColor: inputFill,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    border: makeInputBorder(),
                                    enabledBorder: makeInputBorder(),
                                    focusedBorder: makeInputBorder(
                                      color: Colors.deepOrangeAccent,
                                      width: 1.2,
                                    ),
                                  ),
                                  onChanged: (val) => widget.onChanged(
                                    widget.table.copyWith(ignorePk: val.trim()),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      if (widget.table.dml == ReverseSqlDml.merge ||
                          widget.table.dml == ReverseSqlDml.update) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _colsCtrl,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'Consolas, monospace',
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: widget.table.dml == ReverseSqlDml.merge
                                  ? 'Columnas a actualizar (columns - opcional)'
                                  : 'Columnas a actualizar (columns) *',
                              labelStyle: const TextStyle(fontSize: 11),
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              hintText:
                                  'Ej. cd_procedimiento_antes, in_matriz_certificado',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: widget.isDark
                                    ? Colors.white38
                                    : Colors.black38,
                              ),
                              prefixIcon: const Icon(
                                Icons.view_column_outlined,
                                size: 15,
                                color: Colors.teal,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 34,
                              ),
                              filled: true,
                              fillColor: inputFill,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: makeInputBorder(),
                              enabledBorder: makeInputBorder(),
                              focusedBorder: makeInputBorder(
                                color: Colors.teal,
                                width: 1.2,
                              ),
                            ),
                            onChanged: (val) => widget.onChanged(
                              widget.table.copyWith(columns: val.trim()),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ] else if (_activeTabIndex == 2) ...[
                    // PESTAÑA 2: Orden y Límite
                    Row(
                      children: [
                        // ORDER BY
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ORDER BY (Opcional):',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: widget.isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _orderByCtrl,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'Consolas, monospace',
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'ej. fe_alta DESC, cd_codigo ASC',
                                    hintStyle: TextStyle(
                                      fontSize: 11,
                                      color: widget.isDark
                                          ? Colors.white24
                                          : Colors.black26,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.sort_rounded,
                                      size: 15,
                                      color: Colors.blueGrey,
                                    ),
                                    filled: true,
                                    fillColor: inputFill,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    border: makeInputBorder(),
                                    enabledBorder: makeInputBorder(),
                                    focusedBorder: makeInputBorder(
                                      color: dmlColor,
                                      width: 1.5,
                                    ),
                                  ),
                                  onChanged: (val) {
                                    widget.onChanged(
                                      widget.table.copyWith(
                                        orderBy: val.trim().isEmpty
                                            ? null
                                            : val.trim(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // LIMIT
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Límite Filas:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: widget.isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _limitCtrl,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'Consolas, monospace',
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'ej. 100',
                                    hintStyle: TextStyle(
                                      fontSize: 11,
                                      color: widget.isDark
                                          ? Colors.white24
                                          : Colors.black26,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.format_list_numbered_rounded,
                                      size: 15,
                                      color: Colors.blueGrey,
                                    ),
                                    filled: true,
                                    fillColor: inputFill,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    border: makeInputBorder(),
                                    enabledBorder: makeInputBorder(),
                                    focusedBorder: makeInputBorder(
                                      color: dmlColor,
                                      width: 1.5,
                                    ),
                                  ),
                                  onChanged: (val) {
                                    final parsedInt = int.tryParse(val.trim());
                                    widget.onChanged(
                                      widget.table.copyWith(limit: parsedInt),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Define el orden de extracción y la cantidad máxima de filas a procesar desde la base de datos origen.',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: widget.isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Elemento interno mutable para desacoplar las filas de filtros durante edición.
class _FilterItem {
  final int id;
  String key;
  String value;

  _FilterItem({required this.id, required this.key, required this.value});
}

class _FilterRow extends StatefulWidget {
  final String filterKey;
  final String filterValue;
  final bool isDark;
  final String? hintValue;
  final String? labelValue;
  final IconData? valueIcon;
  final Color? valueAccentColor;
  final void Function(String key, String value) onUpdate;
  final VoidCallback onDelete;

  const _FilterRow({
    required this.filterKey,
    required this.filterValue,
    required this.isDark,
    this.hintValue,
    this.labelValue,
    this.valueIcon,
    this.valueAccentColor,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<_FilterRow> createState() => _FilterRowState();
}

class _FilterRowState extends State<_FilterRow> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _valCtrl;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.filterKey);
    _valCtrl = TextEditingController(text: widget.filterValue);
  }

  @override
  void didUpdateWidget(_FilterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filterKey != _keyCtrl.text) {
      _keyCtrl.text = widget.filterKey;
    }
    if (widget.filterValue != _valCtrl.text) {
      _valCtrl.text = widget.filterValue;
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.isDark
        ? const Color(0xFF33353F)
        : Colors.grey.shade300;
    final inputFill = widget.isDark ? const Color(0xFF16181D) : Colors.white;
    final valAccent = widget.valueAccentColor ?? Colors.lightBlueAccent;

    OutlineInputBorder makeInputBorder({Color? color, double width = 1.0}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color ?? borderColor, width: width),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Campo: Columna
          SizedBox(
            width: 190,
            height: 32,
            child: TextField(
              controller: _keyCtrl,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Consolas, monospace',
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'ej. cd_procedimiento',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: widget.isDark ? Colors.white38 : Colors.black38,
                ),
                labelText: 'Columna',
                labelStyle: const TextStyle(fontSize: 11),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                prefixIcon: const Icon(
                  Icons.vpn_key_outlined,
                  size: 14,
                  color: Colors.orangeAccent,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 32,
                ),
                filled: true,
                fillColor: inputFill,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: makeInputBorder(),
                enabledBorder: makeInputBorder(),
                focusedBorder: makeInputBorder(
                  color: Colors.orangeAccent,
                  width: 1.2,
                ),
              ),
              onChanged: (k) => widget.onUpdate(k, _valCtrl.text),
            ),
          ),
          const SizedBox(width: 8),
          // Campo: Condición / Filtro
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _valCtrl,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas, monospace',
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText:
                      widget.hintValue ??
                      "= 'VALOR', like '%test%' o in ('A','B')",
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: widget.isDark ? Colors.white38 : Colors.black38,
                  ),
                  labelText: widget.labelValue ?? 'Condición / Filtro (WHERE)',
                  labelStyle: const TextStyle(fontSize: 11),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  prefixIcon: Icon(
                    widget.valueIcon ?? Icons.filter_list_rounded,
                    size: 14,
                    color: valAccent,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 32,
                  ),
                  filled: true,
                  fillColor: inputFill,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: makeInputBorder(),
                  enabledBorder: makeInputBorder(),
                  focusedBorder: makeInputBorder(color: valAccent, width: 1.2),
                ),
                onChanged: (v) => widget.onUpdate(_keyCtrl.text, v),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Botón eliminar fila
          Tooltip(
            message: widget.labelValue != null
                ? 'Eliminar IN'
                : 'Eliminar filtro',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: widget.onDelete,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor, width: 0.8),
                  color: widget.isDark
                      ? Colors.redAccent.withValues(alpha: 0.08)
                      : Colors.red.shade50,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: Colors.redAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
