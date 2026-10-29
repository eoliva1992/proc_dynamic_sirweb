part of 'code_editor_panel.dart';

/// Abre la ventana de InfoDato.
///
/// Se inserta en el overlay raíz (sin barrera modal) para poder minimizarla
/// y seguir trabajando en el editor.
void showInfoDatoWindow(
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

void _showInfoDatoModal(
  BuildContext context,
  String cdDatoStr,
  String ambiente,
) => showInfoDatoWindow(context, cdDatoStr, ambiente);

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
  late String _ambiente;
  int _tab = 0;
  late Future<List<DatoInfo>> _datoFuture;
  Future<TablaDefinicion>? _defFuture;
  Future<List<ValorTabla>>? _infoFuture;
  Future<List<TablaDefinicionAdicional>>? _defAdicionalFuture;
  Future<List<ValorTabla>>? _infoAdicionalFuture;
  int? _cdTabla;
  int _productosCount = 0;
  int _defAdicionalCount = 0;
  int _infoAdicionalCount = 0;

  /// Código de dato actualmente consultado.
  late String _cdDato;

  /// Historial de datos consultados en esta sesión.
  final List<String> _historial = [];

  /// Permite cambiar el dato a consultar directamente desde el encabezado.
  bool _editandoDato = false;
  final _datoCtrl = TextEditingController();
  final _datoFocus = FocusNode();

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
  final _tableVertCtrl = ScrollController();
  final _tableHorizCtrl = ScrollController();

  // Tabla Información selection and filters
  final Set<int> _selectedRowIndices = {};
  final _indexCtrl = TextEditingController();
  final _fechaDesdeCtrl = TextEditingController();
  final _fechaHastaCtrl = TextEditingController();
  int? _inSuspendido;
  Set<String> _hiddenCols = {};

  // Filtros avanzados y búsqueda para Tab 2 (Tabla Información)
  final _tab2GlobalSearchCtrl = TextEditingController();
  final _tab2DescCtrl = TextEditingController();
  final _tab2TablaCtrl = TextEditingController();
  final _tab2UsuarioCtrl = TextEditingController();
  final _tab2FeModifCtrl = TextEditingController();
  bool _tab2ShowAdvancedFilters = false;

  // Filtro de búsqueda para Tab 3 (Productos: código o descripción)
  final _tab3FilterCtrl = TextEditingController();

  // Filtros avanzados y búsqueda para Tab 5 (Información Adicional)
  final _tab5GlobalSearchCtrl = TextEditingController();
  final _tab5IndexCtrl = TextEditingController();
  final _tab5DescCtrl = TextEditingController();
  final _tab5TablaCtrl = TextEditingController();
  final _tab5UsuarioCtrl = TextEditingController();
  final _tab5FeDesdeCtrl = TextEditingController();
  final _tab5FeHastaCtrl = TextEditingController();
  final _tab5FeModifCtrl = TextEditingController();
  int? _tab5InSuspendido;
  bool _tab5ShowAdvancedFilters = false;

  @override
  void initState() {
    super.initState();
    _ambiente = widget.ambiente;
    _cdDato = widget.cdDatoStr.trim();
    if (_cdDato.isEmpty) {
      _editandoDato = true;
      _datoFuture = Future.value(<DatoInfo>[]);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _datoFocus.requestFocus(),
      );
    } else {
      _loadDato();
    }
  }

  @override
  void dispose() {
    _MinimizedSlots.release(_slot);
    _vertCtrl.dispose();
    _horizCtrl.dispose();
    _tableVertCtrl.dispose();
    _tableHorizCtrl.dispose();
    _indexCtrl.dispose();
    _fechaDesdeCtrl.dispose();
    _fechaHastaCtrl.dispose();
    _tab2GlobalSearchCtrl.dispose();
    _tab2DescCtrl.dispose();
    _tab2TablaCtrl.dispose();
    _tab2UsuarioCtrl.dispose();
    _tab2FeModifCtrl.dispose();
    _tab3FilterCtrl.dispose();
    _tab5GlobalSearchCtrl.dispose();
    _tab5IndexCtrl.dispose();
    _tab5DescCtrl.dispose();
    _tab5TablaCtrl.dispose();
    _tab5UsuarioCtrl.dispose();
    _tab5FeDesdeCtrl.dispose();
    _tab5FeHastaCtrl.dispose();
    _tab5FeModifCtrl.dispose();
    _datoCtrl.dispose();
    _datoFocus.dispose();
    super.dispose();
  }

  void _loadDato() {
    final parsed = int.tryParse(_cdDato);
    _datoFuture = SirwebService().buscarDato(
      cdDato: parsed,
      deDato: parsed == null && _cdDato.isNotEmpty ? _cdDato : null,
      ambiente: _ambiente,
    );
    _datoFuture.then((datos) {
      if (!mounted) return;
      final cdTabla = datos.isNotEmpty ? datos.first.cdTabla : null;
      setState(() {
        _cdTabla = cdTabla;
        _productosCount = datos.isNotEmpty ? datos.first.productos.length : 0;
      });
      if (cdTabla != null) {
        _verificarTablasAdicionales(cdTabla);
      }
    });
  }

  void _verificarTablasAdicionales(int cdTabla) {
    _defAdicionalFuture = SirwebService().infoTablaAdicional(
      cdTabla,
      ambiente: _ambiente,
    );
    _defAdicionalFuture!
        .then((items) {
          if (mounted) setState(() => _defAdicionalCount = items.length);
        })
        .catchError((_) {
          if (mounted) setState(() => _defAdicionalCount = 0);
        });

    _infoAdicionalFuture = SirwebService().valoresTablaAdicional(
      cdTabla,
      ambiente: _ambiente,
    );
    _infoAdicionalFuture!
        .then((items) {
          if (mounted) setState(() => _infoAdicionalCount = items.length);
        })
        .catchError((_) {
          if (mounted) setState(() => _infoAdicionalCount = 0);
        });
  }

  void _toggleCambiarDato() {
    setState(() {
      _editandoDato = !_editandoDato;
      if (_editandoDato) {
        _datoCtrl.text = _cdDato;
        _datoCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _datoCtrl.text.length,
        );
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _datoFocus.requestFocus(),
        );
      }
    });
  }

  void _cargarDato(String cdDato) {
    final nuevo = cdDato.trim();
    if (nuevo.isEmpty) return;
    setState(() {
      if (nuevo != _cdDato && _cdDato.isNotEmpty) {
        _historial.remove(_cdDato);
        _historial.add(_cdDato);
        if (_historial.length > 10) _historial.removeAt(0);
      }
      _cdDato = nuevo;
      _editandoDato = false;
      _tab = 0;
      _defFuture = null;
      _infoFuture = null;
      _defAdicionalFuture = null;
      _infoAdicionalFuture = null;
      _defAdicionalCount = 0;
      _infoAdicionalCount = 0;
      _loadDato();
    });
  }

  void _cambiarAmbiente(String nuevo) {
    if (nuevo == _ambiente) return;
    setState(() {
      _ambiente = nuevo;
      _defFuture = null;
      _infoFuture = null;
      _defAdicionalFuture = null;
      _infoAdicionalFuture = null;
      _defAdicionalCount = 0;
      _infoAdicionalCount = 0;
      _selectedRowIndices.clear();
      _loadDato();
      if (_tab == 1 && _cdTabla != null) {
        _defFuture = SirwebService().infoTabla(_cdTabla!, ambiente: _ambiente);
      } else if (_tab == 2 && _cdTabla != null) {
        _buscarInfo();
      } else if (_tab == 4 && _cdTabla != null) {
        _defAdicionalFuture = SirwebService().infoTablaAdicional(
          _cdTabla!,
          ambiente: _ambiente,
        );
      } else if (_tab == 5 && _cdTabla != null) {
        _buscarInfoAdicional();
      }
    });
  }

  void _selectTab(int idx) {
    if (idx == _tab) return;
    setState(() {
      _tab = idx;
      _hiddenCols = {};
      _selectedRowIndices.clear();
    });
    final cdTabla = _cdTabla;
    if (cdTabla == null) return;
    if (idx == 1 && _defFuture == null) {
      setState(
        () => _defFuture = SirwebService().infoTabla(
          cdTabla,
          ambiente: _ambiente,
        ),
      );
    } else if (idx == 2 && _infoFuture == null) {
      setState(
        () => _infoFuture = SirwebService().valoresTabla(
          cdTabla,
          ambiente: _ambiente,
        ),
      );
    } else if (idx == 4 && _defAdicionalFuture == null) {
      setState(
        () => _defAdicionalFuture = SirwebService().infoTablaAdicional(
          cdTabla,
          ambiente: _ambiente,
        ),
      );
    } else if (idx == 5 && _infoAdicionalFuture == null) {
      setState(
        () => _infoAdicionalFuture = SirwebService().valoresTablaAdicional(
          cdTabla,
          ambiente: _ambiente,
        ),
      );
    }
  }

  void _buscarInfo() {
    final cdTabla = _cdTabla;
    if (cdTabla == null) return;
    setState(() {
      _hiddenCols = {};
      _selectedRowIndices.clear();
      _infoFuture = SirwebService().valoresTabla(
        cdTabla,
        ambiente: _ambiente,
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

  void _buscarInfoAdicional() {
    final cdTabla = _cdTabla;
    if (cdTabla == null) return;
    setState(() {
      _hiddenCols = {};
      _selectedRowIndices.clear();
      _infoAdicionalFuture = SirwebService().valoresTablaAdicional(
        cdTabla,
        ambiente: _ambiente,
        deIndiceDato: _tab5IndexCtrl.text.trim().isEmpty
            ? null
            : _tab5IndexCtrl.text.trim(),
      );
    });
  }

  /// Evalúa si el valor textual cumple con comodines ('%') o contención case-insensitive.
  static bool _matchesPattern(String value, String query) {
    final q = query.trim();
    if (q.isEmpty) return true;
    final vLower = value.toLowerCase();
    final qLower = q.toLowerCase();
    if (qLower.contains('%')) {
      final parts = qLower.split('%').where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) return true;
      var currentIdx = 0;
      for (final part in parts) {
        final matchIdx = vLower.indexOf(part, currentIdx);
        if (matchIdx == -1) return false;
        currentIdx = matchIdx + part.length;
      }
      return true;
    }
    return vLower.contains(qLower);
  }

  /// Extrae el valor textual de un campo específico en ValorTabla
  static String _extractValorCampo(
    ValorTabla item,
    String fieldKey,
    int? defaultCdTabla,
  ) {
    final keyUpper = fieldKey.toUpperCase().replaceAll('_', '');
    if (keyUpper == 'CDTABLA' || keyUpper == 'TABLA') {
      final direct =
          item.raw['cdTabla'] ??
          item.raw['CD_TABLA'] ??
          item.raw['cdtabla'] ??
          defaultCdTabla;
      return direct?.toString() ?? '';
    }
    for (final entry in item.raw.entries) {
      final kClean = entry.key.toUpperCase().replaceAll('_', '');
      if (kClean == keyUpper) {
        return entry.value?.toString() ?? '';
      }
    }
    return '';
  }

  /// Filtra una lista de [ValorTabla] evaluando los 7 campos:
  /// índice, descripción, tabla, usuario, fecha término, fecha efectiva, fecha modificación.
  List<ValorTabla> _aplicarFiltrosMulticampo({
    required List<ValorTabla> items,
    required String globalQuery,
    required String indiceQuery,
    required String descQuery,
    required String tablaQuery,
    required String usuarioQuery,
    required String feEfectivaQuery,
    required String feTerminoQuery,
    required String feModifQuery,
    required int? inSuspendido,
  }) {
    return items.where((item) {
      // Filtro de suspendido si se especificó
      if (inSuspendido != null) {
        final rawSusp = _extractValorCampo(item, 'inSuspendido', _cdTabla);
        final suspNum =
            int.tryParse(rawSusp) ??
            (rawSusp.toLowerCase() == 'true' || rawSusp == 's' || rawSusp == '1'
                ? 1
                : 0);
        if (suspNum != inSuspendido) return false;
      }

      final indice = _extractValorCampo(item, 'deIndiceDato', _cdTabla);
      final desc = _extractValorCampo(item, 'deDato', _cdTabla);
      final tabla = _extractValorCampo(item, 'cdTabla', _cdTabla);
      final usuario = _extractValorCampo(item, 'cdUsuario', _cdTabla);
      final feEfectiva = _extractValorCampo(
        item,
        'feEfectivaInformacion',
        _cdTabla,
      );
      final feTermino = _extractValorCampo(
        item,
        'feTerminoInformacion',
        _cdTabla,
      );
      final feModif = _extractValorCampo(item, 'feModificacion', _cdTabla);

      // Filtro global sobre cualquiera de los 7 campos
      if (globalQuery.trim().isNotEmpty) {
        final matchesAny =
            _matchesPattern(indice, globalQuery) ||
            _matchesPattern(desc, globalQuery) ||
            _matchesPattern(tabla, globalQuery) ||
            _matchesPattern(usuario, globalQuery) ||
            _matchesPattern(feEfectiva, globalQuery) ||
            _matchesPattern(feTermino, globalQuery) ||
            _matchesPattern(feModif, globalQuery);
        if (!matchesAny) return false;
      }

      // Filtros específicos
      if (indiceQuery.trim().isNotEmpty &&
          !_matchesPattern(indice, indiceQuery)) {
        return false;
      }
      if (descQuery.trim().isNotEmpty && !_matchesPattern(desc, descQuery)) {
        return false;
      }
      if (tablaQuery.trim().isNotEmpty && !_matchesPattern(tabla, tablaQuery)) {
        return false;
      }
      if (usuarioQuery.trim().isNotEmpty &&
          !_matchesPattern(usuario, usuarioQuery)) {
        return false;
      }
      if (feEfectivaQuery.trim().isNotEmpty &&
          !_matchesPattern(feEfectiva, feEfectivaQuery)) {
        return false;
      }
      if (feTerminoQuery.trim().isNotEmpty &&
          !_matchesPattern(feTermino, feTerminoQuery)) {
        return false;
      }
      if (feModifQuery.trim().isNotEmpty &&
          !_matchesPattern(feModif, feModifQuery)) {
        return false;
      }

      return true;
    }).toList();
  }

  void _onToggleSelectAll(List<ValorTabla> valores, bool? allSelected) {
    setState(() {
      if (allSelected == true) {
        _selectedRowIndices.addAll(List.generate(valores.length, (i) => i));
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
                  child: _minimized
                      ? MinimizedWindowCard(
                          title: 'Dato $_cdDato',
                          icon: Icons.info_outline_rounded,
                          accentColor: accent,
                          badge: 'DATO',
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
                                _buildHeader(isDark, accent),
                                if (!_minimized) ...[
                                  _buildTabBar(
                                    isDark,
                                    accent,
                                    productosCount: _productosCount,
                                  ),
                                  Expanded(
                                    child: _buildTabContent(isDark, accent),
                                  ),
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
                    _cdDato.isEmpty ? 'InfoDato' : 'Dato $_cdDato',
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
                      if (_editandoDato)
                        SizedBox(
                          height: 30,
                          child: TextField(
                            controller: _datoCtrl,
                            focusNode: _datoFocus,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Consolas',
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Código o nombre de dato',
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
                                onPressed: () => _cargarDato(_datoCtrl.text),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                              ),
                            ),
                            onSubmitted: _cargarDato,
                          ),
                        )
                      else
                        Text(
                          _cdDato.isEmpty ? '—' : _cdDato,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Consolas',
                            color: _cdDato.isEmpty
                                ? (isDark ? Colors.white38 : Colors.black38)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              if (_historial.isNotEmpty && !_editandoDato && !_minimized)
                PopupMenuButton<String>(
                  tooltip: 'Datos consultados',
                  icon: const Icon(Icons.history, size: 18),
                  padding: EdgeInsets.zero,
                  onSelected: _cargarDato,
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
                  tooltip: _editandoDato
                      ? 'Cancelar'
                      : 'Consultar otro dato en esta ventana',
                  icon: Icon(
                    _editandoDato ? Icons.close_rounded : Icons.manage_search,
                    size: 18,
                    color: _editandoDato ? null : accent,
                  ),
                  onPressed: _toggleCambiarDato,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              if (_cdTabla != null && !_minimized) ...[
                AmbienteSelector(value: _ambiente, onChanged: _cambiarAmbiente),
                const SizedBox(width: 8),
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
              ] else if (!_minimized) ...[
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

  // ── Tab bar ─────────────────────────────────────────────────────────────

  Widget _buildTabBar(bool isDark, Color accent, {int productosCount = 0}) {
    if (_cdTabla == null && productosCount == 0) return const SizedBox.shrink();
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _tab0(isDark, accent),
            if (productosCount > 0) _tab3(isDark, accent, productosCount),
            if (_cdTabla != null) ...[
              _tab1(isDark, accent),
              _tab2(isDark, accent),
              _tab4(isDark, accent, _defAdicionalCount),
              _tab5(isDark, accent, _infoAdicionalCount),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tabItem(
    int idx,
    String label,
    IconData icon,
    bool isDark,
    Color accent, {
    String? badge,
  }) {
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
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent.withValues(alpha: 0.16)
                      : (isDark ? Colors.white12 : Colors.black12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? accent : color,
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
            ],
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
  Widget _tab3(bool isDark, Color accent, int count) => _tabItem(
    3,
    'Productos',
    Icons.inventory_2_outlined,
    isDark,
    accent,
    badge: count.toString(),
  );
  Widget _tab4(bool isDark, Color accent, int count) => _tabItem(
    4,
    'Definición Adicional',
    Icons.playlist_add_check_outlined,
    isDark,
    accent,
    badge: count > 0 ? count.toString() : null,
  );
  Widget _tab5(bool isDark, Color accent, int count) => _tabItem(
    5,
    'Información Adicional',
    Icons.playlist_add_outlined,
    isDark,
    accent,
    badge: count > 0 ? count.toString() : null,
  );

  // ── Tab content router ────────────────────────────────────────────────────

  Widget _buildTabContent(bool isDark, Color accent) {
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

        final d = datos.first;
        return switch (_tab) {
          1 => _buildDefTab(isDark, accent),
          2 => _buildInfoTab(isDark, accent),
          3 => _buildProductosTab(d.productos, isDark, accent),
          4 => _buildDefAdicionalTab(isDark, accent),
          5 => _buildInfoAdicionalTab(isDark, accent),
          _ => _buildDatoTabContent(datos, isDark, accent),
        };
      },
    );
  }

  // ── Tab 0: Dato ───────────────────────────────────────────────────────────

  Widget _buildDatoTabContent(List<DatoInfo> datos, bool isDark, Color accent) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final d in datos) _buildDatoCard(d, isDark, accent)],
      ),
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
      if (d.version != null) ('Versión', d.version.toString()),
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
      'version',
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
      'productos',
      'dato',
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildMiniIconButton(
                icon: Icons.copy_all_rounded,
                tooltip: 'Copiar toda la información del dato',
                color: accent,
                onTap: () => _copyDatoCard(d, props, flags, extras),
              ),
            ],
          ),
          for (final (label, value) in props)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 95,
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
                    child: SelectableText(
                      value,
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildMiniIconButton(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copiar $label',
                    color: labelColor,
                    onTap: () => _copyText(value, label),
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
          if (d.productos.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _selectTab(3),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 14, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      '${d.productos.length} producto(s) asociado(s)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: accent,
                    ),
                  ],
                ),
              ),
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
                      width: 95,
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
                      child: SelectableText(
                        e.value.toString(),
                        style: TextStyle(fontSize: 11, color: textColor),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _buildMiniIconButton(
                      icon: Icons.copy_rounded,
                      tooltip: 'Copiar ${e.key}',
                      color: labelColor,
                      onTap: () => _copyText(e.value.toString(), e.key),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── Tab 3: Productos ──────────────────────────────────────────────────────

  Widget _buildProductosTab(
    List<DatoProducto> productos,
    bool isDark,
    Color accent,
  ) {
    if (productos.isEmpty) {
      return _buildEmpty(
        'No hay productos configurados para este dato',
        isDark,
      );
    }

    final query = _tab3FilterCtrl.text.trim().toLowerCase();
    final productosFiltrados = query.isEmpty
        ? productos
        : productos.where((p) {
            final cdMatches =
                p.cdProducto?.toString().toLowerCase().contains(query) ?? false;
            final deMatches =
                p.deProducto?.toLowerCase().contains(query) ?? false;
            return cdMatches || deMatches;
          }).toList();

    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    final labelColor = isDark ? Colors.white54 : Colors.black45;
    final hintStyle = TextStyle(
      fontSize: 12,
      color: isDark ? Colors.white38 : Colors.black38,
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(
        color: isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header con buscador y contador
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 15, color: accent),
              const SizedBox(width: 8),
              Text(
                query.isEmpty
                    ? '${productos.length} producto${productos.length != 1 ? 's' : ''} encontrado${productos.length != 1 ? 's' : ''}'
                    : '${productosFiltrados.length} de ${productos.length} producto${productos.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _tab3FilterCtrl,
                    style: const TextStyle(fontSize: 12),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Filtrar por código o descripción de producto…',
                      hintStyle: hintStyle,
                      prefixIcon: const Icon(Icons.search, size: 14),
                      prefixIconConstraints: const BoxConstraints(minWidth: 30),
                      suffixIcon: _tab3FilterCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              tooltip: 'Limpiar filtro',
                              onPressed: () {
                                setState(() {
                                  _tab3FilterCtrl.clear();
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                            )
                          : null,
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // List of products or empty search result
        Expanded(
          child: productosFiltrados.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_outlined,
                        size: 36,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No hay productos que coincidan con "$query"',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.clear, size: 14),
                        label: const Text(
                          'Limpiar filtro',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          setState(() {
                            _tab3FilterCtrl.clear();
                          });
                        },
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: productosFiltrados.length,
                  itemBuilder: (ctx, i) => _buildProductoCard(
                    productosFiltrados[i],
                    isDark,
                    accent,
                    borderColor,
                    labelColor,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildProductoCard(
    DatoProducto p,
    bool isDark,
    Color accent,
    Color borderColor,
    Color labelColor,
  ) {
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.87)
        : Colors.black87;
    final cardBg = isDark ? const Color(0xFF222223) : const Color(0xFFFDFDFE);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header of product
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              border: Border(
                bottom: BorderSide(color: borderColor.withValues(alpha: 0.6)),
              ),
            ),
            child: Row(
              children: [
                if (p.cdProducto != null)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      p.cdProducto.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    p.deProducto ?? 'Producto ${p.cdProducto ?? ''}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (p.version != null)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'v${p.version}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                if (p.inActivo != null)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (p.inActivo == 1 ? Colors.green : Colors.red)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (p.inActivo == 1 ? Colors.green : Colors.red)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      p.inActivo == 1 ? 'ACTIVO' : 'INACTIVO',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: p.inActivo == 1
                            ? (isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade700)
                            : Colors.redAccent,
                      ),
                    ),
                  ),
                _buildMiniIconButton(
                  icon: Icons.copy_all_rounded,
                  tooltip: 'Copiar ficha completa del producto',
                  color: accent,
                  onTap: () => _copyProductoCard(p),
                ),
              ],
            ),
          ),

          // Body details
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Configuración Básica
                _buildSectionHeader(
                  'Configuración Principal',
                  Icons.tune,
                  isDark,
                  accent,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    if (p.nuBienAsegurado != null)
                      _buildProdProp(
                        'Bien Asegurado',
                        p.nuBienAsegurado.toString(),
                        labelColor,
                        textColor,
                      ),
                    if (p.cdGrupo != null)
                      _buildProdProp(
                        'Grupo',
                        p.cdGrupo.toString(),
                        labelColor,
                        textColor,
                      ),
                    if (p.nuConsecutivo != null)
                      _buildProdProp(
                        'Consecutivo',
                        p.nuConsecutivo.toString(),
                        labelColor,
                        textColor,
                      ),
                    if (p.inLugarUsoDato != null)
                      _buildProdProp(
                        'Lugar Uso',
                        p.inLugarUsoDato.toString(),
                        labelColor,
                        textColor,
                      ),
                    if (p.cdDatoPadre != null)
                      _buildProdProp(
                        'Dato Padre',
                        p.cdDatoPadre.toString(),
                        labelColor,
                        textColor,
                      ),
                  ],
                ),

                // 2. Valores por Defecto
                if ((p.vaDefectoDato != null && p.vaDefectoDato!.isNotEmpty) ||
                    (p.vaDefectoDatoWebExterna != null &&
                        p.vaDefectoDatoWebExterna!.isNotEmpty) ||
                    (p.vaDefectoDatoWebMediador != null &&
                        p.vaDefectoDatoWebMediador!.isNotEmpty) ||
                    (p.vaDefectoDatoWebDelegado != null &&
                        p.vaDefectoDatoWebDelegado!.isNotEmpty)) ...[
                  const SizedBox(height: 10),
                  _buildSectionHeader(
                    'Valores por Defecto',
                    Icons.edit_note,
                    isDark,
                    accent,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      if (p.vaDefectoDato != null &&
                          p.vaDefectoDato!.isNotEmpty)
                        _buildProdProp(
                          'General',
                          p.vaDefectoDato!,
                          labelColor,
                          textColor,
                        ),
                      if (p.vaDefectoDatoWebExterna != null &&
                          p.vaDefectoDatoWebExterna!.isNotEmpty)
                        _buildProdProp(
                          'Web Ext.',
                          p.vaDefectoDatoWebExterna!,
                          labelColor,
                          textColor,
                        ),
                      if (p.vaDefectoDatoWebMediador != null &&
                          p.vaDefectoDatoWebMediador!.isNotEmpty)
                        _buildProdProp(
                          'Web Med.',
                          p.vaDefectoDatoWebMediador!,
                          labelColor,
                          textColor,
                        ),
                      if (p.vaDefectoDatoWebDelegado != null &&
                          p.vaDefectoDatoWebDelegado!.isNotEmpty)
                        _buildProdProp(
                          'Web Del.',
                          p.vaDefectoDatoWebDelegado!,
                          labelColor,
                          textColor,
                        ),
                    ],
                  ),
                ],

                // 3. Procedures / Scripts
                if (p.cdProcedimientoAntes != null ||
                    p.cdProcedimientoDespues != null ||
                    p.cdJavascriptDespues != null ||
                    p.nmPackageAjax != null) ...[
                  const SizedBox(height: 10),
                  _buildSectionHeader(
                    'Procedimientos & Scripts',
                    Icons.code,
                    isDark,
                    accent,
                  ),
                  const SizedBox(height: 6),
                  if (p.cdProcedimientoAntes != null)
                    _buildCodeProp(
                      'Proc. Antes',
                      p.cdProcedimientoAntes!,
                      const Color(0xFF0078D4),
                      isDark,
                      onOpen: () => _abrirProcedimientoDinamico(
                        context,
                        p.cdProcedimientoAntes!,
                      ),
                      openTooltip: 'Abrir procedimiento dinámico en pestaña',
                    ),
                  if (p.cdProcedimientoDespues != null)
                    _buildCodeProp(
                      'Proc. Después',
                      p.cdProcedimientoDespues!,
                      const Color(0xFF0078D4),
                      isDark,
                      onOpen: () => _abrirProcedimientoDinamico(
                        context,
                        p.cdProcedimientoDespues!,
                      ),
                      openTooltip: 'Abrir procedimiento dinámico en pestaña',
                    ),
                  if (p.cdJavascriptDespues != null)
                    _buildCodeProp(
                      'JS Después',
                      p.cdJavascriptDespues!,
                      const Color(0xFFD7BA7D),
                      isDark,
                    ),
                  if (p.nmPackageAjax != null)
                    _buildCodeProp(
                      'Package Ajax',
                      p.nmPackageAjax!,
                      const Color(0xFF4EC9B0),
                      isDark,
                      onOpen: () =>
                          _abrirCodigoFuente(p.nmPackageAjax!, 'PACKAGE'),
                      openTooltip: 'Ver código fuente del package Ajax',
                    ),
                ],

                // 4. Indicadores y Banderas
                const SizedBox(height: 10),
                _buildSectionHeader(
                  'Indicadores & Comportamiento',
                  Icons.flag_outlined,
                  isDark,
                  accent,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (p.inDatoRequerido != null)
                      _buildFlagBadge(
                        'Requerido',
                        p.inDatoRequerido == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inIndexar != null)
                      _buildFlagBadge(
                        'Indexar',
                        p.inIndexar == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inEndoso != null)
                      _buildFlagBadge(
                        'Endoso',
                        p.inEndoso == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inEndosoMultiple != null)
                      _buildFlagBadge(
                        'Endoso múltiple',
                        p.inEndosoMultiple == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inArrastreValor != null)
                      _buildFlagBadge(
                        'Arrastre valor',
                        p.inArrastreValor == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inMatrizCertificado != null)
                      _buildFlagBadge(
                        'Matriz cert.',
                        p.inMatrizCertificado == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inMostrarCertificado != null)
                      _buildFlagBadge(
                        'Mostrar cert.',
                        p.inMostrarCertificado == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inMostrarSiniestro != null)
                      _buildFlagBadge(
                        'Mostrar siniestro',
                        p.inMostrarSiniestro == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inBusquedaSiniestro != null)
                      _buildFlagBadge(
                        'Búsqueda siniestro',
                        p.inBusquedaSiniestro == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inMostrarMercancia != null)
                      _buildFlagBadge(
                        'Mostrar mercancía',
                        p.inMostrarMercancia == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inDataWarehouse != null)
                      _buildFlagBadge(
                        'Data warehouse',
                        p.inDataWarehouse == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inConsultaTotalizada != null)
                      _buildFlagBadge(
                        'Consulta totalizada',
                        p.inConsultaTotalizada == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inInvisibleDefecto != null)
                      _buildFlagBadge(
                        'Invisible defecto',
                        p.inInvisibleDefecto == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inRecargarDatos != null)
                      _buildFlagBadge(
                        'Recargar datos',
                        p.inRecargarDatos == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inAplicarPoCoaseguro != null)
                      _buildFlagBadge(
                        'Po coaseguro',
                        p.inAplicarPoCoaseguro == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inEjecRenovacionProcAnt != null)
                      _buildFlagBadge(
                        'Ejec. Renov. Ant.',
                        p.inEjecRenovacionProcAnt == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inEjecRenovacionProcDesp != null)
                      _buildFlagBadge(
                        'Ejec. Renov. Desp.',
                        p.inEjecRenovacionProcDesp == 1,
                        isDark,
                        labelColor,
                      ),
                    if (p.inNoMostrarConsultaOtros != null)
                      _buildFlagBadge(
                        'No mostrar consulta otros',
                        p.inNoMostrarConsultaOtros == 1,
                        isDark,
                        labelColor,
                        isNegative: true,
                      ),
                    if (p.inNoMostrarWebExterna != null)
                      _buildFlagBadge(
                        'No mostrar Web Ext.',
                        p.inNoMostrarWebExterna == 1,
                        isDark,
                        labelColor,
                        isNegative: true,
                      ),
                    if (p.inNoMostrarWebMediador != null)
                      _buildFlagBadge(
                        'No mostrar Web Med.',
                        p.inNoMostrarWebMediador == 1,
                        isDark,
                        labelColor,
                        isNegative: true,
                      ),
                    if (p.inNoMostrarWebDelegado != null)
                      _buildFlagBadge(
                        'No mostrar Web Del.',
                        p.inNoMostrarWebDelegado == 1,
                        isDark,
                        labelColor,
                        isNegative: true,
                      ),
                    if (p.inNoMostrarEndosoWebMedi != null)
                      _buildFlagBadge(
                        'No endoso Web Med.',
                        p.inNoMostrarEndosoWebMedi == 1,
                        isDark,
                        labelColor,
                        isNegative: true,
                      ),
                    if (p.inNoMostrarEndosoWebExte != null)
                      _buildFlagBadge(
                        'No endoso Web Ext.',
                        p.inNoMostrarEndosoWebExte == 1,
                        isDark,
                        labelColor,
                        isNegative: true,
                      ),
                    if (p.inNoMostrarEndosoWebDele != null)
                      _buildFlagBadge(
                        'No endoso Web Del.',
                        p.inNoMostrarEndosoWebDele == 1,
                        isDark,
                        labelColor,
                        isNegative: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    bool isDark,
    Color accent,
  ) {
    return Row(
      children: [
        Icon(icon, size: 12, color: accent),
        const SizedBox(width: 5),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: accent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.1,
            ),
            height: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildFlagBadge(
    String label,
    bool active,
    bool isDark,
    Color labelColor, {
    bool isNegative = false,
  }) {
    final effectiveColor = isNegative
        ? (active ? Colors.orange : Colors.grey)
        : (active ? Colors.green : Colors.grey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: effectiveColor.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: active
              ? (isDark
                    ? (isNegative
                          ? Colors.orange.shade300
                          : Colors.green.shade300)
                    : (isNegative
                          ? Colors.orange.shade800
                          : Colors.green.shade700))
              : labelColor,
        ),
      ),
    );
  }

  Widget _buildProdProp(
    String label,
    String value,
    Color labelColor,
    Color textColor,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: labelColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: 11.5,
            color: textColor,
            fontWeight: FontWeight.w600,
            fontFamily: 'Consolas',
          ),
        ),
        const SizedBox(width: 4),
        _buildMiniIconButton(
          icon: Icons.copy_rounded,
          tooltip: 'Copiar $label',
          color: labelColor,
          onTap: () => _copyText(value, label),
        ),
      ],
    );
  }

  void _abrirProcedimientoDinamico(BuildContext context, String rawCode) {
    final clean = rawCode
        .trim()
        .replaceAll(RegExp(r'[\(\);].*'), '')
        .trim()
        .toUpperCase();
    if (clean.isEmpty) return;

    final openTab = DynamicProcedureTabController.openTabOf(context);
    if (openTab != null) {
      openTab(cdProcedimiento: clean, ambiente: _ambiente);
      if (!_minimized) {
        _toggleMinimize();
      }
    } else {
      AppToast.info('No se pudo abrir el procedimiento "$clean".');
    }
  }

  void _abrirCodigoFuente(String objectName, String objectType) {
    final clean = objectName
        .trim()
        .replaceAll(RegExp(r'[\(\);].*'), '')
        .trim()
        .toUpperCase();
    if (clean.isEmpty) return;

    openSourceWindow(
      context,
      name: clean,
      objectType: objectType,
      ambiente: _ambiente,
    );
    if (!_minimized) {
      _toggleMinimize();
    }
  }

  Widget _buildCodeProp(
    String label,
    String code,
    Color color,
    bool isDark, {
    VoidCallback? onOpen,
    String? openTooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      code,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w600,
                        color: isDark ? color.withValues(alpha: 0.9) : color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (onOpen != null) ...[
                    _buildMiniIconButton(
                      icon: Icons.open_in_new_rounded,
                      tooltip: openTooltip ?? 'Abrir $label',
                      color: color,
                      onTap: onOpen,
                    ),
                    const SizedBox(width: 4),
                  ],
                  _buildMiniIconButton(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copiar $label',
                    color: color,
                    onTap: () => _copyText(code, label),
                  ),
                ],
              ),
            ),
          ),
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
      'version',
      'VERSION',
      'inComboConsulta',
      'IN_COMBO_CONSULTA',
      'nmPackageLlenado',
      'NM_PACKAGE_LLENADO',
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
                    if (def.version != null) ...[
                      const SizedBox(width: 16),
                      Text(
                        'Versión: ',
                        style: TextStyle(fontSize: 11, color: labelColor),
                      ),
                      Text(
                        def.version.toString(),
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Consolas',
                          color: textColor,
                        ),
                      ),
                    ],
                  ],
                ),
              if (def.inComboConsulta != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Text(
                        'Combo consulta: ',
                        style: TextStyle(fontSize: 11, color: labelColor),
                      ),
                      Text(
                        def.inComboConsulta! ? 'Sí' : 'No',
                        style: TextStyle(fontSize: 11, color: textColor),
                      ),
                    ],
                  ),
                ),
              if (def.nmPackageLlenado != null &&
                  def.nmPackageLlenado!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Text(
                        'Package llenado: ',
                        style: TextStyle(fontSize: 11, color: labelColor),
                      ),
                      Text(
                        def.nmPackageLlenado!,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Consolas',
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
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
                        // Acceso directo al dato (excluyendo el dato que se está consultando)
                        if (col.cdDato != null) ...[
                          const SizedBox(width: 8),
                          if (col.cdDato.toString() == _cdDato)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Actual',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            )
                          else
                            InkWell(
                              onTap: () => showInfoDatoWindow(
                                context,
                                col.cdDato.toString(),
                                _ambiente,
                              ),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.open_in_new_rounded,
                                      size: 11,
                                      color: accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Ver dato',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Buscador unificado rápido
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _tab2GlobalSearchCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText:
                          'Buscar en índice, desc, tabla, usuario, fechas…',
                      hintStyle: hintStyle,
                      prefixIcon: const Icon(Icons.search, size: 14),
                      prefixIconConstraints: const BoxConstraints(minWidth: 30),
                      suffixIcon: _tab2GlobalSearchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                setState(() {
                                  _tab2GlobalSearchCtrl.clear();
                                  _selectedRowIndices.clear();
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                            )
                          : null,
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      contentPadding: contentPad,
                    ),
                    onChanged: (_) =>
                        setState(() => _selectedRowIndices.clear()),
                    onSubmitted: (_) => _buscarInfo(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Botón desplegable de filtros específicos
              OutlinedButton.icon(
                onPressed: () => setState(
                  () => _tab2ShowAdvancedFilters = !_tab2ShowAdvancedFilters,
                ),
                icon: Icon(
                  _tab2ShowAdvancedFilters
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                  size: 14,
                  color: _tab2ShowAdvancedFilters
                      ? accent
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
                label: Text(
                  _tab2ShowAdvancedFilters
                      ? 'Ocultar filtros'
                      : 'Filtros detallados',
                  style: TextStyle(
                    fontSize: 11,
                    color: _tab2ShowAdvancedFilters
                        ? accent
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 32),
                  side: BorderSide(
                    color: _tab2ShowAdvancedFilters ? accent : borderColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: FilledButton.icon(
                  onPressed: _buscarInfo,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text(
                    'Consultar BD',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
          if (_tab2ShowAdvancedFilters) ...[
            const SizedBox(height: 8),
            // Fila 1 de filtros específicos: Índice, Descripción, Tabla, Usuario
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _indexCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'Índice (admite %)',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                      onSubmitted: (_) => _buscarInfo(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab2DescCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'Descripción',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab2TablaCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'Tabla',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab2UsuarioCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'Usuario',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Fila 2 de filtros específicos: F. Efectiva (Desde), F. Término (Hasta), F. Modificación, Estado
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _fechaDesdeCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'F. Efectiva (dd/MM/yyyy)',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _fechaHastaCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'F. Término (dd/MM/yyyy)',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab2FeModifCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'F. Modificación',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                DropdownButton<int?>(
                  value: _inSuspendido,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  items: const [
                    DropdownMenuItem<int?>(value: null, child: Text('Todos')),
                    DropdownMenuItem<int?>(value: 0, child: Text('Activos')),
                    DropdownMenuItem<int?>(
                      value: 1,
                      child: Text('Suspendidos'),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _inSuspendido = v;
                      _selectedRowIndices.clear();
                    });
                  },
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _tab2GlobalSearchCtrl.clear();
                      _indexCtrl.clear();
                      _tab2DescCtrl.clear();
                      _tab2TablaCtrl.clear();
                      _tab2UsuarioCtrl.clear();
                      _fechaDesdeCtrl.clear();
                      _fechaHastaCtrl.clear();
                      _tab2FeModifCtrl.clear();
                      _inSuspendido = null;
                      _selectedRowIndices.clear();
                    });
                  },
                  child: const Text('Limpiar', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
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
        final todosValores = snap.data ?? [];
        if (todosValores.isEmpty) {
          return _buildEmpty(
            'Sin resultados con los filtros indicados',
            isDark,
          );
        }

        // Aplicar filtros multicampo locales (índice, descripción, tabla, usuario, fechas, suspendido)
        final valores = _aplicarFiltrosMulticampo(
          items: todosValores,
          globalQuery: _tab2GlobalSearchCtrl.text,
          indiceQuery: _indexCtrl.text,
          descQuery: _tab2DescCtrl.text,
          tablaQuery: _tab2TablaCtrl.text,
          usuarioQuery: _tab2UsuarioCtrl.text,
          feEfectivaQuery: _fechaDesdeCtrl.text,
          feTerminoQuery: _fechaHastaCtrl.text,
          feModifQuery: _tab2FeModifCtrl.text,
          inSuspendido: _inSuspendido,
        );

        if (valores.isEmpty) {
          return _buildEmpty(
            'Ningún registro coincide con la búsqueda actual (${todosValores.length} registros cargados)',
            isDark,
          );
        }

        final allCols = _detectInfoCols(valores);
        _hiddenCols.removeWhere((c) => !allCols.contains(c));
        final effectiveCols = allCols
            .where((c) => !_hiddenCols.contains(c))
            .toList();
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
              child: InfoDatoVirtualTable(
                isDark: isDark,
                borderColor: borderColor,
                cols: effectiveCols,
                valores: valores,
                cdTabla: _cdTabla,
                vertCtrl: _tableVertCtrl,
                horizCtrl: _tableHorizCtrl,
                selectedRowIndices: _selectedRowIndices,
                onToggleSelectAll: (val) => _onToggleSelectAll(valores, val),
                onToggleRow: _onToggleRow,
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
    for (final v in valores.take(5)) {
      keys.addAll(v.raw.keys);
    }
    const preferred = [
      'version',
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
      'version': 'Versión',
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

  static const _kKnownDbColumnAliases = <String, String>{
    'VERSION': 'VERSION',
    'DEINDICEDATO': 'DE_INDICE_DATO',
    'DEDATO': 'DE_DATO',
    'VADATO1': 'VA_DATO1',
    'VADATO2': 'VA_DATO2',
    'VADATO3': 'VA_DATO3',
    'VADATO4': 'VA_DATO4',
    'VADATO5': 'VA_DATO5',
    'VADATO6': 'VA_DATO6',
    'FEEFECTIVAINFORMACION': 'FE_EFECTIVA_INFORMACION',
    'FETERMINOINFORMACION': 'FE_TERMINO_INFORMACION',
    'INSUSPENDIDO': 'IN_SUSPENDIDO',
    'INVALORDEFECTO': 'IN_VALOR_DEFECTO',
    'INNOVALIDO': 'IN_NO_VALIDO',
    'INNOMOSTRARWEBEXTERNA': 'IN_NO_MOSTRAR_WEB_EXTERNA',
    'INNOMOSTRARWEBMEDIADOR': 'IN_NO_MOSTRAR_WEB_MEDIADOR',
    'INNOMOSTRARWEBPROVEEDOR': 'IN_NO_MOSTRAR_WEB_PROVEEDOR',
    'INNOMOSTRARWEBDELEGADO': 'IN_NO_MOSTRAR_WEB_DELEGADO',
    'FEMODIFICACION': 'FE_MODIFICACION',
    'CDUSUARIO': 'CD_USUARIO',
    'CDTABLA': 'CD_TABLA',
  };

  static bool _isNumericField(String col) {
    final upper = col.toUpperCase();
    final clean = upper.replaceAll('_', '');
    if (upper.startsWith('VA_DATO') ||
        upper == 'CD_TABLA' ||
        upper == 'CD_DATO' ||
        upper == 'VERSION' ||
        clean.startsWith('VADATO') ||
        clean == 'CDTABLA' ||
        clean == 'CDDATO' ||
        clean == 'VERSION') {
      return true;
    }
    const numericFields = [
      'version',
      'vaDato1',
      'vaDato2',
      'vaDato3',
      'vaDato4',
      'vaDato5',
      'vaDato6',
      'cdTabla',
      'cdDato',
    ];
    return numericFields.contains(col);
  }

  Future<SqlQueryResult> _buildSqlQueryResult(
    List<String> visibleCols,
    List<ValorTabla> valores, {
    String suggestedTable = 'TABLAINFORMACION',
  }) async {
    // Consultar las columnas del esquema
    final dbColumns = await SchemaService.instance.getColumns(
      suggestedTable,
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

              if (colUpper == 'CD_TABLA' || colClean == 'CDTABLA') {
                final direct =
                    v.raw[col] ??
                    v.raw['cdTabla'] ??
                    v.raw['CD_TABLA'] ??
                    v.raw['cdtabla'];
                return direct ?? _cdTabla;
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
    List<ValorTabla> valores, {
    String suggestedTable = 'TABLAINFORMACION',
  }) async {
    if (valores.isEmpty) return;
    final rowIndexes = _selectedRowIndices.isEmpty
        ? List<int>.generate(valores.length, (i) => i)
        : (_selectedRowIndices.toList()..sort());

    final sqlResult = await _buildSqlQueryResult(
      cols,
      valores,
      suggestedTable: suggestedTable,
    );
    if (!context.mounted) return;

    showSqlDmlGeneratorDialog(
      context,
      result: sqlResult,
      rowIndexes: rowIndexes,
      suggestedTable: suggestedTable,
      ambiente: _ambiente,
    );
  }

  // ── Toolbar (Tab 2 / Tab 5) ──────────────────────────────────────────────

  Widget _buildInfoToolbar(
    BuildContext context,
    bool isDark,
    Color borderColor,
    List<String> allCols,
    List<String> effectiveCols,
    List<ValorTabla> valores, {
    String suggestedTable = 'TABLAINFORMACION',
  }) {
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
          _infoToolBtn(
            isDark,
            Icons.view_column_outlined,
            hiddenCount > 0 ? 'Columnas ($hiddenCount ocultas)' : 'Columnas',
            () => _showInfoColSelector(context, allCols),
          ),
          const SizedBox(width: 4),
          _infoToolBtn(
            isDark,
            Icons.data_object_outlined,
            'Generar SQL',
            () => _abrirGeneradorDml(
              context,
              effectiveCols,
              valores,
              suggestedTable: suggestedTable,
            ),
            tooltip: selectedCount > 0
                ? 'Generar INSERT / MERGE ($selectedCount filas seleccionadas)'
                : 'Generar INSERT / MERGE (todas las filas)',
          ),
          const SizedBox(width: 4),
          _infoToolBtn(
            isDark,
            Icons.copy_outlined,
            'Copiar',
            () => _copyInfoCsv(effectiveCols, valores),
            tooltip: selectedCount > 0
                ? 'Copiar $selectedCount filas seleccionadas con encabezados'
                : 'Copiar todas las filas con encabezados',
          ),
          const SizedBox(width: 4),
          _infoToolBtn(
            isDark,
            Icons.content_paste_go_outlined,
            'Copiar datos',
            () => _copyInfoCsv(effectiveCols, valores, includeHeaders: false),
            tooltip: selectedCount > 0
                ? 'Copiar $selectedCount filas seleccionadas sin encabezados'
                : 'Copiar todas las filas sin encabezados',
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

  void _showInfoColSelector(BuildContext context, List<String> allCols) {
    showFloatingDialog<void>(
      context,
      (ctx, close) => StatefulBuilder(
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
            TextButton(
              onPressed: () {
                if (allCols.length <= 1) return;
                setState(() {
                  _hiddenCols = allCols.skip(1).toSet();
                });
                setDs(() {});
              },
              child: const Text('Deseleccionar todas'),
            ),
            FilledButton(
              onPressed: () => close(),
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
  }

  // ── CSV export ────────────────────────────────────────────────────────────

  String _buildInfoCsv(
    List<String> cols,
    List<ValorTabla> valores, {
    bool includeHeaders = true,
  }) {
    final effectiveRows = _selectedRowIndices.isEmpty
        ? valores
        : [
            for (final i in (_selectedRowIndices.toList()..sort()))
              if (i >= 0 && i < valores.length) valores[i],
          ];

    final buf = StringBuffer();
    if (includeHeaders) {
      buf.writeln(cols.map((c) => _escInfo(_infoColLabel(c))).join(','));
    }
    for (final v in effectiveRows) {
      buf.writeln(
        cols
            .map(
              (c) => _escInfo(
                InfoDatoVirtualTable.resolveCellValue(v, c, _cdTabla),
              ),
            )
            .join(','),
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

  Future<void> _copyInfoCsv(
    List<String> cols,
    List<ValorTabla> valores, {
    bool includeHeaders = true,
  }) async {
    final csv = _buildInfoCsv(cols, valores, includeHeaders: includeHeaders);
    final count = _selectedRowIndices.isEmpty
        ? valores.length
        : _selectedRowIndices.length;
    await Clipboard.setData(ClipboardData(text: csv));
    final sufijo = includeHeaders ? '' : ' (sin encabezados)';
    AppToast.success(
      'Copiado al portapapeles — $count fila${count != 1 ? 's' : ''}$sufijo',
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

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    AppToast.success('$label copiado al portapapeles');
  }

  Future<void> _copyDatoCard(
    DatoInfo d,
    List<(String, String)> props,
    List<(String, bool)> flags,
    List<MapEntry<String, dynamic>> extras,
  ) async {
    final buf = StringBuffer();
    buf.writeln('INFORMACIÓN DE DATO');
    buf.writeln('====================');
    for (final (label, value) in props) {
      buf.writeln('$label: $value');
    }
    if (flags.isNotEmpty) {
      buf.writeln();
      buf.writeln('Indicadores:');
      for (final (label, value) in flags) {
        buf.writeln(' - $label: ${value ? 'Sí' : 'No'}');
      }
    }
    if (extras.isNotEmpty) {
      buf.writeln();
      buf.writeln('Campos adicionales:');
      for (final e in extras) {
        buf.writeln(' - ${e.key}: ${e.value}');
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString().trimRight()));
    AppToast.success('Ficha del dato copiada al portapapeles');
  }

  Future<void> _copyProductoCard(DatoProducto p) async {
    final buf = StringBuffer();
    buf.writeln('PRODUCTO: ${p.cdProducto ?? ''} - ${p.deProducto ?? ''}');
    buf.writeln('====================');
    if (p.version != null) buf.writeln('Versión: ${p.version}');
    if (p.inActivo != null) {
      buf.writeln('Estado: ${p.inActivo == 1 ? 'ACTIVO' : 'INACTIVO'}');
    }
    if (p.nuBienAsegurado != null) {
      buf.writeln('Bien Asegurado: ${p.nuBienAsegurado}');
    }
    if (p.cdGrupo != null) buf.writeln('Grupo: ${p.cdGrupo}');
    if (p.nuConsecutivo != null) {
      buf.writeln('Consecutivo: ${p.nuConsecutivo}');
    }
    if (p.inLugarUsoDato != null) {
      buf.writeln('Lugar Uso: ${p.inLugarUsoDato}');
    }
    if (p.cdDatoPadre != null) buf.writeln('Dato Padre: ${p.cdDatoPadre}');

    if (p.vaDefectoDato != null && p.vaDefectoDato!.isNotEmpty) {
      buf.writeln('Defecto General: ${p.vaDefectoDato}');
    }
    if (p.vaDefectoDatoWebExterna != null &&
        p.vaDefectoDatoWebExterna!.isNotEmpty) {
      buf.writeln('Defecto Web Ext.: ${p.vaDefectoDatoWebExterna}');
    }
    if (p.vaDefectoDatoWebMediador != null &&
        p.vaDefectoDatoWebMediador!.isNotEmpty) {
      buf.writeln('Defecto Web Med.: ${p.vaDefectoDatoWebMediador}');
    }
    if (p.vaDefectoDatoWebDelegado != null &&
        p.vaDefectoDatoWebDelegado!.isNotEmpty) {
      buf.writeln('Defecto Web Del.: ${p.vaDefectoDatoWebDelegado}');
    }

    if (p.cdProcedimientoAntes != null) {
      buf.writeln('Proc. Antes: ${p.cdProcedimientoAntes}');
    }
    if (p.cdProcedimientoDespues != null) {
      buf.writeln('Proc. Después: ${p.cdProcedimientoDespues}');
    }
    if (p.cdJavascriptDespues != null) {
      buf.writeln('JS Después: ${p.cdJavascriptDespues}');
    }
    if (p.nmPackageAjax != null) {
      buf.writeln('Package Ajax: ${p.nmPackageAjax}');
    }

    await Clipboard.setData(ClipboardData(text: buf.toString().trimRight()));
    AppToast.success('Ficha del producto copiada al portapapeles');
  }

  // ── Tab 4: Definición Adicional ───────────────────────────────────────────

  Widget _buildDefAdicionalTab(bool isDark, Color accent) {
    if (_defAdicionalFuture == null) {
      return _buildEmpty('No hay definición adicional para este dato', isDark);
    }
    return FutureBuilder<List<TablaDefinicionAdicional>>(
      future: _defAdicionalFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _buildError(snap.error.toString(), isDark);
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return _buildEmpty('Sin definiciones adicionales', isDark);
        }

        final borderColor = isDark
            ? const Color(0xFF3A3A3A)
            : const Color(0xFFDDE2EA);
        final labelColor = isDark ? Colors.white54 : Colors.black45;
        final textColor = isDark
            ? Colors.white.withValues(alpha: 0.87)
            : Colors.black87;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                '${list.length} campo${list.length != 1 ? 's' : ''} adicional${list.length != 1 ? 'es' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  color: labelColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _vertCtrl,
                thumbVisibility: true,
                trackVisibility: true,
                child: ListView.builder(
                  controller: _vertCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final item = list[i];
                    final rowBg = i.isEven
                        ? (isDark
                              ? const Color(0xFF252526)
                              : const Color(0xFFF8F9FA))
                        : Colors.transparent;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: rowBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: borderColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '#${item.cdConsecutivoDatoAdicional ?? (i + 1)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'Consolas',
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (item.cdDatoAdicional != null)
                                Text(
                                  'Cód: ${item.cdDatoAdicional}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'Consolas',
                                    color: accent,
                                  ),
                                ),
                              const Spacer(),
                              if (item.version != null)
                                Text(
                                  'v${item.version}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'Consolas',
                                    color: labelColor,
                                  ),
                                ),
                              if (item.cdDatoAdicional != null) ...[
                                const SizedBox(width: 8),
                                if (item.cdDatoAdicional.toString() == _cdDato)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Actual',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: accent,
                                      ),
                                    ),
                                  )
                                else
                                  InkWell(
                                    onTap: () => showInfoDatoWindow(
                                      ctx,
                                      item.cdDatoAdicional.toString(),
                                      _ambiente,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: accent.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.open_in_new_rounded,
                                            size: 11,
                                            color: accent,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Ver dato',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                              if (item.inDatoAdicionalRequerido != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: item.inDatoAdicionalRequerido!
                                        ? Colors.orange.withValues(alpha: 0.15)
                                        : Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.inDatoAdicionalRequerido!
                                        ? 'Requerido'
                                        : 'Opcional',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: item.inDatoAdicionalRequerido!
                                          ? Colors.orange
                                          : labelColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (item.deDatoAdicional != null &&
                              item.deDatoAdicional!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              item.deDatoAdicional!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Tab 5: Información Adicional ──────────────────────────────────────────

  Widget _buildInfoAdicionalFilters(
    bool isDark,
    Color accent,
    Color borderColor,
  ) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Buscador unificado rápido Tab 5
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _tab5GlobalSearchCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText:
                          'Buscar en índice, desc, tabla, usuario, fechas…',
                      hintStyle: hintStyle,
                      prefixIcon: const Icon(Icons.search, size: 14),
                      prefixIconConstraints: const BoxConstraints(minWidth: 30),
                      suffixIcon: _tab5GlobalSearchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                setState(() {
                                  _tab5GlobalSearchCtrl.clear();
                                  _selectedRowIndices.clear();
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                            )
                          : null,
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      contentPadding: contentPad,
                    ),
                    onChanged: (_) =>
                        setState(() => _selectedRowIndices.clear()),
                    onSubmitted: (_) => _buscarInfoAdicional(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Botón desplegable de filtros específicos Tab 5
              OutlinedButton.icon(
                onPressed: () => setState(
                  () => _tab5ShowAdvancedFilters = !_tab5ShowAdvancedFilters,
                ),
                icon: Icon(
                  _tab5ShowAdvancedFilters
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                  size: 14,
                  color: _tab5ShowAdvancedFilters
                      ? accent
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
                label: Text(
                  _tab5ShowAdvancedFilters
                      ? 'Ocultar filtros'
                      : 'Filtros detallados',
                  style: TextStyle(
                    fontSize: 11,
                    color: _tab5ShowAdvancedFilters
                        ? accent
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 32),
                  side: BorderSide(
                    color: _tab5ShowAdvancedFilters ? accent : borderColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: FilledButton.icon(
                  onPressed: _buscarInfoAdicional,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text(
                    'Consultar BD',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
          if (_tab5ShowAdvancedFilters) ...[
            const SizedBox(height: 8),
            // Fila 1 Tab 5: Índice, Descripción, Tabla, Usuario
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab5IndexCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'Índice (admite %)',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                      onSubmitted: (_) => _buscarInfoAdicional(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab5DescCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'Descripción',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab5TablaCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'Tabla',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab5UsuarioCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'Usuario',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Fila 2 Tab 5: F. Efectiva, F. Término, F. Modificación, Estado
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab5FeDesdeCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'F. Efectiva (dd/MM/yyyy)',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab5FeHastaCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'F. Término (dd/MM/yyyy)',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _tab5FeModifCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: 'F. Modificación',
                        hintStyle: hintStyle,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        contentPadding: contentPad,
                      ),
                      onChanged: (_) =>
                          setState(() => _selectedRowIndices.clear()),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                DropdownButton<int?>(
                  value: _tab5InSuspendido,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  items: const [
                    DropdownMenuItem<int?>(value: null, child: Text('Todos')),
                    DropdownMenuItem<int?>(value: 0, child: Text('Activos')),
                    DropdownMenuItem<int?>(
                      value: 1,
                      child: Text('Suspendidos'),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _tab5InSuspendido = v;
                      _selectedRowIndices.clear();
                    });
                  },
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _tab5GlobalSearchCtrl.clear();
                      _tab5IndexCtrl.clear();
                      _tab5DescCtrl.clear();
                      _tab5TablaCtrl.clear();
                      _tab5UsuarioCtrl.clear();
                      _tab5FeDesdeCtrl.clear();
                      _tab5FeHastaCtrl.clear();
                      _tab5FeModifCtrl.clear();
                      _tab5InSuspendido = null;
                      _selectedRowIndices.clear();
                    });
                  },
                  child: const Text('Limpiar', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoAdicionalTab(bool isDark, Color accent) {
    if (_infoAdicionalFuture == null) {
      return _buildEmpty('No hay información adicional para este dato', isDark);
    }
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoAdicionalFilters(isDark, accent, borderColor),
        Expanded(
          child: FutureBuilder<List<ValorTabla>>(
            future: _infoAdicionalFuture,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _buildError(snap.error.toString(), isDark);
              }
              final todosValores = snap.data ?? [];
              if (todosValores.isEmpty) {
                return _buildEmpty(
                  'Sin registros de información adicional',
                  isDark,
                );
              }

              final valores = _aplicarFiltrosMulticampo(
                items: todosValores,
                globalQuery: _tab5GlobalSearchCtrl.text,
                indiceQuery: _tab5IndexCtrl.text,
                descQuery: _tab5DescCtrl.text,
                tablaQuery: _tab5TablaCtrl.text,
                usuarioQuery: _tab5UsuarioCtrl.text,
                feEfectivaQuery: _tab5FeDesdeCtrl.text,
                feTerminoQuery: _tab5FeHastaCtrl.text,
                feModifQuery: _tab5FeModifCtrl.text,
                inSuspendido: _tab5InSuspendido,
              );

              if (valores.isEmpty) {
                return _buildEmpty(
                  'Ningún registro coincide con la búsqueda actual (${todosValores.length} registros cargados)',
                  isDark,
                );
              }

              final allCols = _detectInfoCols(valores);
              _hiddenCols.removeWhere((c) => !allCols.contains(c));
              final effectiveCols = allCols
                  .where((c) => !_hiddenCols.contains(c))
                  .toList();

              return Column(
                children: [
                  _buildInfoToolbar(
                    ctx,
                    isDark,
                    borderColor,
                    allCols,
                    effectiveCols,
                    valores,
                    suggestedTable: 'TABLAINFORMACIONADICIONAL',
                  ),
                  Expanded(
                    child: InfoDatoVirtualTable(
                      isDark: isDark,
                      borderColor: borderColor,
                      cols: effectiveCols,
                      valores: valores,
                      cdTabla: _cdTabla,
                      vertCtrl: _vertCtrl,
                      horizCtrl: _horizCtrl,
                      selectedRowIndices: _selectedRowIndices,
                      onToggleSelectAll: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedRowIndices.addAll(
                              List<int>.generate(valores.length, (i) => i),
                            );
                          } else {
                            _selectedRowIndices.clear();
                          }
                        });
                      },
                      onToggleRow: (rowIdx, val) {
                        setState(() {
                          if (val == true) {
                            _selectedRowIndices.add(rowIdx);
                          } else {
                            _selectedRowIndices.remove(rowIdx);
                          }
                        });
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
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

// ─────────────────────────────────────────────────────────────────────────────
// Grilla Virtualizada de InfoDato (two_dimensional_scrollables)
// ─────────────────────────────────────────────────────────────────────────────

class InfoDatoVirtualTable extends StatefulWidget {
  final bool isDark;
  final Color borderColor;
  final List<String> cols;
  final List<ValorTabla> valores;
  final int? cdTabla;
  final ScrollController vertCtrl;
  final ScrollController horizCtrl;
  final Set<int> selectedRowIndices;
  final ValueChanged<bool?> onToggleSelectAll;
  final void Function(int index, bool? selected) onToggleRow;

  const InfoDatoVirtualTable({
    super.key,
    required this.isDark,
    required this.borderColor,
    required this.cols,
    required this.valores,
    required this.cdTabla,
    required this.vertCtrl,
    required this.horizCtrl,
    required this.selectedRowIndices,
    required this.onToggleSelectAll,
    required this.onToggleRow,
  });

  static String resolveCellValue(ValorTabla item, String col, int? cdTabla) {
    final colUpper = col.toUpperCase();
    final colClean = colUpper.replaceAll('_', '');

    if (colUpper == 'CD_TABLA' || colClean == 'CDTABLA') {
      final direct =
          item.raw[col] ??
          item.raw['cdTabla'] ??
          item.raw['CD_TABLA'] ??
          item.raw['cdtabla'];
      final val = direct?.toString().trim();
      return (val == null || val.isEmpty) ? (cdTabla?.toString() ?? '') : val;
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
          _InfoDatoModalState._kKnownDbColumnAliases[kClean] ??
          _InfoDatoModalState._kKnownDbColumnAliases[kUpper];
      if (alias != null && alias.toUpperCase() == colUpper) {
        return entry.value?.toString() ?? '';
      }
    }

    return '';
  }

  static bool isNumericField(String col) {
    final upper = col.toUpperCase();
    final clean = upper.replaceAll('_', '');
    if (upper.startsWith('VA_DATO') ||
        upper == 'CD_TABLA' ||
        upper == 'CD_DATO' ||
        upper == 'VERSION' ||
        clean.startsWith('VADATO') ||
        clean == 'CDTABLA' ||
        clean == 'CDDATO' ||
        clean == 'VERSION') {
      return true;
    }
    const numericFields = [
      'version',
      'vaDato1',
      'vaDato2',
      'vaDato3',
      'vaDato4',
      'vaDato5',
      'vaDato6',
      'cdTabla',
      'cdDato',
    ];
    return numericFields.contains(col);
  }

  static String colLabel(String col) {
    const labels = <String, String>{
      'version': 'Versión',
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
      'cdTabla': 'Tabla',
    };
    return labels[col] ?? col;
  }

  @override
  State<InfoDatoVirtualTable> createState() => _InfoDatoVirtualTableState();
}

class _InfoDatoVirtualTableState extends State<InfoDatoVirtualTable> {
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
  void didUpdateWidget(covariant InfoDatoVirtualTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valores != widget.valores ||
        oldWidget.cols != widget.cols ||
        oldWidget.cdTabla != widget.cdTabla) {
      _recomputeData();
    }
  }

  void _recomputeData() {
    final cols = widget.cols;
    final valores = widget.valores;
    final cdTabla = widget.cdTabla;

    _colIsNumeric = List<bool>.generate(
      cols.length,
      (c) => InfoDatoVirtualTable.isNumericField(cols[c]),
    );

    // Precomputar matriz fila x columna en O(1) de renderizado
    _cellMatrix = List<List<String>>.generate(valores.length, (r) {
      final item = valores[r];
      return List<String>.generate(cols.length, (c) {
        return InfoDatoVirtualTable.resolveCellValue(item, cols[c], cdTabla);
      });
    });

    // Calcular anchos de columna basados en contenido y cabecera
    _colWidths = List<double>.generate(cols.length, (c) {
      final colName = cols[c];
      final headerText = InfoDatoVirtualTable.colLabel(colName);
      double maxLen = headerText.length.toDouble();

      final sampleCount = valores.length > 40 ? 40 : valores.length;
      for (var r = 0; r < sampleCount; r++) {
        final valLen = _cellMatrix[r][c].length;
        if (valLen > maxLen) {
          maxLen = valLen.toDouble();
        }
      }

      final computed = (maxLen * 7.8) + 24.0;
      return computed.clamp(85.0, 420.0);
    });
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
              final label = InfoDatoVirtualTable.colLabel(colName);
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
