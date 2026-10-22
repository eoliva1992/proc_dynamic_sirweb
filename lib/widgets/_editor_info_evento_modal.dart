part of 'code_editor_panel.dart';

/// Abre la ventana de InfoEvento.
///
/// Se inserta en el overlay raíz (sin barrera modal) para que pueda
/// minimizarse y seguir trabajando en el editor.
///
/// Si [cdEvento] viene vacío, la ventana se abre directamente en modo búsqueda
/// para que el usuario escriba el código del evento a consultar.
void showInfoEventoWindow(
  BuildContext context,
  String cdEvento,
  String ambiente,
) {
  _showFloatingWindow(
    context,
    (close) => _InfoEventoModal(
      cdEvento: cdEvento,
      ambiente: ambiente,
      onClose: close,
    ),
  );
}

void _showInfoEventoModal(
  BuildContext context,
  String cdEvento,
  String ambiente,
) => showInfoEventoWindow(context, cdEvento, ambiente);

class _InfoEventoModal extends StatefulWidget {
  final String cdEvento;
  final String ambiente;
  final VoidCallback onClose;

  const _InfoEventoModal({
    required this.cdEvento,
    required this.ambiente,
    required this.onClose,
  });

  @override
  State<_InfoEventoModal> createState() => _InfoEventoModalState();
}

class _InfoEventoModalState extends State<_InfoEventoModal> {
  static const _kPrefTopEventoValor = 'info_evento_top_limit';

  late String _ambiente;
  late Future<EventoInfo>? _headerFuture;
  Future<List<EventoValor>>? _valoresFuture;
  final _indexCtrl = TextEditingController();
  final _topCtrl = TextEditingController(text: '50');
  bool _hasText = false;
  Offset _position = Offset.zero;
  Set<String> _hiddenCols = {};
  final Set<int> _selectedRowIndices = {};
  double? _modalW;
  double? _modalH;
  final _tableVertCtrl = ScrollController();
  final _tableHorizCtrl = ScrollController();

  /// Evento actualmente mostrado (puede cambiar sin cerrar el modal).
  late String _cdEvento;

  /// Historial de eventos consultados en esta sesión del modal.
  final List<String> _historial = [];

  /// Indica si el campo para cambiar de evento está visible.
  bool _editandoEvento = false;
  final _eventoCtrl = TextEditingController();
  final _eventoFocus = FocusNode();

  /// Ventana maximizada (ocupa casi toda la pantalla).
  bool _maximized = false;

  /// Geometría previa, para restaurar al des-maximizar.
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;

  /// Duración de la animación de la ventana: 180 ms al maximizar/restaurar,
  /// cero mientras se arrastra o redimensiona (para que siga al mouse).
  Duration _anim = Duration.zero;

  /// Ventana minimizada a la barra inferior.
  bool _minimized = false;
  int? _slot;

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
    _ambiente = widget.ambiente;
    _cdEvento = widget.cdEvento.trim();
    if (_cdEvento.isEmpty) {
      // Abierto desde la toolbar sin evento: arranca en modo búsqueda.
      _headerFuture = null;
      _editandoEvento = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _eventoFocus.requestFocus(),
      );
    } else {
      _headerFuture = SirwebService().infoEventoHeader(
        _cdEvento,
        ambiente: _ambiente,
      );
    }
    _indexCtrl.addListener(() {
      final v = _indexCtrl.text.isNotEmpty;
      if (v != _hasText) setState(() => _hasText = v);
    });
    _cargarTopGuardado();
  }

  Future<void> _cargarTopGuardado() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTop = prefs.getInt(_kPrefTopEventoValor);
      if (savedTop != null && savedTop > 0 && mounted) {
        _topCtrl.text = savedTop.toString();
      }
    } catch (_) {}
  }

  Future<void> _guardarTop(int top) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kPrefTopEventoValor, top);
    } catch (_) {}
  }

  @override
  void dispose() {
    _MinimizedSlots.release(_slot);
    _indexCtrl.dispose();
    _topCtrl.dispose();
    _eventoCtrl.dispose();
    _eventoFocus.dispose();
    _tableVertCtrl.dispose();
    _tableHorizCtrl.dispose();
    super.dispose();
  }

  void _onToggleSelectAll(List<EventoValor> valores, bool? allSelected) {
    setState(() {
      if (allSelected == true) {
        _selectedRowIndices.clear();
        for (var i = 0; i < valores.length; i++) {
          _selectedRowIndices.add(i);
        }
      } else {
        _selectedRowIndices.clear();
      }
    });
  }

  void _onToggleRow(int index, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedRowIndices.add(index);
      } else {
        _selectedRowIndices.remove(index);
      }
    });
  }

  void _toggleCambiarEvento() {
    setState(() {
      _editandoEvento = !_editandoEvento;
      if (_editandoEvento) {
        _eventoCtrl.text = _cdEvento;
        _eventoCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _eventoCtrl.text.length,
        );
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _eventoFocus.requestFocus(),
        );
      }
    });
  }

  /// Carga otro evento reutilizando la misma ventana.
  void _cargarEvento(String cdEvento) {
    final nuevo = cdEvento.trim();
    if (nuevo.isEmpty) return;
    setState(() {
      if (nuevo != _cdEvento && _cdEvento.isNotEmpty) {
        _historial.remove(_cdEvento);
        _historial.add(_cdEvento);
        if (_historial.length > 10) _historial.removeAt(0);
      }
      _cdEvento = nuevo;
      _editandoEvento = false;
      _headerFuture = SirwebService().infoEventoHeader(
        _cdEvento,
        ambiente: _ambiente,
      );
      _valoresFuture = null;
      _hiddenCols = {};
      _selectedRowIndices.clear();
      _indexCtrl.clear();
    });
  }

  void _buscarValores() {
    final texto = _indexCtrl.text.trim();
    if (texto.isEmpty || _cdEvento.isEmpty) return;
    final topLimit = int.tryParse(_topCtrl.text.trim()) ?? 50;
    final effectiveTop = topLimit > 0 ? topLimit : 50;
    _guardarTop(effectiveTop);
    setState(() {
      _valoresFuture = SirwebService().valoresEvento(
        _cdEvento,
        deIndiceEvento: texto,
        ambiente: _ambiente,
        top: effectiveTop,
      );
      _hiddenCols = {};
      _selectedRowIndices.clear();
    });
  }

  void _cambiarAmbiente(String nuevo) {
    if (nuevo == _ambiente) return;
    setState(() {
      _ambiente = nuevo;
      _selectedRowIndices.clear();
      if (_cdEvento.isNotEmpty) {
        _headerFuture = SirwebService().infoEventoHeader(
          _cdEvento,
          ambiente: _ambiente,
        );
        if (_valoresFuture != null) {
          _buscarValores();
        }
      }
    });
  }

  void _limpiarBusqueda() {
    _indexCtrl.clear();
    setState(() {
      _valoresFuture = null;
      _hiddenCols = {};
      _selectedRowIndices.clear();
    });
  }

  /// Alterna entre ventana maximizada y el tamaño/posición previos,
  /// con la misma animación que el modal de snippets.
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (_maximized) {
      _modalW = (size.width - 48).clamp(420.0, size.width);
      _modalH = (size.height - 48).clamp(320.0, size.height);
    } else {
      _modalW ??= (size.width * 0.80).clamp(520.0, 820.0);
      _modalH ??= (size.height * 0.78).clamp(440.0, 680.0);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accentColor = Color(0xFF0078D4);
    final gripColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.18,
    );

    // Geometría efectiva: minimizada ocupa solo la barra de título.
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
                  child: _minimized
                      ? MinimizedWindowCard(
                          title: 'Evento ${widget.cdEvento}',
                          icon: Icons.flash_on_rounded,
                          accentColor: accentColor,
                          badge: 'EVENTO DML',
                          onRestore: _toggleMinimize,
                          onClose: _cerrar,
                        )
                      : OverflowBox(
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
                                    child: _buildBody(
                                      context,
                                      isDark,
                                      accentColor,
                                    ),
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
                        420.0,
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
            // Bottom-right corner resize handle (visible grip)
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
                        420.0,
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
                  Icons.bolt_rounded,
                  size: _minimized ? 15 : 20,
                  color: accent,
                ),
              ),
              SizedBox(width: _minimized ? 8 : 12),
              if (_minimized)
                Expanded(
                  child: Text(
                    _cdEvento.isEmpty
                        ? 'Información de Evento'
                        : 'Evento $_cdEvento',
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
                        'Información de Evento',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white38 : Colors.black38,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (_editandoEvento)
                        SizedBox(
                          height: 30,
                          child: TextField(
                            controller: _eventoCtrl,
                            focusNode: _eventoFocus,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Consolas',
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Código de evento',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF1E1E1E)
                                  : Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              suffixIcon: IconButton(
                                tooltip: 'Consultar',
                                icon: const Icon(Icons.arrow_forward, size: 16),
                                onPressed: () =>
                                    _cargarEvento(_eventoCtrl.text),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                              ),
                            ),
                            onSubmitted: _cargarEvento,
                          ),
                        )
                      else
                        Text(
                          _cdEvento.isEmpty ? '—' : _cdEvento,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Consolas',
                            color: _cdEvento.isEmpty
                                ? (isDark ? Colors.white38 : Colors.black38)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              if (_historial.isNotEmpty && !_editandoEvento && !_minimized)
                PopupMenuButton<String>(
                  tooltip: 'Eventos consultados',
                  icon: const Icon(Icons.history, size: 18),
                  padding: EdgeInsets.zero,
                  onSelected: _cargarEvento,
                  itemBuilder: (_) => _historial.reversed
                      .map(
                        (e) => PopupMenuItem<String>(
                          value: e,
                          child: Text(
                            e,
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (!_minimized)
                IconButton(
                  tooltip: _editandoEvento
                      ? 'Cancelar'
                      : 'Consultar otro evento en esta ventana',
                  icon: Icon(
                    _editandoEvento ? Icons.close_rounded : Icons.manage_search,
                    size: 18,
                    color: _editandoEvento ? null : accent,
                  ),
                  onPressed: _toggleCambiarEvento,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              if (!_minimized) ...[
                AmbienteSelector(value: _ambiente, onChanged: _cambiarAmbiente),
                const SizedBox(width: 8),
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

  Widget _buildBody(BuildContext context, bool isDark, Color accent) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    final labelColor = isDark ? Colors.white54 : Colors.black45;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Definición (carga inmediata) ──────────────────────────────
        if (_headerFuture == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: Text(
              'Ingresá un código de evento para consultarlo.',
              style: TextStyle(fontSize: 12, color: labelColor),
            ),
          )
        else
          FutureBuilder<EventoInfo>(
            future: _headerFuture,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Text(
                    snap.error.toString(),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                );
              }
              final info = snap.data!;
              final hasContent =
                  info.deEvento != null ||
                  info.tipo != null ||
                  info.datos.isNotEmpty ||
                  info.cdComponente != null;
              if (!hasContent) return const SizedBox.shrink();
              return _buildDefinicionCard(isDark, accent, info);
            },
          ),

        // ── Separador entre definición y valores ─────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(child: Divider(color: borderColor, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'VALORES',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              Expanded(child: Divider(color: borderColor, height: 1)),
            ],
          ),
        ),

        // ── Buscador por índice ───────────────────────────────────────
        _buildSearchSection(isDark, accent),

        // ── Resultados ────────────────────────────────────────────────
        Expanded(
          child: _buildValoresSection(context, isDark, borderColor, labelColor),
        ),
      ],
    );
  }

  Widget _buildDefinicionCard(bool isDark, Color accent, EventoInfo info) {
    final labelColor = isDark ? Colors.white54 : Colors.black45;
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.87)
        : Colors.black87;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.7);

    // Scalar properties to display when non-null
    final props = <(String, String)>[
      if (info.tipo != null) ('Tipo', info.tipo!),
      if (info.cdComponente != null)
        ('Componente', info.cdComponente.toString()),
      if (info.deVaComponente != null) ('Va. componente', info.deVaComponente!),
      if (info.deVaMinima != null) ('Va. mínima', info.deVaMinima!),
      if (info.deVaMaxima != null) ('Va. máxima', info.deVaMaxima!),
      if (info.deVaAdicional != null) ('Va. adicional', info.deVaAdicional!),
    ];

    // Boolean flags to display when non-null
    final flags = <(String, bool)>[
      if (info.inUsoUltDato != null) ('Usa último dato', info.inUsoUltDato!),
      if (info.inUsoTasa != null) ('Usa tasa', info.inUsoTasa!),
      if (info.inManejaMinMax != null) ('Maneja mín/máx', info.inManejaMinMax!),
      if (info.inManejaAdicional != null)
        ('Maneja adicional', info.inManejaAdicional!),
      if (info.inMinimoRequerido != null)
        ('Mínimo requerido', info.inMinimoRequerido!),
      if (info.inMaximoRequerido != null)
        ('Máximo requerido', info.inMaximoRequerido!),
      if (info.inAplicaTasaCambio != null)
        ('Aplica tasa cambio', info.inAplicaTasaCambio!),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      constraints: const BoxConstraints(maxHeight: 230),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildMiniIconButton(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copiar toda la información',
                  color: accent,
                  onTap: () => _copyDefinicionCard(info, props, flags),
                ),
              ],
            ),
            // ── Descripción ──────────────────────────────────────────
            if (info.deEvento != null) ...[
              Text(
                'Definición',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: accent,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                info.deEvento!,
                style: TextStyle(fontSize: 13, color: textColor),
              ),
            ],

            // ── Datos (índices asociados al evento) ──────────────────
            if (info.datos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'DATOS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: accent,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              for (final d in info.datos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          '${d.numero}',
                          style: TextStyle(
                            fontSize: 11,
                            color: labelColor,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 64,
                        child: Text(
                          '${d.cdDato}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Consolas',
                            color: subColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          d.deDato,
                          style: TextStyle(fontSize: 12, color: textColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _buildMiniIconButton(
                        icon: Icons.copy_rounded,
                        tooltip: 'Copiar dato',
                        color: subColor,
                        onTap: () => _copyDato(d),
                      ),
                      _buildMiniIconButton(
                        icon: Icons.open_in_new_rounded,
                        tooltip: 'Abrir InfoDato',
                        color: subColor,
                        onTap: () => showInfoDatoWindow(
                          context,
                          d.cdDato.toString(),
                          _ambiente,
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            // ── Propiedades escalares ─────────────────────────────────
            if (props.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final (label, value) in props)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          label,
                          style: TextStyle(fontSize: 11, color: labelColor),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: subColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            // ── Flags booleanos ───────────────────────────────────────
            if (flags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (label, value) in flags)
                    _buildFlagChip(isDark, accent, label, value),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFlagChip(bool isDark, Color accent, String label, bool value) {
    final color = value
        ? (isDark ? Colors.teal.shade300 : Colors.teal.shade700)
        : (isDark ? Colors.red.shade300 : Colors.red.shade600);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            value ? Icons.check_rounded : Icons.close_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _buildSearchSection(bool isDark, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _indexCtrl,
                style: const TextStyle(fontSize: 13),
                onSubmitted: (_) => _buscarValores(),
                decoration: InputDecoration(
                  hintText: 'Índice del evento (DE_INDICE_EVENTO)…',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: Icon(
                    Icons.tag_rounded,
                    size: 16,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  suffixIcon: _hasText
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: _limpiarBusqueda,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF2D2D30)
                      : const Color(0xFFF0F2F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: accent.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 95,
            height: 34,
            child: TextField(
              controller: _topCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              onChanged: (val) {
                final n = int.tryParse(val.trim());
                if (n != null && n > 0) {
                  _guardarTop(n);
                }
              },
              onSubmitted: (_) => _buscarValores(),
              decoration: InputDecoration(
                prefixText: 'Top: ',
                prefixStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
                hintText: '50',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2D2D30)
                    : const Color(0xFFF0F2F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: accent.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: FilledButton.icon(
              onPressed: _buscarValores,
              icon: const Icon(Icons.search, size: 15),
              label: const Text('Buscar', style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValoresSection(
    BuildContext context,
    bool isDark,
    Color borderColor,
    Color labelColor,
  ) {
    final vf = _valoresFuture;
    if (vf == null) {
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
              'Ingrese un índice para consultar los valores',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<List<EventoValor>>(
      future: vf,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
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
                    snap.error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final valores = snap.data!;
        if (valores.isEmpty) {
          return Center(
            child: Text(
              'Sin resultados para el índice indicado',
              style: TextStyle(color: labelColor),
            ),
          );
        }
        return FutureBuilder<List<({String name, String dataType})>>(
          future: SchemaService.instance.getColumns(
            'EVENTOVALOR',
            ambiente: _ambiente,
          ),
          builder: (ctx, schemaSnap) {
            final dbCols = schemaSnap.data ?? const [];
            final allCols = _detectColumns(valores, dbCols: dbCols);
            final effectiveCols = _hiddenCols.isEmpty
                ? allCols
                : allCols.where((c) => !_hiddenCols.contains(c)).toList();
            return Column(
              children: [
                _buildTableToolbar(
                  context,
                  isDark,
                  borderColor,
                  allCols,
                  effectiveCols,
                  valores,
                ),
                Expanded(
                  child: _buildDataTable(
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
      },
    );
  }

  /// Lista exhaustiva por defecto de columnas de EVENTOVALOR por si falla la
  /// consulta al esquema o se trabaja offline.
  static const _kDefaultEventoValorColumns = <String>[
    'VERSION',
    'CD_EVENTO',
    'DE_INDICE_EVENTO',
    'FE_EFECTIVA_EVENTO',
    'FE_TERMINO_EVENTO',
    'VA_DATO1',
    'VA_DATO2',
    'VA_DATO3',
    'VA_DATO4',
    'VA_DATO5',
    'VA_DATO6',
    'VA_DATO7',
    'VA_DATO8',
    'VA_DATO9',
    'VA_DATO10',
    'VA_COMPONENTE',
    'VA_MINIMO_COMPONENTE',
    'VA_MAXIMO_COMPONENTE',
    'MT_INTERVALO_INFERIOR_A',
    'MT_INTERVALO_SUPERIOR_A',
    'MT_INTERVALO_INFERIOR_B',
    'MT_INTERVALO_SUPERIOR_B',
    'CD_INTERVALO_INFERIOR',
    'CD_INTERVALO_SUPERIOR',
    'VA_COMPONENTE_ADICIONAL',
    'PO_DEDUCIBLE',
    'CD_CATEGORIA',
    'CD_PERSONA_PROVEEDOR',
    'CD_CONCEPTO',
    'CD_SUB_CONCEPTO',
    'FE_INICIO_REGISTRO',
    'FE_TERMINO_REGISTRO',
    'FE_MODIFICACION',
    'CD_USUARIO',
  ];

  /// Detect which columns to show. Combina las columnas del diccionario de datos
  /// de EVENTOVALOR con las devueltas en raw para que se visualicen todos los campos.
  List<String> _detectColumns(
    List<EventoValor> valores, {
    List<({String name, String dataType})> dbCols = const [],
  }) {
    final result = <String>[];
    final seen = <String>{};

    void addCol(String col) {
      final norm = col.trim();
      if (norm.isEmpty) return;
      if (seen.add(norm.toUpperCase())) {
        result.add(norm);
      }
    }

    if (dbCols.isNotEmpty) {
      for (final c in dbCols) {
        addCol(c.name);
      }
    } else {
      for (final c in _kDefaultEventoValorColumns) {
        addCol(c);
      }
    }

    // Agregar cualquier otra propiedad adicional que venga en raw
    for (final v in valores.take(10)) {
      for (final k in v.raw.keys) {
        final kUpper = k.toUpperCase();
        final kClean = k.replaceAll('_', '').toUpperCase();
        final alias =
            _kKnownDbColumnAliases[kClean] ?? _kKnownDbColumnAliases[kUpper];
        if (alias != null) {
          final aliasUpper = alias.toUpperCase();
          final aliasClean = aliasUpper.replaceAll('_', '');
          if (!seen.contains(aliasUpper) && !seen.contains(aliasClean)) {
            addCol(alias);
          }
        } else if (!seen.contains(kUpper) && !seen.contains(kClean)) {
          addCol(k);
        }
      }
    }

    return result;
  }

  Widget _buildDataTable(
    bool isDark,
    Color borderColor,
    List<String> cols,
    List<EventoValor> valores,
  ) {
    return InfoEventoVirtualTable(
      isDark: isDark,
      borderColor: borderColor,
      cols: cols,
      valores: valores,
      cdEvento: _cdEvento,
      vertCtrl: _tableVertCtrl,
      horizCtrl: _tableHorizCtrl,
      selectedRowIndices: _selectedRowIndices,
      onToggleSelectAll: (val) => _onToggleSelectAll(valores, val),
      onToggleRow: _onToggleRow,
    );
  }

  /// Resuelve el valor de una celda para la columna dada, buscando en `raw`
  /// tanto por el nombre exacto como por mayúsculas, alias y sin guiones bajos.
  /// Si la columna corresponde a `CD_EVENTO` y no viene con valor, devuelve `_cdEvento`.
  String _cellValue(EventoValor item, String col) {
    final colUpper = col.toUpperCase();
    final colClean = colUpper.replaceAll('_', '');

    if (colUpper == 'CD_EVENTO' || colClean == 'CDEVENTO') {
      final direct =
          item.raw[col] ??
          item.raw['cdEvento'] ??
          item.raw['CD_EVENTO'] ??
          item.raw['cdevento'];
      final val = direct?.toString().trim();
      return (val == null || val.isEmpty) ? _cdEvento : val;
    }

    if (item.raw.containsKey(col)) {
      return item.raw[col]?.toString() ?? '';
    }

    for (final entry in item.raw.entries) {
      final kUpper = entry.key.toUpperCase();
      final kClean = kUpper.replaceAll('_', '');
      if (kUpper == colUpper || kClean == colClean) {
        return entry.value?.toString() ?? '';
      }
      final alias =
          _kKnownDbColumnAliases[kClean] ?? _kKnownDbColumnAliases[kUpper];
      if (alias != null && alias.toUpperCase() == colUpper) {
        return entry.value?.toString() ?? '';
      }
    }

    return '';
  }

  String _colLabel(String col) {
    final upper = col.toUpperCase();
    final clean = upper.replaceAll('_', '');

    const exactLabels = <String, String>{
      'VERSION': 'Versión',
      'CD_EVENTO': 'Evento',
      'DE_INDICE_EVENTO': 'Descripción índice',
      'FE_EFECTIVA_EVENTO': 'Fecha efectiva',
      'FE_TERMINO_EVENTO': 'Fecha término',
      'VA_DATO1': 'Valor Dato 1',
      'VA_DATO2': 'Valor Dato 2',
      'VA_DATO3': 'Valor Dato 3',
      'VA_DATO4': 'Valor Dato 4',
      'VA_DATO5': 'Valor Dato 5',
      'VA_DATO6': 'Valor Dato 6',
      'VA_DATO7': 'Valor Dato 7',
      'VA_DATO8': 'Valor Dato 8',
      'VA_DATO9': 'Valor Dato 9',
      'VA_DATO10': 'Valor Dato 10',
      'VA_COMPONENTE': 'Valor componente',
      'VA_MINIMO_COMPONENTE': 'Mín. componente',
      'VA_MAXIMO_COMPONENTE': 'Máx. componente',
      'MT_INTERVALO_INFERIOR_A': 'Intervalo inf. A',
      'MT_INTERVALO_SUPERIOR_A': 'Intervalo sup. A',
      'MT_INTERVALO_INFERIOR_B': 'Intervalo inf. B',
      'MT_INTERVALO_SUPERIOR_B': 'Intervalo sup. B',
      'CD_INTERVALO_INFERIOR': 'Cód. int. inferior',
      'CD_INTERVALO_SUPERIOR': 'Cód. int. superior',
      'VA_COMPONENTE_ADICIONAL': 'Componente adicional',
      'PO_DEDUCIBLE': '% Deducible',
      'CD_CATEGORIA': 'Categoría',
      'CD_PERSONA_PROVEEDOR': 'Proveedor',
      'CD_CONCEPTO': 'Concepto',
      'CD_SUB_CONCEPTO': 'Subconcepto',
      'FE_INICIO_REGISTRO': 'Fecha inicio reg.',
      'FE_TERMINO_REGISTRO': 'Fecha término reg.',
      'FE_MODIFICACION': 'Fecha modif.',
      'CD_USUARIO': 'Usuario',
      'INDICE': 'Índice',
      'VALOR': 'Valor',
      'DESCRIPCION': 'Descripción',
    };

    if (exactLabels.containsKey(upper)) return exactLabels[upper]!;
    if (exactLabels.containsKey(clean)) return exactLabels[clean]!;

    const labels = <String, String>{
      'indice': 'Índice',
      'cdIndice': 'Índice',
      'nuIndice': 'Nº Índice',
      'index': 'Índice',
      'valor': 'Valor',
      'cdValor': 'Valor',
      'vaValor': 'Valor',
      'value': 'Valor',
      'descripcion': 'Descripción',
      'deValor': 'Descripción',
      'deIndiceEvento': 'Descripción índice',
      'description': 'Descripción',
      'cdEvento': 'Evento',
      'feEfectivaEvento': 'Fecha efectiva',
      'feEfectiva': 'Fecha efectiva',
    };
    return labels[col] ?? col;
  }

  bool _isNumericField(String col) {
    final upper = col.toUpperCase();
    final clean = upper.replaceAll('_', '');
    if (upper == 'VERSION' ||
        upper.startsWith('VA_') ||
        upper.startsWith('MT_') ||
        upper.startsWith('PO_') ||
        upper == 'CD_INDICE' ||
        upper == 'INDICE' ||
        clean == 'CDINDICE' ||
        clean == 'VERSION' ||
        clean.startsWith('VA') ||
        clean.startsWith('MT') ||
        clean.startsWith('PO')) {
      return true;
    }
    const numericFields = [
      'indice',
      'cdIndice',
      'index',
      'valor',
      'cdValor',
      'value',
    ];
    return numericFields.contains(col);
  }

  // ── Toolbar de la tabla ─────────────────────────────────────────────────

  Widget _buildTableToolbar(
    BuildContext context,
    bool isDark,
    Color borderColor,
    List<String> allCols,
    List<String> effectiveCols,
    List<EventoValor> valores,
  ) {
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA);
    final labelColor = isDark ? Colors.white54 : Colors.black45;
    final hiddenCount = allCols.length - effectiveCols.length;
    final selectedCount = _selectedRowIndices.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Text(
            selectedCount > 0
                ? '$selectedCount de ${valores.length} seleccionado${selectedCount != 1 ? 's' : ''}'
                : '${valores.length} registro${valores.length != 1 ? 's' : ''}',
            style: TextStyle(fontSize: 11, color: labelColor),
          ),
          const Spacer(),
          // Selector de columnas
          _toolbarBtn(
            isDark,
            Icons.view_column_outlined,
            hiddenCount > 0 ? 'Columnas ($hiddenCount ocultas)' : 'Columnas',
            () => _showColumnSelector(context, allCols),
          ),
          const SizedBox(width: 4),
          // Generar INSERT/MERGE
          _toolbarBtn(
            isDark,
            Icons.data_object_outlined,
            'Generar SQL',
            () => _abrirGeneradorDml(context, effectiveCols, valores),
            tooltip: selectedCount > 0
                ? 'Generar INSERT / MERGE ($selectedCount filas seleccionadas)'
                : 'Generar INSERT / MERGE (todas las filas)',
          ),
          const SizedBox(width: 4),
          // Copiar al portapapeles
          _toolbarBtn(
            isDark,
            Icons.copy_outlined,
            'Copiar',
            () => _copyToCsv(effectiveCols, valores),
          ),
          const SizedBox(width: 4),
          // Exportar CSV
          _toolbarBtn(
            isDark,
            Icons.download_outlined,
            'Exportar CSV',
            () => _exportCsv(effectiveCols, valores),
          ),
        ],
      ),
    );
  }

  Widget _toolbarBtn(
    bool isDark,
    IconData icon,
    String label,
    VoidCallback onTap, {
    String? tooltip,
  }) {
    final color = isDark ? Colors.white54 : Colors.black54;
    final btn = InkWell(
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
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }

  void _showColumnSelector(BuildContext context, List<String> allCols) {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
                          _colLabel(col),
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          col,
                          style: const TextStyle(fontSize: 10),
                        ),
                        value: !_hiddenCols.contains(col),
                        onChanged: (checked) {
                          // Prevent hiding every column
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
                          setDialogState(() {});
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
                setDialogState(() {});
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

  // ── Generación de INSERT / MERGE (DML) ───────────────────────────────

  /// Mapeo canónico entre abreviaciones/claves devueltas por la API de backend
  /// y los nombres exactos y originales de columnas en la tabla EVENTOVALOR.
  static const _kKnownDbColumnAliases = <String, String>{
    'MTINTINFERIORA': 'MT_INTERVALO_INFERIOR_A',
    'MTINTSUPERIORA': 'MT_INTERVALO_SUPERIOR_A',
    'MTINTINFERIORB': 'MT_INTERVALO_INFERIOR_B',
    'MTINTSUPERIORB': 'MT_INTERVALO_SUPERIOR_B',
    'CDINTINFERIOR': 'CD_INTERVALO_INFERIOR',
    'CDINTSUPERIOR': 'CD_INTERVALO_SUPERIOR',
    'VACOMPONENTE': 'VA_COMPONENTE',
    'VAMINIMOCOMPONENTE': 'VA_MINIMO_COMPONENTE',
    'VAMAXIMOCOMPONENTE': 'VA_MAXIMO_COMPONENTE',
    'VACOMPONENTEADICIONAL': 'VA_COMPONENTE_ADICIONAL',
    'PODEDUCIBLE': 'PO_DEDUCIBLE',
    'CDCATEGORIA': 'CD_CATEGORIA',
    'CDPERSONAPROVEEDOR': 'CD_PERSONA_PROVEEDOR',
    'CDCONCEPTO': 'CD_CONCEPTO',
    'CDSUBCONCEPTO': 'CD_SUB_CONCEPTO',
    'FEEFECTIVAEVENTO': 'FE_EFECTIVA_EVENTO',
    'FETERMINOEVENTO': 'FE_TERMINO_EVENTO',
    'FEINICIOREGISTRO': 'FE_INICIO_REGISTRO',
    'FETERMINOREGISTRO': 'FE_TERMINO_REGISTRO',
    'FEMODIFICACION': 'FE_MODIFICACION',
    'CDUSUARIO': 'CD_USUARIO',
    'DEINDICEEVENTO': 'DE_INDICE_EVENTO',
    'CDEVENTO': 'CD_EVENTO',
  };

  Future<SqlQueryResult> _buildSqlQueryResult(
    List<String> visibleCols,
    List<EventoValor> valores,
  ) async {
    // Consultar las columnas del esquema de EVENTOVALOR
    final dbColumns = await SchemaService.instance.getColumns(
      'EVENTOVALOR',
      ambiente: _ambiente,
    );

    final dbColMap = <String, ({String name, String dataType})>{};
    for (final col in dbColumns) {
      final clean = col.name.replaceAll('_', '').toUpperCase();
      dbColMap[clean] = col;
      dbColMap[col.name.toUpperCase()] = col;
    }

    final sqlCols = <SqlColumn>[];
    final seenSqlColNames = <String>{};
    final resolvedColIndices = <int>[];

    for (var idx = 0; idx < visibleCols.length; idx++) {
      final col = visibleCols[idx];
      final upper = col.toUpperCase();
      final clean = upper.replaceAll('_', '');
      var matched = dbColMap[upper] ?? dbColMap[clean];
      if (matched == null && _kKnownDbColumnAliases.containsKey(clean)) {
        final aliasTarget = _kKnownDbColumnAliases[clean]!;
        matched = dbColMap[aliasTarget];
        if (matched == null) {
          final colName = aliasTarget;
          if (seenSqlColNames.add(colName.toUpperCase())) {
            sqlCols.add(
              SqlColumn(
                name: colName,
                dataType: _isNumericField(col) ? 'NUMBER' : 'VARCHAR2',
              ),
            );
            resolvedColIndices.add(idx);
          }
          continue;
        }
      }

      final colName = matched?.name ?? upper;
      if (seenSqlColNames.add(colName.toUpperCase())) {
        sqlCols.add(
          SqlColumn(
            name: colName,
            dataType:
                matched?.dataType ??
                (_isNumericField(col) ? 'NUMBER' : 'VARCHAR2'),
          ),
        );
        resolvedColIndices.add(idx);
      }
    }

    final sqlRows = [
      for (final v in valores)
        [
          for (final idx in resolvedColIndices)
            () {
              final col = visibleCols[idx];
              final colUpper = col.toUpperCase();
              final colClean = colUpper.replaceAll('_', '');
              if (colUpper == 'CD_EVENTO' || colClean == 'CDEVENTO') {
                final direct =
                    v.raw[col] ??
                    v.raw['cdEvento'] ??
                    v.raw['CD_EVENTO'] ??
                    v.raw['cdevento'];
                final str = direct?.toString().trim();
                return (str == null || str.isEmpty) ? _cdEvento : direct;
              }

              if (v.raw.containsKey(col)) {
                return v.raw[col];
              }

              for (final entry in v.raw.entries) {
                final kUpper = entry.key.toUpperCase();
                final kClean = kUpper.replaceAll('_', '');
                if (kUpper == colUpper || kClean == colClean) {
                  return entry.value;
                }
                final alias =
                    _kKnownDbColumnAliases[kClean] ??
                    _kKnownDbColumnAliases[kUpper];
                if (alias != null &&
                    (alias.toUpperCase() == colUpper ||
                        alias.replaceAll('_', '').toUpperCase() == colClean)) {
                  return entry.value;
                }
              }

              return null;
            }(),
        ],
    ];

    return SqlQueryResult(
      columns: sqlCols,
      rows: sqlRows,
      returnedRows: valores.length,
      truncated: false,
      durationMs: 0,
    );
  }

  Future<void> _abrirGeneradorDml(
    BuildContext context,
    List<String> cols,
    List<EventoValor> valores,
  ) async {
    if (valores.isEmpty) return;
    final rowIndexes = _selectedRowIndices.isEmpty
        ? List<int>.generate(valores.length, (i) => i)
        : (_selectedRowIndices.toList()..sort());

    final sqlResult = await _buildSqlQueryResult(cols, valores);
    if (!context.mounted) return;

    showSqlDmlGeneratorDialog(
      context,
      result: sqlResult,
      rowIndexes: rowIndexes,
      suggestedTable: 'EVENTOVALOR',
      ambiente: _ambiente,
    );
  }

  // ── Exportar / copiar ───────────────────────────────────────────────────

  String _buildCsv(List<String> cols, List<EventoValor> valores) {
    final buf = StringBuffer();
    buf.writeln(cols.map((c) => _csvEscape(_colLabel(c))).join(','));
    for (final v in valores) {
      buf.writeln(cols.map((c) => _csvEscape(_cellValue(v, c))).join(','));
    }
    return buf.toString();
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _copyToCsv(List<String> cols, List<EventoValor> valores) async {
    final csv = _buildCsv(cols, valores);
    await Clipboard.setData(ClipboardData(text: csv));
    AppToast.success(
      'Copiado al portapapeles — ${valores.length} fila${valores.length != 1 ? 's' : ''}',
    );
  }

  Widget _buildMiniIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 13, color: color),
        ),
      ),
    );
  }

  Future<void> _copyDefinicionCard(
    EventoInfo info,
    List<(String, String)> props,
    List<(String, bool)> flags,
  ) async {
    final buf = StringBuffer();
    if (info.deEvento != null) {
      buf.writeln('Definición: ${info.deEvento}');
    }
    if (info.datos.isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln('DATOS');
      for (final d in info.datos) {
        buf.writeln('${d.numero}\t${d.cdDato}\t${d.deDato}');
      }
    }
    if (props.isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      for (final (label, value) in props) {
        buf.writeln('$label: $value');
      }
    }
    if (flags.isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      for (final (label, value) in flags) {
        buf.writeln('$label: ${value ? 'Sí' : 'No'}');
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString().trimRight()));
    AppToast.success('Información copiada al portapapeles');
  }

  Future<void> _copyDato(EventoDato d) async {
    await Clipboard.setData(ClipboardData(text: '${d.cdDato} - ${d.deDato}'));
    AppToast.success('Dato copiado al portapapeles');
  }

  Future<void> _exportCsv(List<String> cols, List<EventoValor> valores) async {
    final csv = _buildCsv(cols, valores);
    final bytes = utf8.encode(csv);
    final path = await FilePicker.saveFile(
      dialogTitle: 'Exportar CSV',
      fileName: 'evento_$_cdEvento.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: bytes,
      lockParentWindow: true,
    );
    if (path != null) {
      AppToast.success('CSV exportado correctamente');
    }
  }
}

// Draws the classic 3-dot resize grip in the bottom-right corner
class _GripPainter extends CustomPainter {
  final Color color;
  const _GripPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const r = 2.0;
    const gap = 5.0;
    // 3 dots on the diagonal
    for (var i = 0; i < 3; i++) {
      final offset = Offset(
        size.width - gap * i - r,
        size.height - gap * i - r,
      );
      canvas.drawCircle(offset, r, paint);
    }
  }

  @override
  bool shouldRepaint(_GripPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Grilla Virtualizada de InfoEvento (two_dimensional_scrollables)
// ─────────────────────────────────────────────────────────────────────────────

class InfoEventoVirtualTable extends StatefulWidget {
  final bool isDark;
  final Color borderColor;
  final List<String> cols;
  final List<EventoValor> valores;
  final String cdEvento;
  final ScrollController vertCtrl;
  final ScrollController horizCtrl;
  final Set<int> selectedRowIndices;
  final ValueChanged<bool?> onToggleSelectAll;
  final void Function(int index, bool? selected) onToggleRow;

  const InfoEventoVirtualTable({
    super.key,
    required this.isDark,
    required this.borderColor,
    required this.cols,
    required this.valores,
    required this.cdEvento,
    required this.vertCtrl,
    required this.horizCtrl,
    required this.selectedRowIndices,
    required this.onToggleSelectAll,
    required this.onToggleRow,
  });

  @override
  State<InfoEventoVirtualTable> createState() => _InfoEventoVirtualTableState();
}

class _InfoEventoVirtualTableState extends State<InfoEventoVirtualTable> {
  static const double _headerHeight = 32.0;
  static const double _rowHeight = 30.0;
  static const double _checkboxColWidth = 44.0;

  late List<List<String>> _cellMatrix;
  late List<double> _colWidths;
  late List<bool> _colIsNumeric;

  @override
  void initState() {
    super.initState();
    _recomputeData();
  }

  @override
  void didUpdateWidget(covariant InfoEventoVirtualTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valores != widget.valores ||
        oldWidget.cols != widget.cols ||
        oldWidget.cdEvento != widget.cdEvento) {
      _recomputeData();
    }
  }

  void _recomputeData() {
    final cols = widget.cols;
    final valores = widget.valores;
    final cdEvento = widget.cdEvento;

    _colIsNumeric = List<bool>.generate(
      cols.length,
      (c) => _isNumericField(cols[c]),
    );

    // Precomputar la matriz fila x columna en O(1) de renderizado
    _cellMatrix = List<List<String>>.generate(valores.length, (r) {
      final item = valores[r];
      return List<String>.generate(cols.length, (c) {
        return _resolveCellValue(item, cols[c], cdEvento);
      });
    });

    // Calcular anchos aproximados de columna basados en contenido y cabecera
    _colWidths = List<double>.generate(cols.length, (c) {
      final colName = cols[c];
      final headerText = _colLabel(colName);
      double maxLen = headerText.length.toDouble();

      // Muestra las primeras 40 filas para estimar el ancho sin costo excesivo
      final sampleCount = valores.length > 40 ? 40 : valores.length;
      for (var r = 0; r < sampleCount; r++) {
        final valLen = _cellMatrix[r][c].length;
        if (valLen > maxLen) {
          maxLen = valLen.toDouble();
        }
      }

      // 7.8 px por caracter + 24px de padding; acotado entre 85 y 420 px
      final computed = (maxLen * 7.8) + 24.0;
      return computed.clamp(85.0, 420.0);
    });
  }

  static String _resolveCellValue(
    EventoValor item,
    String col,
    String cdEvento,
  ) {
    final colUpper = col.toUpperCase();
    final colClean = colUpper.replaceAll('_', '');

    if (colUpper == 'CD_EVENTO' || colClean == 'CDEVENTO') {
      final direct =
          item.raw[col] ??
          item.raw['cdEvento'] ??
          item.raw['CD_EVENTO'] ??
          item.raw['cdevento'];
      final val = direct?.toString().trim();
      return (val == null || val.isEmpty) ? cdEvento : val;
    }

    if (item.raw.containsKey(col)) {
      return item.raw[col]?.toString() ?? '';
    }

    for (final entry in item.raw.entries) {
      final kUpper = entry.key.toUpperCase();
      final kClean = kUpper.replaceAll('_', '');
      if (kUpper == colUpper || kClean == colClean) {
        return entry.value?.toString() ?? '';
      }
      final alias =
          _InfoEventoModalState._kKnownDbColumnAliases[kClean] ??
          _InfoEventoModalState._kKnownDbColumnAliases[kUpper];
      if (alias != null && alias.toUpperCase() == colUpper) {
        return entry.value?.toString() ?? '';
      }
    }

    return '';
  }

  static bool _isNumericField(String col) {
    final upper = col.toUpperCase();
    final clean = upper.replaceAll('_', '');
    if (upper == 'VERSION' ||
        upper.startsWith('VA_') ||
        upper.startsWith('MT_') ||
        upper.startsWith('PO_') ||
        upper == 'CD_INDICE' ||
        upper == 'INDICE' ||
        clean == 'CDINDICE' ||
        clean == 'VERSION' ||
        clean.startsWith('VA') ||
        clean.startsWith('MT') ||
        clean.startsWith('PO')) {
      return true;
    }
    const numericFields = [
      'indice',
      'cdIndice',
      'index',
      'valor',
      'cdValor',
      'value',
    ];
    return numericFields.contains(col);
  }

  static String _colLabel(String col) {
    final upper = col.toUpperCase();
    final clean = upper.replaceAll('_', '');

    const exactLabels = <String, String>{
      'VERSION': 'Versión',
      'CD_EVENTO': 'Evento',
      'DE_INDICE_EVENTO': 'Descripción índice',
      'FE_EFECTIVA_EVENTO': 'Fecha efectiva',
      'FE_TERMINO_EVENTO': 'Fecha término',
      'VA_DATO1': 'Valor Dato 1',
      'VA_DATO2': 'Valor Dato 2',
      'VA_DATO3': 'Valor Dato 3',
      'VA_DATO4': 'Valor Dato 4',
      'VA_DATO5': 'Valor Dato 5',
      'VA_DATO6': 'Valor Dato 6',
      'VA_DATO7': 'Valor Dato 7',
      'VA_DATO8': 'Valor Dato 8',
      'VA_DATO9': 'Valor Dato 9',
      'VA_DATO10': 'Valor Dato 10',
      'VA_COMPONENTE': 'Valor componente',
      'VA_MINIMO_COMPONENTE': 'Mín. componente',
      'VA_MAXIMO_COMPONENTE': 'Máx. componente',
      'MT_INTERVALO_INFERIOR_A': 'Intervalo inf. A',
      'MT_INTERVALO_SUPERIOR_A': 'Intervalo sup. A',
      'MT_INTERVALO_INFERIOR_B': 'Intervalo inf. B',
      'MT_INTERVALO_SUPERIOR_B': 'Intervalo sup. B',
      'CD_INTERVALO_INFERIOR': 'Cód. int. inferior',
      'CD_INTERVALO_SUPERIOR': 'Cód. int. superior',
      'VA_COMPONENTE_ADICIONAL': 'Componente adicional',
      'PO_DEDUCIBLE': '% Deducible',
      'CD_CATEGORIA': 'Categoría',
      'CD_PERSONA_PROVEEDOR': 'Proveedor',
      'CD_CONCEPTO': 'Concepto',
      'CD_SUB_CONCEPTO': 'Subconcepto',
      'FE_INICIO_REGISTRO': 'Fecha inicio reg.',
      'FE_TERMINO_REGISTRO': 'Fecha término reg.',
      'FE_MODIFICACION': 'Fecha modif.',
      'CD_USUARIO': 'Usuario',
      'INDICE': 'Índice',
      'VALOR': 'Valor',
      'DESCRIPCION': 'Descripción',
    };

    if (exactLabels.containsKey(upper)) return exactLabels[upper]!;
    if (exactLabels.containsKey(clean)) return exactLabels[clean]!;

    const labels = <String, String>{
      'indice': 'Índice',
      'cdIndice': 'Índice',
      'nuIndice': 'Nº Índice',
      'index': 'Índice',
      'valor': 'Valor',
      'cdValor': 'Valor',
      'vaValor': 'Valor',
      'value': 'Valor',
      'descripcion': 'Descripción',
      'deValor': 'Descripción',
      'deIndiceEvento': 'Descripción índice',
      'description': 'Descripción',
      'cdEvento': 'Evento',
      'feEfectivaEvento': 'Fecha efectiva',
      'feEfectiva': 'Fecha efectiva',
    };
    return labels[col] ?? col;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final headerBg = isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA);
    final rowCount = widget.valores.length;
    final colCount = widget.cols.length;
    final allSelected =
        rowCount > 0 && widget.selectedRowIndices.length == rowCount;
    final hasSelection = widget.selectedRowIndices.isNotEmpty;

    final cellRightBorder = BorderSide(
      color: widget.borderColor.withValues(alpha: isDark ? 0.35 : 0.5),
      width: 0.5,
    );
    final cellBottomBorder = BorderSide(
      color: widget.borderColor.withValues(alpha: isDark ? 0.35 : 0.5),
      width: 0.5,
    );

    return Scrollbar(
      controller: widget.vertCtrl,
      thumbVisibility: true,
      trackVisibility: true,
      child: Scrollbar(
        controller: widget.horizCtrl,
        thumbVisibility: true,
        trackVisibility: true,
        notificationPredicate: (notif) =>
            notif.depth == 1 || notif.metrics.axis == Axis.horizontal,
        child: TableView.builder(
          verticalDetails: ScrollableDetails.vertical(
            controller: widget.vertCtrl,
          ),
          horizontalDetails: ScrollableDetails.horizontal(
            controller: widget.horizCtrl,
          ),
          pinnedRowCount: 1,
          pinnedColumnCount: 1,
          rowCount: rowCount + 1,
          columnCount: colCount + 1,
          rowBuilder: (int row) {
            return TableSpan(
              extent: FixedTableSpanExtent(
                row == 0 ? _headerHeight : _rowHeight,
              ),
              backgroundDecoration: row == 0
                  ? TableSpanDecoration(color: headerBg)
                  : null,
            );
          },
          columnBuilder: (int col) {
            return TableSpan(
              extent: FixedTableSpanExtent(
                col == 0 ? _checkboxColWidth : _colWidths[col - 1],
              ),
            );
          },
          cellBuilder: (BuildContext context, TableVicinity vicinity) {
            final row = vicinity.row;
            final col = vicinity.column;

            // 1. Esquina superior izquierda: Checkbox para seleccionar todo
            if (row == 0 && col == 0) {
              return TableViewCell(
                child: Container(
                  decoration: BoxDecoration(
                    color: headerBg,
                    border: Border(
                      right: cellRightBorder,
                      bottom: cellBottomBorder,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Checkbox(
                    value: allSelected ? true : (hasSelection ? null : false),
                    tristate: true,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: widget.onToggleSelectAll,
                  ),
                ),
              );
            }

            // 2. Encabezado de columnas (row == 0, col > 0)
            if (row == 0) {
              final c = col - 1;
              final colName = widget.cols[c];
              final label = _colLabel(colName);
              final isNumeric = _colIsNumeric[c];

              return TableViewCell(
                child: Container(
                  decoration: BoxDecoration(
                    color: headerBg,
                    border: Border(
                      right: cellRightBorder,
                      bottom: cellBottomBorder,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: isNumeric
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Tooltip(
                    message: colName,
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : Colors.black45,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              );
            }

            // 3. Columna de checkbox de fila (row > 0, col == 0)
            final r = row - 1;
            final isRowSelected = widget.selectedRowIndices.contains(r);
            final rowBg = isRowSelected
                ? (isDark ? const Color(0xFF1E3A5F) : const Color(0xFFD6E4FF))
                : (r.isOdd
                      ? (isDark
                            ? const Color(0xFF181818)
                            : const Color(0xFFF9FAFB))
                      : (isDark ? const Color(0xFF1F1F1F) : Colors.white));

            if (col == 0) {
              return TableViewCell(
                child: Container(
                  decoration: BoxDecoration(
                    color: rowBg,
                    border: Border(
                      right: cellRightBorder,
                      bottom: cellBottomBorder,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Checkbox(
                    value: isRowSelected,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) => widget.onToggleRow(r, val),
                  ),
                ),
              );
            }

            // 4. Celda de datos (row > 0, col > 0)
            final c = col - 1;
            final text = _cellMatrix[r][c];
            final isNumeric = _colIsNumeric[c];

            return TableViewCell(
              child: Container(
                decoration: BoxDecoration(
                  color: rowBg,
                  border: Border(
                    right: cellRightBorder,
                    bottom: cellBottomBorder,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: isNumeric
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: SelectableText(
                  text,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: isNumeric ? 'Consolas' : null,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.87)
                        : Colors.black87,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
