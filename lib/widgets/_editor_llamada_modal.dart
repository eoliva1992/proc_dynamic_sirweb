part of 'code_editor_panel.dart';

// ── Modal: ejecutar un objeto PL/SQL cualquiera ───────────────────────────
//
// A diferencia de `_editor_ejecutar_modal.dart` (exclusivo de las reglas de
// negocio de PROCEDIMIENTODINAMICO), acá se invoca cualquier PROCEDURE,
// FUNCTION o miembro de un PACKAGE del esquema.
//
// El objeto se elige de la **misma lista que muestra el sidebar de esquema**
// (`SchemaService.instance.getMetadata().objects`), no se tipea a mano: así
// no hay errores de nombre y el owner sale resuelto del diccionario.

const _kLlamadaAccent = Color(0xFF7C3AED);

/// Tipos de objeto que se pueden invocar desde esta ventana.
const _kTiposInvocables = {'PROCEDURE', 'FUNCTION', 'PACKAGE'};

/// Abre la ventana de invocación de un objeto PL/SQL.
///
/// Se inserta en el overlay raíz (sin barrera modal) para poder minimizarla y
/// seguir trabajando en el editor.
///
/// [objeto] precarga la selección (`SIR.PCK_X.MI_PROC` o `MI_PROC`).
void showEjecutarLlamadaWindow(
  BuildContext context, {
  String ambiente = 'Desa',
  String? objeto,
}) {
  _showFloatingWindow(
    context,
    (close) => _LlamadaPlsqlModal(
      ambienteInicial: ambiente,
      objetoInicial: objeto,
      onClose: close,
    ),
  );
}

/// Un subprograma de package tal como lo devuelve `SchemaService`.
typedef _Subprograma = ({
  String name,
  String kind,
  List<({String name, String dataType, String inOut})> arguments,
});

/// Un objeto del esquema tal como lo devuelve `SchemaMetadata.objects`.
typedef _ObjetoEsquema = ({String name, String type, String owner});

class _LlamadaPlsqlModal extends StatefulWidget {
  final String ambienteInicial;
  final String? objetoInicial;
  final VoidCallback onClose;

  const _LlamadaPlsqlModal({
    required this.ambienteInicial,
    required this.onClose,
    this.objetoInicial,
  });

  @override
  State<_LlamadaPlsqlModal> createState() => _LlamadaPlsqlModalState();
}

class _LlamadaPlsqlModalState extends State<_LlamadaPlsqlModal> {
  static const _accent = _kLlamadaAccent;
  static const _prefsRecientes = 'llamada_plsql_recientes';

  final _buscarObjetoCtrl = TextEditingController();
  final _buscarMiembroCtrl = TextEditingController();
  final _overloadCtrl = TextEditingController();
  final _timeoutCtrl = TextEditingController(text: '30');
  final _manualCtrl = TextEditingController();
  final _paramsScroll = ScrollController();
  final _resultScroll = ScrollController();

  late String _ambiente = widget.ambienteInicial;

  // ── Catálogo de objetos (mismo origen que el sidebar) ───────────────────
  SchemaMetadata? _meta;
  bool _cargandoMeta = false;

  _ObjetoEsquema? _objetoSel;
  bool _listaObjetosAbierta = false;

  // ── Subprogramas cuando el objeto elegido es un PACKAGE ─────────────────
  List<_Subprograma> _subprogramas = const [];
  _Subprograma? _miembroSel;
  bool _cargandoSubprogramas = false;
  bool _listaMiembrosAbierta = false;

  /// Firma resuelta del subprograma (incluye OUT y retorno, para mostrarla).
  List<ParametroFirma> _firma = const [];

  /// Tipos exactos declarados en PL/SQL (ej. package spec) para cada parámetro.
  Map<String, String> _tiposDeclaracion = {};

  /// Controllers de los valores de entrada, indexados por nombre de parámetro.
  final Map<String, TextEditingController> _valores = {};

  /// Parámetros cuyo valor se manda **crudo** como expresión SQL
  /// (`SYSDATE`, `TO_DATE('…','…')`) en vez de literal entrecomillado.
  final Set<String> _expresiones = {};

  /// `true` ⇒ el usuario escribe la llamada completa a mano.
  bool _manual = false;

  /// Despliega la lista de objetos usados recientemente.
  bool _mostrarRecientes = false;

  /// Ambiente elegido que está esperando confirmación (sólo `Prod`).
  ///
  /// La confirmación es **inline**: un `showDialog` se renderizaría por debajo
  /// de esta ventana, que vive en un `OverlayEntry` propio por encima de las
  /// rutas del Navigator.
  String? _confirmarAmbiente;

  /// Despliega el combo de ambiente del encabezado.
  bool _menuAmbienteAbierto = false;

  /// Ancla el menú del combo a su botón dentro del `Stack` de esta ventana.
  ///
  /// El menú se dibuja como hijo del propio `Stack` (no con `DropdownButton`,
  /// que lo pushea como ruta del Navigator y quedaría tapado por la ventana).
  final LayerLink _linkAmbiente = LayerLink();

  bool _cargandoFirma = false;
  bool _ejecutando = false;
  http.Client? _ejecucionClient;
  bool _cancelado = false;
  LlamadaResultado? _resultado;

  /// Llamada literal que se mandó en la última ejecución.
  ///
  /// Se guarda aparte porque el backend devuelve la versión normalizada (con
  /// los literales ya reemplazados por variables `v_N` del bloque anónimo).
  String? _llamadaEnviada;
  String? _error;
  String? _avisoFirma;
  int _tab = 0; // 0 salidas · 1 enviados · 2 firma · 3 traza

  List<String> _recientes = const [];

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

  @override
  void initState() {
    super.initState();
    unawaited(_cargarRecientes());
    unawaited(_cargarCatalogo(seleccionInicial: widget.objetoInicial));
  }

  @override
  void dispose() {
    if (_ejecutando) {
      _cancelado = true;
      _ejecucionClient?.close();
      _ejecucionClient = null;
    }
    _MinimizedSlots.release(_slot);
    _buscarObjetoCtrl.dispose();
    _buscarMiembroCtrl.dispose();
    _overloadCtrl.dispose();
    _timeoutCtrl.dispose();
    _manualCtrl.dispose();
    for (final c in _valores.values) {
      c.dispose();
    }
    _paramsScroll.dispose();
    _resultScroll.dispose();
    super.dispose();
  }

  // ── Catálogo de objetos ─────────────────────────────────────────────────

  /// Carga el catálogo del esquema (el mismo que alimenta el sidebar).
  Future<void> _cargarCatalogo({
    String? seleccionInicial,
    bool forceRefresh = false,
  }) async {
    setState(() => _cargandoMeta = true);
    try {
      final meta = await SchemaService.instance.getMetadata(
        ambiente: _ambiente,
      );
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _cargandoMeta = false;
      });
      if (seleccionInicial != null && seleccionInicial.trim().isNotEmpty) {
        final resuelto = await _aplicarNombreCompleto(
          seleccionInicial,
          forceRefresh: forceRefresh,
        );
        if (!mounted) return;
        if (!resuelto) {
          setState(() {
            _objetoSel = null;
            _miembroSel = null;
            _subprogramas = const [];
            _buscarObjetoCtrl.clear();
            _buscarMiembroCtrl.clear();
            _firma = const [];
            _avisoFirma =
                '$seleccionInicial no aparece en el catálogo de $_ambiente. '
                'Elegí otro objeto o revisá los permisos.';
            _listaObjetosAbierta = true;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoMeta = false;
        _avisoFirma =
            'No se pudo cargar el catálogo de $_ambiente — '
            '${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  /// Objetos invocables filtrados por el texto del buscador.
  List<_ObjetoEsquema> get _objetosFiltrados {
    final meta = _meta;
    if (meta == null) return const [];
    final q = _buscarObjetoCtrl.text.trim().toUpperCase();

    final base = meta.objects.where(
      (o) => _kTiposInvocables.contains(o.type.toUpperCase()),
    );
    final filtrados = q.isEmpty
        ? base.toList()
        : base.where((o) => o.name.toUpperCase().contains(q)).toList();

    // Los que empiezan con lo tipeado primero; después alfabético.
    filtrados.sort((a, b) {
      if (q.isNotEmpty) {
        final ap = a.name.toUpperCase().startsWith(q) ? 0 : 1;
        final bp = b.name.toUpperCase().startsWith(q) ? 0 : 1;
        if (ap != bp) return ap - bp;
      }
      return a.name.compareTo(b.name);
    });
    return filtrados.take(80).toList();
  }

  /// Subprogramas del package filtrados por el buscador de miembro.
  List<_Subprograma> get _miembrosFiltrados {
    final q = _buscarMiembroCtrl.text.trim().toUpperCase();
    final filtrados = q.isEmpty
        ? _subprogramas.toList()
        : _subprogramas.where((s) => s.name.toUpperCase().contains(q)).toList();
    filtrados.sort((a, b) => a.name.compareTo(b.name));
    return filtrados;
  }

  /// Nombre calificado del objeto elegido (`OWNER.OBJETO[.MIEMBRO]`).
  String get _nombreCompleto {
    final o = _objetoSel;
    if (o == null) return '';
    final owner = o.owner.isNotEmpty ? o.owner : (_meta?.owner ?? '');
    final base = owner.isEmpty ? o.name : '$owner.${o.name}';
    if (o.type.toUpperCase() == 'PACKAGE') {
      final m = _miembroSel;
      return m == null ? '' : '$base.${m.name}';
    }
    return base;
  }

  /// Aplica la selección al elegir un objeto de la lista.
  ///
  /// Los valores ya tipeados no se tocan: si la firma nueva comparte nombres
  /// de parámetro, se reaprovechan.
  Future<void> _seleccionarObjeto(
    _ObjetoEsquema objeto, {
    bool forceRefresh = false,
  }) async {
    setState(() {
      _objetoSel = objeto;
      _listaObjetosAbierta = false;
      _buscarObjetoCtrl.text = objeto.name;
      _miembroSel = null;
      _subprogramas = const [];
      _buscarMiembroCtrl.clear();
      _firma = const [];
      _resultado = null;
      _error = null;
      _avisoFirma = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();

    if (objeto.type.toUpperCase() == 'PACKAGE') {
      await _cargarSubprogramas(objeto, forceRefresh: forceRefresh);
    } else {
      await _cargarFirma(forceRefresh: forceRefresh);
    }
  }

  Future<void> _cargarSubprogramas(
    _ObjetoEsquema paquete, {
    bool forceRefresh = false,
  }) async {
    setState(() {
      _cargandoSubprogramas = true;
      _avisoFirma = null;
    });
    try {
      final subs = await SchemaService.instance.getPackageSubprograms(
        paquete.name,
        ambiente: _ambiente,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _subprogramas = subs;
        _cargandoSubprogramas = false;
        _listaMiembrosAbierta = subs.isNotEmpty;
        _avisoFirma = subs.isEmpty
            ? '${paquete.name} no expone subprogramas públicos.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoSubprogramas = false;
        _avisoFirma = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Elige un miembro del package: su firma ya viene con los subprogramas.
  void _seleccionarMiembro(_Subprograma miembro) {
    setState(() {
      _miembroSel = miembro;
      _listaMiembrosAbierta = false;
      _buscarMiembroCtrl.text = miembro.name;
      _resultado = null;
      _error = null;
      _avisoFirma = null;
      _firma = _aFirma(miembro.arguments);
      _asegurarControllers(_firma);
      _tiposDeclaracion = {};
    });
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_actualizarTiposDeclaracion());
  }

  /// Resuelve un nombre calificado contra el catálogo y aplica la selección.
  ///
  /// Se usa para los objetos recientes, para el `objetoInicial` con el que se
  /// abre la ventana y para reencontrar la selección tras cambiar de ambiente.
  ///
  /// Devuelve `true` si el objeto (y el miembro, si lo hubiera) existe en el
  /// catálogo del ambiente actual.
  Future<bool> _aplicarNombreCompleto(
    String nombre, {
    bool forceRefresh = false,
  }) async {
    final meta = _meta;
    if (meta == null) return false;

    final parts = nombre
        .toUpperCase()
        .split('.')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return false;

    _ObjetoEsquema? buscar(String name, {String? tipo}) {
      for (final o in meta.objects) {
        if (o.name.toUpperCase() != name) continue;
        if (!_kTiposInvocables.contains(o.type.toUpperCase())) continue;
        if (tipo != null && o.type.toUpperCase() != tipo) continue;
        return o;
      }
      return null;
    }

    // ESQUEMA.PACKAGE.MIEMBRO o PACKAGE.MIEMBRO
    if (parts.length >= 2) {
      final pkg = buscar(parts[parts.length - 2], tipo: 'PACKAGE');
      if (pkg != null) {
        final miembro = parts.last;
        await _seleccionarObjeto(pkg, forceRefresh: forceRefresh);
        if (!mounted) return false;
        for (final s in _subprogramas) {
          if (s.name.toUpperCase() == miembro) {
            _seleccionarMiembro(s);
            return true;
          }
        }
        return false;
      }
    }

    // Objeto standalone (con o sin esquema por delante).
    final obj = buscar(parts.last);
    if (obj == null) return false;
    await _seleccionarObjeto(obj, forceRefresh: forceRefresh);
    return true;
  }

  // ── Objetos recientes ───────────────────────────────────────────────────

  Future<void> _cargarRecientes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsRecientes) ?? const [];
      if (!mounted) return;
      setState(() => _recientes = list);
    } catch (_) {
      // Preferencias corruptas: los recientes son un extra, no bloquean nada.
    }
  }

  Future<void> _registrarReciente(String objeto) async {
    final nombre = objeto.trim().toUpperCase();
    if (nombre.isEmpty) return;
    final list = [nombre, ..._recientes.where((e) => e != nombre)].take(12);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsRecientes, list.toList());
    } catch (_) {
      // Best-effort.
    }
    if (!mounted) return;
    setState(() => _recientes = list.toList());
  }

  // ── Ambiente ────────────────────────────────────────────────────────────

  /// Pide cambiar de ambiente desde el combo del encabezado.
  ///
  /// `Prod` pasa primero por una confirmación inline; el resto se aplica
  /// directo.
  void _pedirCambioAmbiente(String nuevo) {
    setState(() => _menuAmbienteAbierto = false);
    if (nuevo == _ambiente) return;
    if (nuevo == 'Prod') {
      setState(() => _confirmarAmbiente = nuevo);
      return;
    }
    _aplicarAmbiente(nuevo);
  }

  /// Cambia de ambiente **conservando el trabajo en curso**.
  ///
  /// La firma y cantidad de parámetros varían por ambiente:
  /// al cambiar, se limpia la firma anterior inmediatamente para no mostrar
  /// datos obsoletos, se carga el catálogo del nuevo ambiente y se resuelve
  /// el objeto trayendo sus parámetros exactos para dicho ambiente.
  void _aplicarAmbiente(String nuevo) {
    if (nuevo == _ambiente) return;

    final prevObj = _objetoSel;
    final prevMiembro = _miembroSel;
    final prevObjName = prevObj?.name;
    final prevObjTipo = prevObj?.type;
    final prevMiembroName = prevMiembro?.name;
    final prevParamCount = prevMiembro != null
        ? _cuentaParametros(prevMiembro)
        : _firma.where((p) => !p.esRetorno).length;

    setState(() {
      _ambiente = nuevo;
      _confirmarAmbiente = null;
      _menuAmbienteAbierto = false;
      _resultado = null;
      _error = null;
      _avisoFirma = null;
      _meta = null;
      _listaObjetosAbierta = false;
      _listaMiembrosAbierta = false;
      // Vaciamos la firma para no mostrar los parámetros del ambiente anterior
      // mientras se resuelven los parámetros reales del nuevo ambiente.
      _firma = const [];
      _cargandoFirma = prevObjName != null;
    });

    unawaited(
      _migrarAmbiente(
        prevObjName: prevObjName,
        prevObjTipo: prevObjTipo,
        prevMiembroName: prevMiembroName,
        prevParamCount: prevParamCount,
      ),
    );

    if (nuevo == 'QA' || nuevo == 'Replica') {
      AppToast.warning(
        '$nuevo — los cambios pueden afectar datos compartidos',
        duration: const Duration(seconds: 4),
      );
    }
  }

  /// Migra la selección al nuevo ambiente resolviendo de nuevo los metadatos y la firma.
  Future<void> _migrarAmbiente({
    String? prevObjName,
    String? prevObjTipo,
    String? prevMiembroName,
    int? prevParamCount,
  }) async {
    setState(() => _cargandoMeta = true);
    try {
      final meta = await SchemaService.instance.getMetadata(
        ambiente: _ambiente,
      );
      if (!mounted) return;

      setState(() {
        _meta = meta;
        _cargandoMeta = false;
      });

      if (prevObjName == null || prevObjName.isEmpty) {
        setState(() => _cargandoFirma = false);
        return;
      }

      // Buscar el objeto en el catálogo del nuevo ambiente.
      _ObjetoEsquema? nuevoObjeto;
      for (final o in meta.objects) {
        if (o.name.toUpperCase() == prevObjName.toUpperCase()) {
          if (prevObjTipo != null &&
              o.type.toUpperCase() != prevObjTipo.toUpperCase()) {
            continue;
          }
          nuevoObjeto = o;
          break;
        }
      }

      if (nuevoObjeto == null) {
        if (!mounted) return;
        setState(() {
          _objetoSel = null;
          _miembroSel = null;
          _subprogramas = const [];
          _buscarObjetoCtrl.clear();
          _buscarMiembroCtrl.clear();
          _firma = const [];
          _cargandoFirma = false;
          _avisoFirma =
              '$prevObjName no existe en el catálogo de $_ambiente. '
              'Elegí otro objeto o revisá los permisos.';
          _listaObjetosAbierta = true;
        });
        return;
      }

      final objeto = nuevoObjeto;

      setState(() {
        _objetoSel = objeto;
        _buscarObjetoCtrl.text = objeto.name;
        _miembroSel = null;
        _subprogramas = const [];
        _buscarMiembroCtrl.clear();
        _firma = const [];
      });

      if (objeto.type.toUpperCase() == 'PACKAGE') {
        final subs = await SchemaService.instance.getPackageSubprograms(
          objeto.name,
          ambiente: _ambiente,
          forceRefresh: true,
        );
        if (!mounted) return;

        setState(() {
          _subprogramas = subs;
          _cargandoSubprogramas = false;
        });

        if (subs.isEmpty) {
          setState(() {
            _cargandoFirma = false;
            _avisoFirma =
                '${objeto.name} no expone subprogramas públicos en $_ambiente.';
          });
          return;
        }

        if (prevMiembroName != null && prevMiembroName.isNotEmpty) {
          final coincidencias = subs
              .where(
                (s) => s.name.toUpperCase() == prevMiembroName.toUpperCase(),
              )
              .toList();

          if (coincidencias.isNotEmpty) {
            final seleccionado = coincidencias.firstWhere(
              (s) => _cuentaParametros(s) == prevParamCount,
              orElse: () => coincidencias.first,
            );
            _seleccionarMiembro(seleccionado);
            setState(() => _cargandoFirma = false);
            return;
          } else {
            setState(() {
              _cargandoFirma = false;
              _listaMiembrosAbierta = true;
              _avisoFirma =
                  'El subprograma $prevMiembroName no existe en '
                  '${objeto.name} en $_ambiente. Elegí otro subprograma.';
            });
            return;
          }
        } else {
          setState(() {
            _cargandoFirma = false;
            _listaMiembrosAbierta = true;
          });
          return;
        }
      } else {
        await _cargarFirma(forceRefresh: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoMeta = false;
        _cargandoFirma = false;
        _avisoFirma =
            'No se pudo cargar el catálogo o firma de $_ambiente — '
            '${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  // ── Ventana ─────────────────────────────────────────────────────────────

  void _toggleMaximize() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      // El menú está anclado al botón: si la ventana se mueve, se cierra.
      _menuAmbienteAbierto = false;
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
      _menuAmbienteAbierto = false;
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

  // ── Firma ───────────────────────────────────────────────────────────────

  /// Convierte los argumentos del diccionario en la firma del formulario.
  ///
  /// El servidor los devuelve en orden de posición; la posición 0 es el
  /// retorno de las funciones (`(return)`).
  List<ParametroFirma> _aFirma(
    List<({String name, String dataType, String inOut})> args,
  ) {
    var pos = 0;
    return [
      for (final a in args)
        ParametroFirma(
          nombre: a.name,
          posicion: a.name.toUpperCase() == '(RETURN)' ? 0 : ++pos,
          modo: a.inOut.isEmpty ? 'IN' : a.inOut.toUpperCase(),
          tipo: a.dataType.toUpperCase(),
          noSoportado: a.inOut.toUpperCase() == 'OUT'
              ? null
              : _tipoNoSoportado(a.dataType.toUpperCase()),
        ),
    ];
  }

  /// Resuelve la firma del objeto contra el diccionario de Oracle.
  ///
  /// Sólo hace falta para procedures/functions standalone: los miembros de un
  /// package ya traen sus argumentos con [_cargarSubprogramas].
  Future<void> _cargarFirma({bool forceRefresh = false}) async {
    final objeto = _objetoSel;
    if (objeto == null || _cargandoFirma) return;

    setState(() {
      _cargandoFirma = true;
      _avisoFirma = null;
      _error = null;
    });

    try {
      final args = await SchemaService.instance.getObjectArguments(
        objeto.name,
        ambiente: _ambiente,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;

      final firma = _aFirma(args);
      setState(() {
        _firma = firma;
        _asegurarControllers(firma);
        _cargandoFirma = false;
        _tiposDeclaracion = {};
        _avisoFirma = firma.isEmpty
            ? '${objeto.name} no declara argumentos: se invoca sin parámetros.'
            : null;
      });
      unawaited(_actualizarTiposDeclaracion());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoFirma = false;
        _avisoFirma = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Tipos que no se pueden pasar como literal desde el bloque anónimo.
  static String? _tipoNoSoportado(String tipo) {
    const bloqueados = {
      'PL/SQL RECORD',
      'PL/SQL TABLE',
      'PL/SQL BOOLEAN',
      'REF CURSOR',
      'TABLE',
      'OBJECT',
      'VARRAY',
    };
    return bloqueados.contains(tipo) ? 'Tipo $tipo no enviable' : null;
  }

  /// Crea los controllers que falten para la firma vigente.
  ///
  /// A propósito **no descarta** los de parámetros que ya no están: así los
  /// valores tipeados sobreviven a un cambio de ambiente, de objeto o de
  /// subprograma, y vuelven a aparecer si se regresa a la misma firma. Se
  /// liberan todos juntos en [dispose]; para vaciarlos está «Limpiar valores».
  void _asegurarControllers(List<ParametroFirma> firma) {
    for (final p in firma) {
      _valores.putIfAbsent(p.nombre, TextEditingController.new);
    }
  }

  // ── Armado de la llamada ────────────────────────────────────────────────

  /// Convierte el texto tipeado en el literal PL/SQL que va en la llamada.
  String _literal(ParametroFirma p, String texto) {
    final v = texto.trim();
    // Expresión SQL cruda: el usuario se hace cargo (SYSDATE, TO_DATE(...)…).
    if (_expresiones.contains(p.nombre)) return v;
    if (v.toUpperCase() == 'NULL') return 'NULL';
    if (p.esNumerico) {
      final normalizado = v.replaceAll(',', '.');
      if (num.tryParse(normalizado) != null) return normalizado;
    }
    if (p.esFecha) {
      final vUpper = v.toUpperCase();
      if (vUpper == 'SYSDATE' ||
          vUpper.startsWith('TO_DATE') ||
          vUpper.startsWith('TO_TIMESTAMP') ||
          vUpper.startsWith('TRUNC(')) {
        return v;
      }
      final dt = _parsearFecha(v);
      if (dt != null) {
        if (p.esFechaConHora || v.contains(':')) {
          final s = _formatearFechaHora(dt);
          return "TO_TIMESTAMP('$s', 'DD/MM/YYYY HH24:MI:SS')";
        } else {
          final s = _formatearFecha(dt);
          return "TO_DATE('$s', 'DD/MM/YYYY')";
        }
      }
    }
    return "'${v.replaceAll("'", "''")}'";
  }

  /// Literal PL/SQL de un parámetro para la llamada.
  ///
  /// Nunca devuelve vacío: si no hay valor tipeado (o el parámetro es de
  /// salida) se manda `NULL` explícito, de modo que la llamada lleve siempre
  /// la firma completa y ningún argumento quede implícito.
  String _valorDe(ParametroFirma p) {
    // Los OUT los resuelve Oracle; se mandan como NULL sólo para ocupar la
    // posición y que la firma quede completa.
    if (!p.esEntrada) return 'NULL';
    final texto = _valores[p.nombre]?.text ?? '';
    if (texto.trim().isEmpty) return 'NULL';
    return _literal(p, texto);
  }

  /// Firma final que se manda al backend y se muestra en la aplicación.
  ///
  /// Se envía **la firma completa con valores literales**, sin variables ni
  /// argumentos omitidos: todos los parámetros (IN, IN OUT y OUT) aparecen en
  /// orden de posición y los que no tienen valor van en `NULL`.
  ///
  /// Se formatea multilínea e indentada para mostrarse en el widget de la
  /// aplicación y copiarse con facilidad de lectura.
  String get _llamada {
    if (_manual) return _manualCtrl.text.trim();

    final objeto = _nombreCompleto;
    if (objeto.isEmpty) return '';

    final args = <String>[];
    for (final p in _firma) {
      if (p.esRetorno || p.bloqueado) continue;
      args.add('${p.nombre} => ${_valorDe(p)}');
    }

    return _formatearLlamada(objeto, args);
  }

  /// Ancho máximo de una línea de la llamada generada.
  ///
  /// Basado en el ejemplo:
  /// `SIR.PCK_OFICINA_VIRTUAL.CONSULTAR_COTI_MEDIADOR(P_CD_MEDIADOR => 73379, P_CD_ENTIDAD => 30,` (91 chars).
  /// Al pasarlo, los siguientes argumentos continúan en la línea de abajo.
  static const int _anchoMaxLlamada = 92;

  /// Arma la llamada cortándola en varias líneas al pasar [_anchoMaxLlamada].
  ///
  /// Se meten tantos argumentos por línea como entren; los que no, bajan
  /// alineados con el paréntesis de apertura:
  ///
  /// ```sql
  /// SIR.PCK_OFICINA_VIRTUAL.CONSULTAR_COTI_MEDIADOR(P_CD_MEDIADOR => 73379, P_CD_ENTIDAD => 30,
  ///                                                 P_NU_COTIZACION => NULL);
  /// ```
  static String _formatearLlamada(String objeto, List<String> args) {
    if (args.isEmpty) return '$objeto;';

    final unaLinea = '$objeto(${args.join(', ')});';
    if (unaLinea.length <= _anchoMaxLlamada) return unaLinea;

    // Se alinea con el paréntesis, salvo que el nombre sea tan largo que deje
    // las líneas siguientes sin espacio útil: ahí se usa una sangría fija.
    final columnaParentesis = objeto.length + 1;
    final sangria = columnaParentesis <= _anchoMaxLlamada * 0.6
        ? columnaParentesis
        : 4;
    final indent = ' ' * sangria;

    final buffer = StringBuffer('$objeto(');
    var largoLinea = columnaParentesis;
    var inicioDeLinea = true;

    for (var i = 0; i < args.length; i++) {
      final ultimo = i == args.length - 1;
      // El cierre viaja pegado al último argumento para que cuente en el ancho.
      final texto = ultimo ? '${args[i]});' : '${args[i]},';

      if (!inicioDeLinea && largoLinea + 1 + texto.length > _anchoMaxLlamada) {
        buffer.write('\n$indent');
        largoLinea = sangria;
        inicioDeLinea = true;
      }
      if (!inicioDeLinea) {
        buffer.write(' ');
        largoLinea++;
      }
      buffer.write(texto);
      largoLinea += texto.length;
      inicioDeLinea = false;
    }

    return buffer.toString();
  }

  /// Genera un bloque PL/SQL anónimo ejecutable en Oracle SQL Developer,
  /// declarando variables para cada parámetro OUT / IN OUT y para el retorno de
  /// funciones, e imprimiendo los resultados con DBMS_OUTPUT.
  String get _scriptSqlDeveloper {
    final objeto = _nombreCompleto;
    if (objeto.isEmpty) return '';

    if (_manual) {
      final m = _manualCtrl.text.trim();
      if (m.toUpperCase().startsWith('DECLARE') ||
          m.toUpperCase().startsWith('BEGIN')) {
        return 'SET SERVEROUTPUT ON;\n\n$m\n/';
      }
      return 'SET SERVEROUTPUT ON;\n\nBEGIN\n  $m\nEND;\n/';
    }

    // Identificar retorno y parámetros de salida
    ParametroFirma? retorno;
    final salidas = <ParametroFirma>[];
    for (final p in _firma) {
      if (p.esRetorno) {
        retorno = p;
      } else if (p.modo.contains('OUT')) {
        salidas.add(p);
      }
    }

    // Mapear nombres de variables únicos
    final nombresUsados = <String>{};
    final varNames = <String, String>{};

    String asignarNombre(ParametroFirma p) {
      if (p.esRetorno) return 'v_retorno';
      var n = p.nombre.toLowerCase().trim();
      if (n.startsWith('p_')) {
        n = n.substring(2);
      } else if (n.startsWith('po_') || n.startsWith('pi_')) {
        n = n.substring(3);
      }
      n = n.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      var base = 'v_$n';
      var candidata = base;
      var sufijo = 2;
      while (nombresUsados.contains(candidata)) {
        candidata = '${base}_$sufijo';
        sufijo++;
      }
      nombresUsados.add(candidata);
      varNames[p.nombre] = candidata;
      return candidata;
    }

    if (retorno != null) {
      nombresUsados.add('v_retorno');
    }
    for (final p in salidas) {
      asignarNombre(p);
    }

    final buf = StringBuffer();
    buf.writeln('-- Script generado para Oracle SQL Developer ($_ambiente)');
    buf.writeln('SET SERVEROUTPUT ON;');
    buf.writeln();

    final tieneDeclaraciones = retorno != null || salidas.isNotEmpty;
    if (tieneDeclaraciones) {
      buf.writeln('DECLARE');
      if (retorno != null) {
        final t = _tipoDeclaracionSql(retorno);
        buf.writeln('  v_retorno $t;');
      }
      for (final p in salidas) {
        final vName = varNames[p.nombre]!;
        final t = _tipoDeclaracionSql(p);
        if (p.modo.contains('IN')) {
          final val = _valorDe(p);
          buf.writeln('  $vName $t := $val;');
        } else {
          buf.writeln('  $vName $t;');
        }
      }
    }

    buf.writeln('BEGIN');

    // Construcción de la llamada
    final args = <String>[];
    for (final p in _firma) {
      if (p.esRetorno) continue;
      if (p.modo.contains('OUT')) {
        final vName = varNames[p.nombre]!;
        args.add('${p.nombre} => $vName');
      } else {
        if (p.bloqueado) continue;
        args.add('${p.nombre} => ${_valorDe(p)}');
      }
    }

    if (args.isEmpty) {
      if (retorno != null) {
        buf.writeln('  v_retorno := $objeto;');
      } else {
        buf.writeln('  $objeto;');
      }
    } else {
      if (retorno != null) {
        buf.writeln('  v_retorno := $objeto(');
      } else {
        buf.writeln('  $objeto(');
      }
      for (var i = 0; i < args.length; i++) {
        final coma = i == args.length - 1 ? '' : ',';
        buf.writeln('    ${args[i]}$coma');
      }
      buf.writeln('  );');
    }

    // Salidas por DBMS_OUTPUT
    if (tieneDeclaraciones) {
      buf.writeln();
      if (retorno != null) {
        buf.writeln(
          '  DBMS_OUTPUT.PUT_LINE(\'RETORNO = \' || ${_formatoSalidaSql(retorno, 'v_retorno')});',
        );
      }
      for (final p in salidas) {
        final vName = varNames[p.nombre]!;
        final t = _tipoDeclaracionSql(p);
        final tUpper = t.toUpperCase();
        if (tUpper.contains('CURSOR') ||
            p.tipo.toUpperCase().contains('CURSOR') ||
            p.tipo.toUpperCase() == 'TABLE' ||
            p.tipo.toUpperCase() == 'OBJECT' ||
            p.tipo.toUpperCase() == 'VARRAY' ||
            p.tipo.toUpperCase().contains('RECORD') ||
            tUpper.startsWith('SIR.C_') ||
            tUpper.startsWith('C_') ||
            tUpper.contains('%')) {
          buf.writeln('  -- $vName ($t) devuelto por Oracle');
        } else {
          buf.writeln(
            '  DBMS_OUTPUT.PUT_LINE(\'${p.nombre} = \' || ${_formatoSalidaSql(p, vName)});',
          );
        }
      }
    }

    buf.writeln('END;');
    buf.writeln('/');

    return buf.toString();
  }

  static const _kBuiltInOracleTypes = {
    'NUMBER',
    'INTEGER',
    'INT',
    'SMALLINT',
    'BINARY_INTEGER',
    'PLS_INTEGER',
    'NATURAL',
    'POSITIVE',
    'DATE',
    'TIMESTAMP',
    'VARCHAR2',
    'VARCHAR',
    'NVARCHAR2',
    'CHAR',
    'NCHAR',
    'CLOB',
    'NCLOB',
    'BLOB',
    'BFILE',
    'BOOLEAN',
    'FLOAT',
    'REAL',
    'DECIMAL',
    'DEC',
    'NUMERIC',
    'DOUBLE PRECISION',
    'SYS_REFCURSOR',
    'REF CURSOR',
    'ROWID',
    'UROWID',
    'LONG',
    'LONG RAW',
    'RAW',
  };

  /// Retorna la declaración de tipo PL/SQL adecuada para variables locales.
  String _tipoDeclaracionSql(ParametroFirma p) {
    final nombre = p.nombre.toUpperCase();
    final real = _tiposDeclaracion[nombre];
    if (real != null && real.isNotEmpty) {
      final realUpper = real.toUpperCase().trim();
      if (realUpper == 'VARCHAR2' ||
          realUpper == 'VARCHAR' ||
          realUpper == 'NVARCHAR2') {
        return 'VARCHAR2(4000)';
      }
      if (realUpper == 'CHAR' || realUpper == 'NCHAR') {
        return 'CHAR(255)';
      }
      if (realUpper == 'REF CURSOR' || realUpper == 'SYS_REFCURSOR') {
        return 'SYS_REFCURSOR';
      }
      // Los tipos estándar de Oracle (NUMBER, DATE, CLOB, etc.) NUNCA llevan prefijo de esquema
      if (_kBuiltInOracleTypes.contains(realUpper)) {
        return realUpper;
      }
      // Solo si es un TYPE definido en la base de datos y no tiene ya dueño ni %TYPE
      if (!real.contains('.') && !real.contains('%')) {
        final owner = _resolverOwnerTipo(real);
        if (owner.isNotEmpty) return '$owner.$real';
      }
      return real;
    }

    final t = p.tipo.toUpperCase().trim();
    if (t == 'VARCHAR2' || t == 'VARCHAR' || t == 'NVARCHAR2') {
      return 'VARCHAR2(4000)';
    }
    if (t == 'CHAR' || t == 'NCHAR') {
      return 'CHAR(255)';
    }
    if (t == 'REF CURSOR' || t == 'SYS_REFCURSOR') {
      return 'SYS_REFCURSOR';
    }
    if (_kBuiltInOracleTypes.contains(t)) {
      return t;
    }
    if (t == 'TABLE' ||
        t == 'OBJECT' ||
        t == 'VARRAY' ||
        t == 'PL/SQL TABLE' ||
        t == 'PL/SQL RECORD') {
      final tipoEncontrado = _buscarTipoEnCatalogo(p.nombre);
      if (tipoEncontrado != null) return tipoEncontrado;
      return 'SYS_REFCURSOR';
    }
    return t;
  }

  /// Resuelve el esquema dueño de un tipo Oracle buscando en el catálogo cargado.
  String _resolverOwnerTipo(String nombreTipo) {
    final meta = _meta;
    if (meta == null) return '';
    final upper = nombreTipo.toUpperCase().trim();
    if (_kBuiltInOracleTypes.contains(upper)) return '';
    for (final o in meta.objects) {
      if (o.type.toUpperCase() == 'TYPE' && o.name.toUpperCase() == upper) {
        return o.owner.isNotEmpty ? o.owner : meta.owner;
      }
    }
    return '';
  }

  /// Busca en el catálogo de tipos un TYPE que coincida con el nombre del parámetro (ej. P_CUR_COTIZACIONES -> SIR.C_OFV_COTIZACION).
  String? _buscarTipoEnCatalogo(String nombreParam) {
    final meta = _meta;
    if (meta == null) return null;

    var clean = nombreParam.toUpperCase();
    if (clean.startsWith('P_CUR_')) {
      clean = clean.substring(6);
    } else if (clean.startsWith('P_')) {
      clean = clean.substring(2);
    } else if (clean.startsWith('CUR_')) {
      clean = clean.substring(4);
    }

    final types = meta.objects
        .where((o) => o.type.toUpperCase() == 'TYPE')
        .toList();

    for (final prefijo in ['C_OFV_', 'C_', 'OBJ_OFV_', 'OBJ_']) {
      final candidata = '$prefijo$clean';
      for (final t in types) {
        if (t.name.toUpperCase() == candidata ||
            t.name.toUpperCase() ==
                candidata.replaceAll(RegExp(r'ES$|S$'), '')) {
          final owner = t.owner.isNotEmpty ? t.owner : meta.owner;
          return owner.isNotEmpty ? '$owner.${t.name}' : t.name;
        }
      }
    }

    for (final t in types) {
      if (t.name.toUpperCase().contains(clean) ||
          clean.contains(t.name.toUpperCase())) {
        final owner = t.owner.isNotEmpty ? t.owner : meta.owner;
        return owner.isNotEmpty ? '$owner.${t.name}' : t.name;
      }
    }
    return null;
  }

  /// Actualiza `_tiposDeclaracion` leyendo el código fuente del objeto actual en Oracle.
  Future<void> _actualizarTiposDeclaracion() async {
    final obj = _objetoSel;
    if (obj == null) return;
    try {
      final src = await SchemaService.instance.getObjectSource(
        obj.name,
        obj.type,
        ambiente: _ambiente,
      );
      final text =
          (obj.type.toUpperCase() == 'PACKAGE' ? src.spec : src.body) ?? '';
      if (text.isEmpty) return;

      final subName = _miembroSel?.name ?? obj.name;
      final parsed = _extraerTiposParametros(text, subName);
      if (mounted) {
        setState(() => _tiposDeclaracion = parsed);
      }
    } catch (_) {
      // Best-effort: si falla la obtención del fuente, el fallback por catálogo resuelve.
    }
  }

  /// Extrae el mapa `PARAM_NAME -> TIPO_DECLARADO` desde el código fuente PL/SQL.
  static Map<String, String> _extraerTiposParametros(
    String source,
    String subprograma,
  ) {
    final cleanSource = _limpiarComentarios(source);
    final procRe = RegExp(
      r'(?:PROCEDURE|FUNCTION)\s+' +
          RegExp.escape(subprograma) +
          r'\s*\(([\s\S]*?)\)',
      caseSensitive: false,
    );
    final match = procRe.firstMatch(cleanSource);
    if (match == null) return const {};

    final paramsText = match.group(1)!;
    final res = <String, String>{};

    final paramRe = RegExp(
      r'(\b[a-zA-Z0-9_]+)\s+(?:(?:IN\s+OUT|IN|OUT)\s+)?([a-zA-Z0-9_%]+(?:\.[a-zA-Z0-9_%]+)*(?:\s*\([^)]*\))?)',
      caseSensitive: false,
    );
    for (final m in paramRe.allMatches(paramsText)) {
      final name = m.group(1)!.toUpperCase();
      final type = m.group(2)!.trim();
      if (name != 'IN' && name != 'OUT' && name != 'DEFAULT') {
        res[name] = type;
      }
    }
    return res;
  }

  /// Remueve comentarios simples y multilínea de un código PL/SQL.
  static String _limpiarComentarios(String sql) {
    var s = sql.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    s = s.replaceAll(RegExp(r'--.*$', multiLine: true), '');
    return s;
  }

  /// Expresión para imprimir una variable en DBMS_OUTPUT.PUT_LINE.
  static String _formatoSalidaSql(ParametroFirma p, String varName) {
    if (p.esFecha) {
      return 'TO_CHAR($varName, \'DD/MM/YYYY HH24:MI:SS\')';
    }
    return varName;
  }

  // ── Ejecución y cancelación ─────────────────────────────────────────────

  /// Cancela la petición HTTP en curso si hay una ejecución activa.
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

  Future<void> _ejecutar() async {
    if (_ejecutando) return;

    final llamada = _llamada;
    if (llamada.isEmpty) {
      setState(() {
        _error = _manual
            ? 'Escribí la llamada a ejecutar.'
            : (_objetoSel?.type.toUpperCase() == 'PACKAGE'
                  ? 'Elegí el subprograma del package.'
                  : 'Elegí el objeto a invocar.');
        _resultado = null;
      });
      return;
    }

    final overloadTxt = _overloadCtrl.text.trim();
    if (overloadTxt.isNotEmpty && int.tryParse(overloadTxt) == null) {
      setState(() {
        _error = 'El overload debe ser un número entero.';
        _resultado = null;
      });
      return;
    }

    final client = http.Client();
    _ejecucionClient = client;
    _cancelado = false;

    setState(() {
      _ejecutando = true;
      _error = null;
      _llamadaEnviada = llamada;
    });

    try {
      final res = await SirwebService().ejecutarLlamada(
        LlamadaRequest(
          llamada: llamada,
          ambiente: _ambiente == 'Desa' ? null : _ambiente,
          overload: int.tryParse(overloadTxt),
          timeoutSegundos: int.tryParse(_timeoutCtrl.text.trim()),
        ),
        client: client,
        cancelado: () => _cancelado,
      );
      if (!mounted || _cancelado) return;

      setState(() {
        _resultado = res;
        _ejecutando = false;
        _tab = res.tieneError ? 3 : 0;
        // El backend devuelve la firma real (con overloads resueltos): pisa la
        // del diccionario para que ambas queden consistentes.
        if (res.firma.isNotEmpty) {
          _firma = res.firma;
          _asegurarControllers(res.firma);
          _avisoFirma = null;
        }
      });

      unawaited(_registrarReciente(res.objeto ?? _nombreCompleto));

      if (res.tieneError) {
        AppToast.error('La llamada devolvió un error de Oracle');
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

  void _limpiar() {
    setState(() {
      for (final c in _valores.values) {
        c.clear();
      }
      _expresiones.clear();
      _overloadCtrl.clear();
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

  Future<void> _copiarLlamada() async {
    final llamada = _llamada;
    if (llamada.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: llamada));
    AppToast.info('Llamada copiada');
  }

  Future<void> _copiarScriptSqlDeveloper() async {
    final script = _scriptSqlDeveloper;
    if (script.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: script));
    AppToast.info('Script para SQL Developer copiado ($_ambiente)');
  }

  /// Pasa al modo manual precargando la llamada armada con el formulario.
  void _toggleManual() {
    setState(() {
      if (!_manual && _manualCtrl.text.trim().isEmpty) {
        _manualCtrl.text = _llamada;
      }
      _manual = !_manual;
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (_maximized) {
      _modalW = (size.width - 48).clamp(560.0, size.width);
      _modalH = (size.height - 48).clamp(360.0, size.height);
    } else {
      _modalW ??= (size.width * 0.86).clamp(760.0, 1100.0);
      _modalH ??= (size.height * 0.82).clamp(500.0, 780.0);
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

            // ── Menú del combo de ambiente ───────────────────────────────
            //
            // Va acá, al final del Stack de la ventana, para que se pinte
            // sobre el contenido del modal. No se usa `DropdownButton`/
            // `PopupMenuButton` porque empujan una ruta al Navigator y ésta
            // queda por debajo del `OverlayEntry` de la ventana: el menú no
            // se vería y el segundo clic rompería el assert de Flutter.
            if (_menuAmbienteAbierto && !_minimized) ...[
              // Capa transparente para cerrar al clickear fuera.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _menuAmbienteAbierto = false),
                ),
              ),
              CompositedTransformFollower(
                link: _linkAmbiente,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                // Sin `Align` alrededor: en un Stack las constraints son
                // loose y el Align se expandiría a toda la ventana,
                // descolocando el menú respecto de su ancla.
                child: _MenuAmbiente(
                  seleccionado: _ambiente,
                  isDark: isDark,
                  onSeleccionar: _pedirCambioAmbiente,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final objeto = _nombreCompleto;
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
                  Icons.terminal_rounded,
                  size: _minimized ? 15 : 20,
                  color: _accent,
                ),
              ),
              SizedBox(width: _minimized ? 8 : 12),
              if (_minimized)
                Expanded(
                  child: Text(
                    'Llamada · ${objeto.isEmpty ? 'sin objeto' : objeto}',
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
                      // Wrap y no Row: con la ventana angosta los badges
                      // (tipo + manual) desbordarían la fila.
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Ejecutar objeto PL/SQL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white38 : Colors.black38,
                              letterSpacing: 0.4,
                            ),
                          ),
                          if (_objetoSel != null)
                            _StatusBadge(
                              label:
                                  _resultado?.tipoObjeto ??
                                  _miembroSel?.kind ??
                                  _objetoSel!.type,
                              color: _accent,
                            ),
                          if (_manual)
                            const _StatusBadge(
                              label: 'Manual',
                              color: Colors.orange,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        objeto.isEmpty ? 'Elegí un objeto' : objeto,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Consolas',
                          color: objeto.isEmpty
                              ? (isDark ? Colors.white38 : Colors.black38)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_minimized) ...[
                CompositedTransformTarget(
                  link: _linkAmbiente,
                  child: _ComboAmbiente(
                    ambiente: _ambiente,
                    abierto: _menuAmbienteAbierto,
                    onTap: () => setState(
                      () => _menuAmbienteAbierto = !_menuAmbienteAbierto,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.cleaning_services_outlined, size: 17),
                  tooltip: 'Limpiar valores',
                  onPressed: _ejecutando ? null : _limpiar,
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
    // Por debajo de ~820 px las dos columnas dejan los campos ilegibles.
    final compacto = width < 820;

    final params = _buildFormulario(isDark, borderColor);
    final resultado = _buildResultado(isDark, borderColor);

    if (compacto) {
      return Column(
        children: [
          SizedBox(height: 320, child: params),
          Container(height: 1, color: borderColor),
          Expanded(child: resultado),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(width: 390, child: params),
        Container(width: 1, color: borderColor),
        Expanded(child: resultado),
      ],
    );
  }

  // ── Panel del formulario ────────────────────────────────────────────────

  Widget _buildFormulario(bool isDark, Color borderColor) {
    // Firma completa (el retorno de las funciones no es un argumento).
    final parametros = _firma.where((p) => !p.esRetorno).toList();
    final esPackage = _objetoSel?.type.toUpperCase() == 'PACKAGE';

    return Column(
      children: [
        if (_cargandoMeta || _cargandoFirma || _cargandoSubprogramas)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Scrollbar(
            controller: _paramsScroll,
            child: ListView(
              controller: _paramsScroll,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              children: [
                // Confirmación de Producción, pedida desde el combo del
                // encabezado (inline: un showDialog quedaría por detrás).
                if (_confirmarAmbiente != null) ...[
                  _ConfirmacionInline(
                    mensaje:
                        'Vas a apuntar a Producción: las llamadas se ejecutan '
                        'contra datos reales (con ROLLBACK, salvo que el '
                        'objeto haga COMMIT).',
                    isDark: isDark,
                    onCancelar: () => setState(() => _confirmarAmbiente = null),
                    onConfirmar: () => _aplicarAmbiente(_confirmarAmbiente!),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── Selector de objeto (catálogo del esquema) ─────────────
                Row(
                  children: [
                    Expanded(
                      child: _SeccionLabel(
                        label: _meta == null
                            ? 'Objeto'
                            : 'Objeto (${_objetosFiltrados.length})',
                        isDark: isDark,
                      ),
                    ),
                    if (_recientes.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          Icons.history_rounded,
                          size: 16,
                          color: _mostrarRecientes ? _accent : null,
                        ),
                        tooltip: 'Objetos recientes',
                        onPressed: () => setState(
                          () => _mostrarRecientes = !_mostrarRecientes,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      tooltip: 'Recargar catálogo del esquema',
                      onPressed: _cargandoMeta
                          ? null
                          : () {
                              final selActual = _nombreCompleto;
                              unawaited(
                                SchemaService.instance.refreshAmbiente(
                                  _ambiente,
                                ),
                              );
                              unawaited(
                                _cargarCatalogo(
                                  seleccionInicial: selActual.isEmpty
                                      ? null
                                      : selActual,
                                  forceRefresh: true,
                                ),
                              );
                            },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
                if (_mostrarRecientes && _recientes.isNotEmpty)
                  _ListaSeleccion(
                    isDark: isDark,
                    vacio: 'Sin objetos recientes',
                    items: [
                      for (final r in _recientes)
                        _ItemSeleccion(
                          titulo: r,
                          badge: 'RECIENTE',
                          badgeColor: const Color(0xFF607D8B),
                          seleccionado: false,
                          onTap: () {
                            setState(() => _mostrarRecientes = false);
                            unawaited(_aplicarNombreCompleto(r));
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: 6),
                _BuscadorEsquema(
                  controller: _buscarObjetoCtrl,
                  hint: _cargandoMeta
                      ? 'Cargando catálogo…'
                      : 'Buscar procedure, function o package…',
                  isDark: isDark,
                  habilitado: _meta != null,
                  onChanged: (_) => setState(() => _listaObjetosAbierta = true),
                  onTap: () => setState(() => _listaObjetosAbierta = true),
                  onLimpiar: () => setState(() {
                    _buscarObjetoCtrl.clear();
                    _listaObjetosAbierta = true;
                  }),
                ),
                if (_listaObjetosAbierta && _meta != null)
                  _ListaSeleccion(
                    isDark: isDark,
                    vacio: 'Sin coincidencias en $_ambiente',
                    items: [
                      for (final o in _objetosFiltrados)
                        _ItemSeleccion(
                          titulo: o.name,
                          badge: o.type,
                          badgeColor: _colorTipo(o.type),
                          seleccionado: _objetoSel?.name == o.name,
                          onTap: () => unawaited(_seleccionarObjeto(o)),
                        ),
                    ],
                  ),

                // ── Selector de subprograma cuando es un PACKAGE ──────────
                if (esPackage) ...[
                  const SizedBox(height: 12),
                  _SeccionLabel(
                    label: 'Subprograma (${_subprogramas.length})',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 6),
                  _BuscadorEsquema(
                    controller: _buscarMiembroCtrl,
                    hint: _cargandoSubprogramas
                        ? 'Cargando subprogramas…'
                        : 'Buscar procedure o function del package…',
                    isDark: isDark,
                    habilitado: _subprogramas.isNotEmpty,
                    onChanged: (_) =>
                        setState(() => _listaMiembrosAbierta = true),
                    onTap: () => setState(() => _listaMiembrosAbierta = true),
                    onLimpiar: () => setState(() {
                      _buscarMiembroCtrl.clear();
                      _listaMiembrosAbierta = true;
                    }),
                  ),
                  if (_listaMiembrosAbierta && _subprogramas.isNotEmpty)
                    _ListaSeleccion(
                      isDark: isDark,
                      vacio: 'Sin coincidencias',
                      items: [
                        for (final s in _miembrosFiltrados)
                          _ItemSeleccion(
                            titulo: s.name,
                            badge: s.kind,
                            badgeColor: _colorTipo(s.kind),
                            subtitulo: '${_cuentaParametros(s)} parámetro(s)',
                            seleccionado: _miembroSel?.name == s.name,
                            onTap: () => _seleccionarMiembro(s),
                          ),
                      ],
                    ),
                ],

                if (_avisoFirma != null) ...[
                  const SizedBox(height: 10),
                  _AvisoInline(mensaje: _avisoFirma!, isDark: isDark),
                ],
                const SizedBox(height: 14),

                // ── Modo manual vs formulario por parámetro ───────────────
                Row(
                  children: [
                    Expanded(
                      child: _SeccionLabel(
                        label: _manual
                            ? 'Llamada manual'
                            : 'Firma completa (${parametros.length})',
                        isDark: isDark,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _toggleManual,
                      icon: Icon(
                        _manual ? Icons.list_alt_rounded : Icons.edit_rounded,
                        size: 14,
                      ),
                      label: Text(
                        _manual ? 'Formulario' : 'Manual',
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                if (_manual)
                  _CampoTexto(
                    controller: _manualCtrl,
                    label: '',
                    hint: "SIR.PCK_X.MI_PROC(P_UNO => 1, P_DOS => 'texto');",
                    numerico: false,
                    isDark: isDark,
                    maxLines: 6,
                    onChanged: (_) => setState(() {}),
                  )
                else if (parametros.isEmpty)
                  Text(
                    _objetoSel == null
                        ? 'Elegí un objeto para ver su firma.'
                        : (esPackage && _miembroSel == null
                              ? 'Elegí un subprograma del package.'
                              : 'No tiene parámetros.'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  )
                else
                  for (final p in parametros) ...[
                    _ParamEntradaRow(
                      parametro: p,
                      controller: _valores[p.nombre]!,
                      esExpresion: _expresiones.contains(p.nombre),
                      isDark: isDark,
                      onToggleExpresion: () => setState(() {
                        if (!_expresiones.remove(p.nombre)) {
                          _expresiones.add(p.nombre);
                        }
                      }),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => unawaited(_ejecutar()),
                    ),
                    const SizedBox(height: 10),
                  ],

                const SizedBox(height: 8),
                _SeccionLabel(label: 'Opciones', isDark: isDark),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _CampoTexto(
                        controller: _overloadCtrl,
                        label: 'Overload',
                        hint: 'Sólo si está sobrecargado',
                        numerico: true,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CampoTexto(
                        controller: _timeoutCtrl,
                        label: 'Timeout (s)',
                        numerico: true,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _SeccionLabel(
                        label: 'Llamada a ejecutar',
                        isDark: isDark,
                      ),
                    ),
                    Tooltip(
                      message:
                          'Copiar bloque anónimo con variables DECLARE para Oracle SQL Developer',
                      child: InkWell(
                        onTap: () => unawaited(_copiarScriptSqlDeveloper()),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.terminal_rounded,
                                size: 13,
                                color: _kLlamadaAccent,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'SQL Developer',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: _kLlamadaAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _LlamadaPreview(
                  llamada: _llamada,
                  isDark: isDark,
                  onCopiar: () => unawaited(_copiarLlamada()),
                  onCopiarSqlDeveloper: () =>
                      unawaited(_copiarScriptSqlDeveloper()),
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

  /// Cantidad de parámetros reales de un subprograma (sin contar el retorno).
  static int _cuentaParametros(_Subprograma s) =>
      s.arguments.where((a) => a.name.toUpperCase() != '(RETURN)').length;

  /// Color del badge según el tipo de objeto (mismo criterio que el sidebar).
  static Color _colorTipo(String tipo) => switch (tipo.toUpperCase()) {
    'PROCEDURE' => const Color(0xFF0078D4),
    'FUNCTION' => const Color(0xFF16A34A),
    'PACKAGE' => _kLlamadaAccent,
    _ => const Color(0xFF607D8B),
  };

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
              icon: Icons.terminal_rounded,
              message: _ejecutando
                  ? 'Ejecutando la llamada…'
                  : 'Elegí un objeto del esquema, completá los parámetros\n'
                        'y ejecutá para ver el retorno, las salidas y la traza.',
              isDark: isDark,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (_ejecutando) const LinearProgressIndicator(minHeight: 2),
        _buildResumen(res, borderColor),
        _buildTabs(res, isDark, borderColor),
        Expanded(child: _buildTabContent(res, isDark)),
      ],
    );
  }

  Widget _buildResumen(LlamadaResultado res, Color borderColor) {
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
            color: res.tieneError ? Colors.redAccent : const Color(0xFF16A34A),
          ),
          if (res.tipoObjeto != null && res.tipoObjeto!.isNotEmpty)
            _StatusBadge(label: res.tipoObjeto!, color: _accent),
          if (res.ambiente != null && res.ambiente!.isNotEmpty)
            _StatusBadge(
              label: res.ambiente!,
              color: AmbienteSelector.colorForAmbiente(res.ambiente!),
            ),
          if (res.overload != null)
            _StatusBadge(
              label: 'Overload ${res.overload}',
              color: const Color(0xFF607D8B),
            ),
          if (res.duracionMs != null)
            _StatusBadge(
              label: _formatearTiempoMsYSeg(res.duracionMs!),
              color: const Color(0xFF0078D4),
            ),
          if (res.duracionLlamadaMs != null)
            _StatusBadge(
              label: _formatearTiempoMsYSeg(
                res.duracionLlamadaMs!,
                prefix: 'Oracle ',
              ),
              color: const Color(0xFF0F766E),
            ),
          if (res.rollback)
            const _StatusBadge(label: 'Rollback', color: Colors.orange),
          if (res.commitDetectado)
            const _StatusBadge(
              label: 'COMMIT detectado',
              color: Colors.deepOrange,
            ),
          if (res.codigoError != null && res.codigoError!.isNotEmpty)
            _StatusBadge(label: res.codigoError!, color: Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildTabs(LlamadaResultado res, bool isDark, Color borderColor) {
    final salidas = res.argumentosSalida.length + (res.esFuncion ? 1 : 0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          _TabChip(
            label: 'Salidas',
            count: salidas,
            active: _tab == 0,
            accent: const Color(0xFF16A34A),
            isDark: isDark,
            onTap: () => setState(() => _tab = 0),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'Enviados',
            count: res.argumentosEnviados.length,
            active: _tab == 1,
            accent: const Color(0xFF0078D4),
            isDark: isDark,
            onTap: () => setState(() => _tab = 1),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'Firma',
            count: res.firma.length,
            active: _tab == 2,
            accent: _accent,
            isDark: isDark,
            onTap: () => setState(() => _tab = 2),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'Traza',
            count: res.traza.length + (res.tieneError ? 1 : 0),
            active: _tab == 3,
            accent: res.tieneError ? Colors.redAccent : const Color(0xFF8E44AD),
            isDark: isDark,
            onTap: () => setState(() => _tab = 3),
          ),
          const Spacer(),
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

  Widget _buildTabContent(LlamadaResultado res, bool isDark) {
    return switch (_tab) {
      0 => _buildSalidas(res, isDark),
      1 => _buildEnviados(res, isDark),
      2 => _buildFirma(res, isDark),
      _ => _buildTraza(res, isDark),
    };
  }

  Widget _buildSalidas(LlamadaResultado res, bool isDark) {
    final entries = res.argumentosSalida.entries.toList();
    if (entries.isEmpty && !res.esFuncion) {
      return _EmptyState(
        icon: Icons.output_rounded,
        message: 'La llamada no devolvió parámetros de salida',
        isDark: isDark,
      );
    }

    final borderColor = isDark
        ? const Color(0xFF2F2F2F)
        : const Color(0xFFEDF0F5);

    return Scrollbar(
      controller: _resultScroll,
      child: ListView(
        controller: _resultScroll,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          if (res.esFuncion) ...[
            _FilaValor(campo: 'RETURN', valor: res.retorno, isDark: isDark),
            Divider(height: 1, color: borderColor),
          ],
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(height: 1, color: borderColor),
            _FilaValor(
              campo: entries[i].key,
              valor: entries[i].value,
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnviados(LlamadaResultado res, bool isDark) {
    if (res.argumentosEnviados.isEmpty) {
      return _EmptyState(
        icon: Icons.input_rounded,
        message: 'No se envió ningún parámetro de entrada',
        isDark: isDark,
      );
    }

    final borderColor = isDark
        ? const Color(0xFF2F2F2F)
        : const Color(0xFFEDF0F5);
    final entries = res.argumentosEnviados.entries.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) Divider(height: 1, color: borderColor),
          _FilaValor(
            campo: entries[i].key,
            valor: entries[i].value,
            isDark: isDark,
          ),
        ],
        if (_llamadaEnviada != null && _llamadaEnviada!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: _SeccionLabel(label: 'Llamada enviada', isDark: isDark),
          ),
          const SizedBox(height: 6),
          _SqlBlock(sql: _llamadaEnviada!, isDark: isDark),
        ],
        if (res.llamada != null && res.llamada!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: _SeccionLabel(
              label: 'Bloque ejecutado (normalizado por Oracle)',
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 6),
          _SqlBlock(sql: res.llamada!, isDark: isDark),
        ],
      ],
    );
  }

  Widget _buildFirma(LlamadaResultado res, bool isDark) {
    if (res.firma.isEmpty) {
      return _EmptyState(
        icon: Icons.functions_rounded,
        message: 'Sin firma resuelta',
        isDark: isDark,
      );
    }

    final borderColor = isDark
        ? const Color(0xFF2F2F2F)
        : const Color(0xFFEDF0F5);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: res.firma.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: borderColor),
      itemBuilder: (_, i) =>
          _FirmaTile(parametro: res.firma[i], isDark: isDark),
    );
  }

  Widget _buildTraza(LlamadaResultado res, bool isDark) {
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
}

// ── Widgets auxiliares ─────────────────────────────────────────────────────

/// Combo de ambiente del encabezado.
///
/// Replica el look del `AmbienteSelector` pero **no** usa `DropdownButton`:
/// éste abre su menú como una ruta del Navigator, que se renderiza por debajo
/// del `OverlayEntry` de esta ventana. Al no verse, el usuario vuelve a
/// clickear y el segundo `_handleTap` rompe el assert `_dropdownRoute == null`.
/// Acá el botón sólo hace de ancla ([LayerLink]) y el menú lo dibuja la propia
/// ventana en su `Stack` ([_MenuAmbiente]).
class _ComboAmbiente extends StatelessWidget {
  final String ambiente;
  final bool abierto;
  final VoidCallback onTap;

  const _ComboAmbiente({
    required this.ambiente,
    required this.abierto,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = AmbienteSelector.colorForAmbiente(ambiente);
    return Tooltip(
      message: 'Ambiente de ejecución',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: abierto ? 0.25 : 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                AmbienteSelector.iconForAmbiente(ambiente),
                size: 13,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                ambiente,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Icon(
                abierto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: color,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Menú desplegable del combo de ambiente.
///
/// Lo dibuja el `Stack` de la ventana, anclado con `CompositedTransformFollower`
/// al botón, así queda siempre por encima del contenido del modal.
class _MenuAmbiente extends StatelessWidget {
  final String seleccionado;
  final bool isDark;
  final ValueChanged<String> onSeleccionar;

  const _MenuAmbiente({
    required this.seleccionado,
    required this.isDark,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252526) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in AmbienteSelector.ambientes)
              _MenuAmbienteItem(
                ambiente: a,
                activo: a == seleccionado,
                isDark: isDark,
                onTap: () => onSeleccionar(a),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuAmbienteItem extends StatelessWidget {
  final String ambiente;
  final bool activo;
  final bool isDark;
  final VoidCallback onTap;

  const _MenuAmbienteItem({
    required this.ambiente,
    required this.activo,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = AmbienteSelector.colorForAmbiente(ambiente);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: activo ? color.withValues(alpha: 0.12) : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 8),
            Icon(
              AmbienteSelector.iconForAmbiente(ambiente),
              size: 13,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                ambiente,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ),
            if (activo) Icon(Icons.check, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}

/// Confirmación inline (sin `showDialog`, que quedaría detrás de la ventana).
class _ConfirmacionInline extends StatelessWidget {
  final String mensaje;
  final bool isDark;
  final VoidCallback onCancelar;
  final VoidCallback onConfirmar;

  const _ConfirmacionInline({
    required this.mensaje,
    required this.isDark,
    required this.onCancelar,
    required this.onConfirmar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 15,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  mensaje,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.redAccent,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancelar,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Cancelar', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: onConfirmar,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text(
                  'Confirmar',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Campo de búsqueda de los selectores de objeto y de subprograma.
class _BuscadorEsquema extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool isDark;
  final bool habilitado;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;
  final VoidCallback onLimpiar;

  const _BuscadorEsquema({
    required this.controller,
    required this.hint,
    required this.isDark,
    required this.habilitado,
    required this.onChanged,
    required this.onTap,
    required this.onLimpiar,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);

    return TextField(
      controller: controller,
      enabled: habilitado,
      onChanged: onChanged,
      onTap: onTap,
      style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 11,
          fontFamily: 'Consolas',
          color: isDark ? Colors.white24 : Colors.black26,
        ),
        prefixIcon: const Icon(Icons.search_rounded, size: 16),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 30,
          minHeight: 30,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 14),
                tooltip: 'Limpiar búsqueda',
                onPressed: onLimpiar,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: borderColor),
        ),
      ),
    );
  }
}

/// Datos de una fila de los selectores.
class _ItemSeleccion {
  final String titulo;
  final String badge;
  final Color badgeColor;
  final String? subtitulo;
  final bool seleccionado;
  final VoidCallback onTap;

  const _ItemSeleccion({
    required this.titulo,
    required this.badge,
    required this.badgeColor,
    required this.seleccionado,
    required this.onTap,
    this.subtitulo,
  });
}

/// Lista desplegable inline con los resultados del catálogo.
///
/// Va dentro del `ListView` del formulario (no en un overlay aparte) para que
/// acompañe a la ventana flotante cuando se arrastra o se redimensiona.
class _ListaSeleccion extends StatelessWidget {
  final List<_ItemSeleccion> items;
  final bool isDark;
  final String vacio;

  const _ListaSeleccion({
    required this.items,
    required this.isDark,
    required this.vacio,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 230),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171717) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  vacio,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
            )
          : Scrollbar(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i];
                  return InkWell(
                    onTap: it.onTap,
                    child: Container(
                      color: it.seleccionado
                          ? it.badgeColor.withValues(alpha: 0.12)
                          : null,
                      padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  it.titulo,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'Consolas',
                                    fontWeight: it.seleccionado
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                if (it.subtitulo != null)
                                  Text(
                                    it.subtitulo!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          _StatusBadge(label: it.badge, color: it.badgeColor),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Fila de un parámetro de la firma: nombre, modo/tipo y valor a mandar.
///
/// Los `IN`/`IN OUT` son editables; los `OUT` se muestran de sólo lectura
/// porque siempre viajan como `NULL` (los completa Oracle).
class _ParamEntradaRow extends StatelessWidget {
  final ParametroFirma parametro;
  final TextEditingController controller;
  final bool esExpresion;
  final bool isDark;
  final VoidCallback onToggleExpresion;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _ParamEntradaRow({
    required this.parametro,
    required this.controller,
    required this.esExpresion,
    required this.isDark,
    required this.onToggleExpresion,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final bloqueado = parametro.bloqueado;
    final editable = parametro.esEntrada && !bloqueado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '${parametro.posicion}',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Consolas',
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
              ),
            ),
            Expanded(
              child: Text(
                parametro.nombre,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _StatusBadge(
              label: parametro.modo,
              color: parametro.modo.contains('OUT')
                  ? const Color(0xFF0F766E)
                  : const Color(0xFF0078D4),
            ),
            const SizedBox(width: 4),
            _StatusBadge(label: parametro.tipo, color: const Color(0xFF607D8B)),
            if (parametro.tieneDefault) ...[
              const SizedBox(width: 4),
              const _StatusBadge(label: 'DEFAULT', color: Color(0xFF8E44AD)),
            ],
            if (editable) ...[
              const SizedBox(width: 2),
              IconButton(
                icon: Icon(
                  Icons.functions_rounded,
                  size: 15,
                  color: esExpresion
                      ? _kLlamadaAccent
                      : (isDark ? Colors.white38 : Colors.black38),
                ),
                tooltip: esExpresion
                    ? 'Expresión SQL cruda (click para mandar como literal)'
                    : 'Literal (click para mandar como expresión SQL)',
                onPressed: onToggleExpresion,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        if (bloqueado)
          _ValorFijo(
            texto: '${parametro.noSoportado} — se omite de la llamada',
            color: Colors.orange,
            isDark: isDark,
          )
        else if (!parametro.esEntrada)
          _ValorFijo(
            texto: 'NULL — lo devuelve Oracle',
            color: const Color(0xFF0F766E),
            isDark: isDark,
          )
        else if (parametro.esFecha && !esExpresion)
          _CampoFecha(
            controller: controller,
            conHora: parametro.esFechaConHora,
            isDark: isDark,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          )
        else
          _CampoTexto(
            controller: controller,
            label: '',
            hint: esExpresion
                ? 'SYSDATE, TO_DATE(…)'
                : (parametro.esNumerico
                      ? '123 · vacío = NULL'
                      : 'vacío = NULL'),
            numerico: !esExpresion && parametro.esNumerico,
            inputFormatters: (!esExpresion && parametro.esNumerico)
                ? [
                    FilteringTextInputFormatter.allow(
                      parametro.esEntero
                          ? RegExp(r'[0-9\-]')
                          : RegExp(r'[0-9\.,\-]'),
                    ),
                  ]
                : null,
            isDark: isDark,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
      ],
    );
  }
}

/// Valor no editable de un parámetro (OUT o de tipo no enviable).
class _ValorFijo extends StatelessWidget {
  final String texto;
  final Color color;
  final bool isDark;

  const _ValorFijo({
    required this.texto,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 11, fontFamily: 'Consolas', color: color),
      ),
    );
  }
}

/// Vista previa de la llamada que se va a mandar al backend.
class _LlamadaPreview extends StatelessWidget {
  final String llamada;
  final bool isDark;
  final VoidCallback onCopiar;
  final VoidCallback? onCopiarSqlDeveloper;

  const _LlamadaPreview({
    required this.llamada,
    required this.isDark,
    required this.onCopiar,
    this.onCopiarSqlDeveloper,
  });

  @override
  Widget build(BuildContext context) {
    final vacio = llamada.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
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
            // Scroll horizontal y no wrap suave: así se respeta el corte de
            // línea y la sangría con la que se copia la llamada.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                vacio ? '—' : llamada,
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'Consolas',
                  height: 1.4,
                  color: vacio
                      ? (isDark ? Colors.white38 : Colors.black38)
                      : null,
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.content_copy_rounded, size: 14),
                tooltip: 'Copiar llamada simple',
                onPressed: vacio ? null : onCopiar,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
              if (onCopiarSqlDeveloper != null)
                IconButton(
                  icon: const Icon(
                    Icons.terminal_rounded,
                    size: 14,
                    color: _kLlamadaAccent,
                  ),
                  tooltip:
                      'Copiar script con variables de salida para Oracle SQL Developer',
                  onPressed: vacio ? null : onCopiarSqlDeveloper,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fila de la pestaña «Firma».
class _FirmaTile extends StatelessWidget {
  final ParametroFirma parametro;
  final bool isDark;

  const _FirmaTile({required this.parametro, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${parametro.posicion}',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Consolas',
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
          Expanded(
            child: Text(
              parametro.esRetorno ? 'RETURN' : parametro.nombre,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Wrap(
            spacing: 4,
            children: [
              _StatusBadge(
                label: parametro.modo,
                color: parametro.modo.contains('OUT')
                    ? const Color(0xFF0F766E)
                    : const Color(0xFF0078D4),
              ),
              _StatusBadge(
                label: parametro.tipo,
                color: const Color(0xFF607D8B),
              ),
              if (parametro.tieneDefault)
                const _StatusBadge(label: 'DEFAULT', color: Color(0xFF8E44AD)),
              if (parametro.bloqueado)
                _StatusBadge(
                  label: parametro.noSoportado!,
                  color: Colors.orange,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aviso no bloqueante dentro del formulario (catálogo, firma vacía, etc.).
class _AvisoInline extends StatelessWidget {
  final String mensaje;
  final bool isDark;

  const _AvisoInline({required this.mensaje, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: Colors.orange,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.orange,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget de fecha y selector modal para parámetros DATE/TIMESTAMP ─────────

/// Formatea un [DateTime] a cadena `DD/MM/YYYY`.
String _formatearFecha(DateTime d) {
  final dia = d.day.toString().padLeft(2, '0');
  final mes = d.month.toString().padLeft(2, '0');
  final anio = d.year.toString().padLeft(4, '0');
  return '$dia/$mes/$anio';
}

/// Formatea un [DateTime] a cadena `DD/MM/YYYY HH:mm:ss`.
String _formatearFechaHora(DateTime d) {
  final f = _formatearFecha(d);
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  final s = d.second.toString().padLeft(2, '0');
  return '$f $h:$m:$s';
}

/// Parsea una cadena de fecha ingresada a mano (`DD/MM/YYYY` o `DD/MM/YYYY HH:mm:ss`).
DateTime? _parsearFecha(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final match = RegExp(
    r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})(?:\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?$',
  ).firstMatch(t);
  if (match != null) {
    final dia = int.tryParse(match.group(1)!);
    final mes = int.tryParse(match.group(2)!);
    final anio = int.tryParse(match.group(3)!);
    final h = match.group(4) != null ? int.tryParse(match.group(4)!) ?? 0 : 0;
    final min = match.group(5) != null ? int.tryParse(match.group(5)!) ?? 0 : 0;
    final sec = match.group(6) != null ? int.tryParse(match.group(6)!) ?? 0 : 0;
    if (dia != null &&
        mes != null &&
        anio != null &&
        mes >= 1 &&
        mes <= 12 &&
        dia >= 1 &&
        dia <= 31) {
      try {
        return DateTime(anio, mes, dia, h, min, sec);
      } catch (_) {}
    }
  }
  return DateTime.tryParse(t);
}

/// Campo de texto para fecha/hora con botón para abrir el selector de calendario.
class _CampoFecha extends StatelessWidget {
  final TextEditingController controller;
  final bool conHora;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  const _CampoFecha({
    required this.controller,
    required this.conHora,
    required this.isDark,
    required this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final tieneTexto = value.text.isNotEmpty;
        return TextField(
          controller: controller,
          keyboardType: TextInputType.datetime,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9\/\- :.]')),
          ],
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
          decoration: InputDecoration(
            isDense: true,
            hintText: conHora
                ? 'DD/MM/YYYY HH24:MI:SS · vacío = NULL'
                : 'DD/MM/YYYY · vacío = NULL',
            hintStyle: TextStyle(
              fontSize: 11,
              fontFamily: 'Consolas',
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 28,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tieneTexto)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 14),
                    tooltip: 'Limpiar (NULL)',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    color: isDark ? Colors.white38 : Colors.black38,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
                IconButton(
                  icon: const Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: _kLlamadaAccent,
                  ),
                  tooltip: conHora ? 'Elegir fecha y hora' : 'Elegir fecha',
                  padding: const EdgeInsets.only(right: 6),
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 22,
                  ),
                  onPressed: () => _mostrarSelectorFechaModal(
                    context: context,
                    controller: controller,
                    conHora: conHora,
                    isDark: isDark,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: _kLlamadaAccent, width: 1.5),
            ),
          ),
        );
      },
    );
  }
}

/// Muestra un selector de calendario tipo popup en el `rootOverlay` sin crear rutas de Navigator.
void _mostrarSelectorFechaModal({
  required BuildContext context,
  required TextEditingController controller,
  required bool conHora,
  required bool isDark,
  required ValueChanged<String> onChanged,
}) {
  late OverlayEntry entry;
  var cerrado = false;

  void cerrar() {
    if (cerrado) return;
    cerrado = true;
    entry.remove();
  }

  DateTime fechaSel = _parsearFecha(controller.text) ?? DateTime.now();
  final horaCtrl = TextEditingController(
    text: fechaSel.hour.toString().padLeft(2, '0'),
  );
  final minCtrl = TextEditingController(
    text: fechaSel.minute.toString().padLeft(2, '0'),
  );
  final segCtrl = TextEditingController(
    text: fechaSel.second.toString().padLeft(2, '0'),
  );

  entry = OverlayEntry(
    builder: (ctx) {
      final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
      final borderCol = isDark
          ? const Color(0xFF3A3A3A)
          : const Color(0xFFDDE2EA);
      final textCol = isDark ? Colors.white : const Color(0xFF1E293B);

      return Stack(
        children: [
          // Fondo oscuro para cerrar al hacer clic afuera
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: cerrar,
              child: Container(color: Colors.black.withValues(alpha: 0.45)),
            ),
          ),
          // Diálogo centrado
          Center(
            child: Material(
              color: Colors.transparent,
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  void confirmar(DateTime d) {
                    final DateTime fechaFinal;
                    if (conHora) {
                      final h = int.tryParse(horaCtrl.text.trim()) ?? 0;
                      final m = int.tryParse(minCtrl.text.trim()) ?? 0;
                      final s = int.tryParse(segCtrl.text.trim()) ?? 0;
                      fechaFinal = DateTime(
                        d.year,
                        d.month,
                        d.day,
                        h.clamp(0, 23),
                        m.clamp(0, 59),
                        s.clamp(0, 59),
                      );
                      final texto = _formatearFechaHora(fechaFinal);
                      controller.text = texto;
                      onChanged(texto);
                    } else {
                      fechaFinal = DateTime(d.year, d.month, d.day);
                      final texto = _formatearFecha(fechaFinal);
                      controller.text = texto;
                      onChanged(texto);
                    }
                    cerrar();
                  }

                  return Container(
                    width: 360,
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.6 : 0.2,
                          ),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Encabezado
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: borderCol),
                            ),
                            color: isDark
                                ? const Color(0xFF252526)
                                : const Color(0xFFF8FAFC),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(9),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_month_rounded,
                                size: 18,
                                color: _kLlamadaAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  conHora
                                      ? 'Seleccionar fecha y hora'
                                      : 'Seleccionar fecha',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: textCol,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: cerrar,
                                tooltip: 'Cerrar',
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                        // Calendario interactivo
                        Theme(
                          data: (isDark ? ThemeData.dark() : ThemeData.light())
                              .copyWith(
                                colorScheme:
                                    (isDark
                                            ? const ColorScheme.dark()
                                            : const ColorScheme.light())
                                        .copyWith(
                                          primary: _kLlamadaAccent,
                                          onPrimary: Colors.white,
                                          surface: bg,
                                          onSurface: textCol,
                                        ),
                              ),
                          child: SizedBox(
                            height: 280,
                            child: CalendarDatePicker(
                              initialDate: fechaSel,
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2100),
                              onDateChanged: (nueva) {
                                setModalState(() {
                                  fechaSel = nueva;
                                });
                              },
                            ),
                          ),
                        ),
                        // Controles de hora si aplica
                        if (conHora) ...[
                          Divider(height: 1, color: borderCol),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 16,
                                  color: _kLlamadaAccent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Hora (HH:MM:SS):',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: textCol,
                                  ),
                                ),
                                const Spacer(),
                                _InputHora(
                                  controller: horaCtrl,
                                  isDark: isDark,
                                ),
                                const Text(
                                  ' : ',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                _InputHora(controller: minCtrl, isDark: isDark),
                                const Text(
                                  ' : ',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                _InputHora(controller: segCtrl, isDark: isDark),
                              ],
                            ),
                          ),
                        ],
                        Divider(height: 1, color: borderCol),
                        // Barra inferior con botones
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.today_rounded, size: 14),
                                label: const Text(
                                  'Hoy',
                                  style: TextStyle(fontSize: 11),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  minimumSize: Size.zero,
                                ),
                                onPressed: () {
                                  final ahora = DateTime.now();
                                  setModalState(() {
                                    fechaSel = ahora;
                                    horaCtrl.text = ahora.hour
                                        .toString()
                                        .padLeft(2, '0');
                                    minCtrl.text = ahora.minute
                                        .toString()
                                        .padLeft(2, '0');
                                    segCtrl.text = ahora.second
                                        .toString()
                                        .padLeft(2, '0');
                                  });
                                },
                              ),
                              const SizedBox(width: 6),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  minimumSize: Size.zero,
                                ),
                                onPressed: () {
                                  controller.clear();
                                  onChanged('');
                                  cerrar();
                                },
                                child: const Text(
                                  'NULL',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: cerrar,
                                child: const Text(
                                  'Cancelar',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 6),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _kLlamadaAccent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  minimumSize: Size.zero,
                                ),
                                onPressed: () => confirmar(fechaSel),
                                child: const Text(
                                  'Aceptar',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Overlay.of(context, rootOverlay: true).insert(entry);
}

/// Campo numérico compacto para hora, minutos y segundos.
class _InputHora extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;

  const _InputHora({required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: 5,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(color: _kLlamadaAccent),
          ),
        ),
      ),
    );
  }
}
