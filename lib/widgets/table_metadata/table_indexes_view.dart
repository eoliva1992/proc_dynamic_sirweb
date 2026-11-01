import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/table_metadata.dart';
import '../../services/table_metadata_service.dart';
import '../app_toast.dart';

Color _rowBg(bool isDark, int i) => i.isEven
    ? Colors.transparent
    : (isDark
          ? Colors.white.withValues(alpha: 0.02)
          : Colors.black.withValues(alpha: 0.02));

/// Vista bajo demanda (Lazy) para listar índices de una tabla o vista.
class TableIndexesView extends StatefulWidget {
  final String tableName;
  final String ambiente;
  final String? owner;

  const TableIndexesView({
    super.key,
    required this.tableName,
    required this.ambiente,
    this.owner,
  });

  @override
  State<TableIndexesView> createState() => _TableIndexesViewState();
}

class _TableIndexesViewState extends State<TableIndexesView>
    with AutomaticKeepAliveClientMixin {
  late Future<List<TableIndexInfo>> _future;
  bool _initialized = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = TableMetadataService().getTableIndexes(
      widget.tableName,
      ambiente: widget.ambiente,
      owner: widget.owner,
    );
    _initialized = true;
  }

  void _refresh() {
    setState(() {
      _future = TableMetadataService().getTableIndexes(
        widget.tableName,
        ambiente: widget.ambiente,
        owner: widget.owner,
        forceRefresh: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_initialized) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;

    return FutureBuilder<List<TableIndexInfo>>(
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
                    'Error al cargar índices:\n${snap.error}',
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
                  Icons.key_off_outlined,
                  size: 36,
                  color: sc.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sin índices registrados',
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
                    width: 72,
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
                      'NOMBRE ÍNDICE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sc,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      'COLUMNAS INDEXADAS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sc,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
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
                  final idx = items[i];
                  final isUnique = idx.isUnique;
                  final badgeColor = isUnique
                      ? const Color(0xFF0078D4)
                      : Colors.grey;

                  return InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: idx.name));
                      AppToast.info('Copiado: ${idx.name}');
                    },
                    child: Container(
                      color: _rowBg(isDark, i),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          // Badge Unicidad / Tipo
                          SizedBox(
                            width: 72,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: badgeColor.withValues(alpha: 0.4),
                                  width: 0.7,
                                ),
                              ),
                              child: Text(
                                isUnique ? 'UNIQUE' : 'NONUNIQUE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: badgeColor,
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
                                  '${idx.name}\nTipo: ${idx.indexType}\nClick para copiar',
                              child: Text(
                                idx.name,
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
                          // Columnas Indexadas
                          Expanded(
                            flex: 5,
                            child: Tooltip(
                              message: idx.columnsFormatted,
                              child: Text(
                                idx.columnsFormatted,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Consolas',
                                  color: tc.withValues(alpha: 0.85),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          // Estado
                          SizedBox(
                            width: 72,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: idx.isValid
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: idx.isValid
                                        ? Colors.green.withValues(alpha: 0.35)
                                        : Colors.red.withValues(alpha: 0.35),
                                    width: 0.6,
                                  ),
                                ),
                                child: Text(
                                  idx.status,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: idx.isValid
                                        ? Colors.green
                                        : Colors.red,
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
