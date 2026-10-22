/// Grilla de resultados de un SELECT ejecutado en el Ejecutor SQL/PL-SQL.
///
/// Muestra las columnas devueltas, permite ocultar columnas, seleccionar
/// filas (para generar INSERT/UPDATE/MERGE) y exportar a CSV.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import '../../models/sql_execution.dart';
import '../app_toast.dart';

class SqlResultsGrid extends StatefulWidget {
  const SqlResultsGrid({
    super.key,
    required this.result,
    required this.maxRows,
    this.onMaxRowsChanged,
    this.onGenerateDml,
    this.onLoadMore,
    this.isLoadingMore = false,
  });

  final SqlQueryResult? result;
  final int maxRows;
  final ValueChanged<int>? onMaxRowsChanged;

  /// Callback para cargar más filas (paginación infinita).
  final VoidCallback? onLoadMore;

  /// Indica si actualmente se está ejecutando la carga del siguiente lote.
  final bool isLoadingMore;

  /// Se llama con los índices de fila seleccionados cuando el usuario pide
  /// generar INSERT/UPDATE/MERGE.
  final void Function(List<int> selectedRows)? onGenerateDml;

  @override
  State<SqlResultsGrid> createState() => _SqlResultsGridState();
}

class _SqlResultsGridState extends State<SqlResultsGrid> {
  final Set<int> _hiddenColumns = {};
  final Set<int> _selectedRows = {};

  /// Coordenadas de celdas seleccionadas: (row, col) donde col es el índice visible.
  final Set<(int, int)> _selectedCells = {};

  /// Notificador granular de selección de celdas para redibujar únicamente celdas afectadas
  final ValueNotifier<int> _cellSelectionRevision = ValueNotifier<int>(0);

  /// Índice de filas que contienen al menos una celda seleccionada (acceso O(1)).
  final Set<int> _selectedCellRows = {};
  (int, int)? _anchorCell;
  (int, int)? _cursorCell;
  int? _anchorRow;
  Timer? _searchDebounce;
  final _gridFocusNode = FocusNode();
  final _horizCtrl = ScrollController();
  final _vertCtrl = ScrollController();
  late final TextEditingController _searchCtrl;
  late final FocusNode _searchFocus;
  bool _searchOpen = false;
  String _searchQuery = '';
  final Map<int, String> _columnFilters = {};
  int? _sortColIndex;
  bool _sortAsc = true;

  // Anchos personalizados asignados por el usuario mediante drag-to-resize (por índice de columna real)
  final Map<int, double> _customColumnWidths = {};

  // Cache de anchos de columna e índices filtrados para rendimiento
  List<double>? _cachedWidths;
  SqlQueryResult? _cachedWidthsResult;
  int _cachedWidthsVisibleHash = 0;

  List<int>? _cachedDisplayIndices;
  SqlQueryResult? _cachedIndicesResult;
  String _cachedIndicesQuery = '';
  int _cachedIndicesColFiltersHash = 0;
  int? _cachedIndicesSortCol;
  bool _cachedIndicesSortAsc = true;
  int _cachedIndicesVisibleHash = 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _searchFocus = FocusNode();
    _vertCtrl.addListener(_onVerticalScroll);
  }

  void _onVerticalScroll() {
    if (widget.isLoadingMore || widget.onLoadMore == null) return;
    final res = widget.result;
    if (res == null || !res.truncated) return;
    if (!_vertCtrl.hasClients) return;

    final maxScroll = _vertCtrl.position.maxScrollExtent;
    final currentScroll = _vertCtrl.position.pixels;
    // Dispara al estar cerca del final del scroll (dentro de 60px o si ya llegó al fondo)
    if (currentScroll >= maxScroll - 60) {
      widget.onLoadMore!();
    }
  }

  @override
  void didUpdateWidget(SqlResultsGrid old) {
    super.didUpdateWidget(old);
    if (!identical(old.result, widget.result)) {
      _hiddenColumns.clear();
      _selectedRows.clear();
      _selectedCells.clear();
      _selectedCellRows.clear();
      _cellSelectionRevision.value++;
      _anchorCell = null;
      _cursorCell = null;
      _anchorRow = null;
      _searchDebounce?.cancel();
      _searchCtrl.clear();
      _searchQuery = '';
      _searchOpen = false;
      _columnFilters.clear();
      _sortColIndex = null;
      _sortAsc = true;
      _customColumnWidths.clear();
      _cachedWidths = null;
      _cachedDisplayIndices = null;
    }
  }

  @override
  void dispose() {
    _vertCtrl.removeListener(_onVerticalScroll);
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _gridFocusNode.dispose();
    _cellSelectionRevision.dispose();
    _horizCtrl.dispose();
    _vertCtrl.dispose();
    super.dispose();
  }

  String _buildCsv() {
    final result = widget.result!;
    final visibleIdx = [
      for (var i = 0; i < result.columns.length; i++)
        if (!_hiddenColumns.contains(i)) i,
    ];
    final buf = StringBuffer();
    buf.writeln(visibleIdx.map((i) => _esc(result.columns[i].name)).join(','));
    for (final row in result.rows) {
      buf.writeln(
        visibleIdx.map((i) => _esc(row[i]?.toString() ?? '')).join(','),
      );
    }
    return buf.toString();
  }

  String _esc(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _copyCsv() async {
    await Clipboard.setData(ClipboardData(text: _buildCsv()));
    if (mounted) AppToast.success('Copiado al portapapeles');
  }

  Future<void> _exportCsv() async {
    final csv = _buildCsv();
    final path = await FilePicker.saveFile(
      dialogTitle: 'Exportar CSV',
      fileName: 'resultado.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: utf8.encode(csv),
      lockParentWindow: true,
    );
    if (path != null && mounted) {
      AppToast.success('CSV exportado correctamente');
    }
  }

  void _onColumnHeaderTap(int colIdx) {
    setState(() {
      if (_sortColIndex == colIdx) {
        if (_sortAsc) {
          _sortAsc = false;
        } else {
          _sortColIndex = null;
          _sortAsc = true;
        }
      } else {
        _sortColIndex = colIdx;
        _sortAsc = true;
      }
    });
  }

  void _openColumnsSelectorPopup(
    BuildContext buttonContext,
    SqlQueryResult result,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        renderBox.localToGlobal(Offset.zero, ancestor: overlay),
        renderBox.localToGlobal(
          renderBox.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final borderColor = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.6);

    showMenu<void>(
      context: context,
      position: position,
      color: isDark ? const Color(0xFF161B22) : const Color(0xFFFFFFFF),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: 0.8),
      ),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 300),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (menuContext, setMenuState) {
              return _ColumnsSelectorPopover(
                columns: result.columns,
                hiddenColumns: _hiddenColumns,
                isDark: isDark,
                onToggle: (i) {
                  setState(() {
                    if (_hiddenColumns.contains(i)) {
                      _hiddenColumns.remove(i);
                    } else {
                      if (_hiddenColumns.length < result.columns.length - 1) {
                        _hiddenColumns.add(i);
                      }
                    }
                  });
                  setMenuState(() {});
                },
                onShowAll: () {
                  setState(() => _hiddenColumns.clear());
                  setMenuState(() {});
                },
                onHideOthers: (keepIdx) {
                  setState(() {
                    _hiddenColumns.clear();
                    for (var i = 0; i < result.columns.length; i++) {
                      if (i != keepIdx) _hiddenColumns.add(i);
                    }
                  });
                  setMenuState(() {});
                },
                onClose: () => Navigator.of(menuContext).pop(),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openColumnFilterPopup(
    BuildContext buttonContext,
    int rawColIdx,
    String colName,
  ) {
    final currentFilter = _columnFilters[rawColIdx] ?? '';
    final ctrl = TextEditingController(text: currentFilter);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        renderBox.localToGlobal(Offset.zero, ancestor: overlay),
        renderBox.localToGlobal(
          renderBox.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<void>(
      context: context,
      position: position,
      color: isDark ? cs.surfaceContainerHigh : cs.surface,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.filter_alt_rounded, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Filtrar $colName',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: TextStyle(fontSize: 12, color: cs.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Buscar valor...',
                    hintStyle: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    prefixIcon: const Icon(Icons.search, size: 14),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    suffixIcon: ctrl.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              ctrl.clear();
                              _applyColumnFilter(rawColIdx, '');
                              Navigator.of(buttonContext).pop();
                            },
                            child: Icon(
                              Icons.clear,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onSubmitted: (val) {
                    _applyColumnFilter(rawColIdx, val);
                    Navigator.of(buttonContext).pop();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (currentFilter.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 26),
                      ),
                      onPressed: () {
                        _applyColumnFilter(rawColIdx, '');
                        Navigator.of(buttonContext).pop();
                      },
                      child: const Text(
                        'Limpiar',
                        style: TextStyle(fontSize: 11, color: Colors.redAccent),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 26),
                    ),
                    onPressed: () {
                      _applyColumnFilter(rawColIdx, ctrl.text);
                      Navigator.of(buttonContext).pop();
                    },
                    child: const Text(
                      'Aplicar',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _applyColumnFilter(int rawColIdx, String val) {
    setState(() {
      final text = val.trim();
      if (text.isEmpty) {
        _columnFilters.remove(rawColIdx);
      } else {
        _columnFilters[rawColIdx] = text;
      }
      _cachedDisplayIndices = null;
    });
  }

  void _copyRow(int r, List<int> visibleIdx) {
    final result = widget.result;
    if (result == null) return;
    final line = visibleIdx
        .map((i) => _esc(result.rows[r][i]?.toString() ?? ''))
        .join('\t');
    Clipboard.setData(ClipboardData(text: line));
    AppToast.success('Fila copiada al portapapeles');
  }

  void _copyCell(String text) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success('Copiado: "$text"');
  }

  /// Copia las celdas seleccionadas en formato TSV (separado por tabulación y salto de línea).
  /// Esto permite pegar de forma nativa en Excel, Google Sheets, LibreOffice Calc o editores.
  void _copySelectedCells(List<int> visibleIdx) {
    final result = widget.result;
    if (result == null || _selectedCells.isEmpty) return;

    if (_selectedCells.length == 1) {
      final (r, c) = _selectedCells.first;
      if (r < result.rows.length && c < visibleIdx.length) {
        final rawVal = result.rows[r][visibleIdx[c]];
        _copyCell(rawVal?.toString() ?? 'NULL');
      }
      return;
    }

    // Agrupar filas y ordenar
    final rowMap = <int, List<int>>{};
    for (final (r, c) in _selectedCells) {
      rowMap.putIfAbsent(r, () => []).add(c);
    }
    final sortedRows = rowMap.keys.toList()..sort();

    final lines = <String>[];
    for (final r in sortedRows) {
      final cols = rowMap[r]!..sort();
      final lineVals = cols
          .map((c) {
            if (r < result.rows.length && c < visibleIdx.length) {
              final rawVal = result.rows[r][visibleIdx[c]];
              return rawVal?.toString() ?? 'NULL';
            }
            return '';
          })
          .join('\t');
      lines.add(lineVals);
    }

    final text = lines.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success('${_selectedCells.length} celda(s) copiada(s)');
  }

  /// Copia el encabezado de la(s) columna(s) seleccionada(s) junto con los
  /// valores de las filas seleccionadas. Sin selección, copia solo los
  /// nombres de las columnas visibles.
  void _copyColumnNames(List<int> visibleIdx) {
    final result = widget.result;
    if (result == null || visibleIdx.isEmpty) return;

    if (_selectedCells.isNotEmpty) {
      final cols = _selectedCells.map((c) => c.$2).toSet().toList()..sort();
      final rows = _selectedCells.map((c) => c.$1).toSet().toList()..sort();
      final header = cols
          .map((c) => result.columns[visibleIdx[c]].name)
          .join('\t');
      final lines = [header];
      for (final r in rows) {
        final line = cols
            .map((c) {
              if (!_selectedCells.contains((r, c))) return '';
              final rawVal = result.rows[r][visibleIdx[c]];
              return rawVal?.toString() ?? 'NULL';
            })
            .join('\t');
        lines.add(line);
      }
      Clipboard.setData(ClipboardData(text: lines.join('\n')));
      AppToast.success('Encabezado y ${rows.length} fila(s) copiados');
      return;
    }

    if (_selectedRows.isNotEmpty) {
      final rowsToCopy = _selectedRows.toList()..sort();
      final header = visibleIdx.map((i) => result.columns[i].name).join('\t');
      final lines = [header];
      for (final r in rowsToCopy) {
        final line = visibleIdx
            .map((i) => _esc(result.rows[r][i]?.toString() ?? ''))
            .join('\t');
        lines.add(line);
      }
      Clipboard.setData(ClipboardData(text: lines.join('\n')));
      AppToast.success('Encabezado y ${rowsToCopy.length} fila(s) copiados');
      return;
    }

    final line = visibleIdx.map((i) => result.columns[i].name).join('\t');
    Clipboard.setData(ClipboardData(text: line));
    AppToast.success('Nombre(s) de columna copiado(s)');
  }

  void _copySelection(List<int> visibleIdx) {
    if (_selectedCells.isNotEmpty) {
      _copySelectedCells(visibleIdx);
      return;
    }
    if (_selectedRows.isNotEmpty) {
      final rowsToCopy = _selectedRows.toList()..sort();
      final lines = <String>[];
      for (final r in rowsToCopy) {
        final line = visibleIdx
            .map((i) => _esc(widget.result!.rows[r][i]?.toString() ?? ''))
            .join('\t');
        lines.add(line);
      }
      Clipboard.setData(ClipboardData(text: lines.join('\n')));
      AppToast.success('${rowsToCopy.length} fila(s) copiada(s)');
      return;
    }
    _copyCsv();
  }

  void _showCellContextMenu(
    BuildContext context,
    Offset globalPos,
    String text,
    int rowIndex,
    List<int> visibleIdx,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final hasMultiCells = _selectedCells.length > 1;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx + 1,
        globalPos.dy + 1,
      ),
      color: isDark ? cs.surfaceContainerHigh : cs.surface,
      elevation: 6,
      items: [
        if (hasMultiCells)
          PopupMenuItem(
            value: 'copy_selection',
            height: 32,
            child: Row(
              children: [
                const Icon(Icons.select_all_rounded, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Copiar ${_selectedCells.length} celdas seleccionadas (TSV)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'copy_with_header',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.view_column_outlined, size: 14),
              SizedBox(width: 8),
              Text(
                'Copiar con encabezado (Ctrl+Shift+C)',
                style: TextStyle(fontSize: 11.5),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_cell',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.content_copy_rounded, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Copiar celda ($text)',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_row',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.table_rows_rounded, size: 14),
              SizedBox(width: 8),
              Text(
                'Copiar fila completa (TSV/Excel)',
                style: TextStyle(fontSize: 11.5),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'filter_by',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.filter_alt_outlined, size: 14),
              SizedBox(width: 8),
              Text('Filtrar por este valor', style: TextStyle(fontSize: 11.5)),
            ],
          ),
        ),
      ],
    ).then((choice) {
      if (choice == 'copy_selection') {
        _copySelectedCells(visibleIdx);
      } else if (choice == 'copy_with_header') {
        _copyColumnNames(visibleIdx);
      } else if (choice == 'copy_cell') {
        _copyCell(text);
      } else if (choice == 'copy_row') {
        _copyRow(rowIndex, visibleIdx);
      } else if (choice == 'filter_by') {
        setState(() {
          _searchOpen = true;
          _searchCtrl.text = text == 'NULL' ? '' : text;
          _searchQuery = text == 'NULL' ? '' : text;
        });
      }
    });
  }

  void _handleCellTap(int r, int c, List<int> visibleIdx) {
    if (!_gridFocusNode.hasFocus) {
      _gridFocusNode.requestFocus();
    }
    final kb = HardwareKeyboard.instance;
    final isCtrl = kb.isControlPressed || kb.isMetaPressed;
    final isShift = kb.isShiftPressed;

    // 1. Ctrl + Shift + Click: suma un nuevo rango rectangular a la selección existente
    if (isCtrl && isShift) {
      final anchor = _anchorCell ?? (r, c);
      final minR = math.min(anchor.$1, r);
      final maxR = math.max(anchor.$1, r);
      final minC = math.min(anchor.$2, c);
      final maxC = math.max(anchor.$2, c);

      for (var row = minR; row <= maxR; row++) {
        _selectedCellRows.add(row);
        for (var col = minC; col <= maxC; col++) {
          _selectedCells.add((row, col));
        }
      }
      _cursorCell = (r, c);
    }
    // 2. Shift + Click: selecciona exclusivamente el rango rectangular entre ancla y actual
    else if (isShift) {
      final anchor = _anchorCell ?? (r, c);
      final minR = math.min(anchor.$1, r);
      final maxR = math.max(anchor.$1, r);
      final minC = math.min(anchor.$2, c);
      final maxC = math.max(anchor.$2, c);

      _selectedCells.clear();
      _selectedCellRows.clear();
      for (var row = minR; row <= maxR; row++) {
        _selectedCellRows.add(row);
        for (var col = minC; col <= maxC; col++) {
          _selectedCells.add((row, col));
        }
      }
      _cursorCell = (r, c);
    }
    // 3. Ctrl + Click: toggle celda individual
    else if (isCtrl) {
      final coord = (r, c);
      if (_selectedCells.contains(coord)) {
        _selectedCells.remove(coord);
        if (!_selectedCells.any((cell) => cell.$1 == r)) {
          _selectedCellRows.remove(r);
        }
        if (_cursorCell == coord) _cursorCell = null;
      } else {
        _selectedCells.add(coord);
        _selectedCellRows.add(r);
        _cursorCell = coord;
      }
      _anchorCell = coord;
    }
    // 4. Click normal: selecciona únicamente esta celda
    else {
      final coord = (r, c);
      if (_selectedCells.length == 1 && _selectedCells.contains(coord)) {
        _selectedCells.clear();
        _selectedCellRows.clear();
        _anchorCell = null;
        _cursorCell = null;
      } else {
        _selectedCells.clear();
        _selectedCellRows.clear();
        _selectedCells.add(coord);
        _selectedCellRows.add(r);
        _anchorCell = coord;
        _cursorCell = coord;
      }
    }

    _cellSelectionRevision.value++;
  }

  void _ensureCellVisible(
    int displayRowPos,
    int visibleColPos,
    List<double> widths,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Vertical auto-scroll
      if (_vertCtrl.hasClients && _vertCtrl.position.hasViewportDimension) {
        const rowHeight = 35.0;
        final viewportHeight = _vertCtrl.position.viewportDimension;
        final cellTop = displayRowPos * rowHeight;
        final cellBottom = cellTop + rowHeight;
        final currentOffset = _vertCtrl.offset;

        if (cellTop < currentOffset) {
          _vertCtrl.jumpTo(math.max(0.0, cellTop));
        } else if (cellBottom > currentOffset + viewportHeight) {
          _vertCtrl.jumpTo(cellBottom - viewportHeight);
        }
      }

      // Horizontal auto-scroll
      if (_horizCtrl.hasClients && _horizCtrl.position.hasViewportDimension) {
        final viewportWidth = _horizCtrl.position.viewportDimension;
        var cellLeft = 0.0;
        for (var i = 0; i < visibleColPos && i < widths.length; i++) {
          cellLeft += widths[i];
        }
        final cellRight =
            cellLeft +
            (visibleColPos < widths.length ? widths[visibleColPos] : 80.0);
        final currentOffset = _horizCtrl.offset;

        if (cellLeft < currentOffset) {
          _horizCtrl.jumpTo(math.max(0.0, cellLeft));
        } else if (cellRight > currentOffset + viewportWidth) {
          _horizCtrl.jumpTo(cellRight - viewportWidth);
        }
      }
    });
  }

  KeyEventResult _handleGridKeyEvent(
    KeyEvent event,
    List<int> displayIndices,
    List<int> visibleIdx,
    List<double> widths,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    int deltaRow = 0;
    int deltaCol = 0;

    if (key == LogicalKeyboardKey.arrowUp) {
      deltaRow = -1;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      deltaRow = 1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      deltaCol = -1;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      deltaCol = 1;
    } else {
      return KeyEventResult.ignored;
    }

    // Si no hay ninguna celda seleccionada, se requiere clic previo en una celda
    if (_selectedCells.isEmpty) {
      return KeyEventResult.ignored;
    }

    final currentCoord = _cursorCell ?? _anchorCell ?? _selectedCells.first;
    var currentDisplayRow = displayIndices.indexOf(currentCoord.$1);
    if (currentDisplayRow == -1) {
      currentDisplayRow = 0;
    }
    final currentVisibleCol = currentCoord.$2;

    final targetDisplayRow = (currentDisplayRow + deltaRow).clamp(
      0,
      displayIndices.length - 1,
    );
    final targetVisibleCol = (currentVisibleCol + deltaCol).clamp(
      0,
      visibleIdx.length - 1,
    );

    if (targetDisplayRow == currentDisplayRow &&
        targetVisibleCol == currentVisibleCol) {
      return KeyEventResult.handled;
    }

    final targetActualRow = displayIndices[targetDisplayRow];
    final targetCoord = (targetActualRow, targetVisibleCol);
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isShift) {
      final anchor = _anchorCell ?? currentCoord;
      var anchorDisplayRow = displayIndices.indexOf(anchor.$1);
      if (anchorDisplayRow == -1) anchorDisplayRow = currentDisplayRow;
      final anchorCol = anchor.$2;

      final minDisplayRow = math.min(anchorDisplayRow, targetDisplayRow);
      final maxDisplayRow = math.max(anchorDisplayRow, targetDisplayRow);
      final minCol = math.min(anchorCol, targetVisibleCol);
      final maxCol = math.max(anchorCol, targetVisibleCol);

      _selectedCells.clear();
      _selectedCellRows.clear();
      for (var dRow = minDisplayRow; dRow <= maxDisplayRow; dRow++) {
        final actualRow = displayIndices[dRow];
        _selectedCellRows.add(actualRow);
        for (var col = minCol; col <= maxCol; col++) {
          _selectedCells.add((actualRow, col));
        }
      }
      _cursorCell = targetCoord;
    } else {
      _selectedCells.clear();
      _selectedCellRows.clear();
      _selectedCells.add(targetCoord);
      _selectedCellRows.add(targetActualRow);
      _anchorCell = targetCoord;
      _cursorCell = targetCoord;
    }

    _cellSelectionRevision.value++;
    _ensureCellVisible(targetDisplayRow, targetVisibleCol, widths);
    return KeyEventResult.handled;
  }

  void _handleRowCheckboxTap(int r, bool? value, List<int> displayIndices) {
    final kb = HardwareKeyboard.instance;
    final isShift = kb.isShiftPressed;

    setState(() {
      if (isShift && _anchorRow != null) {
        final currentPos = displayIndices.indexOf(r);
        final anchorPos = displayIndices.indexOf(_anchorRow!);
        if (currentPos != -1 && anchorPos != -1) {
          final start = math.min(currentPos, anchorPos);
          final end = math.max(currentPos, anchorPos);
          final rangeRows = displayIndices.sublist(start, end + 1);

          if (value == true) {
            _selectedRows.addAll(rangeRows);
          } else {
            _selectedRows.removeAll(rangeRows);
          }
          return;
        }
      }

      if (value == true) {
        _selectedRows.add(r);
        _anchorRow = r;
      } else {
        _selectedRows.remove(r);
        if (_anchorRow == r) _anchorRow = null;
      }
    });
  }

  List<int> _computeDisplayIndices(
    SqlQueryResult result,
    List<int> visibleIdx,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    final visibleHash = Object.hashAll(visibleIdx);
    final activeFiltersHash = Object.hashAll(
      _columnFilters.entries.map((e) => Object.hash(e.key, e.value)),
    );

    if (_cachedDisplayIndices != null &&
        identical(_cachedIndicesResult, result) &&
        _cachedIndicesQuery == query &&
        _cachedIndicesSortCol == _sortColIndex &&
        _cachedIndicesSortAsc == _sortAsc &&
        _cachedIndicesVisibleHash == visibleHash &&
        _cachedIndicesColFiltersHash == activeFiltersHash) {
      return _cachedDisplayIndices!;
    }

    var indices = List<int>.generate(result.rows.length, (i) => i);
    if (query.isNotEmpty) {
      indices = indices.where((r) {
        for (final c in visibleIdx) {
          final val = result.rows[r][c]?.toString().toLowerCase() ?? '';
          if (val.contains(query)) return true;
        }
        return false;
      }).toList();
    }

    // Filtros por columna específica
    if (_columnFilters.isNotEmpty) {
      indices = indices.where((r) {
        for (final entry in _columnFilters.entries) {
          final c = entry.key;
          final filterVal = entry.value.trim().toLowerCase();
          if (filterVal.isEmpty) continue;
          if (c >= result.columns.length) continue;
          final cellVal = result.rows[r][c]?.toString().toLowerCase() ?? '';
          if (!cellVal.contains(filterVal)) return false;
        }
        return true;
      }).toList();
    }

    if (_sortColIndex != null && _sortColIndex! < visibleIdx.length) {
      final c = visibleIdx[_sortColIndex!];
      indices.sort((a, b) {
        final valA = result.rows[a][c];
        final valB = result.rows[b][c];
        if (valA == null && valB == null) return 0;
        if (valA == null) return _sortAsc ? 1 : -1;
        if (valB == null) return _sortAsc ? -1 : 1;

        final numA = num.tryParse(valA.toString());
        final numB = num.tryParse(valB.toString());
        int cmp;
        if (numA != null && numB != null) {
          cmp = numA.compareTo(numB);
        } else {
          cmp = valA.toString().toLowerCase().compareTo(
            valB.toString().toLowerCase(),
          );
        }
        return _sortAsc ? cmp : -cmp;
      });
    }

    _cachedDisplayIndices = indices;
    _cachedIndicesResult = result;
    _cachedIndicesQuery = query;
    _cachedIndicesSortCol = _sortColIndex;
    _cachedIndicesSortAsc = _sortAsc;
    _cachedIndicesVisibleHash = visibleHash;
    _cachedIndicesColFiltersHash = activeFiltersHash;

    return indices;
  }

  Widget _buildEmptyHint(ColorScheme cs, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurfaceVariant.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    if (result == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.table_chart_outlined,
              size: 40,
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              'Ejecutá un SELECT para ver resultados acá',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 14),
            _buildEmptyHint(
              cs,
              Icons.keyboard_return_rounded,
              'Ctrl + Enter — ejecutar sentencia actual / selección',
            ),
            const SizedBox(height: 4),
            _buildEmptyHint(
              cs,
              Icons.playlist_play_rounded,
              'F5 — ejecutar todo el script',
            ),
          ],
        ),
      );
    }
    if (result.columns.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 40,
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              'La consulta no devolvió columnas',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    final visibleIdx = [
      for (var i = 0; i < result.columns.length; i++)
        if (!_hiddenColumns.contains(i)) i,
    ];
    final displayIndices = _computeDisplayIndices(result, visibleIdx);

    return Column(
      children: [
        _buildToolbar(isDark, result, visibleIdx, displayIndices),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant),
        Expanded(
          child: _buildTable(isDark, result, visibleIdx, displayIndices),
        ),
        if (widget.isLoadingMore)
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF30363D) : cs.outlineVariant.withValues(alpha: 0.8),
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Cargando siguientes filas...',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTable(
    bool isDark,
    SqlQueryResult result,
    List<int> visibleIdx,
    List<int> displayIndices,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final borderColor = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.8);
    const headerStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );
    const cellStyle = TextStyle(fontSize: 12, fontFamily: 'monospace');
    final widths = _computeColumnWidths(
      result,
      visibleIdx,
      headerStyle,
      cellStyle,
    );

    if (displayIndices.isEmpty && result.rows.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 32,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              'No se encontraron filas con el filtro actual',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () {
                setState(() {
                  _searchCtrl.clear();
                  _searchQuery = '';
                });
              },
              child: const Text(
                'Limpiar filtro',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    final allSelected =
        displayIndices.isNotEmpty &&
        displayIndices.every((idx) => _selectedRows.contains(idx));
    final noneSelected = displayIndices.every(
      (idx) => !_selectedRows.contains(idx),
    );
    final bool? selectAllValue = allSelected
        ? true
        : (noneSelected ? false : null);

    final cellRightBorder = BorderSide(
      color: borderColor.withValues(alpha: isDark ? 0.45 : 0.4),
      width: 0.8,
    );
    final cellBottomBorder = BorderSide(
      color: borderColor.withValues(alpha: isDark ? 0.45 : 0.4),
      width: 0.8,
    );
    final selectedBorder = BorderSide(color: cs.primary, width: 1.4);
    final anchorBorder = BorderSide(color: cs.primary, width: 2.0);
    const checkboxColWidth = 44.0;
    const rowHeight = 35.0;
    const headerHeight = 35.0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
            _copySelection(visibleIdx),
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          shift: true,
        ): () =>
            _copyColumnNames(visibleIdx),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedCells.isNotEmpty || _selectedRows.isNotEmpty) {
            setState(() {
              _selectedCells.clear();
              _selectedCellRows.clear();
              _selectedRows.clear();
              _anchorCell = null;
              _cursorCell = null;
              _anchorRow = null;
            });
            _cellSelectionRevision.value++;
          }
        },
      },
      child: Focus(
        key: const Key('sqlResultsGridFocus'),
        focusNode: _gridFocusNode,
        autofocus: false,
        onKeyEvent: (node, event) =>
            _handleGridKeyEvent(event, displayIndices, visibleIdx, widths),
        child: RepaintBoundary(
          child: Scrollbar(
            controller: _vertCtrl,
            thumbVisibility: true,
            trackVisibility: true,
            child: Scrollbar(
              controller: _horizCtrl,
              thumbVisibility: true,
              trackVisibility: true,
              notificationPredicate: (notif) =>
                  notif.depth == 1 || notif.metrics.axis == Axis.horizontal,
              child: TableView.builder(
                verticalDetails: ScrollableDetails.vertical(
                  controller: _vertCtrl,
                ),
                horizontalDetails: ScrollableDetails.horizontal(
                  controller: _horizCtrl,
                ),
                pinnedRowCount: 1,
                pinnedColumnCount: 1,
                rowCount: displayIndices.length + 1,
                columnCount: visibleIdx.length + 1,
                rowBuilder: (int row) {
                  return TableSpan(
                    extent: FixedTableSpanExtent(
                      row == 0 ? headerHeight : rowHeight,
                    ),
                    backgroundDecoration: row == 0
                        ? TableSpanDecoration(color: cs.surfaceContainerHighest)
                        : null,
                  );
                },
                columnBuilder: (int col) {
                  return TableSpan(
                    extent: FixedTableSpanExtent(
                      col == 0 ? checkboxColWidth : widths[col - 1],
                    ),
                  );
                },
                cellBuilder: (BuildContext context, TableVicinity vicinity) {
                  final row = vicinity.row;
                  final col = vicinity.column;

                  // 1. Top-Left corner: Checkbox para seleccionar todo
                  if (row == 0 && col == 0) {
                    return TableViewCell(
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          border: Border(
                            right: cellRightBorder,
                            bottom: cellBottomBorder,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Checkbox(
                          value: selectAllValue,
                          tristate: true,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedRows.addAll(displayIndices);
                              } else {
                                _selectedRows.removeAll(displayIndices);
                              }
                            });
                          },
                        ),
                      ),
                    );
                  }

                  // 2. Fila de Encabezados de Columna
                  if (row == 0) {
                    final c = col - 1;
                    final rawColIdx = visibleIdx[c];
                    final colData = result.columns[rawColIdx];
                    final isSorted = _sortColIndex == c;
                    final isFiltered =
                        _columnFilters.containsKey(rawColIdx) &&
                        _columnFilters[rawColIdx]!.isNotEmpty;

                    return TableViewCell(
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          border: Border(
                            right: cellRightBorder,
                            bottom: cellBottomBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _onColumnHeaderTap(c),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 10,
                                    top: 4,
                                    bottom: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Tooltip(
                                          message:
                                              '${colData.name} (${colData.dataType})\nClic para ordenar',
                                          waitDuration: const Duration(
                                            milliseconds: 600,
                                          ),
                                          child: Text(
                                            colData.name,
                                            style: headerStyle.copyWith(
                                              color: isSorted
                                                  ? cs.primary
                                                  : cs.onSurfaceVariant,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                      if (isSorted)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4,
                                          ),
                                          child: Icon(
                                            _sortAsc
                                                ? Icons.arrow_upward_rounded
                                                : Icons.arrow_downward_rounded,
                                            size: 14,
                                            color: cs.primary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Botón de filtro por columna
                            Builder(
                              builder: (btnCtx) {
                                return Tooltip(
                                  message: isFiltered
                                      ? 'Filtro: "${_columnFilters[rawColIdx]}" (clic para editar)'
                                      : 'Filtrar columna ${colData.name}',
                                  waitDuration: const Duration(
                                    milliseconds: 400,
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () => _openColumnFilterPopup(
                                      btnCtx,
                                      rawColIdx,
                                      colData.name,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 6,
                                      ),
                                      child: Icon(
                                        isFiltered
                                            ? Icons.filter_alt_rounded
                                            : Icons.filter_alt_outlined,
                                        size: 14,
                                        color: isFiltered
                                            ? cs.primary
                                            : cs.onSurfaceVariant.withValues(
                                                alpha: 0.5,
                                              ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            // Handle de resize interactivo de la columna
                            MouseRegion(
                              cursor: SystemMouseCursors.resizeColumn,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onDoubleTap: () {
                                  // Doble clic: restablece al ancho estimado por defecto
                                  setState(() {
                                    _customColumnWidths.remove(rawColIdx);
                                    _cachedWidths = null;
                                  });
                                },
                                onHorizontalDragUpdate: (details) {
                                  final currentW = widths[c];
                                  final newW = (currentW + details.delta.dx).clamp(48.0, 900.0);
                                  setState(() {
                                    _customColumnWidths[rawColIdx] = newW;
                                    _cachedWidths = null;
                                  });
                                },
                                child: Container(
                                  width: 8,
                                  height: double.infinity,
                                  color: Colors.transparent,
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    width: 1.5,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: cs.outlineVariant.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // 3. Columna fija izquierda: Checkbox de Fila
                  final r = displayIndices[row - 1];
                  final isRowSelected = _selectedRows.contains(r);
                  final rowHasSelectedCell = _selectedCellRows.contains(r);
                  final rowBgColor = isRowSelected
                      ? cs.primaryContainer.withValues(
                          alpha: isDark ? 0.35 : 0.45,
                        )
                      : (rowHasSelectedCell
                            ? cs.primary.withValues(alpha: isDark ? 0.08 : 0.06)
                            : (r.isOdd
                                  ? (isDark
                                        ? const Color(0xFF13171D)
                                        : const Color(0xFFF6F8FA))
                                  : (isDark
                                        ? const Color(0xFF0F1318)
                                        : Colors.white)));

                  if (col == 0) {
                    return TableViewCell(
                      child: Container(
                        decoration: BoxDecoration(
                          color: rowBgColor,
                          border: Border(
                            right: cellRightBorder,
                            bottom: cellBottomBorder,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Checkbox(
                          value: isRowSelected,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) =>
                              _handleRowCheckboxTap(r, v, displayIndices),
                        ),
                      ),
                    );
                  }

                  // 4. Celda de Datos (row > 0, col > 0)
                  final c = col - 1;
                  final coord = (r, c);
                  final rawVal = result.rows[r][visibleIdx[c]];
                  final isNull = rawVal == null;
                  final text = rawVal?.toString() ?? 'NULL';

                  return TableViewCell(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _cellSelectionRevision,
                      builder: (context, _, _) {
                        final isCellSelected = _selectedCells.contains(coord);
                        final isAnchor = _anchorCell == coord;
                        final activeBorder = isAnchor
                            ? anchorBorder
                            : selectedBorder;

                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: isCellSelected
                                ? cs.primary.withValues(
                                    alpha: isDark ? 0.28 : 0.2,
                                  )
                                : rowBgColor,
                            border: Border(
                              right: isCellSelected
                                  ? activeBorder
                                  : cellRightBorder,
                              bottom: isCellSelected
                                  ? activeBorder
                                  : cellBottomBorder,
                              top: isCellSelected
                                  ? activeBorder
                                  : BorderSide.none,
                              left: isCellSelected
                                  ? activeBorder
                                  : BorderSide.none,
                            ),
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _handleCellTap(r, c, visibleIdx),
                            onDoubleTap: () => _copyCell(text),
                            onSecondaryTapUp: (details) {
                              if (!_gridFocusNode.hasFocus) {
                                _gridFocusNode.requestFocus();
                              }
                              if (!_selectedCells.contains(coord)) {
                                _selectedCells.clear();
                                _selectedCellRows.clear();
                                _selectedCells.add(coord);
                                _selectedCellRows.add(r);
                                _anchorCell = coord;
                                _cursorCell = coord;
                                _cellSelectionRevision.value++;
                              }
                              _showCellContextMenu(
                                context,
                                details.globalPosition,
                                text,
                                r,
                                visibleIdx,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: isNull
                                    ? cellStyle.copyWith(
                                        color: cs.onSurfaceVariant.withValues(
                                          alpha: 0.5,
                                        ),
                                        fontStyle: FontStyle.italic,
                                      )
                                    : cellStyle.copyWith(
                                        color: isCellSelected
                                            ? cs.primary
                                            : cs.onSurface,
                                        fontWeight: isCellSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(
    bool isDark,
    SqlQueryResult result,
    List<int> visibleIdx,
    List<int> displayIndices,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isFiltered =
        _searchQuery.trim().isNotEmpty || _columnFilters.isNotEmpty;
    final toolbarBg = isDark
        ? const Color(0xFF161B22)
        : const Color(0xFFF6F8FA);
    final borderColor = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.8);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: toolbarBg,
        border: Border(bottom: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Row(
                children: [
                  // Badge cápsula de Filas
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: isFiltered
                          ? const Color(
                              0xFFE2A03F,
                            ).withValues(alpha: isDark ? 0.2 : 0.14)
                          : cs.primary.withValues(alpha: isDark ? 0.18 : 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isFiltered
                            ? const Color(0xFFE2A03F).withValues(alpha: 0.5)
                            : cs.primary.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFiltered
                              ? Icons.filter_list_rounded
                              : Icons.table_rows_rounded,
                          size: 13,
                          color: isFiltered
                              ? const Color(0xFFE2A03F)
                              : cs.primary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isFiltered
                              ? '${displayIndices.length} de ${result.returnedRows} filas'
                              : '${result.returnedRows} fila${result.returnedRows == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isFiltered
                                ? (isDark
                                      ? const Color(0xFFFFB74D)
                                      : const Color(0xFFB45309))
                                : (isDark
                                      ? cs.primary
                                      : cs.primary.withValues(alpha: 0.9)),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Badge cápsula de Duración
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor.withValues(alpha: 0.6),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 13,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${result.durationMs} ms',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (result.truncated) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: widget.isLoadingMore
                          ? 'Cargando siguientes filas...'
                          : 'Consulta truncada. Hacé clic para cargar más filas (o hacé scroll hasta el fondo)',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: widget.isLoadingMore || widget.onLoadMore == null
                            ? null
                            : () => widget.onLoadMore!(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(
                              alpha: isDark ? 0.22 : 0.14,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.6),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.isLoadingMore)
                                SizedBox(
                                  width: 11,
                                  height: 11,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isDark
                                          ? const Color(0xFFFFB74D)
                                          : Colors.orange[800]!,
                                    ),
                                  ),
                                )
                              else
                                Icon(
                                  Icons.arrow_circle_down_rounded,
                                  size: 13,
                                  color: isDark
                                      ? const Color(0xFFFFB74D)
                                      : Colors.orange[800],
                                ),
                              const SizedBox(width: 4),
                              Text(
                                widget.isLoadingMore
                                    ? 'Cargando...'
                                    : 'Truncado · +Cargar más',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? const Color(0xFFFFB74D)
                                      : Colors.orange[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  if (_searchOpen) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 26,
                      width: 170,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 14, color: cs.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Filtrar filas...',
                                hintStyle: TextStyle(fontSize: 10.5),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (q) {
                                _searchDebounce?.cancel();
                                _searchDebounce = Timer(
                                  const Duration(milliseconds: 200),
                                  () {
                                    if (mounted) {
                                      setState(() => _searchQuery = q);
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                          if (_searchQuery.isNotEmpty ||
                              _searchCtrl.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchDebounce?.cancel();
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Tooltip(
                      message: 'Buscar / filtrar en resultados',
                      child: IconButton(
                        icon: const Icon(Icons.search_rounded, size: 17),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        onPressed: () {
                          setState(() => _searchOpen = true);
                          _searchFocus.requestFocus();
                        },
                      ),
                    ),
                  ],
                  if (_searchOpen) ...[
                    Tooltip(
                      message: 'Cerrar filtro',
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 15),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        onPressed: () {
                          setState(() {
                            _searchOpen = false;
                            _searchCtrl.clear();
                            _searchQuery = '';
                          });
                        },
                      ),
                    ),
                  ],
                  if (_columnFilters.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.filter_alt_rounded,
                            size: 11,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${_columnFilters.length} filtro${_columnFilters.length == 1 ? '' : 's'} de col.',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _columnFilters.clear();
                                _cachedDisplayIndices = null;
                              });
                            },
                            child: Tooltip(
                              message: 'Limpiar todos los filtros de columnas',
                              child: Icon(
                                Icons.close_rounded,
                                size: 11,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (_sortColIndex != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _sortAsc
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 11,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Ordenado',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 3),
                          GestureDetector(
                            onTap: () => setState(() => _sortColIndex = null),
                            child: Icon(
                              Icons.close_rounded,
                              size: 11,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_selectedRows.isNotEmpty) ...[
                    Text(
                      '${_selectedRows.length} seleccionada${_selectedRows.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Deseleccionar todas',
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 14),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        onPressed: () => setState(() => _selectedRows.clear()),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 18,
                      child: VerticalDivider(
                        color: cs.outlineVariant,
                        width: 12,
                      ),
                    ),
                  ],
                  Builder(
                    builder: (btnCtx) {
                      final hasHidden = _hiddenColumns.isNotEmpty;
                      return IconButton(
                        key: const Key('sqlResultsGridColumnsBtn'),
                        tooltip: hasHidden
                            ? 'Columnas (${visibleIdx.length}/${result.columns.length} visibles)'
                            : 'Configurar columnas visibles',
                        style: IconButton.styleFrom(
                          backgroundColor: hasHidden
                              ? cs.primary.withValues(alpha: 0.08)
                              : Colors.transparent,
                          side: BorderSide(
                            color: hasHidden
                                ? cs.primary.withValues(alpha: 0.4)
                                : Colors.transparent,
                            width: 0.8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            _openColumnsSelectorPopup(btnCtx, result),
                        icon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.view_column_outlined,
                              size: 16,
                              color: hasHidden
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                            if (hasHidden) ...[
                              const SizedBox(width: 4),
                              Text(
                                '${visibleIdx.length}/${result.columns.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                  fontFamily: 'Consolas',
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: _selectedCells.isNotEmpty
                        ? 'Copiar celdas seleccionadas (Ctrl+C)'
                        : (_selectedRows.isNotEmpty
                              ? 'Copiar fila(s) seleccionada(s) (Ctrl+C)'
                              : 'Copiar todo como CSV (Ctrl+C)'),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () => _copySelection(visibleIdx),
                  ),
                  IconButton(
                    tooltip: 'Exportar CSV',
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    onPressed: _exportCsv,
                  ),
                  IconButton(
                    tooltip: _selectedRows.isEmpty
                        ? 'Seleccioná filas para generar INSERT/UPDATE/MERGE'
                        : 'Generar INSERT/UPDATE/MERGE',
                    icon: const Icon(Icons.data_object_outlined, size: 18),
                    onPressed: _selectedRows.isEmpty
                        ? null
                        : () => widget.onGenerateDml?.call(
                            _selectedRows.toList()..sort(),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Estima el ancho de cada columna de forma ultra rápida (O(1)) según la longitud
  /// del encabezado y una muestra reducida de filas, sin ejecutar layout de TextPainter en el hilo UI. Cacheado.
  List<double> _computeColumnWidths(
    SqlQueryResult result,
    List<int> visibleIdx,
    TextStyle headerStyle,
    TextStyle cellStyle,
  ) {
    final visibleHash = Object.hashAll(visibleIdx);
    if (_cachedWidths != null &&
        identical(_cachedWidthsResult, result) &&
        _cachedWidthsVisibleHash == visibleHash) {
      return _cachedWidths!;
    }

    // Heurística de ancho por carácter (monospace ~7.3px por char a 12pt; sans-serif ~7.0px a 11pt)
    double estimateWidth(String text, bool isHeader) {
      final charWidth = isHeader ? 7.2 : 7.4;
      return text.length * charWidth;
    }

    final sampleSize = math.min(5, result.rows.length);
    final widths = [
      for (final i in visibleIdx)
        if (_customColumnWidths.containsKey(i))
          _customColumnWidths[i]!
        else
          () {
            var w = estimateWidth(result.columns[i].name, true);
            for (var r = 0; r < sampleSize; r++) {
              final raw = result.rows[r][i];
              final str = raw?.toString() ?? 'NULL';
              final tw = estimateWidth(str, false);
              if (tw > w) w = tw;
            }
            return (w + 28).clamp(72.0, 360.0);
          }(),
    ];

    _cachedWidths = widths;
    _cachedWidthsResult = result;
    _cachedWidthsVisibleHash = visibleHash;

    return widths;
  }
}

/// Popover moderno para seleccionar y filtrar columnas visibles de la consulta SQL.
/// Diseñado para permanecer abierto durante toda la interacción (no se cierra al
/// marcar/desmarcar checkboxes) y ofrece búsqueda reactiva y opciones masivas.
class _ColumnsSelectorPopover extends StatefulWidget {
  const _ColumnsSelectorPopover({
    required this.columns,
    required this.hiddenColumns,
    required this.isDark,
    required this.onToggle,
    required this.onShowAll,
    required this.onHideOthers,
    this.onClose,
  });

  final List<SqlColumn> columns;
  final Set<int> hiddenColumns;
  final bool isDark;
  final ValueChanged<int> onToggle;
  final VoidCallback onShowAll;
  final ValueChanged<int> onHideOthers;
  final VoidCallback? onClose;

  @override
  State<_ColumnsSelectorPopover> createState() =>
      _ColumnsSelectorPopoverState();
}

class _ColumnsSelectorPopoverState extends State<_ColumnsSelectorPopover> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = widget.isDark;
    final visibleCount = widget.columns.length - widget.hiddenColumns.length;

    final q = _filter.trim().toLowerCase();
    final items = <int>[];
    for (var i = 0; i < widget.columns.length; i++) {
      if (q.isEmpty ||
          widget.columns[i].name.toLowerCase().contains(q) ||
          widget.columns[i].dataType.toLowerCase().contains(q)) {
        items.add(i);
      }
    }

    final borderColor = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.6);

    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Encabezado ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderColor, width: 0.8),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.view_column_rounded, size: 15, color: cs.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Columnas visibles',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? const Color(0xFFF0F6FC)
                          : const Color(0xFF1F2328),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$visibleCount de ${widget.columns.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Consolas',
                      color: cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Cerrar',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      if (widget.onClose != null) {
                        widget.onClose!();
                      } else {
                        Navigator.of(context, rootNavigator: false).maybePop();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Buscador reactivo ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _filter = v),
                style: const TextStyle(fontSize: 11.5, fontFamily: 'Consolas'),
                decoration: InputDecoration(
                  hintText: 'Filtrar columnas...',
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  suffixIcon: _filter.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 12),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _filter = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  fillColor: isDark
                      ? const Color(0xFF0D1117)
                      : cs.surfaceContainerLowest,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderColor, width: 0.8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderColor, width: 0.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: cs.primary, width: 1.2),
                  ),
                ),
              ),
            ),
          ),

          // ── Acciones rápidas (Todas / Contador) ─────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: widget.hiddenColumns.isEmpty
                        ? null
                        : widget.onShowAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        'Mostrar todas',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: widget.hiddenColumns.isEmpty
                              ? cs.onSurfaceVariant.withValues(alpha: 0.4)
                              : cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  '${items.length} encontrada${items.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Divider(height: 1, color: borderColor),

          // ── Lista de columnas con checkboxes ─────────────────────
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'Sin coincidencias',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  )
                : ScrollConfiguration(
                    behavior: const ScrollBehavior().copyWith(
                      scrollbars: false,
                    ),
                    child: SingleChildScrollView(
                      primary: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final colIndex in items)
                            _buildColumnRow(
                              colIndex: colIndex,
                              col: widget.columns[colIndex],
                              isVisible: !widget.hiddenColumns.contains(
                                colIndex,
                              ),
                              cs: cs,
                              isDark: isDark,
                              borderColor: borderColor,
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnRow({
    required int colIndex,
    required SqlColumn col,
    required bool isVisible,
    required ColorScheme cs,
    required bool isDark,
    required Color borderColor,
  }) {
    return InkWell(
      onTap: () => widget.onToggle(colIndex),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: isVisible,
                onChanged: (_) => widget.onToggle(colIndex),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                col.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'Consolas',
                  fontWeight: isVisible ? FontWeight.w600 : FontWeight.w400,
                  color: isVisible
                      ? (isDark
                            ? const Color(0xFFE6EDF3)
                            : const Color(0xFF1F2328))
                      : cs.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
            if (col.dataType.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF21262D)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: borderColor, width: 0.6),
                ),
                child: Text(
                  col.dataType,
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: 'Consolas',
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Tooltip(
              message: 'Solo esta columna',
              child: InkWell(
                borderRadius: BorderRadius.circular(3),
                onTap: () => widget.onHideOthers(colIndex),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  child: Text(
                    'solo',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: cs.primary.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
