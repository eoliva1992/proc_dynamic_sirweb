/// Consola de problemas (sintaxis PL/SQL + compilación Oracle) con la misma
/// identidad visual que `SqlOutputConsole`: filtros, búsqueda y entradas
/// expandibles.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import '../models/object_compilation_entry.dart';
import '_editor_plsql_checker.dart';
import 'app_toast.dart';

enum _ProblemsFilter { all, error, warning }

class ProblemsOutputConsole extends StatefulWidget {
  const ProblemsOutputConsole({
    super.key,
    required this.issues,
    required this.checking,
    required this.onJumpTo,
    this.lastCompilation,
    this.onClear,
  });

  final List<PlSqlIssue> issues;
  final bool checking;
  final void Function(PlSqlIssue issue) onJumpTo;
  final ObjectCompilationEntry? lastCompilation;
  final VoidCallback? onClear;

  @override
  State<ProblemsOutputConsole> createState() => _ProblemsOutputConsoleState();
}

class _ProblemsOutputConsoleState extends State<ProblemsOutputConsole> {
  static const _errorColor = Color(0xFFE5484D);
  static const _warnColor = Color(0xFFE2A03F);

  _ProblemsFilter _filter = _ProblemsFilter.all;
  final Set<int> _expanded = {};
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int _keyFor(PlSqlIssue issue) =>
      Object.hash(issue.line, issue.col, issue.message);

  void _toggleExpanded(int key) => setState(() {
    if (!_expanded.remove(key)) _expanded.add(key);
  });

  Future<void> _handleClear(BuildContext context) async {
    if (widget.onClear == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar mensajes'),
        content: const Text(
          '¿Deseas vaciar todos los mensajes y problemas de compilación?',
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final errorCount = widget.issues
        .where((e) => e.severity == MarkerSeverity.error)
        .length;
    final warnCount = widget.issues
        .where((e) => e.severity == MarkerSeverity.warning)
        .length;

    final q = _search.trim().toLowerCase();
    final filtered = widget.issues.where((e) {
      final matches = switch (_filter) {
        _ProblemsFilter.all => true,
        _ProblemsFilter.error => e.severity == MarkerSeverity.error,
        _ProblemsFilter.warning => e.severity == MarkerSeverity.warning,
      };
      if (!matches) return false;
      if (q.isEmpty) return true;
      return e.message.toLowerCase().contains(q) ||
          e.source.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        _buildFilterBar(cs, isDark, errorCount, warnCount, filtered),
        Divider(
          height: 1,
          thickness: 1,
          color: cs.outlineVariant.withValues(alpha: 0.8),
        ),
        if (widget.lastCompilation != null)
          _buildCompilationBanner(widget.lastCompilation!, cs, isDark),
        Expanded(
          child: widget.issues.isEmpty
              ? _buildEmpty(cs)
              : filtered.isEmpty
              ? Center(
                  child: Text(
                    'Sin resultados con este filtro',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _buildRow(filtered[i], cs, isDark),
                ),
        ),
      ],
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    if (widget.lastCompilation != null) {
      final isSuccess =
          widget.lastCompilation!.status == ObjectCompilationStatus.success;
      if (isSuccess) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 36,
                  color: Color(0xFF2EA043),
                ),
                const SizedBox(height: 8),
                Text(
                  'Compilación completada sin errores',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.lastCompilation!.targetTitle} en ambiente ${widget.lastCompilation!.ambiente} (${widget.lastCompilation!.durationMs} ms)',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // Falló la compilación pero no hay issues individuales o fueron filtrados
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 36,
                  color: Color(0xFFE5484D),
                ),
                const SizedBox(height: 8),
                Text(
                  'Error en la compilación',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                if (widget.lastCompilation!.message != null &&
                    widget.lastCompilation!.message!.isNotEmpty) ...[
                  SelectableText(
                    widget.lastCompilation!.message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'Consolas',
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.lastCompilation!.message!),
                      );
                      AppToast.success('Mensaje de error copiado');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text(
                      'Copiar error',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Revisa la pestaña "Servidor" para ver los detalles de la respuesta de Oracle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.task_alt_rounded,
            size: 32,
            color: cs.onSurfaceVariant.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 8),
          Text(
            'Sin problemas detectados',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompilationBanner(
    ObjectCompilationEntry entry,
    ColorScheme cs,
    bool isDark,
  ) {
    final isSuccess = entry.status == ObjectCompilationStatus.success;
    final isError = entry.status == ObjectCompilationStatus.error;
    final statusColor = isSuccess
        ? const Color(0xFF2EA043)
        : isError
        ? const Color(0xFFE5484D)
        : const Color(0xFF388BFD);
    final statusBg = isDark
        ? statusColor.withValues(alpha: 0.12)
        : statusColor.withValues(alpha: 0.08);

    final statusIcon = isSuccess
        ? Icons.check_circle_rounded
        : isError
        ? Icons.error_rounded
        : Icons.hourglass_top_rounded;

    final statusLabel = isSuccess
        ? 'Compilado exitosamente'
        : isError
        ? 'Compilación con errores'
        : 'Compilando...';

    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusBg,
        border: Border(
          bottom: BorderSide(
            color: statusColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 15, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '•',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.targetTitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '•',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.ambiente} (${entry.durationMs} ms)',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 10.5,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(
    ColorScheme cs,
    bool isDark,
    int errorCount,
    int warnCount,
    List<PlSqlIssue> filtered,
  ) {
    return Container(
      height: 36,
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
      color: isDark ? const Color(0xFF161B22) : const Color(0xFFF1F3F5),
      child: LayoutBuilder(
        builder: (context, c) {
          final mostrarBuscador = c.maxWidth >= 360;
          return Row(
            children: [
              if (mostrarBuscador) ...[
                SizedBox(
                  width: 140,
                  height: 24,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(fontSize: 11.5),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filtrar…',
                      hintStyle: const TextStyle(fontSize: 11),
                      prefixIcon: const Icon(Icons.search, size: 13),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildChip(
                        'Todos',
                        widget.issues.length,
                        _ProblemsFilter.all,
                        cs.primary,
                        cs,
                      ),
                      const SizedBox(width: 5),
                      _buildChip(
                        'Errores',
                        errorCount,
                        _ProblemsFilter.error,
                        _errorColor,
                        cs,
                      ),
                      const SizedBox(width: 5),
                      _buildChip(
                        'Avisos',
                        warnCount,
                        _ProblemsFilter.warning,
                        _warnColor,
                        cs,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.checking) ...[
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
              if (widget.onClear != null &&
                  (widget.issues.isNotEmpty || widget.lastCompilation != null))
                _iconBtn(
                  Icons.delete_sweep_outlined,
                  'Limpiar mensajes',
                  () => _handleClear(context),
                  cs,
                ),
              _iconBtn(Icons.copy_all_rounded, 'Copiar todo', () {
                final text = filtered
                    .map(
                      (e) => '${e.source} L${e.line}:${e.col} — ${e.message}',
                    )
                    .join('\n');
                Clipboard.setData(ClipboardData(text: text));
                AppToast.success('Problemas copiados al portapapeles');
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
        child: Icon(icon, size: 14, color: cs.onSurfaceVariant),
      ),
    ),
  );

  Widget _buildChip(
    String label,
    int count,
    _ProblemsFilter target,
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

  Widget _buildRow(PlSqlIssue issue, ColorScheme cs, bool isDark) {
    final isError = issue.severity == MarkerSeverity.error;
    final color = isError ? _errorColor : _warnColor;
    final key = _keyFor(issue);
    final expanded = _expanded.contains(key);
    final longMsg = issue.message.length > 90 || issue.message.contains('\n');

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF161B22) : Colors.white).withValues(
          alpha: 0.7,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
          width: 0.6,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => widget.onJumpTo(issue),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isError ? Icons.error_rounded : Icons.warning_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  issue.message,
                  style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
                  maxLines: expanded ? null : 2,
                  overflow: expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (issue.line > 1 || issue.col > 1)
                Text(
                  'L${issue.line}:${issue.col}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: cs.onSurfaceVariant,
                    fontFamily: 'Consolas',
                  ),
                ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  issue.source,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: issue.source == 'Oracle'
                        ? Colors.orange[400]
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (longMsg)
                InkWell(
                  onTap: () => _toggleExpanded(key),
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      expanded
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                      size: 13,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              Tooltip(
                message: 'Copiar mensaje',
                child: InkWell(
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            '${issue.source} L${issue.line}:${issue.col} — ${issue.message}',
                      ),
                    );
                    AppToast.info('Copiado al portapapeles');
                  },
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 13,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
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
