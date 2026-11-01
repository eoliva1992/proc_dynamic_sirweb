import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/table_metadata.dart';
import '../../services/table_metadata_service.dart';
import '../app_toast.dart';
import '../schema_object_details_sheet.dart';

Color _rowBg(bool isDark, int i) => i.isEven
    ? Colors.transparent
    : (isDark
          ? Colors.white.withValues(alpha: 0.02)
          : Colors.black.withValues(alpha: 0.02));

/// Vista bajo demanda (Lazy) para listar restricciones (Constraints) de una tabla o vista.
class TableConstraintsView extends StatefulWidget {
  final String tableName;
  final String ambiente;
  final String? owner;

  const TableConstraintsView({
    super.key,
    required this.tableName,
    required this.ambiente,
    this.owner,
  });

  @override
  State<TableConstraintsView> createState() => _TableConstraintsViewState();
}

class _TableConstraintsViewState extends State<TableConstraintsView>
    with AutomaticKeepAliveClientMixin {
  late Future<List<TableConstraintInfo>> _future;
  bool _initialized = false;
  final Set<String> _togglingConstraints = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = TableMetadataService().getTableConstraints(
      widget.tableName,
      ambiente: widget.ambiente,
      owner: widget.owner,
    );
    _initialized = true;
  }

  void _refresh() {
    setState(() {
      _future = TableMetadataService().getTableConstraints(
        widget.tableName,
        ambiente: widget.ambiente,
        owner: widget.owner,
        forceRefresh: true,
      );
    });
  }

  Future<void> _toggleConstraint(TableConstraintInfo c) async {
    final nextEnable = !c.isEnabled;
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
              '$actionWord Restricción',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Estás seguro de que deseas $actionWord la restricción "${c.name}" de la tabla "${widget.tableName}"?',
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
                'ALTER TABLE ${widget.tableName} $actionDdl CONSTRAINT ${c.name}',
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

    setState(() => _togglingConstraints.add(c.name));
    try {
      await TableMetadataService().setConstraintStatus(
        tableName: widget.tableName,
        constraintName: c.name,
        enable: nextEnable,
        ambiente: widget.ambiente,
        owner: widget.owner,
      );
      if (mounted) {
        AppToast.success(
          'Restricción ${c.name} ${nextEnable ? "habilitada" : "deshabilitada"} correctamente',
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('Error al cambiar estado de la restricción: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _togglingConstraints.remove(c.name));
      }
    }
  }

  Color _typeColor(ConstraintType type) => switch (type) {
    ConstraintType.primaryKey => const Color(0xFF0078D4),
    ConstraintType.foreignKey => const Color(0xFF107C10),
    ConstraintType.unique => const Color(0xFFCA5010),
    ConstraintType.check => const Color(0xFF8764B8),
    ConstraintType.other => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_initialized) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;

    return FutureBuilder<List<TableConstraintInfo>>(
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
                    'Error al cargar restricciones:\n${snap.error}',
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
                  Icons.rule_folder_outlined,
                  size: 36,
                  color: sc.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sin restricciones registradas',
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
                  SizedBox(
                    width: 32,
                    child: Text(
                      'TIPO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sc,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Text(
                      'NOMBRE RESTRICCIÓN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sc,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      'COLUMNAS / CONDICIÓN',
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
                      'REFERENCIA (FK)',
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
                ],
              ),
            ),
            // Filas
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final c = items[i];
                  final colColor = _typeColor(c.type);

                  final detailText = c.columns.isNotEmpty
                      ? c.columns.join(', ')
                      : (c.searchCondition ?? '-');

                  final refText =
                      c.rTableName != null && c.rTableName!.isNotEmpty
                      ? '${c.rTableName} (${c.rConstraintName ?? ''})'
                      : (c.rConstraintName ?? '-');

                  return InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: c.name));
                      AppToast.info('Copiado: ${c.name}');
                    },
                    child: Container(
                      color: _rowBg(isDark, i),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          // Badge Tipo
                          SizedBox(
                            width: 32,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: colColor.withValues(alpha: 0.4),
                                  width: 0.7,
                                ),
                              ),
                              child: Text(
                                c.type.shortCode,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: colColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Nombre
                          Expanded(
                            flex: 4,
                            child: Tooltip(
                              message:
                                  '${c.name} (${c.type.label})\nClick para copiar',
                              child: Text(
                                c.name,
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
                          // Columnas o Condición
                          Expanded(
                            flex: 4,
                            child: Tooltip(
                              message: detailText,
                              child: Text(
                                detailText,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Consolas',
                                  color: tc.withValues(alpha: 0.85),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          // Referencia FK (Clickable para ir a la definición de la tabla referenciada)
                          Expanded(
                            flex: 3,
                            child: (c.rTableName != null &&
                                    c.rTableName!.isNotEmpty)
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: Tooltip(
                                      message:
                                          'Ver definición de la tabla referenciada (${c.rTableName})\nConstraint: ${c.rConstraintName ?? "-"}',
                                      child: InkWell(
                                        onTap: () => showObjectDetails(
                                          context,
                                          name: c.rTableName!,
                                          type: 'TABLE',
                                          ambiente: widget.ambiente,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF107C10)
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                              color: const Color(0xFF107C10)
                                                  .withValues(alpha: 0.35),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.table_chart_outlined,
                                                size: 11,
                                                color: Color(0xFF107C10),
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  c.rTableName!,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontFamily: 'Consolas',
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF107C10),
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                              const Icon(
                                                Icons.open_in_new_rounded,
                                                size: 10,
                                                color: Color(0xFF107C10),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : Tooltip(
                                    message: refText,
                                    child: Text(
                                      refText,
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
                              child: _togglingConstraints.contains(c.name)
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF0078D4),
                                      ),
                                    )
                                  : Tooltip(
                                      message: c.isEnabled
                                          ? 'Click para DESHABILITAR restricción'
                                          : 'Click para HABILITAR restricción',
                                      child: InkWell(
                                        onTap: () => _toggleConstraint(c),
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.isEnabled
                                                ? Colors.green.withValues(
                                                    alpha: 0.12,
                                                  )
                                                : Colors.red.withValues(
                                                    alpha: 0.12,
                                                  ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                              color: c.isEnabled
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
                                                c.isEnabled
                                                    ? Icons.check_circle_rounded
                                                    : Icons.cancel_rounded,
                                                size: 11,
                                                color: c.isEnabled
                                                    ? Colors.green
                                                    : Colors.red,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                c.status,
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: c.isEnabled
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
