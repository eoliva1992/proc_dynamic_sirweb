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
  late Future<EventoInfo>? _headerFuture;
  Future<List<EventoValor>>? _valoresFuture;
  final _indexCtrl = TextEditingController();
  bool _hasText = false;
  Offset _position = Offset.zero;
  Set<String> _hiddenCols = {};
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
        ambiente: widget.ambiente,
      );
    }
    _indexCtrl.addListener(() {
      final v = _indexCtrl.text.isNotEmpty;
      if (v != _hasText) setState(() => _hasText = v);
    });
  }

  @override
  void dispose() {
    _MinimizedSlots.release(_slot);
    _indexCtrl.dispose();
    _eventoCtrl.dispose();
    _eventoFocus.dispose();
    _tableVertCtrl.dispose();
    _tableHorizCtrl.dispose();
    super.dispose();
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
        ambiente: widget.ambiente,
      );
      _valoresFuture = null;
      _hiddenCols = {};
      _indexCtrl.clear();
    });
  }

  void _buscarValores() {
    final texto = _indexCtrl.text.trim();
    if (texto.isEmpty || _cdEvento.isEmpty) return;
    setState(() {
      _valoresFuture = SirwebService().valoresEvento(
        _cdEvento,
        deIndiceEvento: texto,
        ambiente: widget.ambiente,
      );
      _hiddenCols = {};
    });
  }

  void _limpiarBusqueda() {
    _indexCtrl.clear();
    setState(() {
      _valoresFuture = null;
      _hiddenCols = {};
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
                    _cdEvento.isEmpty ? 'InfoEvento' : 'Evento $_cdEvento',
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
                        'InfoEvento',
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
        final allCols = _detectColumns(valores);
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
  }

  /// Detect which columns to show from the first few rows.
  List<String> _detectColumns(List<EventoValor> valores) {
    if (valores.isEmpty) return [];
    final keys = <String>{};
    for (final v in valores.take(5)) {
      keys.addAll(v.raw.keys);
    }
    // Prioritize known fields first
    const preferred = [
      'indice',
      'cdIndice',
      'index',
      'valor',
      'cdValor',
      'value',
      'descripcion',
      'deValor',
      'description',
    ];
    final ordered = <String>[
      ...preferred.where(keys.contains),
      ...keys.where((k) => !preferred.contains(k)),
    ];
    return ordered;
  }

  Widget _buildDataTable(
    bool isDark,
    Color borderColor,
    List<String> cols,
    List<EventoValor> valores,
  ) {
    final headerBg = isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA);

    // Outer Scrollbar handles horizontal scroll (depth==1); inner handles vertical (depth==0)
    return Scrollbar(
      controller: _tableHorizCtrl,
      thumbVisibility: true,
      trackVisibility: true,
      notificationPredicate: (n) => n.depth == 1,
      child: Scrollbar(
        controller: _tableVertCtrl,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: _tableVertCtrl,
          child: SingleChildScrollView(
            controller: _tableHorizCtrl,
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
                  DataColumn(
                    label: Text(_colLabel(col)),
                    numeric: _isNumericField(col),
                  ),
              ],
              rows: [
                for (final v in valores)
                  DataRow(
                    cells: [
                      for (final col in cols)
                        DataCell(
                          Text(
                            v.raw[col]?.toString() ?? '',
                            style: _isNumericField(col)
                                ? const TextStyle(fontFamily: 'Consolas')
                                : null,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _colLabel(String col) {
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
          // Selector de columnas
          _toolbarBtn(
            isDark,
            Icons.view_column_outlined,
            hiddenCount > 0 ? 'Columnas ($hiddenCount ocultas)' : 'Columnas',
            () => _showColumnSelector(context, allCols),
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

  // ── Exportar / copiar ───────────────────────────────────────────────────

  String _buildCsv(List<String> cols, List<EventoValor> valores) {
    final buf = StringBuffer();
    buf.writeln(cols.map((c) => _csvEscape(_colLabel(c))).join(','));
    for (final v in valores) {
      buf.writeln(
        cols.map((c) => _csvEscape(v.raw[c]?.toString() ?? '')).join(','),
      );
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
