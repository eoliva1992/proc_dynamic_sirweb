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
  });

  final SqlQueryResult? result;
  final int maxRows;
  final ValueChanged<int>? onMaxRowsChanged;

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
  int? _anchorRow;
  Timer? _searchDebounce;
  final _gridFocusNode = FocusNode();
  final _horizCtrl = ScrollController();
  final _vertCtrl = ScrollController();
  late final TextEditingController _maxRowsCtrl;
  late final FocusNode _maxRowsFocus;
  late final TextEditingController _searchCtrl;
  late final FocusNode _searchFocus;
  bool _searchOpen = false;
  String _searchQuery = '';
  int? _sortColIndex;
  bool _sortAsc = true;

  // Cache de anchos de columna e índices filtrados para rendimiento
  List<double>? _cachedWidths;
  SqlQueryResult? _cachedWidthsResult;
  int _cachedWidthsVisibleHash = 0;

  List<int>? _cachedDisplayIndices;
  SqlQueryResult? _cachedIndicesResult;
  String _cachedIndicesQuery = '';
  int? _cachedIndicesSortCol;
  bool _cachedIndicesSortAsc = true;
  int _cachedIndicesVisibleHash = 0;

  @override
  void initState() {
    super.initState();
    _maxRowsCtrl = TextEditingController(text: '${widget.maxRows}');
    _maxRowsFocus = FocusNode();
    _searchCtrl = TextEditingController();
    _searchFocus = FocusNode();
  }

  @override
  void didUpdateWidget(SqlResultsGrid old) {
    super.didUpdateWidget(old);
    if (old.maxRows != widget.maxRows && !_maxRowsFocus.hasFocus) {
      _maxRowsCtrl.text = '${widget.maxRows}';
    }
    if (!identical(old.result, widget.result)) {
      _hiddenColumns.clear();
      _selectedRows.clear();
      _selectedCells.clear();
      _selectedCellRows.clear();
      _cellSelectionRevision.value++;
      _anchorCell = null;
      _anchorRow = null;
      _searchDebounce?.cancel();
      _searchCtrl.clear();
      _searchQuery = '';
      _searchOpen = false;
      _sortColIndex = null;
      _sortAsc = true;
      _cachedWidths = null;
      _cachedDisplayIndices = null;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _maxRowsCtrl.dispose();
    _maxRowsFocus.dispose();
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

  void _commitMaxRows() {
    final value = int.tryParse(_maxRowsCtrl.text.trim());
    if (value == null || value < 1 || value > 100000) {
      _maxRowsCtrl.text = '${widget.maxRows}';
      return;
    }
    widget.onMaxRowsChanged?.call(value);
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
    }
    // 3. Ctrl + Click: toggle celda individual
    else if (isCtrl) {
      final coord = (r, c);
      if (_selectedCells.contains(coord)) {
        _selectedCells.remove(coord);
        if (!_selectedCells.any((cell) => cell.$1 == r)) {
          _selectedCellRows.remove(r);
        }
      } else {
        _selectedCells.add(coord);
        _selectedCellRows.add(r);
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
      } else {
        _selectedCells.clear();
        _selectedCellRows.clear();
        _selectedCells.add(coord);
        _selectedCellRows.add(r);
        _anchorCell = coord;
      }
    }

    _cellSelectionRevision.value++;
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

    if (_cachedDisplayIndices != null &&
        identical(_cachedIndicesResult, result) &&
        _cachedIndicesQuery == query &&
        _cachedIndicesSortCol == _sortColIndex &&
        _cachedIndicesSortAsc == _sortAsc &&
        _cachedIndicesVisibleHash == visibleHash) {
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

    return indices;
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
      ],
    );
  }

  Widget _buildTable(
    bool isDark,
    SqlQueryResult result,
    List<int> visibleIdx,
    List<int> displayIndices,
  ) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = cs.outlineVariant;
    const headerStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
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
      color: borderColor.withValues(alpha: 0.35),
      width: 0.5,
    );
    final cellBottomBorder = BorderSide(
      color: borderColor.withValues(alpha: 0.35),
      width: 0.5,
    );
    final selectedBorder = BorderSide(
      color: cs.primary.withValues(alpha: 0.7),
      width: 1.0,
    );
    final anchorBorder = BorderSide(color: cs.primary, width: 1.5);
    const checkboxColWidth = 44.0;
    const rowHeight = 32.0;
    const headerHeight = 32.0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
            _copySelection(visibleIdx),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedCells.isNotEmpty || _selectedRows.isNotEmpty) {
            setState(() {
              _selectedCells.clear();
              _selectedCellRows.clear();
              _selectedRows.clear();
              _anchorCell = null;
              _anchorRow = null;
            });
            _cellSelectionRevision.value++;
          }
        },
      },
      child: Focus(
        focusNode: _gridFocusNode,
        autofocus: false,
        child: RepaintBoundary(
          child: TableView.builder(
            verticalDetails: ScrollableDetails.vertical(controller: _vertCtrl),
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
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                final colData = result.columns[visibleIdx[c]];
                final isSorted = _sortColIndex == c;

                return TableViewCell(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onColumnHeaderTap(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
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
                            child: Tooltip(
                              message:
                                  '${colData.name} (${colData.dataType})\nClic para ordenar',
                              waitDuration: const Duration(milliseconds: 600),
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
                              padding: const EdgeInsets.only(left: 4),
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
                );
              }

              // 3. Columna fija izquierda: Checkbox de Fila
              final r = displayIndices[row - 1];
              final isRowSelected = _selectedRows.contains(r);
              final rowHasSelectedCell = _selectedCellRows.contains(r);
              final rowBgColor = isRowSelected
                  ? cs.primaryContainer.withValues(alpha: 0.3)
                  : (rowHasSelectedCell
                        ? cs.primary.withValues(alpha: 0.06)
                        : (r.isOdd
                              ? (isDark
                                    ? cs.surfaceContainerLow.withValues(
                                        alpha: 0.35,
                                      )
                                    : cs.surfaceContainerLowest)
                              : (isDark ? cs.surface : Colors.white)));

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
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                            ? cs.primary.withValues(alpha: 0.22)
                            : rowBgColor,
                        border: Border(
                          right: isCellSelected
                              ? activeBorder
                              : cellRightBorder,
                          bottom: isCellSelected
                              ? activeBorder
                              : cellBottomBorder,
                          top: isCellSelected ? activeBorder : BorderSide.none,
                          left: isCellSelected ? activeBorder : BorderSide.none,
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
                          padding: const EdgeInsets.symmetric(horizontal: 10),
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
    );
  }

  Widget _buildToolbar(
    bool isDark,
    SqlQueryResult result,
    List<int> visibleIdx,
    List<int> displayIndices,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isFiltered = _searchQuery.trim().isNotEmpty;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: isDark ? cs.surfaceContainerLow : cs.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Row(
                children: [
                  Text(
                    isFiltered
                        ? '${displayIndices.length} de ${result.returnedRows} filas'
                        : '${result.returnedRows} fila${result.returnedRows == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    ' · ${result.durationMs} ms',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                  if (result.truncated) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        'truncado',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[700],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 18,
                    child: VerticalDivider(color: cs.outlineVariant, width: 12),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Límite',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.7),
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IntrinsicWidth(
                          child: TextField(
                            controller: _maxRowsCtrl,
                            focusNode: _maxRowsFocus,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                            ),
                            onSubmitted: (_) => _commitMaxRows(),
                            onTapOutside: (_) {
                              _commitMaxRows();
                              _maxRowsFocus.unfocus();
                            },
                          ),
                        ),
                        Text(
                          ' filas',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                  PopupMenuButton<int>(
                    tooltip: 'Columnas',
                    icon: const Icon(Icons.view_column_outlined, size: 18),
                    itemBuilder: (_) => [
                      for (var i = 0; i < result.columns.length; i++)
                        CheckedPopupMenuItem(
                          value: i,
                          checked: !_hiddenColumns.contains(i),
                          child: Text(result.columns[i].name),
                        ),
                    ],
                    onSelected: (i) => setState(() {
                      if (_hiddenColumns.contains(i)) {
                        _hiddenColumns.remove(i);
                      } else {
                        _hiddenColumns.add(i);
                      }
                    }),
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
