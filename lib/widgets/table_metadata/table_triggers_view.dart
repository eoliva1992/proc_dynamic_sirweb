import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/table_metadata.dart';
import '../../services/table_metadata_service.dart';
import '../app_toast.dart';
import '../source_float_window.dart';

Color _rowBg(bool isDark, int i) => i.isEven
    ? Colors.transparent
    : (isDark
          ? Colors.white.withValues(alpha: 0.02)
          : Colors.black.withValues(alpha: 0.02));

/// Vista bajo demanda (Lazy) para listar disparadores (Triggers) de una tabla o vista.
class TableTriggersView extends StatefulWidget {
  final String tableName;
  final String ambiente;
  final String? owner;

  const TableTriggersView({
    super.key,
    required this.tableName,
    required this.ambiente,
    this.owner,
  });

  @override
  State<TableTriggersView> createState() => _TableTriggersViewState();
}

class _TableTriggersViewState extends State<TableTriggersView>
    with AutomaticKeepAliveClientMixin {
  late Future<List<TableTriggerInfo>> _future;
  bool _initialized = false;
  final Set<String> _togglingTriggers = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = TableMetadataService().getTableTriggers(
      widget.tableName,
      ambiente: widget.ambiente,
      owner: widget.owner,
    );
    _initialized = true;
  }

  void _refresh() {
    setState(() {
      _future = TableMetadataService().getTableTriggers(
        widget.tableName,
        ambiente: widget.ambiente,
        owner: widget.owner,
        forceRefresh: true,
      );
    });
  }

  Future<void> _toggleTrigger(TableTriggerInfo t) async {
    final nextEnable = !t.isEnabled;
    final actionWord = nextEnable ? 'Habilitar' : 'Deshabilitar';
    final actionDdl = nextEnable ? 'ENABLE' : 'DISABLE';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF252528) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              nextEnable ? Icons.check_circle_outline : Icons.warning_amber_rounded,
              color: nextEnable ? Colors.green : Colors.amber.shade700,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              '$actionWord Disparador',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Estás seguro de que deseas $actionWord el trigger "${t.name}" asociado a la tabla "${widget.tableName}"?',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF4F6F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Text(
                'ALTER TRIGGER ${t.name} $actionDdl',
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0078D4),
                ),
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: nextEnable ? Colors.green : Colors.redAccent,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(actionWord),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _togglingTriggers.add(t.name));
    try {
      await TableMetadataService().setTriggerStatus(
        triggerName: t.name,
        enable: nextEnable,
        ambiente: widget.ambiente,
        owner: t.owner.isNotEmpty ? t.owner : widget.owner,
        tableName: widget.tableName,
      );
      if (mounted) {
        AppToast.success(
          'Trigger ${t.name} ${nextEnable ? "habilitado" : "deshabilitado"} correctamente',
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('Error al cambiar estado del trigger: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _togglingTriggers.remove(t.name));
      }
    }
  }

  void _openTriggerSource(String triggerName) {
    openSourceWindow(
      context,
      name: triggerName,
      objectType: 'TRIGGER',
      ambiente: widget.ambiente,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_initialized) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;

    return FutureBuilder<List<TableTriggerInfo>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF0078D4),
              strokeWidth: 2,
            ),
          );
        }

        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 32,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Error al cargar triggers:\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red.shade400, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text(
                      'Reintentar',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bolt_outlined,
                  size: 36,
                  color: sc.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sin disparadores (triggers) asociados',
                  style: TextStyle(fontSize: 13, color: sc),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Cabecera
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF252526)
                    : const Color(0xFFF5F7FA),
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFDDE2EA),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 28,
                    child: Icon(
                      Icons.bolt_rounded,
                      size: 16,
                      color: Color(0xFFEAA300),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Text(
                      'NOMBRE TRIGGER',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sc,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'TIMING / TIPO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sc,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'EVENTO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sc,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      'ESTADO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sc,
                      ),
                    ),
                  ),
                  const SizedBox(width: 36), // espacio de acciones
                ],
              ),
            ),
            // Filas
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final t = items[i];

                  return InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: t.name));
                      AppToast.info('Copiado: ${t.name}');
                    },
                    child: Container(
                      color: _rowBg(isDark, i),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 28,
                            child: Icon(
                              Icons.bolt_outlined,
                              size: 15,
                              color: Color(0xFFEAA300),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Nombre
                          Expanded(
                            flex: 4,
                            child: Tooltip(
                              message:
                                  '${t.name}\nOwner: ${t.owner}\nClick para copiar',
                              child: Text(
                                t.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Consolas',
                                  fontWeight: FontWeight.w600,
                                  color: tc,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          // Timing/Tipo
                          Expanded(
                            flex: 3,
                            child: Tooltip(
                              message: t.triggerType,
                              child: Text(
                                t.triggerType,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Consolas',
                                  color: tc.withValues(alpha: 0.85),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          // Evento
                          Expanded(
                            flex: 3,
                            child: Tooltip(
                              message: t.triggeringEvent,
                              child: Text(
                                t.triggeringEvent,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Consolas',
                                  color: sc,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          // Estado (Clickable para Habilitar / Deshabilitar)
                          SizedBox(
                            width: 80,
                            child: Center(
                              child: _togglingTriggers.contains(t.name)
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF0078D4),
                                      ),
                                    )
                                  : Tooltip(
                                      message: t.isEnabled
                                          ? 'Click para DESHABILITAR trigger'
                                          : 'Click para HABILITAR trigger',
                                      child: InkWell(
                                        onTap: () => _toggleTrigger(t),
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: t.isEnabled
                                                ? Colors.green.withValues(
                                                    alpha: 0.12,
                                                  )
                                                : Colors.red.withValues(
                                                    alpha: 0.12,
                                                  ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                              color: t.isEnabled
                                                  ? Colors.green.withValues(
                                                      alpha: 0.4,
                                                    )
                                                  : Colors.red.withValues(
                                                      alpha: 0.4,
                                                    ),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                t.isEnabled
                                                    ? Icons.check_circle_rounded
                                                    : Icons.cancel_rounded,
                                                size: 11,
                                                color: t.isEnabled
                                                    ? Colors.green
                                                    : Colors.red,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                t.status,
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: t.isEnabled
                                                      ? Colors.green
                                                      : Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          // Botón Ver Código Fuente del Trigger
                          SizedBox(
                            width: 36,
                            child: Tooltip(
                              message: 'Ver fuente de trigger (${t.name})',
                              child: IconButton(
                                icon: const Icon(Icons.code_rounded, size: 15),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                color: const Color(0xFF0078D4),
                                onPressed: () => _openTriggerSource(t.name),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
