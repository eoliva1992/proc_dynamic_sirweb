part of 'code_editor_panel.dart';

// ── Modal: ejecutar procedimiento dinámico ────────────────────────────────
//
// Exclusivo de los procedimientos dinámicos: arma el contexto (cotización,
// póliza, siniestro…), llama al endpoint REST `/ejecutar` y muestra las
// salidas, la traza y el error Oracle devueltos por el orquestador.

/// Abre la ventana de ejecución del procedimiento.
///
/// Se inserta en el overlay raíz (sin barrera modal) para poder minimizarla
/// y seguir trabajando en el editor.
///
/// [obtenerTexto] decide contra qué endpoint se ejecuta:
/// * si viene (estás en el **editor**), se manda el código actual del editor a
///   `POST /tools/procedimiento-dinamico/ejecutar-borrador`;
/// * si es `null` (estás en la **consulta**), sólo se manda el nombre a
///   `POST /tools/procedimiento-dinamico/{cd}/ejecutar`.
void showEjecutarProcedimientoWindow(
  BuildContext context,
  String cdProcedimiento,
  String ambiente, {
  String? inConfiguracion,
  Future<String?> Function()? obtenerTexto,
}) {
  _showFloatingWindow(
    context,
    (close) => _EjecutarProcedimientoModal(
      cdProcedimiento: cdProcedimiento,
      ambiente: ambiente,
      inConfiguracion: inConfiguracion,
      obtenerTexto: obtenerTexto,
      onClose: close,
    ),
  );
}

/// Alias interno usado por el editor.
void _showEjecutarProcedimientoModal(
  BuildContext context,
  String cdProcedimiento,
  String ambiente, {
  String? inConfiguracion,
  Future<String?> Function()? obtenerTexto,
}) => showEjecutarProcedimientoWindow(
  context,
  cdProcedimiento,
  ambiente,
  inConfiguracion: inConfiguracion,
  obtenerTexto: obtenerTexto,
);

/// Definición de un campo del formulario de contexto.
class _CampoEjecucion {
  final String key;
  final String label;
  final bool numerico;
  final String? hint;

  const _CampoEjecucion(
    this.key,
    this.label, {
    this.numerico = true,
    this.hint,
  });
}

const _kCamposEjecucion = <_CampoEjecucion>[
  _CampoEjecucion('cdEntidad', 'CD_ENTIDAD'),
  _CampoEjecucion('cdArea', 'CD_AREA'),
  _CampoEjecucion('nuCotizacion', 'NU_COTIZACION'),
  _CampoEjecucion('nuItem', 'NU_ITEM'),
  _CampoEjecucion('nuPoliza', 'NU_POLIZA'),
  _CampoEjecucion('nuCertificado', 'NU_CERTIFICADO'),
  _CampoEjecucion('nuEndoso', 'NU_ENDOSO'),
  _CampoEjecucion('nuSiniestro', 'NU_SINIESTRO'),
  _CampoEjecucion('nuMovimiento', 'NU_MOVIMIENTO'),
  _CampoEjecucion('nuInspeccion', 'NU_INSPECCION'),
];

const _kCamposTextoEjecucion = <_CampoEjecucion>[
  _CampoEjecucion('inAccion', 'IN_ACCION', numerico: false),
  _CampoEjecucion('vaDato', 'VA_DATO', numerico: false),
  _CampoEjecucion(
    'tipoContexto',
    'Tipo de contexto',
    numerico: false,
    hint: 'Autodetectado si se deja vacío',
  ),
  _CampoEjecucion('stringDatos', 'STRING_DATOS', numerico: false),
  _CampoEjecucion('stringMatriz', 'STRING_MATRIZ', numerico: false),
];

class _EjecutarProcedimientoModal extends StatefulWidget {
  final String cdProcedimiento;
  final String ambiente;
  final String? inConfiguracion;

  /// Devuelve el código actual del editor. Si es `null`, la ventana se abrió
  /// desde la consulta y se ejecuta el texto guardado en la base.
  final Future<String?> Function()? obtenerTexto;
  final VoidCallback onClose;

  const _EjecutarProcedimientoModal({
    required this.cdProcedimiento,
    required this.ambiente,
    required this.onClose,
    this.inConfiguracion,
    this.obtenerTexto,
  });

  @override
  State<_EjecutarProcedimientoModal> createState() =>
      _EjecutarProcedimientoModalState();
}

class _EjecutarProcedimientoModalState
    extends State<_EjecutarProcedimientoModal> {
  static const _accent = Color(0xFF16A34A);

  final Map<String, TextEditingController> _ctrls = {};
  final _camposAdicionalesCtrl = TextEditingController();
  final _timeoutCtrl = TextEditingController(text: '30');
  final _paramsScroll = ScrollController();
  final _resultScroll = ScrollController();

  bool _ejecutando = false;
  http.Client? _ejecucionClient;
  bool _cancelado = false;
  EjecucionResultado? _resultado;
  String? _error;

  /// Ambiente contra el que se ejecuta. Arranca en el del tab pero se puede
  /// cambiar sin cerrar la ventana: probar la misma regla en Desa y en QA es
  /// el caso de uso habitual.
  late String _ambiente = widget.ambiente;

  /// 0 = salidas, 1 = traza, 2 = contexto, 3 = variables dinámicas,
  /// 4 = variables declaradas (bloque `DECLARE` del orquestador).
  int _tab = 0;

  Offset _position = Offset.zero;
  double? _modalW;
  double? _modalH;

  bool _maximized = false;
  bool _minimized = false;
  int? _slot;
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;
  Duration _anim = Duration.zero;

  String get _prefsKey => 'ejecutar_params_${widget.cdProcedimiento}';

  @override
  void initState() {
    super.initState();
    for (final c in [..._kCamposEjecucion, ..._kCamposTextoEjecucion]) {
      _ctrls[c.key] = TextEditingController();
    }
    _ctrls['cdEntidad']!.text = '1';
    unawaited(_restaurarParametros());
  }

  @override
  void dispose() {
    if (_ejecutando) {
      _cancelado = true;
      _ejecucionClient?.close();
      _ejecucionClient = null;
    }
    _MinimizedSlots.release(_slot);
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _camposAdicionalesCtrl.dispose();
    _timeoutCtrl.dispose();
    _paramsScroll.dispose();
    _resultScroll.dispose();
    super.dispose();
  }

  // ── Persistencia de los últimos parámetros usados ───────────────────────

  Future<void> _restaurarParametros() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || !mounted) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        for (final entry in _ctrls.entries) {
          final v = map[entry.key];
          if (v != null) entry.value.text = v.toString();
        }
        final extra = map['camposAdicionales'];
        if (extra != null) _camposAdicionalesCtrl.text = extra.toString();
        final t = map['timeoutSegundos'];
        if (t != null) _timeoutCtrl.text = t.toString();
      });
    } catch (_) {
      // Preferencias corruptas o formato viejo: se ignoran.
    }
  }

  Future<void> _guardarParametros() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{
        for (final e in _ctrls.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
        if (_camposAdicionalesCtrl.text.trim().isNotEmpty)
          'camposAdicionales': _camposAdicionalesCtrl.text.trim(),
        'timeoutSegundos': _timeoutCtrl.text.trim(),
      };
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (_) {
      // Persistir los parámetros es best-effort: nunca bloquea la ejecución.
    }
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
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _cerrar() {
    _MinimizedSlots.release(_slot);
    _slot = null;
    widget.onClose();
  }

  // ── Ejecución ───────────────────────────────────────────────────────────

  int? _int(String key) {
    final txt = _ctrls[key]?.text.trim() ?? '';
    if (txt.isEmpty) return null;
    return int.tryParse(txt);
  }

  String? _str(String key) {
    final txt = _ctrls[key]?.text.trim() ?? '';
    return txt.isEmpty ? null : txt;
  }

  Future<void> _ejecutar() async {
    if (_ejecutando) return;

    Map<String, dynamic>? extra;
    final extraTxt = _camposAdicionalesCtrl.text.trim();
    if (extraTxt.isNotEmpty) {
      try {
        final decoded = jsonDecode(extraTxt);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Debe ser un objeto JSON');
        }
        extra = decoded;
      } catch (e) {
        setState(() {
          _error = 'Campos adicionales: JSON inválido — $e';
          _resultado = null;
        });
        return;
      }
    }

    // Validación de numéricos: un valor no parseable se enviaría como null
    // silenciosamente y la ejecución daría un resultado engañoso.
    for (final c in _kCamposEjecucion) {
      final txt = _ctrls[c.key]!.text.trim();
      if (txt.isNotEmpty && int.tryParse(txt) == null) {
        setState(() {
          _error = '${c.label} debe ser un número entero.';
          _resultado = null;
        });
        return;
      }
    }

    final timeout = int.tryParse(_timeoutCtrl.text.trim());

    final request = EjecucionRequest(
      cdEntidad: _int('cdEntidad'),
      nuCotizacion: _int('nuCotizacion'),
      nuItem: _int('nuItem'),
      cdArea: _int('cdArea'),
      nuPoliza: _int('nuPoliza'),
      nuCertificado: _int('nuCertificado'),
      nuEndoso: _int('nuEndoso'),
      nuSiniestro: _int('nuSiniestro'),
      nuMovimiento: _int('nuMovimiento'),
      nuInspeccion: _int('nuInspeccion'),
      inAccion: _str('inAccion'),
      vaDato: _str('vaDato'),
      stringDatos: _str('stringDatos'),
      stringMatriz: _str('stringMatriz'),
      camposAdicionales: extra,
      tipoContexto: _str('tipoContexto'),
      ambiente: _ambiente == 'Desa' ? null : _ambiente,
      timeoutSegundos: timeout,
    );

    final client = http.Client();
    _ejecucionClient = client;
    _cancelado = false;

    setState(() {
      _ejecutando = true;
      _error = null;
    });

    unawaited(_guardarParametros());

    try {
      final EjecucionResultado res;
      if (widget.obtenerTexto != null) {
        // Editor: se prueba el código tal cual está, sin guardarlo.
        final texto = await widget.obtenerTexto!();
        if (!mounted || _cancelado) return;
        if (texto == null || texto.trim().isEmpty) {
          setState(() {
            _error = 'El editor está vacío: no hay código para ejecutar.';
            _resultado = null;
            _ejecutando = false;
          });
          return;
        }
        res = await SirwebService().ejecutarBorrador(
          deTexto: texto,
          inConfiguracion: widget.inConfiguracion,
          request: request,
          client: client,
          cancelado: () => _cancelado,
        );
      } else {
        // Consulta: sólo se manda el nombre; el backend lee el texto guardado.
        res = await SirwebService().ejecutarProcedimiento(
          widget.cdProcedimiento,
          request: request,
          client: client,
          cancelado: () => _cancelado,
        );
      }
      if (!mounted || _cancelado) return;
      setState(() {
        _resultado = res;
        _ejecutando = false;
        _tab = res.tieneError ? 1 : 0;
      });
      if (res.tieneError) {
        AppToast.error('La ejecución devolvió un error de Oracle');
      } else {
        AppToast.info(
          'Ejecutado en ${_formatearTiempoMsYSeg(res.duracionMs ?? 0)}',
        );
      }
    } catch (e) {
      if (!mounted || _cancelado) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _resultado = null;
        _ejecutando = false;
      });
    } finally {
      client.close();
      if (identical(_ejecucionClient, client)) {
        _ejecucionClient = null;
      }
    }
  }

  /// Cancela la petición HTTP en curso.
  void _cancelar() {
    if (!_ejecutando) return;
    _cancelado = true;
    _ejecucionClient?.close();
    _ejecucionClient = null;
    setState(() {
      _ejecutando = false;
      _error = 'Petición cancelada por el usuario.';
    });
    AppToast.info('Petición cancelada');
  }

  void _limpiar() {
    setState(() {
      for (final entry in _ctrls.entries) {
        entry.value.text = entry.key == 'cdEntidad' ? '1' : '';
      }
      _camposAdicionalesCtrl.clear();
      _timeoutCtrl.text = '30';
      _resultado = null;
      _error = null;
    });
  }

  Future<void> _copiarJson() async {
    final res = _resultado;
    if (res == null) return;
    const encoder = JsonEncoder.withIndent('  ');
    await Clipboard.setData(ClipboardData(text: encoder.convert(res.raw)));
    AppToast.info('Resultado copiado al portapapeles');
  }

  // ── Ambiente ──────────────────────────────────────────
  /// Cambia la base contra la que se ejecuta sin cerrar la ventana.
  ///
  /// El resultado anterior se descarta a propósito: sus salidas, su traza y su
  /// contexto son de otra base y mezclarlos lleva a conclusiones equivocadas.
  void _onAmbienteChanged(String nuevo) {
    if (nuevo == _ambiente || _ejecutando) return;
    setState(() {
      _ambiente = nuevo;
      _resultado = null;
      _error = null;
      _tab = 0;
    });
  }

  // ── Exportación ────────────────────────────────────────
  static String _stamp() {
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${p(now.month)}${p(now.day)}_'
        '${p(now.hour)}${p(now.minute)}${p(now.second)}';
  }

  /// Pide la ruta, escribe [contenido] y avisa con un toast que permite abrir
  /// la carpeta destino. Centraliza el manejo de errores de disco.
  Future<void> _guardarArchivo({
    required String contenido,
    required String fileName,
    required String extension,
    required String titulo,
  }) async {
    if (contenido.trim().isEmpty) {
      AppToast.warning('No hay datos para exportar');
      return;
    }
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: titulo,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
      if (path == null) return;
      await File(path).writeAsString(contenido, flush: true);
      AppLog.instance.transaction(
        'Exportar ejecución ${widget.cdProcedimiento}',
        source: 'Ejecución',
        datos: {'Ambiente': _ambiente, 'Archivo': path},
      );
      AppToast.successWithAction(
        'Exportado: ${path.split(Platform.pathSeparator).last}',
        actionLabel: 'Abrir ubicación',
        onAction: () => unawaited(BackupService.revealInExplorer(path)),
      );
    } catch (e, st) {
      AppLog.instance.exception(
        'Exportar ejecución ${widget.cdProcedimiento}',
        e,
        stack: st,
        source: 'Ejecución',
        datos: {'Ambiente': _ambiente, 'Archivo': fileName},
      );
      AppToast.error('No se pudo exportar: ${AppLog.describe(e)}');
    }
  }

  /// Parámetros de contexto con los que se disparó la ejecución (sin vacíos).
  Map<String, String> get _parametrosUsados => {
    for (final e in _ctrls.entries)
      if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    if (_camposAdicionalesCtrl.text.trim().isNotEmpty)
      'camposAdicionales': _camposAdicionalesCtrl.text.trim(),
    'timeoutSegundos': _timeoutCtrl.text.trim(),
  };

  /// Exporta todo: parámetros enviados + la respuesta completa del backend.
  Future<void> _exportarTodo() async {
    final res = _resultado;
    if (res == null) {
      AppToast.warning('Ejecutá el procedimiento antes de exportar');
      return;
    }
    const encoder = JsonEncoder.withIndent('  ');
    final contenido = encoder.convert({
      'cdProcedimiento': widget.cdProcedimiento,
      'ambiente': _ambiente,
      'origen': widget.obtenerTexto != null
          ? 'borrador (código del editor)'
          : 'guardado en PROCEDIMIENTODINAMICO',
      'exportado': DateTime.now().toIso8601String(),
      'parametros': _parametrosUsados,
      'resultado': res.raw,
    });
    await _guardarArchivo(
      contenido: contenido,
      fileName:
          'ejecucion_${widget.cdProcedimiento}_'
          '${_ambiente.toUpperCase()}_${_stamp()}.json',
      extension: 'json',
      titulo: 'Exportar ejecución completa',
    );
  }

  String get _nombreTab => switch (_tab) {
    0 => 'salidas',
    1 => 'traza',
    2 => 'contexto',
    3 => 'variables',
    _ => 'declaradas',
  };
  static String _tsv(Iterable<List<String>> filas) =>
      filas.map((f) => f.join('\t')).join('\n');
  static String _txt(dynamic v) => v?.toString() ?? '';

  /// Contenido y extensión del tab activo, en el formato que mejor le calza:
  /// tabular (TSV, para pegar en una planilla) o texto plano para la traza.
  (String, String) _contenidoTab(EjecucionResultado res) {
    switch (_tab) {
      case 0:
        final e = res.salidas.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return (
          _tsv([
            ['CAMPO', 'VALOR'],
            ...e.map((x) => [x.key, _txt(x.value)]),
          ]),
          'tsv',
        );
      case 1:
        final buf = StringBuffer();
        if (res.tieneError) buf.writeln('ERROR ORACLE: ${res.errorOracle}\n');
        buf.writeAll(res.traza, '\n');
        return (buf.toString(), 'log');
      case 2:
        final ctx = res.contexto;
        final campos = ctx.camposDesdeBd.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final buf = StringBuffer()
          ..writeln('Tipo de contexto: ${_txt(ctx.tipo)}')
          ..writeln('Record          : ${_txt(ctx.record)}')
          ..writeln()
          ..writeln('CAMPO\tVALOR\tORIGEN');
        for (final c in campos) {
          buf.writeln('${c.key}\t${_txt(c.value)}\tBD');
        }
        for (final c in ctx.camposSobreescritos) {
          buf.writeln('$c\t\tSOBRESCRITO');
        }
        for (final c in ctx.camposSinResolver) {
          buf.writeln('$c\t\tSIN RESOLVER');
        }
        return (buf.toString(), 'txt');
      case 3:
        final e = res.variablesDinamicasUsadas.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return (
          _tsv([
            ['VARIABLE', 'VALOR'],
            ...e.map((x) => [x.key, _txt(x.value)]),
          ]),
          'tsv',
        );
      default:
        return (
          _tsv([
            ['VARIABLE', 'TIPO', 'INICIAL', 'VALOR FINAL'],
            ...res.variablesDeclaradas.map(
              (v) => [
                v.nombre,
                _txt(v.tipo),
                _txt(v.valorInicial),
                _txt(v.valor),
              ],
            ),
          ]),
          'tsv',
        );
    }
  }

  /// Exporta únicamente lo que se está viendo en el tab activo.
  Future<void> _exportarTab(EjecucionResultado res) async {
    final (contenido, ext) = _contenidoTab(res);
    await _guardarArchivo(
      contenido: contenido,
      fileName:
          '${_nombreTab}_${widget.cdProcedimiento}_'
          '${_ambiente.toUpperCase()}_${_stamp()}.$ext',
      extension: ext,
      titulo: 'Exportar $_nombreTab',
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (_maximized) {
      _modalW = (size.width - 48).clamp(560.0, size.width);
      _modalH = (size.height - 48).clamp(360.0, size.height);
    } else {
      _modalW ??= (size.width * 0.84).clamp(700.0, 1020.0);
      _modalH ??= (size.height * 0.80).clamp(480.0, 740.0);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_ejecutar()),
      },
      child: Focus(
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
                          if (!_minimized)
                            Expanded(child: _buildBody(isDark, w)),
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
                        560.0,
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
                        560.0,
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

  Widget _buildHeader(bool isDark) {
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
                padding: EdgeInsets.all(_minimized ? 5 : 8),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(_minimized ? 6 : 8),
                ),
                child: Icon(
                  Icons.play_circle_outline_rounded,
                  size: _minimized ? 15 : 20,
                  color: _accent,
                ),
              ),
              SizedBox(width: _minimized ? 8 : 12),
              if (_minimized)
                Expanded(
                  child: Text(
                    'Ejecutar · ${widget.cdProcedimiento}',
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
                      Row(
                        children: [
                          Text(
                            'Ejecutar procedimiento dinámico',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white38 : Colors.black38,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // El ambiente se cambia acá mismo: no hace falta
                          // cerrar la ventana ni volver al tab del editor.
                          AmbienteSelector(
                            value: _ambiente,
                            onChanged: _onAmbienteChanged,
                          ),
                          if (widget.inConfiguracion != null &&
                              widget.inConfiguracion!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _StatusBadge(
                              label: 'Config ${widget.inConfiguracion}',
                              color: const Color(0xFF607D8B),
                            ),
                          ],
                          const SizedBox(width: 6),
                          _StatusBadge(
                            label: widget.obtenerTexto != null
                                ? 'Código del editor'
                                : 'Código guardado',
                            color: widget.obtenerTexto != null
                                ? Colors.orange
                                : const Color(0xFF16A34A),
                          ),
                        ],
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
                  icon: const Icon(Icons.save_alt_rounded, size: 17),
                  tooltip: 'Exportar toda la ejecución (JSON)',
                  onPressed: _resultado == null
                      ? null
                      : () => unawaited(_exportarTodo()),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              if (!_minimized)
                IconButton(
                  icon: const Icon(Icons.cleaning_services_outlined, size: 17),
                  tooltip: 'Limpiar parámetros',
                  onPressed: _ejecutando ? null : _limpiar,
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

  Widget _buildBody(bool isDark, double width) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);
    // Por debajo de ~760 px el layout de dos columnas deja los campos
    // ilegibles: se apila el formulario arriba del resultado.
    final compacto = width < 760;

    final params = _buildParametros(isDark, borderColor);
    final resultado = _buildResultado(isDark, borderColor);

    if (compacto) {
      return Column(
        children: [
          SizedBox(height: 260, child: params),
          Container(height: 1, color: borderColor),
          Expanded(child: resultado),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(width: 330, child: params),
        Container(width: 1, color: borderColor),
        Expanded(child: resultado),
      ],
    );
  }

  // ── Panel de parámetros ─────────────────────────────────────────────────

  Widget _buildParametros(bool isDark, Color borderColor) {
    return Column(
      children: [
        Expanded(
          child: Scrollbar(
            controller: _paramsScroll,
            child: ListView(
              controller: _paramsScroll,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              children: [
                _SeccionLabel(label: 'Contexto', isDark: isDark),
                const SizedBox(height: 8),
                for (final c in _kCamposEjecucion) ...[
                  _CampoTexto(
                    controller: _ctrls[c.key]!,
                    label: c.label,
                    hint: c.hint ?? '',
                    numerico: c.numerico,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 4),
                _SeccionLabel(label: 'Parámetros', isDark: isDark),
                const SizedBox(height: 8),
                for (final c in _kCamposTextoEjecucion) ...[
                  _CampoTexto(
                    controller: _ctrls[c.key]!,
                    label: c.label,
                    hint: c.hint ?? '',
                    numerico: c.numerico,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 4),
                _SeccionLabel(
                  label: 'Campos adicionales (JSON)',
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _CampoTexto(
                  controller: _camposAdicionalesCtrl,
                  label: '',
                  hint: '{ "CD_PRODUCTO": 10 }',
                  numerico: false,
                  isDark: isDark,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                _CampoTexto(
                  controller: _timeoutCtrl,
                  label: 'Timeout (segundos)',
                  hint: '30',
                  numerico: true,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 34,
            child: _ejecutando
                ? Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent.withValues(alpha: 0.6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          icon: const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: Colors.white,
                            ),
                          ),
                          label: const Text(
                            'Ejecutando…',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _cancelar,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(
                            color: Colors.redAccent.withValues(alpha: 0.8),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        icon: const Icon(Icons.stop_rounded, size: 16),
                        label: const Text(
                          'Cancelar',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                : FilledButton.icon(
                    onPressed: () => unawaited(_ejecutar()),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 17),
                    label: const Text(
                      'Ejecutar (Ctrl+Enter)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ── Panel de resultado ──────────────────────────────────────────────────

  Widget _buildResultado(bool isDark, Color borderColor) {
    if (_error != null) {
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
              SelectableText(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _ejecutando ? null : () => unawaited(_ejecutar()),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final res = _resultado;
    if (res == null) {
      return Column(
        children: [
          if (_ejecutando) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _EmptyState(
              icon: Icons.play_circle_outline_rounded,
              message: _ejecutando
                  ? 'Ejecutando el procedimiento…'
                  : 'Completá el contexto y ejecutá el procedimiento\n'
                        'para ver salidas, traza y errores de Oracle.',
              isDark: isDark,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (_ejecutando) const LinearProgressIndicator(minHeight: 2),
        _buildResumen(res, isDark, borderColor),
        _buildTabs(res, isDark, borderColor),
        Expanded(child: _buildTabContent(res, isDark)),
      ],
    );
  }

  Widget _buildResumen(EjecucionResultado res, bool isDark, Color borderColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StatusBadge(
            label: res.tieneError ? 'Error Oracle' : 'OK',
            color: res.tieneError ? Colors.redAccent : _accent,
          ),
          // Lo confirma el backend: sirve para detectar que se ejecutó el
          // texto del editor y no el guardado en la base.
          if (res.borrador)
            const _StatusBadge(label: 'Borrador', color: Colors.orange),
          if (res.duracionMs != null)
            _StatusBadge(
              label: _formatearTiempoMsYSeg(res.duracionMs!),
              color: const Color(0xFF0078D4),
            ),
          if (res.rollback)
            const _StatusBadge(label: 'Rollback', color: Colors.orange),
          if (res.commitDetectado)
            const _StatusBadge(
              label: 'COMMIT detectado',
              color: Colors.deepOrange,
            ),
          if (res.orquestador != null && res.orquestador!.isNotEmpty)
            _StatusBadge(
              label: res.orquestador!,
              color: const Color(0xFF8E44AD),
            ),
          if (res.inConfiguracion != null && res.inConfiguracion!.isNotEmpty)
            _StatusBadge(
              label: 'Config ${res.inConfiguracion}',
              color: const Color(0xFF607D8B),
            ),
          // Estado del procedimiento en la base: un '0' avisa que la regla
          // está inactiva aunque la ejecución haya salido bien.
          if (res.stProcedimiento != null && res.stProcedimiento!.isNotEmpty)
            _StatusBadge(
              label: res.stProcedimiento == '1' ? 'Activo' : 'Inactivo',
              color: res.stProcedimiento == '1'
                  ? const Color(0xFF16A34A)
                  : Colors.redAccent,
            ),
          if (res.variablesDeclaradas.isNotEmpty)
            _StatusBadge(
              label: '${res.variablesDeclaradas.length} declaradas',
              color: const Color(0xFF2E9E6B),
            ),
        ],
      ),
    );
  }

  Widget _buildTabs(EjecucionResultado res, bool isDark, Color borderColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          _TabChip(
            label: 'Salidas',
            count: res.salidas.length,
            active: _tab == 0,
            accent: _accent,
            isDark: isDark,
            onTap: () => setState(() => _tab = 0),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'Traza',
            count: res.traza.length + (res.tieneError ? 1 : 0),
            active: _tab == 1,
            accent: res.tieneError ? Colors.redAccent : const Color(0xFF0078D4),
            isDark: isDark,
            onTap: () => setState(() => _tab = 1),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'Contexto',
            count:
                res.contexto.camposDesdeBd.length +
                res.contexto.camposSobreescritos.length +
                res.contexto.camposSinResolver.length,
            active: _tab == 2,
            accent: const Color(0xFF8E44AD),
            isDark: isDark,
            onTap: () => setState(() => _tab = 2),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'Variables',
            count: res.variablesDinamicasUsadas.length,
            active: _tab == 3,
            accent: Colors.orange,
            isDark: isDark,
            onTap: () => setState(() => _tab = 3),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'Declaradas',
            count: res.variablesDeclaradas.length,
            active: _tab == 4,
            accent: const Color(0xFF2E9E6B),
            isDark: isDark,
            onTap: () => setState(() => _tab = 4),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.file_download_outlined, size: 16),
            tooltip: 'Exportar $_nombreTab',
            onPressed: () => unawaited(_exportarTab(res)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_rounded, size: 16),
            tooltip: 'Copiar resultado (JSON)',
            onPressed: () => unawaited(_copiarJson()),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(EjecucionResultado res, bool isDark) {
    return switch (_tab) {
      0 => _buildSalidas(res, isDark),
      1 => _buildTraza(res, isDark),
      2 => _buildContexto(res, isDark),
      3 => _buildVariables(res, isDark),
      _ => _buildDeclaradas(res, isDark),
    };
  }

  Widget _buildSalidas(EjecucionResultado res, bool isDark) {
    if (res.salidas.isEmpty) {
      return _EmptyState(
        icon: Icons.output_rounded,
        message: 'El procedimiento no devolvió salidas',
        isDark: isDark,
      );
    }

    final borderColor = isDark
        ? const Color(0xFF2F2F2F)
        : const Color(0xFFEDF0F5);
    final entries = res.salidas.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Scrollbar(
      controller: _resultScroll,
      child: ListView.separated(
        controller: _resultScroll,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: entries.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: borderColor),
        itemBuilder: (_, i) => _FilaValor(
          campo: entries[i].key,
          valor: entries[i].value,
          isDark: isDark,
        ),
      ),
    );
  }

  Widget _buildTraza(EjecucionResultado res, bool isDark) {
    if (res.traza.isEmpty && !res.tieneError) {
      return _EmptyState(
        icon: Icons.notes_rounded,
        message: 'Sin traza de ejecución',
        isDark: isDark,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      children: [
        if (res.tieneError) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    res.errorOracle!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'Consolas',
                      height: 1.4,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.content_copy_rounded, size: 14),
                  tooltip: 'Copiar error',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: res.errorOracle!));
                    AppToast.info('Error copiado');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (res.traza.isNotEmpty)
          _SqlBlock(sql: res.traza.join('\n'), isDark: isDark),
      ],
    );
  }

  Widget _buildContexto(EjecucionResultado res, bool isDark) {
    final ctx = res.contexto;
    if (ctx.isEmpty) {
      return _EmptyState(
        icon: Icons.dataset_outlined,
        message: 'Sin información de contexto',
        isDark: isDark,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      children: [
        if (ctx.tipo != null && ctx.tipo!.isNotEmpty) ...[
          _SeccionLabel(label: 'Tipo de contexto', isDark: isDark),
          const SizedBox(height: 6),
          SelectableText(
            ctx.tipo!,
            style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
          ),
          const SizedBox(height: 12),
        ],
        if (ctx.record != null && ctx.record!.isNotEmpty) ...[
          _SeccionLabel(label: 'Record', isDark: isDark),
          const SizedBox(height: 6),
          _SqlBlock(sql: ctx.record!, isDark: isDark),
          const SizedBox(height: 6),
        ],
        _MapaCampos(
          titulo: 'Campos desde BD',
          campos: ctx.camposDesdeBd,
          isDark: isDark,
        ),
        _ListaCampos(
          titulo: 'Campos sobrescritos',
          campos: ctx.camposSobreescritos,
          color: const Color(0xFF0078D4),
          isDark: isDark,
        ),
        _ListaCampos(
          titulo: 'Campos sin resolver',
          campos: ctx.camposSinResolver,
          color: Colors.orange,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildVariables(EjecucionResultado res, bool isDark) {
    if (res.variablesDinamicasUsadas.isEmpty) {
      return _EmptyState(
        icon: Icons.data_object_rounded,
        message: 'No se usaron variables dinámicas',
        isDark: isDark,
      );
    }

    // El backend devuelve `variable → valor resuelto`; las respuestas viejas
    // sólo traían los nombres y el valor queda en `null` (se muestra NULL).
    final borderColor = isDark
        ? const Color(0xFF2F2F2F)
        : const Color(0xFFEDF0F5);
    final entries = res.variablesDinamicasUsadas.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: borderColor),
      itemBuilder: (_, i) => _FilaValor(
        campo: entries[i].key,
        valor: entries[i].value,
        isDark: isDark,
      ),
    );
  }

  /// Bloque `DECLARE` que armó el orquestador: nombre, tipo y valor inicial de
  /// cada variable con la que se envolvió el texto de la regla.
  Widget _buildDeclaradas(EjecucionResultado res, bool isDark) {
    final vars = res.variablesDeclaradas;
    if (vars.isEmpty) {
      return _EmptyState(
        icon: Icons.code_rounded,
        message: 'El orquestador no declaró variables',
        isDark: isDark,
      );
    }

    final borderColor = isDark
        ? const Color(0xFF2F2F2F)
        : const Color(0xFFEDF0F5);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      children: [
        _SeccionLabel(
          label: 'Variables declaradas (${vars.length})',
          isDark: isDark,
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _HeaderDeclaradas(isDark: isDark),
              Divider(height: 1, color: borderColor),
              for (var i = 0; i < vars.length; i++) ...[
                if (i > 0) Divider(height: 1, color: borderColor),
                _FilaVariableDeclarada(variable: vars[i], isDark: isDark),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Fila del detalle de una variable declarada: nombre, tipo PL/SQL, el valor
/// inicial del `DECLARE` y el valor con el que quedó al terminar la ejecución.
///
/// Cuando la regla modificó la variable, el valor final se resalta: es el dato
/// que se mira al depurar por qué el procedimiento devolvió lo que devolvió.
class _FilaVariableDeclarada extends StatelessWidget {
  final VariableDeclarada variable;
  final bool isDark;
  const _FilaVariableDeclarada({required this.variable, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final tipo = (variable.tipo ?? '').trim();
    final inicial = variable.valorInicial?.toString() ?? '';
    final valor = variable.valor?.toString() ?? '';
    final muted = isDark ? Colors.white38 : Colors.black38;
    final cambio = variable.cambio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: SelectableText(
              variable.nombre,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: tipo.isEmpty
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E9E6B).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF2E9E6B).withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        tipo,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E9E6B),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              inicial.isEmpty ? 'NULL' : inicial,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Consolas',
                color: inicial.isEmpty ? muted : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.arrow_right_alt_rounded, size: 15, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              valor.isEmpty ? 'NULL' : valor,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Consolas',
                fontWeight: cambio ? FontWeight.w700 : FontWeight.w400,
                color: valor.isEmpty
                    ? muted
                    : (cambio ? const Color(0xFF2E9E6B) : null),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.content_copy_rounded, size: 13),
            tooltip: 'Copiar valor final',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: valor));
              AppToast.info('${variable.nombre} copiado');
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
        ],
      ),
    );
  }
}

/// Encabezado de la tabla de variables declaradas.
class _HeaderDeclaradas extends StatelessWidget {
  final bool isDark;
  const _HeaderDeclaradas({required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: _SeccionLabel(label: 'Variable', isDark: isDark),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: _SeccionLabel(label: 'Tipo', isDark: isDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SeccionLabel(label: 'Inicial', isDark: isDark),
          ),
          const SizedBox(width: 31),
          Expanded(
            child: _SeccionLabel(label: 'Valor final', isDark: isDark),
          ),
        ],
      ),
    );
  }
}

/// Lista de campos del contexto agrupados por origen.
class _ListaCampos extends StatelessWidget {
  final String titulo;
  final List<String> campos;
  final Color color;
  final bool isDark;

  const _ListaCampos({
    required this.titulo,
    required this.campos,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (campos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SeccionLabel(label: '$titulo (${campos.length})', isDark: isDark),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in campos) _StatusBadge(label: c, color: color),
            ],
          ),
        ],
      ),
    );
  }
}

/// Campos del contexto resueltos con su valor (`CAMPO` → valor).
class _MapaCampos extends StatelessWidget {
  final String titulo;
  final Map<String, dynamic> campos;
  final bool isDark;

  const _MapaCampos({
    required this.titulo,
    required this.campos,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (campos.isEmpty) return const SizedBox.shrink();

    final borderColor = isDark
        ? const Color(0xFF2F2F2F)
        : const Color(0xFFEDF0F5);
    final entries = campos.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SeccionLabel(
                  label: '$titulo (${campos.length})',
                  isDark: isDark,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_all_rounded, size: 14),
                tooltip: 'Copiar campos (TSV)',
                onPressed: () {
                  final buf = StringBuffer();
                  for (final e in entries) {
                    buf.writeln('${e.key}\t${e.value ?? ''}');
                  }
                  Clipboard.setData(ClipboardData(text: buf.toString()));
                  AppToast.info('Campos copiados');
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: borderColor),
                  _FilaValor(
                    campo: entries[i].key,
                    valor: entries[i].value,
                    isDark: isDark,
                    anchoCampo: 170,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila `CAMPO → valor` con soporte de formateo (beautify) y colapsado para arrays JSON.
///
/// La comparten la pestaña de salidas y la de contexto en ambos modales de ejecución.
class _FilaValor extends StatefulWidget {
  final String campo;
  final dynamic valor;
  final bool isDark;
  final double anchoCampo;

  const _FilaValor({
    required this.campo,
    required this.valor,
    required this.isDark,
    this.anchoCampo = 190,
  });

  @override
  State<_FilaValor> createState() => _FilaValorState();
}

class _FilaValorState extends State<_FilaValor> {
  final _scrollVert = ScrollController();
  bool _colapsado = true;
  bool _beautify = true;
  bool _esJson = false;
  bool _esArray = false;
  dynamic _parsedJson;
  int _cantidadElementos = 0;

  @override
  void initState() {
    super.initState();
    _analizarValor();
  }

  @override
  void didUpdateWidget(_FilaValor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valor != widget.valor) {
      _analizarValor();
    }
  }

  @override
  void dispose() {
    _scrollVert.dispose();
    super.dispose();
  }

  void _analizarValor() {
    final v = widget.valor;
    if (v == null) {
      _esJson = false;
      _esArray = false;
      _parsedJson = null;
      _cantidadElementos = 0;
      return;
    }

    if (v is List) {
      _esJson = true;
      _esArray = true;
      _parsedJson = v;
      _cantidadElementos = v.length;
      return;
    }

    if (v is Map) {
      _esJson = true;
      _esArray = false;
      _parsedJson = v;
      _cantidadElementos = v.length;
      return;
    }

    if (v is String) {
      final s = v.trim();
      if ((s.startsWith('[') && s.endsWith(']')) ||
          (s.startsWith('{') && s.endsWith('}'))) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is List) {
            _esJson = true;
            _esArray = true;
            _parsedJson = decoded;
            _cantidadElementos = decoded.length;
            return;
          } else if (decoded is Map) {
            _esJson = true;
            _esArray = false;
            _parsedJson = decoded;
            _cantidadElementos = decoded.length;
            return;
          }
        } catch (_) {}
      }
    }

    _esJson = false;
    _esArray = false;
    _parsedJson = null;
    _cantidadElementos = 0;
  }

  String _obtenerTextoFormateado() {
    if (!_esJson || _parsedJson == null) {
      return widget.valor?.toString() ?? 'NULL';
    }
    if (_beautify) {
      try {
        const encoder = JsonEncoder.withIndent('  ');
        return encoder.convert(_parsedJson);
      } catch (_) {
        return widget.valor.toString();
      }
    } else {
      try {
        return jsonEncode(_parsedJson);
      } catch (_) {
        return widget.valor.toString();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_esJson) {
      final texto = widget.valor?.toString() ?? 'NULL';
      final vacio = widget.valor == null || texto.isEmpty;

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: widget.anchoCampo,
              child: Text(
                widget.campo,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                vacio ? 'NULL' : texto,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  color: vacio
                      ? (widget.isDark ? Colors.white38 : Colors.black38)
                      : null,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.content_copy_rounded, size: 14),
              tooltip: 'Copiar valor',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: texto));
                AppToast.info('Copiado');
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            ),
          ],
        ),
      );
    }

    final badgeColor = _esArray
        ? const Color(0xFF7C3AED)
        : const Color(0xFF0F766E);
    final badgeLabel = _esArray
        ? '$_cantidadElementos ${_cantidadElementos == 1 ? 'item' : 'items'}'
        : '$_cantidadElementos ${_cantidadElementos == 1 ? 'campo' : 'campos'}';

    if (_colapsado) {
      final textoUnaLinea = widget.valor is String
          ? (widget.valor as String).replaceAll(RegExp(r'\s+'), ' ').trim()
          : jsonEncode(_parsedJson);
      final snippet = textoUnaLinea.length > 70
          ? '${textoUnaLinea.substring(0, 67)}...'
          : textoUnaLinea;

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: widget.anchoCampo,
              child: Text(
                widget.campo,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: badgeColor.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: badgeColor,
                  fontFamily: 'Consolas',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _colapsado = false),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          snippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'Consolas',
                            color: widget.isDark
                                ? const Color(0xFFD4D4D4)
                                : const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: 15,
                        color: widget.isDark ? Colors.white38 : Colors.black38,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              tooltip: 'Expandir JSON (Beautify)',
              onPressed: () => setState(() => _colapsado = false),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            ),
            IconButton(
              icon: const Icon(Icons.content_copy_rounded, size: 14),
              tooltip: 'Copiar JSON',
              onPressed: () {
                final aCopiar = _obtenerTextoFormateado();
                Clipboard.setData(ClipboardData(text: aCopiar));
                AppToast.info('JSON copiado');
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            ),
          ],
        ),
      );
    }

    // Estado expandido con Beautify y scroll
    final textoFormateado = _obtenerTextoFormateado();
    final bgCode = widget.isDark
        ? const Color(0xFF181818)
        : const Color(0xFFF8F9FA);
    final borderCode = widget.isDark
        ? const Color(0xFF333333)
        : const Color(0xFFE2E8F0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.campo,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  'JSON ${_esArray ? 'Array' : 'Object'} ($badgeLabel)',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: badgeColor,
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _beautify = !_beautify),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _beautify
                        ? const Color(0xFF0078D4).withValues(alpha: 0.15)
                        : (widget.isDark ? Colors.white10 : Colors.black12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _beautify
                          ? const Color(0xFF0078D4)
                          : Colors.transparent,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _beautify
                            ? Icons.auto_fix_high_rounded
                            : Icons.compress_rounded,
                        size: 13,
                        color: _beautify
                            ? const Color(0xFF0078D4)
                            : (widget.isDark ? Colors.white70 : Colors.black87),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _beautify ? 'Beautify' : 'Compacto',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _beautify
                              ? const Color(0xFF0078D4)
                              : (widget.isDark
                                    ? Colors.white70
                                    : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.content_copy_rounded, size: 14),
                tooltip:
                    'Copiar JSON (${_beautify ? 'formateado' : 'compacto'})',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: textoFormateado));
                  AppToast.info('JSON copiado');
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.expand_less_rounded, size: 18),
                tooltip: 'Colapsar',
                onPressed: () => setState(() => _colapsado = true),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 340, minHeight: 48),
            decoration: BoxDecoration(
              color: bgCode,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderCode),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Scrollbar(
                controller: _scrollVert,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollVert,
                  padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      textoFormateado,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11.5,
                        height: 1.45,
                        color: widget.isDark
                            ? const Color(0xFFD4D4D4)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
