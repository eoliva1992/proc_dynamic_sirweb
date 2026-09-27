import 'package:flutter/material.dart';

import '../../models/sql_execution.dart';
import 'sql_executor_toolbar.dart'
    show kSqlTooltipDecoration, kSqlTooltipTextStyle, kSqlTooltipWait;
import 'sql_explain_plan_view.dart';
import 'sql_output_console.dart';
import 'sql_results_grid.dart';

/// Panel inferior deslizable y redimensionable con los resultados de la consulta,
/// consola de mensajes, árbol Explain Plan e historial de sentencias.
class SqlExecutorResultsPanel extends StatelessWidget {
  final TabController tabController;
  final bool visible;
  final double height;
  final ValueChanged<double> onHeightChanged;
  final VoidCallback onToggleVisible;
  final SqlQueryResult? lastResult;
  final List<SqlExecutionLogEntry> log;
  final List<SqlExplainPlanNode>? explainNodes;
  final List<String>? explainText;
  final int maxRows;
  final ValueChanged<int> onMaxRowsChanged;
  final void Function(List<int> rowIndexes) onGenerateDml;
  final void Function(SqlExecutionLogEntry entry)? onReplay;

  const SqlExecutorResultsPanel({
    super.key,
    required this.tabController,
    required this.visible,
    required this.height,
    required this.onHeightChanged,
    required this.onToggleVisible,
    required this.lastResult,
    required this.log,
    required this.explainNodes,
    this.explainText,
    required this.maxRows,
    required this.onMaxRowsChanged,
    required this.onGenerateDml,
    this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFFBFBFD);
    final headerBg = isDark ? const Color(0xFF161B22) : const Color(0xFFF1F3F5);

    return RepaintBoundary(
      child: Material(
        elevation: 10,
        color: bg,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Tirador de arrastre superior tipo AppConsole
            MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  onHeightChanged(
                    (height - details.delta.dy).clamp(140.0, 520.0),
                  );
                },
                child: Container(
                  height: 8,
                  width: double.infinity,
                  color: headerBg,
                  child: Center(
                    child: Container(
                      width: 42,
                      height: 3,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Cabecera compacta con pestañas y acciones estilo log
            Container(
              height: 36,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                color: headerBg,
                border: Border(
                  bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.8),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.terminal_rounded,
                    size: 15,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Salida',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TabBar(
                      controller: tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: cs.primaryContainer.withValues(
                          alpha: isDark ? 0.35 : 0.5,
                        ),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      labelColor: cs.primary,
                      unselectedLabelColor: cs.onSurfaceVariant,
                      labelStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: const TextStyle(fontSize: 11),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.table_chart_outlined, size: 13),
                              const SizedBox(width: 5),
                              const Text('Resultados'),
                              if (lastResult != null) ...[
                                const SizedBox(width: 5),
                                _buildCountBadge(
                                  '${lastResult!.returnedRows}',
                                  cs.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.terminal_outlined, size: 13),
                              const SizedBox(width: 5),
                              const Text('Mensajes'),
                              if (log.isNotEmpty) ...[
                                const SizedBox(width: 5),
                                _buildCountBadge(
                                  '${log.length}',
                                  cs.onSurfaceVariant,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.account_tree_outlined, size: 13),
                              const SizedBox(width: 5),
                              const Text('Plan de Ejecución'),
                              if (explainNodes != null) ...[
                                const SizedBox(width: 5),
                                _buildCountBadge(
                                  '${explainNodes!.length}',
                                  cs.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_rounded, size: 13),
                              SizedBox(width: 5),
                              Text('Historial'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: visible ? 'Colapsar salida' : 'Expandir salida',
                    waitDuration: kSqlTooltipWait,
                    preferBelow: false,
                    decoration: kSqlTooltipDecoration,
                    textStyle: kSqlTooltipTextStyle,
                    child: InkWell(
                      onTap: onToggleVisible,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: AnimatedRotation(
                          duration: const Duration(milliseconds: 200),
                          turns: visible ? 0.0 : 0.5,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 17,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: tabController,
                builder: (context, _) {
                  final activeIndex = tabController.index;
                  return TabBarView(
                    controller: tabController,
                    children: [
                      // Tab 0: Grilla de resultados
                      SqlResultsGrid(
                        result: lastResult,
                        maxRows: maxRows,
                        onMaxRowsChanged: onMaxRowsChanged,
                        onGenerateDml: onGenerateDml,
                      ),
                      // Tab 1: Mensajes / Salida (lazy load si no está activo)
                      if (activeIndex == 1)
                        SqlOutputConsole(entries: log)
                      else
                        const SizedBox.shrink(),
                      // Tab 2: Plan de ejecución (lazy load si no está activo)
                      if (activeIndex == 2)
                        SqlExplainPlanView(
                          nodes: explainNodes,
                          textPlan: explainText,
                        )
                      else
                        const SizedBox.shrink(),
                      // Tab 3: Historial (lazy load si no está activo)
                      if (activeIndex == 3)
                        SqlOutputConsole(entries: log, onReplay: onReplay)
                      else
                        const SizedBox.shrink(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: color,
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
    final bg = isDark ? const Color(0xFF161B22) : const Color(0xFFF1F3F5);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        elevation: 8,
        color: bg,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onExpand,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 3,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  Icons.terminal_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Mostrar salida',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                if (lastResult != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.3),
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.table_chart_outlined,
                          size: 11,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${lastResult!.returnedRows} filas · ${lastResult!.durationMs} ms',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
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
    );
  }
}
