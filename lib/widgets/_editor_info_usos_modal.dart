part of 'code_editor_panel.dart';

// ── Modal: usos del procedimiento dinámico (tabla + columna) ──────────────

/// Abre la ventana de usos del procedimiento.
///
/// Se inserta en el overlay raíz (sin barrera modal) para poder minimizarla
/// y seguir trabajando en el editor.
void _showUsosProcedimientoModal(
  BuildContext context,
  String cdProcedimiento,
  String ambiente,
) {
  _showFloatingWindow(
    context,
    (close) => _UsosProcedimientoModal(
      cdProcedimiento: cdProcedimiento,
      ambiente: ambiente,
      onClose: close,
    ),
  );
}

class _UsosProcedimientoModal extends StatefulWidget {
  final String cdProcedimiento;
  final String ambiente;
  final VoidCallback onClose;

  const _UsosProcedimientoModal({
    required this.cdProcedimiento,
    required this.ambiente,
    required this.onClose,
  });

  @override
  State<_UsosProcedimientoModal> createState() =>
      _UsosProcedimientoModalState();
}

class _UsosProcedimientoModalState extends State<_UsosProcedimientoModal> {
  late Future<UsosProcedimiento> _future;
  final _filterCtrl = TextEditingController();
  final _listCtrl = ScrollController();
  String _filter = '';
  int _tab = 0; // 0 = usos, 1 = tablas omitidas
  Offset _position = Offset.zero;
  double? _modalW;
  double? _modalH;

  /// Ventana maximizada / minimizada.
  bool _maximized = false;
  bool _minimized = false;
  int? _slot;
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;
  Duration _anim = Duration.zero;

  void _toggleMaximize() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_maximized) {
        _modalW = _restoreW;
        _modalH = _restoreH;
        _position = _restorePos;
        _maximized = false;
      } else {
        _restoreW = _modalW;
        _restoreH = _modalH;
        _restorePos = _position;
        _position = Offset.zero;
        _maximized = true;
      }
    });
  }

  void _toggleMinimize() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_minimized) {
        _MinimizedSlots.release(_slot);
        _slot = null;
        _minimized = false;
      } else {
        _slot = _MinimizedSlots.take();
        _minimized = true;
        // Devolver el teclado al editor mientras la ventana está minimizada.
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _cerrar() {
    _MinimizedSlots.release(_slot);
    _slot = null;
    widget.onClose();
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
    _filterCtrl.addListener(() {
      final v = _filterCtrl.text.trim().toUpperCase();
      if (v != _filter) setState(() => _filter = v);
    });
  }

  @override
  void dispose() {
    _MinimizedSlots.release(_slot);
    _filterCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  Future<UsosProcedimiento> _load() => SirwebService().usosProcedimiento(
    widget.cdProcedimiento,
    ambiente: widget.ambiente,
  );

  void _recargar() => setState(() => _future = _load());

  List<UsoProcedimiento> _filtrarUsos(List<UsoProcedimiento> items) {
    if (_filter.isEmpty) return items;
    return items
        .where(
          (u) =>
              u.tabla.toUpperCase().contains(_filter) ||
              u.columna.toUpperCase().contains(_filter) ||
              u.entidades.any((e) => e.searchText.contains(_filter)),
        )
        .toList();
  }

  List<SqlOtraTabla> _filtrarOtras(List<SqlOtraTabla> items) {
    if (_filter.isEmpty) return items;
    return items.where((t) => t.tabla.toUpperCase().contains(_filter)).toList();
  }

  Future<void> _copiarTodo(UsosProcedimiento data) async {
    final buf = StringBuffer()
      ..writeln('TABLA\tCOLUMNA\tTIPO\tCODIGO\tDESCRIPCION');
    for (final u in _filtrarUsos(data.usos)) {
      if (u.entidades.isEmpty) {
        buf.writeln('${u.tabla}\t${u.columna}\t\t\t');
        continue;
      }
      for (final e in u.entidades) {
        buf.writeln(
          '${u.tabla}\t${u.columna}\t${e.tipo}\t'
          '${e.codigo ?? ''}\t${e.descripcion ?? ''}',
        );
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    AppToast.info('Usos copiados al portapapeles');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (_maximized) {
      _modalW = (size.width - 48).clamp(460.0, size.width);
      _modalH = (size.height - 48).clamp(320.0, size.height);
    } else {
      _modalW ??= (size.width * 0.80).clamp(560.0, 880.0);
      _modalH ??= (size.height * 0.78).clamp(440.0, 700.0);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accentColor = Color(0xFF0078D4);
    final gripColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.18,
    );

    final double w, h, left, top;
    if (_minimized) {
      w = _MinimizedSlots.barW;
      h = _MinimizedSlots.barH;
      final (l, t) = _MinimizedSlots.offsetFor(_slot ?? 0, size);
      left = l;
      top = t;
    } else {
      w = _modalW!;
      h = _modalH!;
      left = ((size.width - w) / 2 + _position.dx).clamp(0.0, size.width - w);
      top = ((size.height - h) / 2 + _position.dy).clamp(0.0, size.height - h);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximize,
        const SingleActivator(LogicalKeyboardKey.escape): _cerrar,
      },
      child: Focus(
        // Minimizada no debe retener el teclado: el foco vuelve al editor.
        autofocus: !_minimized,
        canRequestFocus: !_minimized,
        descendantsAreFocusable: !_minimized,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: _anim,
              curve: Curves.easeOutCubic,
              left: left,
              top: top,
              width: w,
              height: h,
              child: Material(
                color: Colors.transparent,
                child: AnimatedContainer(
                  duration: _anim,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(
                      _maximized ? 6 : (_minimized ? 8 : 12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.5 : 0.18,
                        ),
                        blurRadius: _minimized ? 16 : 40,
                        offset: Offset(0, _minimized ? 4 : 16),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  // El contenido se maqueta siempre con el tamaño final y se
                  // recorta mientras corre la animación de minimizar/restaurar.
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: Column(
                        children: [
                          _buildHeader(context, isDark, accentColor),
                          if (!_minimized)
                            Expanded(
                              child: _buildBody(context, isDark, accentColor),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Right-edge resize handle
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 5,
                top: top + 44,
                width: 10,
                height: h - 54,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _modalW = (_modalW! + d.delta.dx).clamp(
                        460.0,
                        size.width - 40,
                      );
                    }),
                  ),
                ),
              ),
            // Bottom-edge resize handle
            if (!_maximized && !_minimized)
              Positioned(
                left: left + 16,
                top: top + h - 5,
                width: w - 32,
                height: 10,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _modalH = (_modalH! + d.delta.dy).clamp(
                        320.0,
                        size.height - 40,
                      );
                    }),
                  ),
                ),
              ),
            // Bottom-right corner grip
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 18,
                top: top + h - 18,
                width: 22,
                height: 22,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _modalW = (_modalW! + d.delta.dx).clamp(
                        460.0,
                        size.width - 40,
                      );
                      _modalH = (_modalH! + d.delta.dy).clamp(
                        320.0,
                        size.height - 40,
                      );
                    }),
                    child: CustomPaint(painter: _GripPainter(gripColor)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, Color accent) {
    return MouseRegion(
      cursor: _maximized ? SystemMouseCursors.basic : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (_maximized || _minimized)
            ? null
            : (d) => setState(() {
                _anim = Duration.zero;
                _position += d.delta;
              }),
        onDoubleTap: _minimized ? _toggleMinimize : _toggleMaximize,
        child: ConstellationHeader(
          padding: _minimized
              ? const EdgeInsets.fromLTRB(10, 4, 4, 4)
              : const EdgeInsets.fromLTRB(16, 12, 8, 12),
          lineColor: accent.withValues(alpha: 0.32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
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
              Container(
                padding: EdgeInsets.all(_minimized ? 5 : 8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(_minimized ? 6 : 8),
                ),
                child: Icon(
                  Icons.travel_explore_rounded,
                  size: _minimized ? 15 : 20,
                  color: accent,
                ),
              ),
              SizedBox(width: _minimized ? 8 : 12),
              if (_minimized)
                Expanded(
                  child: Text(
                    'Usos · ${widget.cdProcedimiento}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Usos del procedimiento',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white38 : Colors.black38,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.cdProcedimiento,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_minimized)
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: 'Recargar',
                  onPressed: _recargar,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              IconButton(
                tooltip: _minimized ? 'Restaurar' : 'Minimizar',
                icon: Icon(
                  _minimized
                      ? Icons.open_in_browser_rounded
                      : Icons.remove_rounded,
                  size: _minimized ? 16 : 18,
                ),
                onPressed: _toggleMinimize,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: _minimized ? 28 : 32,
                  minHeight: _minimized ? 28 : 32,
                ),
              ),
              if (!_minimized)
                IconButton(
                  tooltip: _maximized
                      ? 'Restaurar tamaño (F11)'
                      : 'Maximizar (F11)',
                  icon: Icon(
                    _maximized
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    size: 17,
                  ),
                  onPressed: _toggleMaximize,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              IconButton(
                tooltip: 'Cerrar (Esc)',
                icon: Icon(Icons.close, size: _minimized ? 16 : 18),
                onPressed: _cerrar,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: _minimized ? 28 : 32,
                  minHeight: _minimized ? 28 : 32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isDark, Color accent) {
    return FutureBuilder<UsosProcedimiento>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Column(
            children: [
              LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: Center(
                  child: Text(
                    'Analizando tablas…',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          );
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snap.error.toString().replaceFirst('Exception: ', ''),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _recargar,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snap.data ?? const UsosProcedimiento();
        final usos = _filtrarUsos(data.usos);
        final otras = _filtrarOtras(data.sqlOtrasTablas);

        return Column(
          children: [
            _buildToolbar(isDark, accent, data, usos.length, otras.length),
            Expanded(
              child: _tab == 0
                  ? _buildUsosList(isDark, accent, usos)
                  : _buildOtrasTablasList(isDark, otras),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(
    bool isDark,
    Color accent,
    UsosProcedimiento data,
    int usosCount,
    int otrasCount,
  ) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          _TabChip(
            label: 'Usos',
            count: usosCount,
            active: _tab == 0,
            accent: accent,
            isDark: isDark,
            onTap: () => setState(() => _tab = 0),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'SQL otras tablas',
            count: otrasCount,
            active: _tab == 1,
            accent: Colors.orange,
            isDark: isDark,
            onTap: () => setState(() => _tab = 1),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: _filterCtrl,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filtrar por tabla, columna o entidad…',
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.search, size: 15),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: _filterCtrl.clear,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.copy_all_rounded, size: 16),
            tooltip: 'Copiar usos (TSV)',
            onPressed: data.usos.isEmpty ? null : () => _copiarTodo(data),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildUsosList(
    bool isDark,
    Color accent,
    List<UsoProcedimiento> usos,
  ) {
    if (usos.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off_rounded,
        message: _filter.isEmpty
            ? 'El procedimiento no se utiliza en ninguna tabla'
            : 'Sin coincidencias para "$_filter"',
        isDark: isDark,
      );
    }

    final borderColor = isDark
        ? const Color(0xFF2F2F2F)
        : const Color(0xFFEDF0F5);

    return Scrollbar(
      controller: _listCtrl,
      child: ListView.separated(
        controller: _listCtrl,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: usos.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: borderColor),
        itemBuilder: (ctx, i) {
          final u = usos[i];
          return _UsoTile(uso: u, isDark: isDark, accent: accent);
        },
      ),
    );
  }

  Widget _buildOtrasTablasList(bool isDark, List<SqlOtraTabla> otras) {
    if (otras.isEmpty) {
      return _EmptyState(
        icon: Icons.check_circle_outline_rounded,
        message: _filter.isEmpty
            ? 'No hay SQL de otras tablas'
            : 'Sin coincidencias para "$_filter"',
        isDark: isDark,
      );
    }

    final borderColor = isDark
        ? const Color(0xFF2F2F2F)
        : const Color(0xFFEDF0F5);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: otras.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: borderColor),
      itemBuilder: (ctx, i) => _OtraTablaTile(item: otras[i], isDark: isDark),
    );
  }
}

class _OtraTablaTile extends StatefulWidget {
  final SqlOtraTabla item;
  final bool isDark;

  const _OtraTablaTile({required this.item, required this.isDark});

  @override
  State<_OtraTablaTile> createState() => _OtraTablaTileState();
}

class _OtraTablaTileState extends State<_OtraTablaTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.item;
    final isDark = widget.isDark;
    final hasSql = t.sql != null && t.sql!.isNotEmpty;
    final color = t.confirmada ? Colors.green : Colors.orange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: hasSql ? () => setState(() => _expanded = !_expanded) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                Icon(
                  t.confirmada
                      ? Icons.check_circle_outline_rounded
                      : Icons.help_outline_rounded,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.tabla,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'Consolas',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusBadge(
                  label: t.confirmada ? 'Confirmada' : 'No confirmada',
                  color: color,
                ),
                const SizedBox(width: 4),
                if (hasSql)
                  IconButton(
                    icon: const Icon(Icons.content_copy_rounded, size: 14),
                    tooltip: 'Copiar SQL',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: t.sql!));
                      AppToast.info('SQL copiado');
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                if (hasSql)
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
              ],
            ),
          ),
        ),
        if (_expanded && hasSql) _SqlBlock(sql: t.sql!, isDark: isDark),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _SqlBlock extends StatelessWidget {
  final String sql;
  final bool isDark;

  const _SqlBlock({required this.sql, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(40, 0, 14, 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171717) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0xFF303030) : const Color(0xFFE2E7EE),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              sql,
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: 'Consolas',
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.content_copy_rounded, size: 14),
            tooltip: 'Copiar SQL',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: sql));
              AppToast.info('SQL copiado');
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
        ],
      ),
    );
  }
}

class _UsoTile extends StatefulWidget {
  final UsoProcedimiento uso;
  final bool isDark;
  final Color accent;

  const _UsoTile({
    required this.uso,
    required this.isDark,
    required this.accent,
  });

  @override
  State<_UsoTile> createState() => _UsoTileState();
}

class _UsoTileState extends State<_UsoTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final u = widget.uso;
    final isDark = widget.isDark;
    final hasSql = u.sql != null && u.sql!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: hasSql ? () => setState(() => _expanded = !_expanded) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                Icon(
                  Icons.table_chart_outlined,
                  size: 16,
                  color: widget.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              u.tabla,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontFamily: 'Consolas',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            ' . ',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              u.columna,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontFamily: 'Consolas',
                                color: widget.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (u.entidades.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final e in u.entidades)
                                _EntidadChip(entidad: e, isDark: isDark),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.content_copy_rounded, size: 14),
                  tooltip: 'Copiar TABLA.COLUMNA',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: '${u.tabla}.${u.columna}'),
                    );
                    AppToast.info('Copiado');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                if (hasSql)
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
              ],
            ),
          ),
        ),
        if (_expanded && hasSql) _SqlBlock(sql: u.sql!, isDark: isDark),
      ],
    );
  }
}

class _EntidadChip extends StatelessWidget {
  final EntidadUso entidad;
  final bool isDark;

  const _EntidadChip({required this.entidad, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = _colorPorTipo(entidad.tipo);
    final codigo = entidad.codigo;
    final desc = entidad.descripcion;

    return Tooltip(
      message: entidad.label.isEmpty ? entidad.tipo : entidad.label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entidad.tipo.isEmpty ? '—' : entidad.tipo.toUpperCase(),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: color,
              ),
            ),
            if (codigo != null && codigo.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                codigo,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (desc != null && desc.isNotEmpty) ...[
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  desc,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _colorPorTipo(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'EVENTO':
        return const Color(0xFF0078D4);
      case 'TABLA':
        return const Color(0xFF8E44AD);
      case 'DATO':
        return const Color(0xFF16A085);
      case 'PROCESO':
        return const Color(0xFFD35400);
      default:
        return const Color(0xFF607D8B);
    }
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.count,
    required this.active,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? accent.withValues(alpha: 0.5)
                : (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA)),
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? accent : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isDark;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white38 : Colors.black38;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: color),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }
}
