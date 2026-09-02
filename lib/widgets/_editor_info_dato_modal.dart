part of 'code_editor_panel.dart';

/// Abre la ventana de InfoDato.
///
/// Se inserta en el overlay raíz (sin barrera modal) para poder minimizarla
/// y seguir trabajando en el editor.
void _showInfoDatoModal(
  BuildContext context,
  String cdDatoStr,
  String ambiente,
) {
  _showFloatingWindow(
    context,
    (close) => _InfoDatoModal(
      cdDatoStr: cdDatoStr,
      ambiente: ambiente,
      onClose: close,
    ),
  );
}

class _InfoDatoModal extends StatefulWidget {
  final String cdDatoStr;
  final String ambiente;
  final VoidCallback onClose;
  const _InfoDatoModal({
    required this.cdDatoStr,
    required this.ambiente,
    required this.onClose,
  });

  @override
  State<_InfoDatoModal> createState() => _InfoDatoModalState();
}

class _InfoDatoModalState extends State<_InfoDatoModal> {
  int _tab = 0;
  late Future<List<DatoInfo>> _datoFuture;
  Future<TablaDefinicion>? _defFuture;
  Future<List<ValorTabla>>? _infoFuture;
  int? _cdTabla;

  // Drag & resize
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

  // Scroll controllers
  final _vertCtrl = ScrollController();
  final _horizCtrl = ScrollController();

  // Tabla Información filters
  final _indexCtrl = TextEditingController();
  final _fechaDesdeCtrl = TextEditingController();
  final _fechaHastaCtrl = TextEditingController();
  int? _inSuspendido;
  Set<String> _hiddenCols = {};

  @override
  void initState() {
    super.initState();
    _loadDato();
  }

  @override
  void dispose() {
    _MinimizedSlots.release(_slot);
    _vertCtrl.dispose();
    _horizCtrl.dispose();
    _indexCtrl.dispose();
    _fechaDesdeCtrl.dispose();
    _fechaHastaCtrl.dispose();
    super.dispose();
  }

  void _loadDato() {
    _datoFuture = SirwebService().buscarDato(
      cdDato: int.tryParse(widget.cdDatoStr),
      ambiente: widget.ambiente,
    );
    _datoFuture.then((datos) {
      if (!mounted) return;
      setState(() => _cdTabla = datos.isNotEmpty ? datos.first.cdTabla : null);
    });
  }

  void _selectTab(int idx) {
    if (idx == _tab) return;
    setState(() {
      _tab = idx;
      _hiddenCols = {};
    });
    final cdTabla = _cdTabla;
    if (cdTabla == null) return;
    if (idx == 1 && _defFuture == null) {
      setState(
        () => _defFuture = SirwebService().infoTabla(
          cdTabla,
          ambiente: widget.ambiente,
        ),
      );
    } else if (idx == 2 && _infoFuture == null) {
      setState(
        () => _infoFuture = SirwebService().valoresTabla(
          cdTabla,
          ambiente: widget.ambiente,
        ),
      );
    }
  }

  void _buscarInfo() {
    final cdTabla = _cdTabla;
    if (cdTabla == null) return;
    setState(() {
      _hiddenCols = {};
      _infoFuture = SirwebService().valoresTabla(
        cdTabla,
        ambiente: widget.ambiente,
        deIndiceDato: _indexCtrl.text.trim().isEmpty
            ? null
            : _indexCtrl.text.trim(),
        fechaDesde: _fechaDesdeCtrl.text.trim().isEmpty
            ? null
            : _fechaDesdeCtrl.text.trim(),
        fechaHasta: _fechaHastaCtrl.text.trim().isEmpty
            ? null
            : _fechaHastaCtrl.text.trim(),
        inSuspendido: _inSuspendido,
      );
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (_maximized) {
      _modalW = (size.width - 48).clamp(440.0, size.width);
      _modalH = (size.height - 48).clamp(340.0, size.height);
    } else {
      _modalW ??= (size.width * 0.82).clamp(560.0, 920.0);
      _modalH ??= (size.height * 0.80).clamp(460.0, 720.0);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF0E8A4E);
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
                          _buildHeader(isDark, accent),
                          if (!_minimized) ...[
                            _buildTabBar(isDark, accent),
                            Expanded(child: _buildTabContent(isDark, accent)),
                          ],
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
                        440.0,
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
                        340.0,
                        size.height - 40,
                      );
                    }),
                  ),
                ),
              ),
            // Corner resize handle
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
                        440.0,
                        size.width - 40,
                      );
                      _modalH = (_modalH! + d.delta.dy).clamp(
                        340.0,
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

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark, Color accent) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
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
            border: Border(bottom: BorderSide(color: borderColor)),
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
                  Icons.table_chart_outlined,
                  size: _minimized ? 15 : 20,
                  color: accent,
                ),
              ),
              SizedBox(width: _minimized ? 8 : 12),
              if (_minimized)
                Expanded(
                  child: Text(
                    'Dato ${widget.cdDatoStr}',
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
                        'InfoDato',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white38 : Colors.black38,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.cdDatoStr,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ],
                  ),
                ),
              if (_cdTabla != null && !_minimized) ...[
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'TABLA $_cdTabla',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accent,
                      fontFamily: 'Consolas',
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
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

  // ── Tab bar (visible only when dato has a table) ─────────────────────────

  Widget _buildTabBar(bool isDark, Color accent) {
    if (_cdTabla == null) return const SizedBox.shrink();
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          _tab0(isDark, accent),
          _tab1(isDark, accent),
          _tab2(isDark, accent),
        ],
      ),
    );
  }

  Widget _tabItem(
    int idx,
    String label,
    IconData icon,
    bool isDark,
    Color accent,
  ) {
    final isSelected = _tab == idx;
    final color = isSelected
        ? accent
        : (isDark ? Colors.white54 : Colors.black45);
    return InkWell(
      onTap: () => _selectTab(idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab0(bool isDark, Color accent) =>
      _tabItem(0, 'Dato', Icons.data_object_outlined, isDark, accent);
  Widget _tab1(bool isDark, Color accent) =>
      _tabItem(1, 'Tabla Definición', Icons.view_list_outlined, isDark, accent);
  Widget _tab2(bool isDark, Color accent) => _tabItem(
    2,
    'Tabla Información',
    Icons.table_rows_outlined,
    isDark,
    accent,
  );

  // ── Tab content router ────────────────────────────────────────────────────

  Widget _buildTabContent(bool isDark, Color accent) {
    return switch (_tab) {
      1 => _buildDefTab(isDark, accent),
      2 => _buildInfoTab(isDark, accent),
      _ => _buildDatoTab(isDark, accent),
    };
  }

  // ── Tab 0: Dato ───────────────────────────────────────────────────────────

  Widget _buildDatoTab(bool isDark, Color accent) {
    return FutureBuilder<List<DatoInfo>>(
      future: _datoFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _buildError(snap.error.toString(), isDark);
        }
        final datos = snap.data ?? [];
        if (datos.isEmpty) return _buildEmpty('No se encontró el dato', isDark);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final d in datos) _buildDatoCard(d, isDark, accent),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDatoCard(DatoInfo d, bool isDark, Color accent) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    final bg = accent.withValues(alpha: isDark ? 0.08 : 0.05);
    final labelColor = isDark ? Colors.white54 : Colors.black45;
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.87)
        : Colors.black87;

    final props = <(String, String)>[
      if (d.cdDato != null) ('Código', d.cdDato.toString()),
      if (d.deDato != null) ('Descripción', d.deDato!),
      if (d.tpDato != null) ('Tipo', d.tpDato!),
      if (d.nuLongitud != null) ('Longitud', d.nuLongitud.toString()),
      if (d.nuDecimales != null) ('Decimales', d.nuDecimales.toString()),
      if (d.cdTabla != null) ('Tabla', d.cdTabla.toString()),
      if (d.cdBusqueda != null) ('Cód. búsqueda', d.cdBusqueda.toString()),
      if (d.inUso != null) ('En uso', d.inUso! ? 'Sí' : 'No'),
    ];

    final flags = <(String, bool)>[
      if (d.inConsultaSiniestro != null)
        ('Consulta siniestro', d.inConsultaSiniestro!),
      if (d.inValidaPersona != null) ('Valida persona', d.inValidaPersona!),
      if (d.inAsignacionAutomatica != null)
        ('Asignación automática', d.inAsignacionAutomatica!),
    ];

    const knownKeys = {
      'cdDato',
      'deDato',
      'tpDato',
      'nuLongitud',
      'nuDecimales',
      'cdTabla',
      'cdBusqueda',
      'inUso',
      'inConsultaSiniestro',
      'inValidaPersona',
      'inAsignacionAutomatica',
    };
    final extras = d.raw.entries
        .where((e) => !knownKeys.contains(e.key) && e.value != null)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in props)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: labelColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                  ),
                ],
              ),
            ),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (label, value) in flags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (value ? Colors.green : Colors.grey).withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (value ? Colors.green : Colors.grey).withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: value
                            ? (isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade700)
                            : labelColor,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (extras.isNotEmpty) ...[
            Divider(color: borderColor, height: 16),
            for (final e in extras)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        e.key,
                        style: TextStyle(
                          fontSize: 10,
                          color: labelColor,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        e.value.toString(),
                        style: TextStyle(fontSize: 11, color: textColor),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── Tab 1: Tabla Definición ───────────────────────────────────────────────

  Widget _buildDefTab(bool isDark, Color accent) {
    final future = _defFuture;
    if (future == null) return const Center(child: CircularProgressIndicator());
    return FutureBuilder<TablaDefinicion>(
      future: future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _buildError(snap.error.toString(), isDark);
        final def = snap.data;
        if (def == null) return _buildEmpty('Sin datos de definición', isDark);
        return _buildDefContent(def, isDark, accent);
      },
    );
  }

  Widget _buildDefContent(TablaDefinicion def, bool isDark, Color accent) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    final labelColor = isDark ? Colors.white54 : Colors.black45;
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.87)
        : Colors.black87;
    final bg = accent.withValues(alpha: isDark ? 0.08 : 0.05);
    const skipKeys = {
      'cdTabla',
      'deTabla',
      'CD_TABLA',
      'DE_TABLA',
      'datos',
      'columnas',
      'items',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header card
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (def.deTabla != null) ...[
                Text(
                  'Descripción',
                  style: TextStyle(
                    fontSize: 10,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  def.deTabla!,
                  style: TextStyle(fontSize: 13, color: textColor),
                ),
                const SizedBox(height: 6),
              ],
              if (def.cdTabla != null)
                Row(
                  children: [
                    Text(
                      'Código tabla: ',
                      style: TextStyle(fontSize: 11, color: labelColor),
                    ),
                    Text(
                      def.cdTabla.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Consolas',
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              // Extra raw fields
              for (final e in def.raw.entries.where(
                (e) =>
                    !skipKeys.contains(e.key) &&
                    e.value != null &&
                    e.value is! List,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          e.key,
                          style: TextStyle(
                            fontSize: 10,
                            color: labelColor,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.value.toString(),
                          style: TextStyle(fontSize: 11, color: textColor),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Columns count
        if (def.columnas.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              '${def.columnas.length} dato${def.columnas.length != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: labelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        // Column list
        if (def.columnas.isNotEmpty)
          Expanded(
            child: Scrollbar(
              controller: _vertCtrl,
              thumbVisibility: true,
              trackVisibility: true,
              child: ListView.builder(
                controller: _vertCtrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: def.columnas.length,
                itemBuilder: (ctx, i) {
                  final col = def.columnas[i];
                  final rowBg = i.isEven
                      ? (isDark
                            ? const Color(0xFF252526)
                            : const Color(0xFFF8F9FA))
                      : Colors.transparent;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: rowBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: borderColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        // numero
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${col.numero ?? i + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              color: labelColor,
                              fontFamily: 'Consolas',
                            ),
                          ),
                        ),
                        // cdDato
                        if (col.cdDato != null)
                          SizedBox(
                            width: 64,
                            child: Text(
                              col.cdDato.toString(),
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'Consolas',
                                color: accent,
                              ),
                            ),
                          ),
                        // deDato
                        Expanded(
                          child: Text(
                            col.deDato ?? '',
                            style: TextStyle(fontSize: 12, color: textColor),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          )
        else
          Expanded(child: _buildEmpty('Sin columnas definidas', isDark)),
      ],
    );
  }

  // ── Tab 2: Tabla Información ──────────────────────────────────────────────

  Widget _buildInfoTab(bool isDark, Color accent) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    final labelColor = isDark ? Colors.white54 : Colors.black45;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoFilters(isDark, accent, borderColor),
        Expanded(
          child: _buildInfoResults(isDark, accent, borderColor, labelColor),
        ),
      ],
    );
  }

  Widget _buildInfoFilters(bool isDark, Color accent, Color borderColor) {
    final hintStyle = TextStyle(
      fontSize: 11,
      color: isDark ? Colors.white38 : Colors.black38,
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: borderColor),
    );
    const contentPad = EdgeInsets.symmetric(horizontal: 10, vertical: 0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _indexCtrl,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Índice dato (admite %)',
                  hintStyle: hintStyle,
                  prefixIcon: const Icon(Icons.search, size: 14),
                  prefixIconConstraints: const BoxConstraints(minWidth: 30),
                  border: inputBorder,
                  enabledBorder: inputBorder,
                  contentPadding: contentPad,
                ),
                onSubmitted: (_) => _buscarInfo(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _fechaDesdeCtrl,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Desde dd/MM/yyyy',
                  hintStyle: hintStyle,
                  border: inputBorder,
                  enabledBorder: inputBorder,
                  contentPadding: contentPad,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _fechaHastaCtrl,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Hasta dd/MM/yyyy',
                  hintStyle: hintStyle,
                  border: inputBorder,
                  enabledBorder: inputBorder,
                  contentPadding: contentPad,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<int?>(
            value: _inSuspendido,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            items: const [
              DropdownMenuItem<int?>(value: null, child: Text('Todos')),
              DropdownMenuItem<int?>(value: 0, child: Text('Activos')),
              DropdownMenuItem<int?>(value: 1, child: Text('Suspendidos')),
            ],
            onChanged: (v) => setState(() => _inSuspendido = v),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: FilledButton.icon(
              onPressed: _buscarInfo,
              icon: const Icon(Icons.search, size: 14),
              label: const Text('Buscar', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoResults(
    bool isDark,
    Color accent,
    Color borderColor,
    Color labelColor,
  ) {
    final future = _infoFuture;
    if (future == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.manage_search_rounded,
              size: 36,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 10),
            Text(
              'Aplique filtros y presione Buscar',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }
    return FutureBuilder<List<ValorTabla>>(
      future: future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _buildError(snap.error.toString(), isDark);
        final valores = snap.data ?? [];
        if (valores.isEmpty) {
          return _buildEmpty(
            'Sin resultados con los filtros indicados',
            isDark,
          );
        }
        final allCols = _detectInfoCols(valores);
        final effectiveCols = _hiddenCols.isEmpty
            ? allCols
            : allCols.where((c) => !_hiddenCols.contains(c)).toList();
        return Column(
          children: [
            _buildInfoToolbar(
              context,
              isDark,
              borderColor,
              allCols,
              effectiveCols,
              valores,
            ),
            Expanded(
              child: _buildInfoTable(
                isDark,
                borderColor,
                effectiveCols,
                valores,
              ),
            ),
          ],
        );
      },
    );
  }

  List<String> _detectInfoCols(List<ValorTabla> valores) {
    if (valores.isEmpty) return [];
    final keys = <String>{};
    for (final v in valores.take(5)) keys.addAll(v.raw.keys);
    const preferred = [
      'deIndiceDato',
      'deDato',
      'vaDato1',
      'vaDato2',
      'vaDato3',
      'vaDato4',
      'vaDato5',
      'vaDato6',
      'feEfectivaInformacion',
      'feTerminoInformacion',
      'inSuspendido',
      'inValorDefecto',
      'inNoValido',
      'inNoMostrarWebExterna',
      'inNoMostrarWebMediador',
      'inNoMostrarWebProveedor',
      'inNoMostrarWebDelegado',
      'feModificacion',
      'cdUsuario',
    ];
    return [
      ...preferred.where(keys.contains),
      ...keys.where((k) => !preferred.contains(k)),
    ];
  }

  String _infoColLabel(String col) {
    const labels = <String, String>{
      'deIndiceDato': 'Índice',
      'deDato': 'Descripción',
      'vaDato1': 'Dato 1',
      'vaDato2': 'Dato 2',
      'vaDato3': 'Dato 3',
      'vaDato4': 'Dato 4',
      'vaDato5': 'Dato 5',
      'vaDato6': 'Dato 6',
      'feEfectivaInformacion': 'F. efectiva',
      'feTerminoInformacion': 'F. término',
      'inSuspendido': 'Suspendido',
      'inValorDefecto': 'Por defecto',
      'inNoValido': 'No válido',
      'inNoMostrarWebExterna': 'Oculto externo',
      'inNoMostrarWebMediador': 'Oculto mediador',
      'inNoMostrarWebProveedor': 'Oculto proveedor',
      'inNoMostrarWebDelegado': 'Oculto delegado',
      'feModificacion': 'F. modificación',
      'cdUsuario': 'Usuario',
    };
    return labels[col] ?? col;
  }

  // ── Toolbar (Tab 2) ──────────────────────────────────────────────────────

  Widget _buildInfoToolbar(
    BuildContext context,
    bool isDark,
    Color borderColor,
    List<String> allCols,
    List<String> effectiveCols,
    List<ValorTabla> valores,
  ) {
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA);
    final labelColor = isDark ? Colors.white54 : Colors.black45;
    final hiddenCount = allCols.length - effectiveCols.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Text(
            '${valores.length} registro${valores.length != 1 ? 's' : ''}',
            style: TextStyle(fontSize: 11, color: labelColor),
          ),
          const Spacer(),
          _infoToolBtn(
            isDark,
            Icons.view_column_outlined,
            hiddenCount > 0 ? 'Columnas ($hiddenCount)' : 'Columnas',
            () => _showInfoColSelector(context, allCols),
          ),
          const SizedBox(width: 4),
          _infoToolBtn(
            isDark,
            Icons.copy_outlined,
            'Copiar',
            () => _copyInfoCsv(effectiveCols, valores),
          ),
          const SizedBox(width: 4),
          _infoToolBtn(
            isDark,
            Icons.download_outlined,
            'Exportar CSV',
            () => _exportInfoCsv(effectiveCols, valores),
          ),
        ],
      ),
    );
  }

  Widget _infoToolBtn(
    bool isDark,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final color = isDark ? Colors.white54 : Colors.black54;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  void _showInfoColSelector(BuildContext context, List<String> allCols) {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          title: const ConstellationDialogTitle(
            child: Text('Columnas visibles', style: TextStyle(fontSize: 15)),
          ),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: SizedBox(
            width: 280,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final col in allCols)
                      CheckboxListTile(
                        dense: true,
                        title: Text(
                          _infoColLabel(col),
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          col,
                          style: const TextStyle(fontSize: 10),
                        ),
                        value: !_hiddenCols.contains(col),
                        onChanged: (checked) {
                          if (checked == false &&
                              _hiddenCols.length >= allCols.length - 1) {
                            return;
                          }
                          setState(() {
                            if (checked == true) {
                              _hiddenCols.remove(col);
                            } else {
                              _hiddenCols.add(col);
                            }
                          });
                          setDs(() {});
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _hiddenCols.clear());
                setDs(() {});
              },
              child: const Text('Mostrar todas'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Table (Tab 2) ────────────────────────────────────────────────────────

  Widget _buildInfoTable(
    bool isDark,
    Color borderColor,
    List<String> cols,
    List<ValorTabla> valores,
  ) {
    final headerBg = isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA);

    return Scrollbar(
      controller: _horizCtrl,
      thumbVisibility: true,
      trackVisibility: true,
      notificationPredicate: (n) => n.depth == 1,
      child: Scrollbar(
        controller: _vertCtrl,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: _vertCtrl,
          child: SingleChildScrollView(
            controller: _horizCtrl,
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              headingRowHeight: 32,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 44,
              dividerThickness: 1,
              headingRowColor: WidgetStatePropertyAll(headerBg),
              headingTextStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black45,
                letterSpacing: 0.3,
              ),
              dataTextStyle: TextStyle(
                fontSize: 12,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.87)
                    : Colors.black87,
              ),
              border: TableBorder(
                top: BorderSide(color: borderColor),
                horizontalInside: BorderSide(color: borderColor, width: 0.5),
              ),
              columns: [
                for (final col in cols)
                  DataColumn(label: Text(_infoColLabel(col))),
              ],
              rows: [
                for (final v in valores)
                  DataRow(
                    cells: [
                      for (final col in cols)
                        DataCell(Text(v.raw[col]?.toString() ?? '')),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── CSV export ────────────────────────────────────────────────────────────

  String _buildInfoCsv(List<String> cols, List<ValorTabla> valores) {
    final buf = StringBuffer();
    buf.writeln(cols.map((c) => _escInfo(_infoColLabel(c))).join(','));
    for (final v in valores) {
      buf.writeln(
        cols.map((c) => _escInfo(v.raw[c]?.toString() ?? '')).join(','),
      );
    }
    return buf.toString();
  }

  String _escInfo(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _copyInfoCsv(List<String> cols, List<ValorTabla> valores) async {
    final csv = _buildInfoCsv(cols, valores);
    await Clipboard.setData(ClipboardData(text: csv));
    AppToast.success(
      'Copiado al portapapeles — ${valores.length} fila${valores.length != 1 ? 's' : ''}',
    );
  }

  Future<void> _exportInfoCsv(
    List<String> cols,
    List<ValorTabla> valores,
  ) async {
    final csv = _buildInfoCsv(cols, valores);
    final path = await FilePicker.saveFile(
      dialogTitle: 'Exportar CSV',
      fileName: 'dato_${widget.cdDatoStr}_info.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: utf8.encode(csv),
      lockParentWindow: true,
    );
    if (path != null) AppToast.success('CSV exportado correctamente');
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _buildError(String msg, bool isDark) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 40,
            color: isDark ? Colors.redAccent : Colors.red.shade600,
          ),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmpty(String msg, bool isDark) => Center(
    child: Text(
      msg,
      style: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white38 : Colors.black38,
      ),
    ),
  );
}
