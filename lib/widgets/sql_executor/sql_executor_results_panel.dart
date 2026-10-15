import 'package:flutter/material.dart';

import '../../models/sql_execution.dart';
import 'sql_executor_toolbar.dart'
    show kSqlTooltipDecoration, kSqlTooltipTextStyle, kSqlTooltipWait;
import 'sql_explain_plan_view.dart';
import 'sql_output_console.dart';
import 'sql_results_grid.dart';
import 'sql_results_tab_strip.dart';

/// Panel inferior deslizable y redimensionable con los resultados de la consulta,
/// consola de mensajes, árbol Explain Plan e historial de sentencias.
class SqlExecutorResultsPanel extends StatelessWidget {
  final TabController tabController;
  final bool visible;
  final double height;
  final ValueChanged<double> onHeightChanged;
  final VoidCallback onToggleVisible;
  final List<SqlNamedResult> results;
  final int selectedResultIndex;
  final ValueChanged<int> onSelectResult;
  final List<SqlExecutionLogEntry> log;
  final List<SqlExplainPlanNode>? explainNodes;
  final List<String>? explainText;
  final int maxRows;
  final ValueChanged<int> onMaxRowsChanged;
  final void Function(List<int> rowIndexes) onGenerateDml;
  final void Function(SqlExecutionLogEntry entry)? onReplay;
  final VoidCallback? onClearLog;
  final bool isDetached;
  final VoidCallback? onToggleDetached;
  final bool isPinned;
  final VoidCallback? onTogglePinned;
  final ValueChanged<Offset>? onHeaderDrag;

  const SqlExecutorResultsPanel({
    super.key,
    required this.tabController,
    required this.visible,
    required this.height,
    required this.onHeightChanged,
    required this.onToggleVisible,
    required this.results,
    required this.selectedResultIndex,
    required this.onSelectResult,
    required this.log,
    required this.explainNodes,
    this.explainText,
    required this.maxRows,
    required this.onMaxRowsChanged,
    required this.onGenerateDml,
    this.onReplay,
    this.onClearLog,
    this.isDetached = false,
    this.onToggleDetached,
    this.isPinned = true,
    this.onTogglePinned,
    this.onHeaderDrag,
  });

  SqlQueryResult? get _selectedResult =>
      results.isEmpty ? null : results[selectedResultIndex].result;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF0F1318) : Colors.white;
    final headerBg = isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
    final borderColor = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.8);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.16),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: isDark
                  ? cs.primary.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              spreadRadius: 0,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1.0),
            ),
            child: Column(
              children: [
                // Tirador de arrastre superior tipo AppConsole (sólo en modo acoplado)
                if (!isDetached)
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        onHeightChanged(
                          (height - details.delta.dy).clamp(140.0, 700.0),
                        );
                      },
                      child: Container(
                        height: 9,
                        width: double.infinity,
                        color: headerBg,
                        alignment: Alignment.center,
                        child: Container(
                          width: 48,
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant.withValues(
                              alpha: isDark ? 0.35 : 0.45,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Cabecera compacta con pestañas y acciones estilo log
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: isDetached && onHeaderDrag != null
                      ? (details) => onHeaderDrag!(details.delta)
                      : null,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.only(left: 10, right: 6),
                    decoration: BoxDecoration(
                      color: headerBg,
                      border: Border(
                        bottom: BorderSide(color: borderColor, width: 1.0),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (isDetached)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              size: 16,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.terminal_rounded,
                            size: 15,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Salida',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TabBar(
                            controller: tabController,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            dividerColor: Colors.transparent,
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              color: isDark
                                  ? cs.primary.withValues(alpha: 0.18)
                                  : cs.primary.withValues(alpha: 0.12),
                              border: Border.all(
                                color: cs.primary.withValues(alpha: 0.5),
                                width: 1.0,
                              ),
                            ),
                            labelColor: cs.primary,
                            unselectedLabelColor: cs.onSurfaceVariant,
                            labelStyle: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                            tabs: [
                              Tab(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.table_chart_outlined,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('Resultados'),
                                    if (results.length > 1) ...[
                                      const SizedBox(width: 6),
                                      _buildCountBadge(
                                        '${results.length} sets',
                                        cs.primary,
                                        isDark,
                                      ),
                                    ] else if (_selectedResult != null) ...[
                                      const SizedBox(width: 6),
                                      _buildCountBadge(
                                        '${_selectedResult!.returnedRows}',
                                        cs.primary,
                                        isDark,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Tab(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.terminal_outlined,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('Mensajes'),
                                    if (log.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      _buildCountBadge(
                                        '${log.length}',
                                        log.any(
                                              (e) =>
                                                  e.status ==
                                                  SqlLogStatus.error,
                                            )
                                            ? const Color(0xFFE5484D)
                                            : cs.onSurfaceVariant,
                                        isDark,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Tab(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.account_tree_outlined,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('Plan de Ejecución'),
                                    if (explainNodes != null) ...[
                                      const SizedBox(width: 6),
                                      _buildCountBadge(
                                        '${explainNodes!.length}',
                                        cs.primary,
                                        isDark,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Tab(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.history_rounded, size: 14),
                                    SizedBox(width: 6),
                                    Text('Historial'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onTogglePinned != null) ...[
                          Tooltip(
                            message: isPinned
                                ? 'Fijado: permanece visible (clic para activar auto-ocultar al perder foco)'
                                : 'Auto-ocultar activo: se oculta al hacer clic fuera (clic para fijar)',
                            waitDuration: kSqlTooltipWait,
                            preferBelow: false,
                            decoration: kSqlTooltipDecoration,
                            textStyle: kSqlTooltipTextStyle,
                            child: InkWell(
                              onTap: onTogglePinned,
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.all(5),
                                child: Icon(
                                  isPinned
                                      ? Icons.push_pin_rounded
                                      : Icons.push_pin_outlined,
                                  size: 16,
                                  color: isPinned
                                      ? cs.primary
                                      : cs.onSurfaceVariant.withValues(
                                          alpha: 0.6,
                                        ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                        ],
                        if (onToggleDetached != null) ...[
                          Tooltip(
                            message: isDetached
                                ? 'Acoplar al fondo'
                                : 'Desacoplar en ventana flotante',
                            waitDuration: kSqlTooltipWait,
                            preferBelow: false,
                            decoration: kSqlTooltipDecoration,
                            textStyle: kSqlTooltipTextStyle,
                            child: InkWell(
                              onTap: onToggleDetached,
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.all(5),
                                child: Icon(
                                  isDetached
                                      ? Icons.vertical_align_bottom_rounded
                                      : Icons.open_in_new_rounded,
                                  size: 16,
                                  color: isDetached
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Tooltip(
                          message: visible
                              ? 'Colapsar salida'
                              : 'Expandir salida',
                          waitDuration: kSqlTooltipWait,
                          preferBelow: false,
                          decoration: kSqlTooltipDecoration,
                          textStyle: kSqlTooltipTextStyle,
                          child: InkWell(
                            onTap: onToggleVisible,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: AnimatedRotation(
                                duration: const Duration(milliseconds: 200),
                                turns: visible ? 0.0 : 0.5,
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: tabController,
                    children: [
                      // Tab 0: Grilla de resultados
                      Column(
                        children: [
                          if (results.length > 1)
                            SqlResultsTabStrip(
                              results: results,
                              selectedIndex: selectedResultIndex,
                              onSelect: onSelectResult,
                            ),
                          Expanded(
                            child: SqlResultsGrid(
                              key: ValueKey(
                                results.isEmpty
                                    ? -1
                                    : results[selectedResultIndex].id,
                              ),
                              result: _selectedResult,
                              maxRows: maxRows,
                              onMaxRowsChanged: onMaxRowsChanged,
                              onGenerateDml: onGenerateDml,
                            ),
                          ),
                        ],
                      ),
                      // Tab 1: Mensajes / Salida
                      SqlOutputConsole(entries: log, onClear: onClearLog),
                      // Tab 2: Plan de ejecución
                      SqlExplainPlanView(
                        nodes: explainNodes,
                        textPlan: explainText,
                      ),
                      // Tab 3: Historial
                      SqlOutputConsole(
                        entries: log,
                        onReplay: onReplay,
                        onClear: onClearLog,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.45 : 0.3),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Tirador colapsado que aparece al pie cuando la salida está oculta.
class SqlExecutorCollapsedHandle extends StatelessWidget {
  final VoidCallback onExpand;
  final SqlQueryResult? lastResult;

  const SqlExecutorCollapsedHandle({
    super.key,
    required this.onExpand,
    required this.lastResult,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
    final borderColor = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.8);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onExpand,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(
                      Icons.terminal_rounded,
                      size: 14,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Mostrar salida',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 17,
                    color: cs.primary,
                  ),
                  if (lastResult != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(
                          alpha: isDark ? 0.2 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.table_chart_outlined,
                            size: 12,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${lastResult!.returnedRows} filas · ${lastResult!.durationMs} ms',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
