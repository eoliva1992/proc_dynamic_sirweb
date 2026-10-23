import 'package:flutter/material.dart';

import '../../models/sql_execution.dart';
import '../../services/backup_service.dart';
import 'sql_executor_toolbar.dart' show kindColor;

/// Barra de estado inferior del Ejecutor SQL.
///
/// Muestra posición del cursor, conteo de sentencias en el script, modo actual,
/// ruta del archivo local o indicador de script nuevo, tiempo de ejecución de la
/// última sentencia y ambiente activo.
class SqlExecutorStatusBar extends StatelessWidget {
  final int cursorLine;
  final int cursorCol;
  final int statementCount;
  final SqlStatement? statement;
  final bool running;
  final SqlExecutionLogEntry? lastEntry;
  final String ambiente;
  final String? currentFilePath;
  final bool isDirty;

  const SqlExecutorStatusBar({
    super.key,
    required this.cursorLine,
    required this.cursorCol,
    required this.statementCount,
    required this.statement,
    required this.running,
    required this.lastEntry,
    required this.ambiente,
    this.currentFilePath,
    this.isDirty = false,
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
          const SizedBox(width: 8),
          SizedBox(
            height: 12,
            child: VerticalDivider(
              color: cs.outlineVariant.withValues(alpha: 0.5),
              width: 8,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Tooltip(
              message: currentFilePath != null && currentFilePath!.isNotEmpty
                  ? (isDirty
                      ? 'Archivo: $currentFilePath (con cambios pendientes de guardar)\n(Clic para abrir ubicación en el explorador)'
                      : 'Archivo: $currentFilePath\n(Clic para abrir ubicación en el explorador)')
                  : (isDirty
                      ? 'Documento nuevo con cambios sin guardar en disco'
                      : 'Documento nuevo sin guardar en disco'),
              child: InkWell(
                onTap: currentFilePath != null && currentFilePath!.isNotEmpty
                    ? () => BackupService.revealInExplorer(currentFilePath!)
                    : null,
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        currentFilePath != null && currentFilePath!.isNotEmpty
                            ? Icons.description_outlined
                            : Icons.edit_document,
                        size: 12,
                        color: isDirty
                            ? Colors.orange.shade400
                            : (currentFilePath != null &&
                                    currentFilePath!.isNotEmpty
                                ? cs.primary
                                : cs.onSurfaceVariant.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          currentFilePath != null && currentFilePath!.isNotEmpty
                              ? currentFilePath!
                              : 'Script nuevo (sin guardar)',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily:
                                currentFilePath != null &&
                                    currentFilePath!.isNotEmpty
                                ? 'Consolas'
                                : null,
                            color:
                                currentFilePath != null &&
                                    currentFilePath!.isNotEmpty
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                            fontStyle:
                                currentFilePath == null ||
                                    currentFilePath!.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                      if (isDirty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.4),
                              width: 0.6,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade400,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Modificado',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade400,
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
          const SizedBox(width: 8),
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
