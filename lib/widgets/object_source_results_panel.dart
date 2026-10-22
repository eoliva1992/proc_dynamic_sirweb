import 'package:flutter/material.dart';

import '../models/object_compilation_entry.dart';
import '../models/sql_http_trace.dart';
import '_editor_plsql_checker.dart';
import 'problems_output_console.dart';
import 'sql_executor/sql_server_trace_console.dart';

/// Panel inferior deslizable y redimensionable con los resultados del editor
/// de objeto esquema (salida de compilación / mensajes / problemas y trazas HTTP).
class ObjectSourceResultsPanel extends StatelessWidget {
  final TabController tabController;
  final bool visible;
  final double height;
  final ValueChanged<double> onHeightChanged;
  final VoidCallback onToggleVisible;
  final VoidCallback? onClose;
  final bool isPinned;
  final VoidCallback? onTogglePinned;
  final List<PlSqlIssue> issues;
  final bool checking;
  final void Function(PlSqlIssue issue) onJumpTo;
  final List<SqlHttpTraceEntry> httpTraces;
  final VoidCallback? onClearHttpTraces;
  final VoidCallback? onClearIssues;
  final ObjectCompilationEntry? lastCompilation;

  const ObjectSourceResultsPanel({
    super.key,
    required this.tabController,
    required this.visible,
    required this.height,
    required this.onHeightChanged,
    required this.onToggleVisible,
    this.onClose,
    this.isPinned = true,
    this.onTogglePinned,
    required this.issues,
    required this.checking,
    required this.onJumpTo,
    this.httpTraces = const [],
    this.onClearHttpTraces,
    this.onClearIssues,
    this.lastCompilation,
  });

  Widget _buildCountBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF0F1318) : Colors.white;
    final headerBg = isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
    final borderColor = isDark
        ? const Color(0xFF30363D)
        : const Color(0xFFD0D7DE);

    final errorCount = issues
        .where(
          (e) =>
              e.severity.name == 'error' ||
              e.severity.toString().contains('error'),
        )
        .length;
    final warnCount = issues
        .where(
          (e) =>
              e.severity.name == 'warning' ||
              e.severity.toString().contains('warning'),
        )
        .length;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Barra superior de redimensionamiento
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: (details) {
                onHeightChanged(
                  (height - details.delta.dy).clamp(140.0, 520.0),
                );
              },
              child: Container(
                height: 8,
                color: headerBg,
                alignment: Alignment.center,
                child: Container(
                  width: 38,
                  height: 3,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          // Header con tabs y acciones
          Container(
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
                            const Icon(Icons.list_alt_rounded, size: 14),
                            const SizedBox(width: 6),
                            const Text('Mensajes'),
                            if (issues.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _buildCountBadge(
                                '${issues.length}',
                                errorCount > 0
                                    ? const Color(0xFFE5484D)
                                    : (warnCount > 0
                                          ? const Color(0xFFD97706)
                                          : cs.onSurfaceVariant),
                                isDark,
                              ),
                            ],
                            if (checking) ...[
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.dns_outlined, size: 14),
                            const SizedBox(width: 6),
                            const Text('Servidor'),
                            if (httpTraces.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _buildCountBadge(
                                '${httpTraces.length}',
                                httpTraces.any(
                                      (t) =>
                                          t.status == SqlHttpTraceStatus.error,
                                    )
                                    ? const Color(0xFFE5484D)
                                    : cs.onSurfaceVariant,
                                isDark,
                              ),
                            ],
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
                              : cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
                Tooltip(
                  message: visible ? 'Colapsar salida' : 'Expandir salida',
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
                if (onClose != null) ...[
                  const SizedBox(width: 2),
                  Tooltip(
                    message: 'Cerrar panel',
                    child: InkWell(
                      onTap: onClose,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Contenido de las pestañas
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: [
                // Tab 0: Mensajes / Compilación / Problemas
                ProblemsOutputConsole(
                  issues: issues,
                  checking: checking,
                  onJumpTo: onJumpTo,
                  lastCompilation: lastCompilation,
                  onClear: onClearIssues,
                ),
                // Tab 1: Trazas HTTP del Servidor
                SqlServerTraceConsole(
                  traces: httpTraces,
                  onClear: onClearHttpTraces,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tirador colapsado que flota en la parte inferior cuando el panel de resultados
/// del visor de objetos de esquema está oculto.
class ObjectSourceCollapsedHandle extends StatelessWidget {
  final VoidCallback onExpand;
  final List<PlSqlIssue> issues;
  final ObjectCompilationEntry? lastCompilation;
  final int httpTraceCount;

  const ObjectSourceCollapsedHandle({
    super.key,
    required this.onExpand,
    this.issues = const [],
    this.lastCompilation,
    this.httpTraceCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
    final borderColor = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.8);

    final errorCount = issues
        .where(
          (e) =>
              e.severity.name == 'error' ||
              e.message.toLowerCase().contains('error'),
        )
        .length;
    final warnCount = issues
        .where(
          (e) =>
              e.severity.name == 'warning' ||
              e.message.toLowerCase().contains('warning') ||
              e.message.toLowerCase().contains('aviso'),
        )
        .length;

    final isCompilationError =
        lastCompilation?.status == ObjectCompilationStatus.error ||
        errorCount > 0;
    final isCompilationSuccess =
        lastCompilation?.status == ObjectCompilationStatus.success &&
        errorCount == 0;

    final statusColor = isCompilationError
        ? const Color(0xFFE5484D)
        : isCompilationSuccess
        ? const Color(0xFF2EA043)
        : cs.primary;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(
                      Icons.terminal_rounded,
                      size: 14,
                      color: statusColor,
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
                    color: statusColor,
                  ),
                  if (errorCount > 0) ...[
                    const SizedBox(width: 8),
                    _buildPill(
                      icon: Icons.cancel_rounded,
                      text: '$errorCount error${errorCount > 1 ? 'es' : ''}',
                      color: const Color(0xFFE5484D),
                      isDark: isDark,
                    ),
                  ] else if (warnCount > 0) ...[
                    const SizedBox(width: 8),
                    _buildPill(
                      icon: Icons.warning_amber_rounded,
                      text: '$warnCount aviso${warnCount > 1 ? 's' : ''}',
                      color: const Color(0xFFE2A03F),
                      isDark: isDark,
                    ),
                  ] else if (isCompilationSuccess) ...[
                    const SizedBox(width: 8),
                    _buildPill(
                      icon: Icons.check_circle_rounded,
                      text: 'Compilado OK',
                      color: const Color(0xFF2EA043),
                      isDark: isDark,
                    ),
                  ] else if (httpTraceCount > 0) ...[
                    const SizedBox(width: 8),
                    _buildPill(
                      icon: Icons.cloud_outlined,
                      text: '$httpTraceCount req',
                      color: cs.onSurfaceVariant,
                      isDark: isDark,
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

  Widget _buildPill({
    required IconData icon,
    required String text,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
