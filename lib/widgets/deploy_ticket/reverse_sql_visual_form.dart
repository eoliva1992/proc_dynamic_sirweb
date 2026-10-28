import 'package:flutter/material.dart';
import '../../models/reverse_sql_config.dart';

/// Formulario visual estructurado para configurar tablas de extracción YAML (Reverse SQL).
class ReverseSqlVisualForm extends StatelessWidget {
  final ReverseSqlConfig config;
  final ValueChanged<ReverseSqlConfig> onChanged;

  const ReverseSqlVisualForm({
    super.key,
    required this.config,
    required this.onChanged,
  });

  void _addTable() {
    final updated = List<ReverseSqlTableConfig>.from(config.tables)
      ..add(
        const ReverseSqlTableConfig(
          dml: ReverseSqlDml.merge,
          name: '',
          pkAdd: true,
        ),
      );
    onChanged(config.copyWith(tables: updated));
  }

  void _removeTable(int index) {
    if (index < 0 || index >= config.tables.length) return;
    final updated = List<ReverseSqlTableConfig>.from(config.tables)
      ..removeAt(index);
    onChanged(config.copyWith(tables: updated));
  }

  void _duplicateTable(int index) {
    if (index < 0 || index >= config.tables.length) return;
    final item = config.tables[index];
    final copy = item.copyWith(
      name: item.name.isNotEmpty ? '${item.name}_copy' : '',
    );
    final updated = List<ReverseSqlTableConfig>.from(config.tables)
      ..insert(index + 1, copy);
    onChanged(config.copyWith(tables: updated));
  }

  void _updateTable(int index, ReverseSqlTableConfig updatedItem) {
    final updated = List<ReverseSqlTableConfig>.from(config.tables);
    updated[index] = updatedItem;
    onChanged(config.copyWith(tables: updated));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (config.tables.isEmpty) {
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                'Tablas configuradas (${config.tables.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Agregar Tabla',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: _addTable,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: config.tables.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, idx) {
              final table = config.tables[idx];
              return _TableCard(
                key: ValueKey('table_$idx'),
                index: idx,
                table: table,
                isDark: isDark,
                onChanged: (updated) => _updateTable(idx, updated),
                onDelete: () => _removeTable(idx),
                onDuplicate: () => _duplicateTable(idx),
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
  final ReverseSqlTableConfig table;
  final bool isDark;
  final ValueChanged<ReverseSqlTableConfig> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;

  const _TableCard({
    super.key,
    required this.index,
    required this.table,
    required this.isDark,
    required this.onChanged,
    required this.onDelete,
    required this.onDuplicate,
  });

  @override
  State<_TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<_TableCard> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _colsCtrl;
  late final TextEditingController _sqlCtrl;
  late final TextEditingController _ignorePkCtrl;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.table.name);
    _colsCtrl = TextEditingController(text: widget.table.columns ?? '');
    _sqlCtrl = TextEditingController(text: widget.table.sql ?? '');
    _ignorePkCtrl = TextEditingController(text: widget.table.ignorePk ?? '');
  }

  @override
  void didUpdateWidget(_TableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
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
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _colsCtrl.dispose();
    _sqlCtrl.dispose();
    _ignorePkCtrl.dispose();
    super.dispose();
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
    final filters = Map<String, String>.from(widget.table.filters);
    final key = 'campo_${filters.length + 1}';
    filters[key] = "= 'VALOR'";
    widget.onChanged(widget.table.copyWith(filters: filters));
  }

  void _removeFilter(String key) {
    final filters = Map<String, String>.from(widget.table.filters)..remove(key);
    widget.onChanged(widget.table.copyWith(filters: filters));
  }

  void _updateFilterKey(String oldKey, String newKey, String value) {
    if (oldKey == newKey) {
      final filters = Map<String, String>.from(widget.table.filters);
      filters[oldKey] = value;
      widget.onChanged(widget.table.copyWith(filters: filters));
      return;
    }
    final filters = <String, String>{};
    widget.table.filters.forEach((k, v) {
      if (k == oldKey) {
        if (newKey.trim().isNotEmpty) filters[newKey.trim()] = value;
      } else {
        filters[k] = v;
      }
    });
    widget.onChanged(widget.table.copyWith(filters: filters));
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
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
                  IconButton(
                    tooltip: 'Duplicar configuración',
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    onPressed: widget.onDuplicate,
                  ),
                  IconButton(
                    tooltip: 'Eliminar tabla',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: Colors.redAccent,
                    ),
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

                  // Columnas y PK (Columnas visible para merge y update; oculto para insert y delete)
                  if (widget.table.dml == ReverseSqlDml.merge ||
                      widget.table.dml == ReverseSqlDml.update) ...[
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
                          floatingLabelBehavior: FloatingLabelBehavior.always,
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
                    const SizedBox(height: 10),
                  ],

                  // SQL personalizado & Ignore PK (Ignore PK solo si no es delete)
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
                              hintText: 'Query sin saltos de línea (opcional)',
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

                  const SizedBox(height: 14),

                  // Sección Filtros (Where / And)
                  Row(
                    children: [
                      const Icon(
                        Icons.filter_alt_outlined,
                        size: 15,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Filtros de Extracción (filters):',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
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
                  const SizedBox(height: 6),

                  if (widget.table.filters.isEmpty)
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
                    ...widget.table.filters.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _FilterRow(
                          filterKey: entry.key,
                          filterValue: entry.value,
                          isDark: widget.isDark,
                          onUpdate: (k, v) => _updateFilterKey(entry.key, k, v),
                          onDelete: () => _removeFilter(entry.key),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatefulWidget {
  final String filterKey;
  final String filterValue;
  final bool isDark;
  final void Function(String key, String value) onUpdate;
  final VoidCallback onDelete;

  const _FilterRow({
    required this.filterKey,
    required this.filterValue,
    required this.isDark,
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
                  hintText: "= 'VALOR', like '%test%' o in ('A','B')",
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: widget.isDark ? Colors.white38 : Colors.black38,
                  ),
                  labelText: 'Condición / Filtro (WHERE)',
                  labelStyle: const TextStyle(fontSize: 11),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  prefixIcon: const Icon(
                    Icons.filter_list_rounded,
                    size: 14,
                    color: Colors.lightBlueAccent,
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
                    color: Colors.lightBlueAccent,
                    width: 1.2,
                  ),
                ),
                onChanged: (v) => widget.onUpdate(_keyCtrl.text, v),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Botón eliminar filtro
          Tooltip(
            message: 'Eliminar filtro',
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
