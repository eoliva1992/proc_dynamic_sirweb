/// Consola de traza HTTP tipo IDE: lista de peticiones enviadas y respuestas
/// recibidas del servidor SirWeb (POST /tools/sql/statement, explain, sesiones),
/// con detalle de método, URL, status code HTTP, tiempo en ms, payload JSON
/// y respuesta cruda del backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/sql_http_trace.dart';
import '../app_toast.dart';

enum _ServerTraceFilter { all, success, error, running }

class SqlServerTraceConsole extends StatefulWidget {
  const SqlServerTraceConsole({super.key, required this.traces, this.onClear});

  final List<SqlHttpTraceEntry> traces;
  final VoidCallback? onClear;

  @override
  State<SqlServerTraceConsole> createState() => _SqlServerTraceConsoleState();
}

class _SqlServerTraceConsoleState extends State<SqlServerTraceConsole> {
  _ServerTraceFilter _filter = _ServerTraceFilter.all;
  final Set<int> _expandedTraces = {};
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(SqlHttpTraceEntry trace, bool isDark) {
    return switch (trace.status) {
      SqlHttpTraceStatus.running => const Color(0xFF388BFD),
      SqlHttpTraceStatus.success => const Color(0xFF2EA043),
      SqlHttpTraceStatus.error => const Color(0xFFE5484D),
      SqlHttpTraceStatus.cancelled => const Color(0xFFD97706),
    };
  }

  String _statusLabel(SqlHttpTraceEntry trace) {
    if (trace.status == SqlHttpTraceStatus.running) return 'EN CURSO';
    if (trace.status == SqlHttpTraceStatus.cancelled) return 'CANCELADO';
    if (trace.statusCode != null) {
      return '${trace.statusCode} ${trace.status == SqlHttpTraceStatus.success ? "OK" : "ERROR"}';
    }
    return trace.status == SqlHttpTraceStatus.success ? '200 OK' : 'ERROR';
  }

  void _toggleDetalle(int id) {
    setState(() {
      if (!_expandedTraces.remove(id)) _expandedTraces.add(id);
    });
  }

  void _toggleTodos() {
    setState(() {
      if (_expandedTraces.length == widget.traces.length) {
        _expandedTraces.clear();
      } else {
        _expandedTraces
          ..clear()
          ..addAll(widget.traces.map((t) => t.id));
      }
    });
  }

  Future<void> _handleClear(BuildContext context) async {
    if (widget.onClear == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar trazas del servidor'),
        content: const Text(
          '¿Deseas vaciar todo el registro de envíos y respuestas HTTP?',
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

  void _copyAllTraces() {
    if (widget.traces.isEmpty) return;
    final sb = StringBuffer();
    for (final t in widget.traces) {
      sb.writeln('========================================');
      sb.writeln('[${t.timestamp.toIso8601String()}] ${t.method} ${t.url}');
      sb.writeln(
        'Status: ${_statusLabel(t)} | Duración: ${t.durationMs ?? 0} ms',
      );
      if (t.requestBody != null) {
        sb.writeln('--- REQUEST PAYLOAD ---');
        sb.writeln(t.prettyRequestBody);
      }
      if (t.responseBody != null) {
        sb.writeln('--- RESPONSE BODY ---');
        sb.writeln(t.prettyResponseBody);
      }
      if (t.error != null) {
        sb.writeln('--- ERROR ---');
        sb.writeln(t.error);
      }
      sb.writeln();
    }

    Clipboard.setData(ClipboardData(text: sb.toString()));
    AppToast.success('Trazas HTTP copiadas al portapapeles');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    if (widget.traces.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 40,
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              'Sin peticiones HTTP registradas',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Los envíos y respuestas del servidor SirWeb aparecerán acá en tiempo real',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    final successCount = widget.traces
        .where((t) => t.status == SqlHttpTraceStatus.success)
        .length;
    final errorCount = widget.traces
        .where((t) => t.status == SqlHttpTraceStatus.error)
        .length;
    final runningCount = widget.traces
        .where((t) => t.status == SqlHttpTraceStatus.running)
        .length;

    final q = _search.trim().toLowerCase();
    final filtered = widget.traces.where((t) {
      final matchesFilter = switch (_filter) {
        _ServerTraceFilter.all => true,
        _ServerTraceFilter.success => t.status == SqlHttpTraceStatus.success,
        _ServerTraceFilter.error => t.status == SqlHttpTraceStatus.error,
        _ServerTraceFilter.running => t.status == SqlHttpTraceStatus.running,
      };
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      return t.endpoint.toLowerCase().contains(q) ||
          t.url.toLowerCase().contains(q) ||
          (t.requestBody?.toLowerCase().contains(q) ?? false) ||
          (t.responseBody?.toLowerCase().contains(q) ?? false) ||
          (t.error?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Column(
      children: [
        _buildFilterBar(cs, isDark, successCount, errorCount, runningCount),
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
                    final trace = filtered[filtered.length - 1 - i];
                    return _buildTraceCard(trace, cs, isDark);
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
    int runningCount,
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
                  width: 180,
                  height: 26,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filtrar HTTP…',
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
                        widget.traces.length,
                        _ServerTraceFilter.all,
                        cs.primary,
                        cs,
                      ),
                      const SizedBox(width: 5),
                      _buildFilterChip(
                        'Éxito 2xx',
                        successCount,
                        _ServerTraceFilter.success,
                        const Color(0xFF2EA043),
                        cs,
                      ),
                      const SizedBox(width: 5),
                      _buildFilterChip(
                        'Errores',
                        errorCount,
                        _ServerTraceFilter.error,
                        const Color(0xFFE5484D),
                        cs,
                      ),
                      if (runningCount > 0) ...[
                        const SizedBox(width: 5),
                        _buildFilterChip(
                          'En curso',
                          runningCount,
                          _ServerTraceFilter.running,
                          const Color(0xFF388BFD),
                          cs,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _iconBtn(
                Icons.unfold_more_rounded,
                'Expandir / colapsar todas las trazas',
                _toggleTodos,
                cs,
              ),
              _iconBtn(
                Icons.copy_all_rounded,
                'Copiar todo el registro HTTP',
                _copyAllTraces,
                cs,
              ),
              if (widget.onClear != null)
                _iconBtn(
                  Icons.delete_sweep_outlined,
                  'Limpiar trazas del servidor',
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
    _ServerTraceFilter target,
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
              '$label ($count)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? activeColor : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTraceCard(SqlHttpTraceEntry trace, ColorScheme cs, bool isDark) {
    final isExpanded = _expandedTraces.contains(trace.id);
    final statusColor = _statusColor(trace, isDark);
    final statusText = _statusLabel(trace);

    final cardBorder = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.6);
    final cardBg = isDark ? const Color(0xFF161B22) : cs.surfaceContainerLowest;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cardBorder, width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _toggleDetalle(trace.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Método HTTP badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      trace.method,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.5),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (trace.status == SqlHttpTraceStatus.running)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: statusColor,
                              ),
                            ),
                          ),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Endpoint
                  Expanded(
                    child: Text(
                      trace.endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Duración
                  if (trace.durationMs != null)
                    Text(
                      '${trace.durationMs} ms',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  const SizedBox(width: 8),
                  // Hora
                  Text(
                    _formatTime(trace.timestamp),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Botón cURL
                  Tooltip(
                    message: 'Copiar comando cURL',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: trace.toCurlCommand()),
                        );
                        AppToast.success('Comando cURL copiado');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.terminal,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _buildTraceDetails(trace, cs, isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTraceDetails(
    SqlHttpTraceEntry trace,
    ColorScheme cs,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // URL completa
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'URL: ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: SelectableText(
                trace.url,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Sección REQUEST
        _buildSectionHeader(
          title: 'Request (Payload enviado al servidor)',
          contentToCopy: trace.prettyRequestBody,
          cs: cs,
        ),
        const SizedBox(height: 4),
        _buildJsonViewer(
          trace.prettyRequestBody.isNotEmpty
              ? trace.prettyRequestBody
              : '(sin cuerpo de petición)',
          cs,
          isDark,
        ),
        const SizedBox(height: 10),

        // Sección RESPONSE
        _buildSectionHeader(
          title: 'Response (Respuesta devuelta por el servidor)',
          contentToCopy: trace.prettyResponseBody.isNotEmpty
              ? trace.prettyResponseBody
              : (trace.error ?? ''),
          cs: cs,
        ),
        const SizedBox(height: 4),
        if (trace.error != null && trace.error!.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE5484D).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: const Color(0xFFE5484D).withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: SelectableText(
              'Error: ${trace.error}',
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 11,
                color: Color(0xFFE5484D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        _buildJsonViewer(
          trace.prettyResponseBody.isNotEmpty
              ? trace.prettyResponseBody
              : (trace.status == SqlHttpTraceStatus.running
                    ? 'Esperando respuesta del servidor...'
                    : '(sin cuerpo de respuesta)'),
          cs,
          isDark,
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String contentToCopy,
    required ColorScheme cs,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        if (contentToCopy.isNotEmpty)
          Tooltip(
            message: 'Copiar JSON',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                Clipboard.setData(ClipboardData(text: contentToCopy));
                AppToast.success('Copiado al portapapeles');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded, size: 12, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Copiar',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildJsonViewer(String text, ColorScheme cs, bool isDark) {
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5);
    final border = isDark
        ? const Color(0xFF21262D)
        : cs.outlineVariant.withValues(alpha: 0.5);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 260),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border, width: 0.8),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 11,
            height: 1.35,
            color: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}
