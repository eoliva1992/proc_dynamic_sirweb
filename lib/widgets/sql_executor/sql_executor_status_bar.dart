import 'package:flutter/material.dart';

import '../../models/sql_execution.dart';
import 'sql_executor_toolbar.dart' show kindColor;

/// Barra de estado inferior del Ejecutor SQL.
///
/// Muestra posición del cursor, conteo de sentencias en el script, modo actual,
/// tiempo de ejecución de la última sentencia y ambiente activo.
class SqlExecutorStatusBar extends StatelessWidget {
  final int cursorLine;
  final int cursorCol;
  final int statementCount;
  final SqlStatement? statement;
  final bool running;
  final SqlExecutionLogEntry? lastEntry;
  final String ambiente;

  const SqlExecutorStatusBar({
    super.key,
    required this.cursorLine,
    required this.cursorCol,
    required this.statementCount,
    required this.statement,
    required this.running,
    required this.lastEntry,
    required this.ambiente,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLowest : cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.text_fields_rounded, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            'Ln $cursorLine, Col $cursorCol',
            style: TextStyle(
              fontSize: 10.5,
              color: cs.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 12,
            child: VerticalDivider(
              color: cs.outlineVariant.withValues(alpha: 0.5),
              width: 8,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.code_rounded, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '$statementCount ${statementCount == 1 ? 'sentencia' : 'sentencias'}',
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
          if (statement != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 12,
              child: VerticalDivider(
                color: cs.outlineVariant.withValues(alpha: 0.5),
                width: 8,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Modo: ${statement!.kind.label}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: kindColor(statement!.kind, isDark),
              ),
            ),
          ],
          const Spacer(),
          if (running) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.2,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'Ejecutando…',
              style: TextStyle(fontSize: 10.5, color: cs.primary),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 12,
              child: VerticalDivider(
                color: cs.outlineVariant.withValues(alpha: 0.5),
                width: 8,
              ),
            ),
          ] else if (lastEntry != null) ...[
            Icon(
              lastEntry!.status == SqlLogStatus.success
                  ? Icons.check_circle_rounded
                  : Icons.error_rounded,
              size: 12,
              color: lastEntry!.status == SqlLogStatus.success
                  ? Colors.green
                  : (lastEntry!.status == SqlLogStatus.warning
                        ? Colors.orange
                        : Colors.red),
            ),
            const SizedBox(width: 4),
            Text(
              lastEntry!.durationMs != null
                  ? '${lastEntry!.durationMs} ms'
                  : (lastEntry!.status == SqlLogStatus.success
                        ? 'OK'
                        : 'Error'),
              style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 12,
              child: VerticalDivider(
                color: cs.outlineVariant.withValues(alpha: 0.5),
                width: 8,
              ),
            ),
          ],
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.greenAccent.shade700,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            ambiente,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 12,
            child: VerticalDivider(
              color: cs.outlineVariant.withValues(alpha: 0.5),
              width: 8,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Oracle SQL · UTF-8',
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
