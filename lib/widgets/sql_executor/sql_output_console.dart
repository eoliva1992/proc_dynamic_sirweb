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
  const SqlOutputConsole({
    super.key,
    required this.entries,
    this.onReplay,
    this.onClear,
  });

  final List<SqlExecutionLogEntry> entries;

  /// Reinserta la sentencia de la entrada en el editor (usado también por Historial).
  final void Function(SqlExecutionLogEntry entry)? onReplay;

  /// Limpia los mensajes/historial de ejecución.
  final VoidCallback? onClear;

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
    SqlLogStatus.success => const Color(0xFF2EA043),
    SqlLogStatus.error => const Color(0xFFE5484D),
    SqlLogStatus.warning => const Color(0xFFD97706),
    SqlLogStatus.running => const Color(0xFF388BFD),
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
    setState(() {
      if (_expandedEntries.length == widget.entries.length) {
        _expandedEntries.clear();
      } else {
        _expandedEntries
          ..clear()
          ..addAll(widget.entries.map((e) => e.id));
      }
    });
  }

  Future<void> _handleClear(BuildContext context) async {
    if (widget.onClear == null) return;
    final esHistorial = widget.onReplay != null;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esHistorial ? 'Limpiar historial' : 'Limpiar mensajes'),
        content: Text(
          esHistorial
              ? '¿Deseas vaciar todo el historial de ejecuciones registrado?'
              : '¿Deseas vaciar todos los mensajes de ejecución?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE5484D),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      widget.onClear!();
    }
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
    final borderColor = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.8);

    return Container(
      height: 40,
      padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
        border: Border(bottom: BorderSide(color: borderColor, width: 1.0)),
      ),
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
                        const Color(0xFF2EA043),
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
                        const Color(0xFFD97706),
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
              _iconBtn(
                Icons.copy_all_rounded,
                widget.onReplay != null
                    ? 'Copiar todo el historial'
                    : 'Copiar todos los mensajes',
                () {
                  final esHistorial = widget.onReplay != null;
                  final text = widget.entries
                      .map((e) {
                        if (esHistorial) {
                          // En historial, el cuerpo de ejecución es el código/sentencia SQL
                          return e.statementPreview;
                        } else {
                          // En mensajes, el cuerpo es el mensaje/resultado de ejecución
                          return (e.message != null && e.message!.isNotEmpty)
                              ? e.message!
                              : (e.statementPreview.isNotEmpty
                                    ? e.statementPreview
                                    : 'OK');
                        }
                      })
                      .where((t) => t.isNotEmpty)
                      .join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  try {
                    AppToast.success(
                      esHistorial
                          ? 'Historial copiado al portapapeles'
                          : 'Mensajes copiados al portapapeles',
                    );
                  } catch (_) {}
                },
                cs,
              ),
              if (widget.onClear != null)
                _iconBtn(
                  Icons.delete_sweep_outlined,
                  widget.onReplay != null
                      ? 'Limpiar historial'
                      : 'Limpiar mensajes',
                  () => _handleClear(context),
                  cs,
                ),
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.7)
                : cs.outlineVariant.withValues(alpha: 0.5),
            width: active ? 1.0 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: activeColor,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              count > 0 ? '$label ($count)' : label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
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

    final cardBorder = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.6);

    return InkWell(
      onTap: hasDetalle ? () => _toggleDetalle(entry.id) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xFF161B22) : const Color(0xFFFFFFFF)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cardBorder, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3.5, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Fila superior: badges de estado, tipo, ambiente, duración y acciones
                      Row(
                        children: [
                          if (hasDetalle)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_down_rounded
                                    : Icons.chevron_right_rounded,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _statusIcon(entry.status),
                                  size: 11,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _statusLabel(entry.status),
                                  style: TextStyle(
                                    fontSize: 10,
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
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(
                                alpha: 0.25,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              entry.kind.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    [
                                      entry.timestamp
                                          .toIso8601String()
                                          .substring(11, 19),
                                      entry.ambiente,
                                      if (entry.durationMs != null)
                                        '${entry.durationMs} ms',
                                      if (entry.rowsAffectedOrReturned != null)
                                        '${entry.rowsAffectedOrReturned} fila(s)',
                                    ].join(' · '),
                                    style: TextStyle(
                                      fontFamily: 'Consolas',
                                      fontSize: 10.5,
                                      color: cs.onSurfaceVariant.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ),
                                  if (codigos.isNotEmpty)
                                    const SizedBox(width: 6),
                                  for (final c in codigos) ...[
                                    Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: statusColor.withValues(
                                            alpha: 0.7,
                                          ),
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
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (widget.onReplay != null)
                            Tooltip(
                              message: 'Insertar en editor',
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 14,
                                ),
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
                            message: widget.onReplay != null
                                ? 'Copiar SQL'
                                : (hasDetalle
                                      ? 'Copiar mensaje'
                                      : 'Copiar SQL'),
                            child: IconButton(
                              icon: const Icon(
                                Icons.content_copy_rounded,
                                size: 13,
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 22,
                                minHeight: 22,
                              ),
                              onPressed: () {
                                final esHistorial = widget.onReplay != null;
                                final text = esHistorial
                                    ? entry.statementPreview
                                    : (hasDetalle
                                          ? detalle
                                          : entry.statementPreview);
                                Clipboard.setData(ClipboardData(text: text));
                                try {
                                  AppToast.success(
                                    esHistorial || !hasDetalle
                                        ? 'Sentencia copiada'
                                        : 'Mensaje copiado',
                                  );
                                } catch (_) {}
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Sentencia SQL / preview
                      SelectableText(
                        entry.statementPreview.isNotEmpty
                            ? entry.statementPreview
                            : '(Sentencia vacía)',
                        onTap: hasDetalle
                            ? () => _toggleDetalle(entry.id)
                            : null,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Consolas',
                          color: isDark
                              ? const Color(0xFFE6EDF3)
                              : const Color(0xFF1F2328),
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (hasDetalle) ...[
                        const SizedBox(height: 6),
                        if (!isExpanded) ...[
                          Row(
                            children: [
                              Icon(
                                entry.status == SqlLogStatus.error
                                    ? Icons.error_outline_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 13,
                                color: statusColor,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  detalle.split('\n').first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Consolas',
                                    fontSize: 11,
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (detalle.split('\n').length > 1) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '${detalle.split('\n').length} línea(s)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ] else ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(
                                alpha: isDark ? 0.10 : 0.06,
                              ),
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(4),
                                bottomRight: Radius.circular(4),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    width: 3,
                                    color: statusColor,
                                    margin: const EdgeInsets.only(right: 8),
                                  ),
                                  Expanded(
                                    child: SelectableText(
                                      detalle,
                                      onTap: () => _toggleDetalle(entry.id),
                                      style: TextStyle(
                                        fontFamily: 'Consolas',
                                        fontSize: 11.5,
                                        color: isDark
                                            ? (entry.status ==
                                                      SqlLogStatus.error
                                                  ? const Color(0xFFFF7B72)
                                                  : const Color(0xFF7EE787))
                                            : statusColor,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
