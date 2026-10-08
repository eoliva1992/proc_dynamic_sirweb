/// Diálogo para generar INSERT/UPDATE/MERGE a partir de filas seleccionadas
/// en la grilla de resultados.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/sql_execution.dart';
import '../../services/schema_service.dart';
import '../../services/sql_dml_generator.dart';
import '../app_toast.dart';
import '../constellation_background.dart';

enum _DmlKind { insert, update, merge }

Future<void> showSqlDmlGeneratorDialog(
  BuildContext context, {
  required SqlQueryResult result,
  required List<int> rowIndexes,
  required String suggestedTable,
  required String ambiente,
  void Function(String sql)? onInsert,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'sql-dml-generator',
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, _, _) => _SqlDmlGeneratorDialog(
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
  final TextEditingController _keyFilterCtrl = TextEditingController();
  _DmlKind _kind = _DmlKind.insert;
  final Set<String> _keyColumns = {};
  bool _loadingKeys = false;
  bool _autoDetectFailed = false;
  String _keyFilter = '';

  // Desplazamiento acumulado del arrastre del panel (estilo _ObjectDetailsModal).
  Offset _position = Offset.zero;

  @override
  void initState() {
    super.initState();
    _detectKeys();
  }

  @override
  void dispose() {
    _tableCtrl.dispose();
    _keyFilterCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectKeys({bool forceRefresh = false}) async {
    final table = _tableCtrl.text.trim();
    if (table.isEmpty) return;
    if (!forceRefresh) {
      final cached = SchemaService.instance.peekPrimaryKeyColumns(
        table,
        ambiente: widget.ambiente,
      );
      if (cached != null) {
        setState(() {
          _keyColumns.clear();
          _keyColumns.addAll(cached);
          _autoDetectFailed = false;
        });
        return;
      }
    }
    setState(() {
      _loadingKeys = true;
      _autoDetectFailed = false;
    });
    try {
      final keys = await SchemaService.instance.getPrimaryKeyColumns(
        table,
        ambiente: widget.ambiente,
        forceRefresh: forceRefresh,
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
    final size = MediaQuery.sizeOf(context);
    final w = (size.width * 0.5).clamp(560.0, 760.0);
    final h = (size.height * 0.75).clamp(520.0, 680.0);
    final left = ((size.width - w) / 2 + _position.dx).clamp(
      0.0,
      (size.width - w).clamp(0.0, double.infinity),
    );
    final top = ((size.height - h) / 2 + _position.dy).clamp(
      0.0,
      (size.height - h).clamp(0.0, double.infinity),
    );

    final filteredColumns = _keyFilter.isEmpty
        ? widget.result.columns
        : widget.result.columns
              .where(
                (c) => c.name.toUpperCase().contains(_keyFilter.toUpperCase()),
              )
              .toList();

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: w,
          height: h,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.primary.withValues(alpha: isDark ? 0.22 : 0.16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.20),
                    blurRadius: 48,
                    spreadRadius: -4,
                    offset: const Offset(0, 20),
                  ),
                  BoxShadow(
                    color: cs.primary.withValues(alpha: isDark ? 0.10 : 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanUpdate: (d) =>
                            setState(() => _position += d.delta),
                        onDoubleTap: () =>
                            setState(() => _position = Offset.zero),
                        child: _buildHeader(cs, isDark),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel('TABLA DESTINO', cs),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _tableCtrl,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  tooltip: 'Volver a detectar Primary Key',
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                  ),
                                  onPressed: () =>
                                      _detectKeys(forceRefresh: true),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 14),
                            _sectionLabel('TIPO DE OPERACIÓN', cs),
                            const SizedBox(height: 6),
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
                                  icon: Icon(
                                    Icons.call_merge_rounded,
                                    size: 15,
                                  ),
                                ),
                              ],
                              selected: {_kind},
                              onSelectionChanged: (s) =>
                                  setState(() => _kind = s.first),
                            ),
                            if (needsKeys) ...[
                              const SizedBox(height: 14),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  _sectionLabel(
                                    'COLUMNAS CLAVE (WHERE / ON)',
                                    cs,
                                  ),
                                  _keyStatusChip(cs),
                                  TextButton.icon(
                                    onPressed: () => setState(() {
                                      _keyColumns.addAll(
                                        widget.result.columns.map(
                                          (c) => c.name.toUpperCase(),
                                        ),
                                      );
                                    }),
                                    icon: const Icon(
                                      Icons.select_all_rounded,
                                      size: 14,
                                    ),
                                    label: const Text('Todas'),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      textStyle: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _keyColumns.clear()),
                                    icon: const Icon(
                                      Icons.deselect_rounded,
                                      size: 14,
                                    ),
                                    label: const Text('Ninguna'),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      textStyle: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _keyFilterCtrl,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Buscar columna…',
                                  hintStyle: const TextStyle(fontSize: 12),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 16,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (v) =>
                                    setState(() => _keyFilter = v.trim()),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                constraints: const BoxConstraints(
                                  maxHeight: 120,
                                ),
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(6),
                                  child: filteredColumns.isEmpty
                                      ? Text(
                                          'Sin coincidencias',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        )
                                      : Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            for (final col in filteredColumns)
                                              FilterChip(
                                                label: Text(
                                                  col.name,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                selected: _keyColumns.contains(
                                                  col.name.toUpperCase(),
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onSelected: (v) => setState(() {
                                                  if (v) {
                                                    _keyColumns.add(
                                                      col.name.toUpperCase(),
                                                    );
                                                  } else {
                                                    _keyColumns.remove(
                                                      col.name.toUpperCase(),
                                                    );
                                                  }
                                                }),
                                              ),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _sectionLabel('SQL GENERADO', cs),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Container(
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
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(10),
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
                      ),
                    ),
                    _buildActions(cs),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text, ColorScheme cs) => Row(
    children: [
      Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: cs.onSurfaceVariant,
        ),
      ),
    ],
  );

  /// Indica el estado de la detección de PK: cargando, fallida, o cuántas
  /// columnas clave hay seleccionadas (auto-detectadas o manuales).
  Widget _keyStatusChip(ColorScheme cs) {
    if (_loadingKeys) {
      return _chip(
        icon: null,
        spinner: true,
        label: 'Detectando…',
        color: cs.onSurfaceVariant,
      );
    }
    if (_autoDetectFailed) {
      return _chip(
        icon: Icons.error_outline_rounded,
        label: 'PK no detectada: elegí manualmente',
        color: cs.tertiary,
      );
    }
    if (_keyColumns.isEmpty) {
      return _chip(
        icon: Icons.info_outline_rounded,
        label: 'Sin columnas seleccionadas',
        color: cs.onSurfaceVariant,
      );
    }
    return _chip(
      icon: Icons.check_circle_rounded,
      label:
          '${_keyColumns.length} seleccionada${_keyColumns.length == 1 ? '' : 's'}',
      color: const Color(0xFF107C10),
    );
  }

  Widget _chip({
    IconData? icon,
    bool spinner = false,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else if (icon != null)
            Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10.5, color: color)),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    return ConstellationHeader(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      lineColor: cs.primary.withValues(alpha: 0.35),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF262626), const Color(0xFF212121)]
              : [const Color(0xFFF7F9FC), const Color(0xFFF0F3F8)],
        ),
        border: Border(
          bottom: BorderSide(
            color: cs.primary.withValues(alpha: isDark ? 0.25 : 0.18),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.28),
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Icon(
              Icons.auto_fix_high_rounded,
              size: 20,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Generar INSERT / UPDATE / MERGE',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
              hoverColor: const Color(0xFFE81123).withValues(alpha: 0.14),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          const SizedBox(width: 8),
          _DmlActionButton(
            icon: Icons.content_copy_rounded,
            label: 'Copiar',
            filled: false,
            enabled: _generatedSql.isNotEmpty,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _generatedSql));
              AppToast.success('SQL copiado al portapapeles');
            },
          ),
          if (widget.onInsert != null) ...[
            const SizedBox(width: 8),
            _DmlActionButton(
              icon: Icons.input_rounded,
              label: 'Insertar en editor',
              filled: true,
              enabled: _generatedSql.isNotEmpty,
              onPressed: () async {
                widget.onInsert!(_generatedSql);
                AppToast.success('SQL insertado en el editor');
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Botón de acción del footer con feedback de check animado tras completarse
/// la acción, antes de cerrar el modal.
class _DmlActionButton extends StatefulWidget {
  const _DmlActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  State<_DmlActionButton> createState() => _DmlActionButtonState();
}

class _DmlActionButtonState extends State<_DmlActionButton> {
  bool _success = false;

  Future<void> _handleTap() async {
    await widget.onPressed();
    if (!mounted) return;
    setState(() => _success = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      _success ? Icons.check_rounded : widget.icon,
      size: 15,
      color: _success ? const Color(0xFF107C10) : null,
    );
    final label = Text(_success ? '¡Listo!' : widget.label);
    final onPressed = widget.enabled && !_success ? _handleTap : null;
    return widget.filled
        ? FilledButton.icon(icon: icon, label: label, onPressed: onPressed)
        : OutlinedButton.icon(icon: icon, label: label, onPressed: onPressed);
  }
}
