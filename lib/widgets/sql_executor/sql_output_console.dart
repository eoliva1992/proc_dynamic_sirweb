/// Consola de salida tipo IDE: lista de mensajes de ejecución (éxito, error,
/// warning) con detalle de duración y filas afectadas/devueltas, con la misma
/// identidad visual, animaciones y componentes de `AppConsole`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/sql_execution.dart';
import '../../services/app_log.dart';
import '../app_toast.dart';

enum _ConsoleFilter { all, success, error, warning }

class SqlOutputConsole extends StatefulWidget {
  const SqlOutputConsole({super.key, required this.entries, this.onReplay});

  final List<SqlExecutionLogEntry> entries;

  /// Reinserta la sentencia de la entrada en el editor (usado también por Historial).
  final void Function(SqlExecutionLogEntry entry)? onReplay;

  @override
  State<SqlOutputConsole> createState() => _SqlOutputConsoleState();
}

class _SqlOutputConsoleState extends State<SqlOutputConsole> {
  _ConsoleFilter _filter = _ConsoleFilter.all;
  final Set<int> _expandedEntries = {};
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(SqlLogStatus status, bool isDark) => switch (status) {
    SqlLogStatus.success => const Color(0xFF3FB950),
    SqlLogStatus.error => const Color(0xFFE5484D),
    SqlLogStatus.warning => const Color(0xFFE2A03F),
    SqlLogStatus.running => const Color(0xFF4C9AFF),
  };

  IconData _statusIcon(SqlLogStatus status) => switch (status) {
    SqlLogStatus.success => Icons.check_circle_rounded,
    SqlLogStatus.error => Icons.error_rounded,
    SqlLogStatus.warning => Icons.warning_rounded,
    SqlLogStatus.running => Icons.hourglass_top_rounded,
  };

  String _statusLabel(SqlLogStatus status) => switch (status) {
    SqlLogStatus.success => 'Éxito',
    SqlLogStatus.error => 'Error',
    SqlLogStatus.warning => 'Aviso',
    SqlLogStatus.running => 'En curso',
  };

  void _toggleDetalle(int id) => setState(() {
    if (!_expandedEntries.remove(id)) _expandedEntries.add(id);
  });

  void _toggleTodos() {
    final ids = widget.entries.map((e) => e.id).toSet();
    setState(() {
      if (ids.every(_expandedEntries.contains) && ids.isNotEmpty) {
        _expandedEntries.clear();
      } else {
        _expandedEntries.addAll(ids);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    if (widget.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal_rounded,
              size: 40,
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              'Sin mensajes todavía',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Las ejecuciones y respuestas de Oracle aparecerán acá',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    final successCount = widget.entries
        .where((e) => e.status == SqlLogStatus.success)
        .length;
    final errorCount = widget.entries
        .where((e) => e.status == SqlLogStatus.error)
        .length;
    final warnCount = widget.entries
        .where((e) => e.status == SqlLogStatus.warning)
        .length;

    final q = _search.trim().toLowerCase();
    final filtered = widget.entries.where((e) {
      final matchesFilter = switch (_filter) {
        _ConsoleFilter.all => true,
        _ConsoleFilter.success => e.status == SqlLogStatus.success,
        _ConsoleFilter.error => e.status == SqlLogStatus.error,
        _ConsoleFilter.warning => e.status == SqlLogStatus.warning,
      };
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      return e.statementPreview.toLowerCase().contains(q) ||
          e.ambiente.toLowerCase().contains(q) ||
          e.kind.label.toLowerCase().contains(q) ||
          (e.message?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Column(
      children: [
        _buildFilterBar(cs, isDark, successCount, errorCount, warnCount),
        Divider(
          height: 1,
          thickness: 1,
          color: cs.outlineVariant.withValues(alpha: 0.8),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No hay registros con este filtro',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  reverse: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final entry = filtered[filtered.length - 1 - i];
                    return _buildLogCard(entry, cs, isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(
    ColorScheme cs,
    bool isDark,
    int successCount,
    int errorCount,
    int warnCount,
  ) {
    return Container(
      height: 38,
      padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
      color: isDark ? const Color(0xFF161B22) : const Color(0xFFF1F3F5),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final mostrarBuscador = w >= 600;

          return Row(
            children: [
              if (mostrarBuscador) ...[
                SizedBox(
                  width: 170,
                  height: 26,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filtrar mensajes…',
                      hintStyle: const TextStyle(fontSize: 11.5),
                      prefixIcon: const Icon(Icons.search, size: 14),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(
                        'Todos',
                        widget.entries.length,
                        _ConsoleFilter.all,
                        cs.primary,
                        cs,
                      ),
                      const SizedBox(width: 5),
                      _buildFilterChip(
                        'Éxito',
                        successCount,
                        _ConsoleFilter.success,
                        const Color(0xFF3FB950),
                        cs,
                      ),
                      const SizedBox(width: 5),
                      _buildFilterChip(
                        'Errores',
                        errorCount,
                        _ConsoleFilter.error,
                        const Color(0xFFE5484D),
                        cs,
                      ),
                      const SizedBox(width: 5),
                      _buildFilterChip(
                        'Avisos',
                        warnCount,
                        _ConsoleFilter.warning,
                        const Color(0xFFE2A03F),
                        cs,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _iconBtn(
                Icons.unfold_more_rounded,
                'Expandir / colapsar todos los detalles',
                _toggleTodos,
                cs,
              ),
              _iconBtn(Icons.copy_all_rounded, 'Copiar todo el historial', () {
                final text = widget.entries
                    .map(
                      (e) =>
                          '[${e.timestamp.toIso8601String().substring(11, 19)}] '
                          '[${e.kind.label}] ${e.statementPreview}\n'
                          '${e.message ?? 'OK'}\n',
                    )
                    .join('\n');
                Clipboard.setData(ClipboardData(text: text));
                AppToast.success('Historial copiado al portapapeles');
              }, cs),
            ],
          );
        },
      ),
    );
  }

  Widget _iconBtn(
    IconData icon,
    String tip,
    VoidCallback onTap,
    ColorScheme cs,
  ) => Tooltip(
    message: tip,
    child: InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 15, color: cs.onSurfaceVariant),
      ),
    ),
  );

  Widget _buildFilterChip(
    String label,
    int count,
    _ConsoleFilter target,
    Color activeColor,
    ColorScheme cs,
  ) {
    final active = _filter == target;
    return InkWell(
      onTap: () => setState(() => _filter = target),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.6)
                : cs.outlineVariant.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: activeColor,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              count > 0 ? '$label ($count)' : label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? activeColor : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard(
    SqlExecutionLogEntry entry,
    ColorScheme cs,
    bool isDark,
  ) {
    final statusColor = _statusColor(entry.status, isDark);
    final isExpanded = _expandedEntries.contains(entry.id);
    final detalle = entry.message?.trim() ?? '';
    final hasDetalle = detalle.isNotEmpty;
    final codigos = AppLog.oracleCodes(
      '${entry.statementPreview}\n${entry.message ?? ''}',
    );

    return InkWell(
      onTap: hasDetalle ? () => _toggleDetalle(entry.id) : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xFF161B22) : const Color(0xFFFFFFFF))
              .withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.5),
            width: 0.6,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (hasDetalle)
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.chevron_right_rounded,
                        size: 15,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _statusIcon(entry.status),
                          size: 10.5,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _statusLabel(entry.status),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      entry.kind.label,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    [
                      entry.timestamp.toIso8601String().substring(11, 19),
                      entry.ambiente,
                      if (entry.durationMs != null) '${entry.durationMs} ms',
                      if (entry.rowsAffectedOrReturned != null)
                        '${entry.rowsAffectedOrReturned} fila(s)',
                    ].join(' · '),
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 10.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (final c in codigos) ...[
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.7),
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        c,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.onReplay != null)
                    Tooltip(
                      message: 'Insertar en editor',
                      child: IconButton(
                        icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        onPressed: () => widget.onReplay!(entry),
                      ),
                    ),
                  Tooltip(
                    message: 'Copiar SQL',
                    child: IconButton(
                      icon: const Icon(Icons.content_copy_rounded, size: 13),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                      ),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: entry.statementPreview),
                        );
                        AppToast.success('Sentencia copiada');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              SelectableText(
                entry.statementPreview,
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'Consolas',
                  color: cs.onSurface,
                  height: 1.3,
                ),
              ),
              if (hasDetalle) ...[
                const SizedBox(height: 4),
                if (!isExpanded) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          detalle.split('\n').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${detalle.split('\n').length} línea(s)',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(
                        alpha: isDark ? 0.08 : 0.05,
                      ),
                      border: Border(
                        left: BorderSide(color: statusColor, width: 2.5),
                      ),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(4),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: SelectableText(
                      detalle,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11,
                        color: statusColor,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
