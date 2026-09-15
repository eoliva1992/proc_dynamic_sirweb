part of 'code_editor_panel.dart';

// ── Modal: consulta de autorizaciones de proceso ──────────────────────────

/// Abre la ventana de consulta de autorizaciones.
///
/// Se inserta en el overlay raíz (sin barrera modal) para que pueda
/// minimizarse y seguir trabajando en el editor.
/// [filtroInicial] permite precargar una búsqueda.
void showAutorizacionesWindow(
  BuildContext context,
  String ambiente, {
  String filtroInicial = '',
}) {
  _showFloatingWindow(
    context,
    (close) => _AutorizacionesModal(
      ambiente: ambiente,
      filtroInicial: filtroInicial,
      onClose: close,
    ),
  );
}

void _showAutorizacionesModal(
  BuildContext context,
  String ambiente, {
  String filtroInicial = '',
}) => showAutorizacionesWindow(context, ambiente, filtroInicial: filtroInicial);

class _AutorizacionesModal extends StatefulWidget {
  final String ambiente;
  final String filtroInicial;
  final VoidCallback onClose;

  const _AutorizacionesModal({
    required this.ambiente,
    required this.onClose,
    this.filtroInicial = '',
  });

  @override
  State<_AutorizacionesModal> createState() => _AutorizacionesModalState();
}

class _AutorizacionesModalState extends State<_AutorizacionesModal> {
  static const _accent = Color(0xFF2E7D32);

  Future<AutorizacionPage>? _future;
  AutorizacionPage _page = AutorizacionPage.empty;

  final _buscarCtrl = TextEditingController();
  final _listCtrl = ScrollController();
  final _detalleCtrl = ScrollController();

  String _busqueda = '';
  int _pagina = 1;
  int _top = 50;
  int _seleccion = 0;

  // ── Geometría de la ventana ─────────────────────────────────────────────
  Offset _position = Offset.zero;
  double? _modalW;
  double? _modalH;
  bool _maximized = false;
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;
  Duration _anim = Duration.zero;

  /// Ventana minimizada a la barra inferior.
  bool _minimized = false;
  int? _slot;

  @override
  void dispose() {
    _MinimizedSlots.release(_slot);
    _buscarCtrl.dispose();
    _listCtrl.dispose();
    _detalleCtrl.dispose();
    super.dispose();
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
    _buscarCtrl.text = widget.filtroInicial;
    _busqueda = widget.filtroInicial.trim();
    _cargar();
  }

  // ── Datos ───────────────────────────────────────────────────────────────

  void _cargar() {
    final texto = _busqueda;
    setState(() {
      _seleccion = 0;
      _future = SirwebService()
          .listarAutorizaciones(
            // El servidor combina código y descripción con OR, así que un
            // único cuadro de texto busca por ambos campos.
            codigo: texto.isEmpty ? null : texto,
            descripcion: texto.isEmpty ? null : texto,
            ambiente: widget.ambiente,
            pagina: _pagina,
            top: _top,
          )
          .then((p) {
            if (mounted) setState(() => _page = p);
            return p;
          });
    });
  }

  void _buscar() {
    final texto = _buscarCtrl.text.trim();
    if (texto == _busqueda && _pagina == 1) {
      _cargar();
      return;
    }
    _busqueda = texto;
    _pagina = 1;
    _cargar();
  }

  void _limpiar() {
    _buscarCtrl.clear();
    _busqueda = '';
    _pagina = 1;
    _cargar();
  }

  void _irPagina(int delta) {
    final nueva = _pagina + delta;
    if (nueva < 1) return;
    _pagina = nueva;
    _cargar();
  }

  void _cambiarTop(int top) {
    if (top == _top) return;
    _top = top;
    _pagina = 1;
    _cargar();
  }

  Future<void> _copiarSeleccion(AutorizacionProceso a) async {
    final buf = StringBuffer();
    a.raw.forEach((k, v) {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isEmpty) return;
      buf.writeln('$k\t$s');
    });
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    AppToast.success('Autorización copiada al portapapeles');
  }

  Future<void> _copiarPagina(List<AutorizacionProceso> items) async {
    if (items.isEmpty) return;
    final cols = <String>{};
    for (final a in items) {
      cols.addAll(a.raw.keys);
    }
    final buf = StringBuffer()..writeln(cols.join('\t'));
    for (final a in items) {
      buf.writeln(
        cols
            .map((c) => (a.raw[c]?.toString() ?? '').replaceAll('\t', ' '))
            .join('\t'),
      );
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    AppToast.success(
      'Copiadas ${items.length} autorizacion${items.length == 1 ? '' : 'es'}',
    );
  }

  // ── Ventana ─────────────────────────────────────────────────────────────

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
      _modalW = (size.width - 48).clamp(480.0, size.width);
      _modalH = (size.height - 48).clamp(320.0, size.height);
    } else {
      _modalW ??= (size.width * 0.86).clamp(680.0, 1080.0);
      _modalH ??= (size.height * 0.80).clamp(460.0, 720.0);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        const SingleActivator(LogicalKeyboardKey.f5): _cargar,
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
                  // recorta mientras corre la animación de minimizar/restaurar
                  // (si no, desborda al crecer desde la barra minimizada).
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
                          _buildHeader(isDark),
                          if (!_minimized) ...[
                            _buildSearchBar(isDark),
                            Expanded(child: _buildBody(isDark)),
                            _buildFooter(isDark),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
                        480.0,
                        size.width - 40,
                      );
                    }),
                  ),
                ),
              ),
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
                        360.0,
                        size.height - 40,
                      );
                    }),
                  ),
                ),
              ),
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
                        480.0,
                        size.width - 40,
                      );
                      _modalH = (_modalH! + d.delta.dy).clamp(
                        360.0,
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

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark) {
    final items = _page.items;
    final compact = _minimized;
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
          padding: compact
              ? const EdgeInsets.fromLTRB(10, 4, 4, 4)
              : const EdgeInsets.fromLTRB(16, 12, 8, 12),
          lineColor: _accent.withValues(alpha: 0.32),
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
                padding: EdgeInsets.all(compact ? 5 : 8),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(compact ? 6 : 8),
                ),
                child: Icon(
                  Icons.verified_user_rounded,
                  size: compact ? 15 : 20,
                  color: _accent,
                ),
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: compact
                    ? const Text(
                        'Autorizaciones',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Autorizaciones',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white38 : Colors.black38,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            items.isEmpty
                                ? 'Sin resultados'
                                : '${items.length} en la página $_pagina',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
              if (!compact) ...[
                IconButton(
                  tooltip: 'Copiar página al portapapeles',
                  icon: const Icon(Icons.copy_all_rounded, size: 17),
                  onPressed: items.isEmpty
                      ? null
                      : () => unawaited(_copiarPagina(items)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  tooltip: 'Recargar (F5)',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: _cargar,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
              IconButton(
                tooltip: _minimized ? 'Restaurar' : 'Minimizar',
                icon: Icon(
                  _minimized
                      ? Icons.open_in_browser_rounded
                      : Icons.remove_rounded,
                  size: compact ? 16 : 18,
                ),
                onPressed: _toggleMinimize,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: compact ? 28 : 32,
                  minHeight: compact ? 28 : 32,
                ),
              ),
              if (!compact)
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
                icon: Icon(Icons.close, size: compact ? 16 : 18),
                onPressed: _cerrar,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: compact ? 28 : 32,
                  minHeight: compact ? 28 : 32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Buscador ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(bool isDark) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _buscarCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar por descripción o código de autorización…',
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  suffixIcon: _buscarCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar',
                          icon: const Icon(Icons.clear, size: 15),
                          onPressed: _limpiar,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF252526) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _buscar(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _buscar,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Buscar', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<int>(
            tooltip: 'Filas por página',
            initialValue: _top,
            onSelected: _cambiarTop,
            itemBuilder: (_) => [
              for (final n in const [25, 50, 100, 200])
                PopupMenuItem(value: n, child: Text('$n por página')),
            ],
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Text('$_top', style: const TextStyle(fontSize: 12)),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Cuerpo: lista + detalle ─────────────────────────────────────────────

  Widget _buildBody(bool isDark) {
    return FutureBuilder<AutorizacionPage>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snap.hasError) {
          return _buildMensaje(
            isDark,
            Icons.error_outline_rounded,
            snap.error.toString().replaceFirst('Exception: ', ''),
            isError: true,
          );
        }
        final items = snap.data?.items ?? const <AutorizacionProceso>[];
        if (items.isEmpty) {
          return _buildMensaje(
            isDark,
            Icons.inbox_rounded,
            'No se encontraron autorizaciones con ese criterio.',
          );
        }
        final idx = _seleccion.clamp(0, items.length - 1);
        final borderColor = isDark
            ? const Color(0xFF3A3A3A)
            : const Color(0xFFDDE2EA);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _maximized ? 340 : 280,
              child: _buildLista(isDark, items, idx),
            ),
            Container(width: 1, color: borderColor),
            Expanded(child: _buildDetalle(isDark, items[idx])),
          ],
        );
      },
    );
  }

  Widget _buildMensaje(
    bool isDark,
    IconData icon,
    String texto, {
    bool isError = false,
  }) {
    final color = isError
        ? Colors.redAccent
        : (isDark ? Colors.white38 : Colors.black38);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 10),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista(bool isDark, List<AutorizacionProceso> items, int idx) {
    return Container(
      color: isDark ? const Color(0xFF1B1B1B) : const Color(0xFFFAFBFC),
      child: Scrollbar(
        controller: _listCtrl,
        child: ListView.builder(
          controller: _listCtrl,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final a = items[i];
            final sel = i == idx;
            return InkWell(
              onTap: () => setState(() => _seleccion = i),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                decoration: BoxDecoration(
                  color: sel
                      ? _accent.withValues(alpha: isDark ? 0.18 : 0.10)
                      : null,
                  border: Border(
                    left: BorderSide(
                      color: sel ? _accent : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (a.subtitulo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        a.subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'Consolas',
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDetalle(bool isDark, AutorizacionProceso a) {
    return Scrollbar(
      controller: _detalleCtrl,
      child: SingleChildScrollView(
        controller: _detalleCtrl,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    a.titulo,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar esta autorización',
                  icon: const Icon(Icons.content_copy_rounded, size: 15),
                  onPressed: () => unawaited(_copiarSeleccion(a)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (a.indicadores.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (label, value) in a.indicadores)
                    _flagChip(isDark, label, value),
                ],
              ),
            _buildSeccion(isDark, 'IDENTIFICACIÓN', a.identificacion),
            _buildSeccion(isDark, 'ALCANCE', a.alcance),
            _buildSeccion(isDark, 'VALIDACIÓN', a.validacion),
            for (final (titulo, activo, campos) in a.correos)
              if (campos.isNotEmpty || activo != null)
                _buildSeccion(
                  isDark,
                  'CORREO · ${titulo.toUpperCase()}',
                  campos,
                  activo: activo,
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeccion(
    bool isDark,
    String titulo,
    List<(String, String)> campos, {
    bool? activo,
  }) {
    if (campos.isEmpty && activo == null) return const SizedBox.shrink();
    final labelColor = isDark ? Colors.white54 : Colors.black45;
    final valueColor = isDark
        ? Colors.white.withValues(alpha: 0.87)
        : Colors.black87;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                  letterSpacing: 0.8,
                ),
              ),
              if (activo != null) ...[
                const SizedBox(width: 8),
                _flagChip(
                  isDark,
                  activo ? 'Envía correo' : 'Sin correo',
                  activo,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (campos.isEmpty)
            Text('Sin datos', style: TextStyle(fontSize: 11, color: labelColor))
          else
            for (final (label, value) in campos)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 11, color: labelColor),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        value,
                        style: TextStyle(
                          fontSize: 12,
                          color: valueColor,
                          fontFamily: value.length > 60 ? null : 'Consolas',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _flagChip(bool isDark, String label, bool value) {
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

  // ── Footer con paginación ───────────────────────────────────────────────

  Widget _buildFooter(bool isDark) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    final labelColor = isDark ? Colors.white54 : Colors.black45;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Text(
            _busqueda.isEmpty
                ? 'Todas las autorizaciones'
                : 'Filtro: $_busqueda',
            style: TextStyle(fontSize: 11, color: labelColor),
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Página anterior',
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            onPressed: _page.tienePrevio || _pagina > 1
                ? () => _irPagina(-1)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Página $_pagina',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Página siguiente',
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            onPressed: _page.tieneSiguiente ? () => _irPagina(1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ],
      ),
    );
  }
}
