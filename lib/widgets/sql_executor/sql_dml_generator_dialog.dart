/// Diálogo para generar INSERT/UPDATE/MERGE a partir de filas seleccionadas
/// en la grilla de resultados.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/sql_execution.dart';
import '../../services/schema_service.dart';
import '../../services/sql_dml_generator.dart';
import '../app_toast.dart';

enum _DmlKind { insert, update, merge }

Future<void> showSqlDmlGeneratorDialog(
  BuildContext context, {
  required SqlQueryResult result,
  required List<int> rowIndexes,
  required String suggestedTable,
  required String ambiente,
  void Function(String sql)? onInsert,
}) {
  return showDialog(
    context: context,
    builder: (_) => _SqlDmlGeneratorDialog(
      result: result,
      rowIndexes: rowIndexes,
      suggestedTable: suggestedTable,
      ambiente: ambiente,
      onInsert: onInsert,
    ),
  );
}

class _SqlDmlGeneratorDialog extends StatefulWidget {
  const _SqlDmlGeneratorDialog({
    required this.result,
    required this.rowIndexes,
    required this.suggestedTable,
    required this.ambiente,
    this.onInsert,
  });

  final SqlQueryResult result;
  final List<int> rowIndexes;
  final String suggestedTable;
  final String ambiente;
  final void Function(String sql)? onInsert;

  @override
  State<_SqlDmlGeneratorDialog> createState() => _SqlDmlGeneratorDialogState();
}

class _SqlDmlGeneratorDialogState extends State<_SqlDmlGeneratorDialog> {
  late final TextEditingController _tableCtrl = TextEditingController(
    text: widget.suggestedTable,
  );
  _DmlKind _kind = _DmlKind.insert;
  final Set<String> _keyColumns = {};
  bool _loadingKeys = false;
  bool _autoDetectFailed = false;

  @override
  void initState() {
    super.initState();
    _detectKeys();
  }

  Future<void> _detectKeys() async {
    if (widget.suggestedTable.isEmpty) return;
    setState(() {
      _loadingKeys = true;
      _autoDetectFailed = false;
    });
    try {
      final keys = await SchemaService.instance.getPrimaryKeyColumns(
        widget.suggestedTable,
        ambiente: widget.ambiente,
      );
      if (!mounted) return;
      setState(() {
        _keyColumns.clear();
        _keyColumns.addAll(keys.map((k) => k.toUpperCase()));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _autoDetectFailed = true);
    } finally {
      if (mounted) setState(() => _loadingKeys = false);
    }
  }

  String get _generatedSql {
    final table = _tableCtrl.text.trim();
    if (table.isEmpty) return '';
    return switch (_kind) {
      _DmlKind.insert => generateInsert(
        table,
        widget.result,
        widget.rowIndexes,
      ),
      _DmlKind.update => generateUpdate(
        table,
        widget.result,
        widget.rowIndexes,
        _keyColumns.toList(),
      ),
      _DmlKind.merge => generateMerge(
        table,
        widget.result,
        widget.rowIndexes,
        _keyColumns.toList(),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final needsKeys = _kind != _DmlKind.insert;
    final statementCount = _generatedSql
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .length;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_fix_high_rounded, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          const Text(
            'Generar INSERT / UPDATE / MERGE',
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _tableCtrl,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Tabla destino',
                labelStyle: const TextStyle(fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Volver a detectar Primary Key',
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  onPressed: _detectKeys,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_DmlKind>(
              segments: const [
                ButtonSegment(
                  value: _DmlKind.insert,
                  label: Text('INSERT'),
                  icon: Icon(Icons.add_box_outlined, size: 15),
                ),
                ButtonSegment(
                  value: _DmlKind.update,
                  label: Text('UPDATE'),
                  icon: Icon(Icons.edit_note_rounded, size: 15),
                ),
                ButtonSegment(
                  value: _DmlKind.merge,
                  label: Text('MERGE'),
                  icon: Icon(Icons.call_merge_rounded, size: 15),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            if (needsKeys) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Columnas clave (WHERE / ON):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  if (_loadingKeys)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else if (_autoDetectFailed)
                    Text(
                      '(no se detectó PK automáticamente)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _keyColumns.addAll(
                        widget.result.columns.map((c) => c.name.toUpperCase()),
                      );
                    }),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    child: const Text('Todas'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _keyColumns.clear()),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    child: const Text('Ninguna'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final col in widget.result.columns)
                    FilterChip(
                      label: Text(
                        col.name,
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: _keyColumns.contains(col.name.toUpperCase()),
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _keyColumns.add(col.name.toUpperCase());
                        } else {
                          _keyColumns.remove(col.name.toUpperCase());
                        }
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? cs.surfaceContainerLowest
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? cs.surfaceContainerLow
                          : cs.surfaceContainerHigh,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'SQL generado',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$statementCount sentencia${statementCount == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 190),
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _generatedSql.isEmpty
                            ? '(completa la tabla para generar)'
                            : _generatedSql,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: _generatedSql.isEmpty
                              ? cs.onSurfaceVariant
                              : cs.onSurface,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.content_copy_rounded, size: 14),
          label: const Text('Copiar'),
          onPressed: _generatedSql.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: _generatedSql));
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    AppToast.success('SQL copiado al portapapeles');
                  }
                },
        ),
        if (widget.onInsert != null)
          FilledButton.icon(
            icon: const Icon(Icons.input_rounded, size: 15),
            label: const Text('Insertar en editor'),
            onPressed: _generatedSql.isEmpty
                ? null
                : () {
                    widget.onInsert!(_generatedSql);
                    Navigator.of(context).pop();
                    AppToast.success('SQL insertado en el editor');
                  },
          ),
      ],
    );
  }
}
