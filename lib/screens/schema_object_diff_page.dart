import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import '../services/app_log.dart';
import '../services/backup_service.dart';
import '../services/schema_service.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/app_toast.dart';
import '../widgets/constellation_background.dart';
import '../widgets/floating_window.dart';
import '../widgets/native_diff_viewer.dart';

// ─────────────────────────────────────────────────────────────────────────────

/// Abre el comparador de objetos de esquema como ventana flotante.
///
/// Usa la misma infraestructura que el resto de los modales de la app
/// (`showFloatingWindow` → overlay raíz, sin barrera modal): se puede mover con
/// el cursor arrastrando la barra de título, redimensionar desde los bordes,
/// minimizar a la barra inferior y maximizar (F11). Mientras está abierta el
/// resto de la aplicación sigue siendo utilizable.
///
/// Devuelve el callback para cerrarla programáticamente.
VoidCallback showSchemaObjectDiff(
  BuildContext context, {
  required String objectName,
  required String objectType,
  required String sourceAmbiente,
}) {
  AppLog.instance.transaction(
    'Abrir comparador de $objectName ($objectType)',
    source: 'Comparación',
    datos: {'Origen': sourceAmbiente},
  );
  return showFloatingWindow(
    context,
    (close) => SchemaObjectDiffPage(
      objectName: objectName,
      objectType: objectType,
      sourceAmbiente: sourceAmbiente,
      onClose: close,
    ),
  );
}

class SchemaObjectDiffPage extends StatefulWidget {
  final String objectName;
  final String objectType; // PROCEDURE, FUNCTION, PACKAGE, TYPE
  final String sourceAmbiente;

  /// Cierra la ventana flotante. Si es `null` se hace `Navigator.pop`.
  final VoidCallback? onClose;

  const SchemaObjectDiffPage({
    super.key,
    required this.objectName,
    required this.objectType,
    required this.sourceAmbiente,
    this.onClose,
  });

  @override
  State<SchemaObjectDiffPage> createState() => _SchemaObjectDiffPageState();
}

class _SchemaObjectDiffPageState extends State<SchemaObjectDiffPage> {
  /// Ancho mínimo de la ventana: por debajo la toolbar no entra.
  static const double _kMinW = 720;

  /// Alto de la barra de título.
  static const double _kHeaderH = 44;
  // ── Ambientes comparados ───────────────────────────────────────────────────
  /// Ambiente ORIGEN (izquierda). Editable desde la toolbar.
  late String _sourceAmbiente;

  /// Ambiente DESTINO (derecha). Editable desde la toolbar.
  late String _targetAmbiente;

  /// Cambia uno de los ambientes comparados.
  ///
  /// Si el nuevo ambiente coincide con el del otro lado, se intercambian para
  /// que nunca se compare un ambiente contra sí mismo.
  ///
  /// No dispara la comparación: sólo prepara los ambientes. El usuario decide
  /// cuándo traer el código con el botón **Comparar**.
  void _changeAmbiente(String nuevo, {required bool isSource}) {
    if (nuevo == (isSource ? _sourceAmbiente : _targetAmbiente)) return;
    setState(() {
      if (isSource) {
        if (nuevo == _targetAmbiente) _targetAmbiente = _sourceAmbiente;
        _sourceAmbiente = nuevo;
      } else {
        if (nuevo == _sourceAmbiente) _sourceAmbiente = _targetAmbiente;
        _targetAmbiente = nuevo;
      }
      _resetComparacion();
    });
  }

  /// Intercambia origen y destino. Tampoco recompara automáticamente.
  void _swapAmbientes() {
    setState(() {
      final tmp = _sourceAmbiente;
      _sourceAmbiente = _targetAmbiente;
      _targetAmbiente = tmp;
      _resetComparacion();
    });
  }

  /// Descarta la comparación en curso (se debe volver a pulsar *Comparar*).
  void _resetComparacion() {
    _sourceCode = null;
    _sourceData = null;
    _targetData = null;
    _compilationErrors = [];
    _focusedProcName = null;
    _procItems = [];
    _sidebarActiveIdx = -1;
    _history.clear();
    _error = null;
    _sourceMissing = false;
    _targetMissing = false;
  }

  // ── Carga ──────────────────────────────────────────────────────────────────
  bool _loading = false;
  String? _sourceCode;
  String? _error;

  /// El objeto no existe en el ambiente ORIGEN.
  bool _sourceMissing = false;

  /// El objeto no existe en el ambiente DESTINO.
  bool _targetMissing = false;

  /// Transferencia (creación del objeto en el ambiente donde falta) en curso.
  bool _transferring = false;

  /// Ambiente donde falta el objeto (null si existe en ambos).
  String? get _missingAmbiente => _sourceMissing
      ? _sourceAmbiente
      : (_targetMissing ? _targetAmbiente : null);

  /// Ambiente que sí tiene el objeto cuando falta en el otro lado.
  String get _presentAmbiente =>
      _sourceMissing ? _targetAmbiente : _sourceAmbiente;

  // ── Paquete (SPEC/BODY) ────────────────────────────────────────────────────
  ({String spec, String? body})? _sourceData;
  ({String spec, String? body})? _targetData;
  String _part = 'BODY';
  bool get _isPackage => widget.objectType == 'PACKAGE';

  // ── Compilación ────────────────────────────────────────────────────────────
  bool _compiling = false;
  List<({int line, int position, String text, String attribute})>
  _compilationErrors = [];

  // ── Vista ──────────────────────────────────────────────────────────────────
  bool _sideBySide = true;
  bool _showAllLines = true; // por defecto muestra el código completo

  // ── Geometría de la ventana flotante ───────────────────────────────────────
  /// Desplazamiento respecto del centro de la pantalla (arrastre).
  Offset _position = Offset.zero;
  double? _winW;
  double? _winH;

  /// Ventana maximizada (ocupa casi toda la pantalla).
  bool _maximized = false;

  /// Ventana minimizada a la barra inferior.
  bool _minimized = false;
  int? _slot;

  /// Geometría previa, para restaurar al des-maximizar.
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;

  /// 180 ms al maximizar/minimizar; cero mientras se arrastra o redimensiona.
  Duration _anim = Duration.zero;

  void _toggleMaximized() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_maximized) {
        _winW = _restoreW;
        _winH = _restoreH;
        _position = _restorePos;
        _maximized = false;
      } else {
        _restoreW = _winW;
        _restoreH = _winH;
        _restorePos = _position;
        _position = Offset.zero;
        _maximized = true;
      }
    });
  }

  void _toggleMinimized() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_minimized) {
        FloatingWindowSlots.release(_slot);
        _slot = null;
        _minimized = false;
      } else {
        _slot = FloatingWindowSlots.take();
        _minimized = true;
        // Devolver el teclado a la app mientras la ventana está minimizada.
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _close() {
    FloatingWindowSlots.release(_slot);
    _slot = null;
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ── Sidebar (solo PACKAGE) ─────────────────────────────────────────────────
  String _sidebarFilter = '';
  bool _sidebarVisible = true;
  double _sidebarWidth = 210;
  final _sidebarListCtrl = ScrollController();
  int _sidebarActiveIdx = -1; // índice activo en _procItems
  List<({String name, String type, int lineNum, int lineEnd})> _procItems = [];

  // ── Foco en procedimiento ──────────────────────────────────────────────────
  /// Nombre del procedimiento enfocado. null = sin foco (vista completa).
  String? _focusedProcName;

  // ── Texto ──────────────────────────────────────────────────────────────────
  String _modifiedText = '';
  late String _currentOriginal;

  // ── Historial y controlador ────────────────────────────────────────────────
  final _diffCtrl = NativeDiffController();
  final _history = <({String original, String modified})>[];
  final _sidebarFilterCtrl = TextEditingController();

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _sidebarFilterCtrl.addListener(() {
      setState(() => _sidebarFilter = _sidebarFilterCtrl.text);
    });
    _sourceAmbiente = widget.sourceAmbiente;
    _targetAmbiente = AmbienteSelector.ambientes.firstWhere(
      (a) => a != _sourceAmbiente,
    );
    _diffCtrl.visibleOrigLine.addListener(_onVisibleLineChanged);
  }

  @override
  void dispose() {
    FloatingWindowSlots.release(_slot);
    _diffCtrl.dispose();
    _sidebarFilterCtrl.dispose();
    _sidebarListCtrl.dispose();
    super.dispose();
  }

  /// Sincroniza el ítem activo del sidebar con la línea visible en el visor.
  void _onVisibleLineChanged() {
    if (!mounted || _procItems.isEmpty) return;
    final visLine = _diffCtrl.visibleOrigLine.value;
    var newIdx = -1;
    for (var i = _procItems.length - 1; i >= 0; i--) {
      if (_procItems[i].lineNum <= visLine) {
        newIdx = i;
        break;
      }
    }
    if (newIdx == _sidebarActiveIdx) return;
    _sidebarActiveIdx = newIdx;
    // Auto-scroll del sidebar al ítem activo
    if (newIdx >= 0 && _sidebarListCtrl.hasClients) {
      const itemH = 38.0;
      final off = newIdx * itemH;
      final vp = _sidebarListCtrl.position.viewportDimension;
      final cur = _sidebarListCtrl.offset;
      if (off < cur || off + itemH > cur + vp) {
        _sidebarListCtrl.animateTo(
          off.clamp(0.0, _sidebarListCtrl.position.maxScrollExtent),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }
    // Rebuild solo para el highlight
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers de foco
  // ─────────────────────────────────────────────────────────────────────────

  /// Ítem del proc actualmente enfocado (null si sin foco).
  ({String name, String type, int lineNum, int lineEnd})?
  get _focusedProcItem => _focusedProcName == null
      ? null
      : _procItems.where((p) => p.name == _focusedProcName).firstOrNull;

  /// Texto ORIGEN que el visor muestra (fragmento si hay foco).
  String get _viewOrig {
    final fp = _focusedProcItem;
    if (fp == null) return _currentOriginal;
    final lines = _currentOriginal.split('\n');
    final s = (fp.lineNum - 1).clamp(0, lines.length);
    final e = fp.lineEnd.clamp(s, lines.length);
    return lines.sublist(s, e).join('\n');
  }

  /// Texto DESTINO que el visor muestra (fragmento si hay foco).
  /// Usa los límites del procedimiento en _modifiedText (no los del origen).
  String get _viewMod {
    final fp = _focusedProcItem;
    if (fp == null) return _modifiedText;
    final bounds = _findProcBounds(fp.name, _modifiedText);
    if (bounds == null)
      return _modifiedText; // proc no encontrado en destino → vista completa
    final lines = _modifiedText.split('\n');
    final s = (bounds.lineNum - 1).clamp(0, lines.length);
    final e = bounds.lineEnd.clamp(s, lines.length);
    return lines.sublist(s, e).join('\n');
  }

  /// Offset para números de línea del visor cuando hay foco.
  int get _viewLineOffset => (_focusedProcItem?.lineNum ?? 1) - 1;

  /// Reconstruye DESTINO completo reemplazando el fragmento enfocado por [fragment].
  /// Usa los límites del procedimiento en _modifiedText para un corte preciso.
  String _spliceMod(String fragment) {
    final fp = _focusedProcItem;
    if (fp == null) return fragment;
    final bounds = _findProcBounds(fp.name, _modifiedText);
    if (bounds == null)
      return fragment; // no se puede empalmar, retornar tal cual
    final lines = _modifiedText.split('\n');
    final s = (bounds.lineNum - 1).clamp(0, lines.length);
    final e = bounds.lineEnd.clamp(s, lines.length);
    return [
      ...lines.sublist(0, s),
      ...fragment.split('\n'),
      ...lines.sublist(e),
    ].join('\n');
  }

  /// Reconstruye ORIGEN completo reemplazando el fragmento enfocado por [fragment].
  String _spliceOrig(String fragment) {
    final fp = _focusedProcItem;
    if (fp == null) return fragment;
    final lines = _currentOriginal.split('\n');
    final s = (fp.lineNum - 1).clamp(0, lines.length);
    final e = fp.lineEnd.clamp(s, lines.length);
    return [
      ...lines.sublist(0, s),
      ...fragment.split('\n'),
      ...lines.sublist(e),
    ].join('\n');
  }

  void _focusProc(String name) => setState(() {
    _focusedProcName = name;
    _compilationErrors = [];
  });

  void _clearFocus() => setState(() => _focusedProcName = null);

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _extract(({String spec, String? body}) data, {String? forPart}) {
    final p = forPart ?? _part;
    if (_isPackage && p == 'SPEC') return data.spec;
    if (data.body != null && data.body!.isNotEmpty) return data.body!;
    return data.spec;
  }

  String get _objectTypeName => switch (widget.objectType) {
    'PACKAGE' => 'Paquete',
    'PROCEDURE' => 'Procedimiento',
    'FUNCTION' => 'Función',
    'TYPE' => 'Tipo',
    _ => widget.objectType,
  };

  String get _bodyNote => _isPackage ? ' · ${_part.toLowerCase()}' : '';

  // ─────────────────────────────────────────────────────────────────────────
  // Carga / compilación
  // ─────────────────────────────────────────────────────────────────────────

  /// `true` cuando el error del backend significa "el objeto no existe en ese
  /// ambiente" (y no un fallo real de conexión / permisos).
  static bool _isMissingObjectError(Object e) {
    final m = e
        .toString()
        .toLowerCase()
        .replaceAll('ó', 'o')
        .replaceAll('í', 'i');
    return m.contains('no se encontro codigo fuente') ||
        m.contains('no se encontro el objeto') ||
        m.contains('no existe');
  }

  /// Trae el fuente de un ambiente. Devuelve `null` si el objeto no existe allí.
  Future<({String spec, String? body})?> _fetchSource(String ambiente) async {
    try {
      return await SchemaService.instance.getObjectSource(
        widget.objectName,
        widget.objectType,
        ambiente: ambiente,
      );
    } catch (e) {
      if (_isMissingObjectError(e)) return null;
      rethrow;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _sourceCode = null;
      _compilationErrors = [];
      _sourceMissing = false;
      _targetMissing = false;
    });
    try {
      final results = await Future.wait([
        _fetchSource(_sourceAmbiente),
        _fetchSource(_targetAmbiente),
      ]);
      if (!mounted) return;
      final srcRaw = results[0];
      final tgtRaw = results[1];
      // No existe en ninguno de los dos ambientes: no hay nada que comparar.
      if (srcRaw == null && tgtRaw == null) {
        setState(() {
          _error =
              'El objeto ${widget.objectName} no existe en $_sourceAmbiente '
              'ni en $_targetAmbiente.';
          _loading = false;
        });
        return;
      }
      const ({String spec, String? body}) vacio = (spec: '', body: null);
      final srcData = srcRaw ?? vacio;
      final tgtData = tgtRaw ?? vacio;
      final src = _extract(srcData);
      final tgt = _extract(tgtData);
      final procs = _parseProcFuncs(src.isNotEmpty ? src : tgt);
      AppLog.instance.transaction(
        'Comparar ${widget.objectName}: $_sourceAmbiente vs $_targetAmbiente',
        source: 'Comparación',
        datos: {
          'Origen': srcRaw == null ? 'no existe' : '${src.length} chars',
          'Destino': tgtRaw == null ? 'no existe' : '${tgt.length} chars',
          'Iguales': (src == tgt).toString(),
        },
      );
      setState(() {
        _sourceMissing = srcRaw == null;
        _targetMissing = tgtRaw == null;
        _sourceData = srcData;
        _targetData = tgtData;
        _sourceCode = src;
        _modifiedText = tgt;
        _currentOriginal = src;
        _history.clear();
        _loading = false;
        _sidebarFilterCtrl.clear();
        _sidebarFilter = '';
        _procItems = procs;
        _focusedProcName = null;
        _sidebarActiveIdx = procs.isNotEmpty
            ? 0
            : -1; // primer ítem por defecto
      });
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
      AppLog.instance.exception(
        'Comparar ${widget.objectName}',
        e,
        stack: st,
        source: 'Comparación',
        datos: {
          'Objeto': '${widget.objectName} (${widget.objectType})',
          'Origen': _sourceAmbiente,
          'Destino': _targetAmbiente,
        },
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Transferencia al ambiente donde el objeto no existe
  // ─────────────────────────────────────────────────────────────────────────

  /// Incluir los privilegios (GRANT) del ambiente origen en la transferencia.
  bool _transferGrants = true;

  /// Incluir los sinónimos (públicos y privados) en la transferencia.
  bool _transferSynonyms = true;

  /// Owner del objeto en [ambiente] (`INTEGRACION`, `SIR`, …). Vacío si no se
  /// puede resolver: en ese caso el DDL se emite sin calificar el esquema.
  Future<String> _resolveOwner(String ambiente) async {
    try {
      final info = await SchemaService.instance.getObjectInfo(
        widget.objectName,
        widget.objectType,
        ambiente: ambiente,
      );
      for (final e in info) {
        if (e.name.toUpperCase() == 'OWNER') return e.value.toUpperCase();
      }
    } catch (_) {
      /* se ignora: se usa el nombre sin esquema */
    }
    return '';
  }

  /// `OWNER.OBJETO` o sólo `OBJETO` si no se resolvió el owner.
  String _qualified(String owner) =>
      owner.isEmpty ? widget.objectName : '$owner.${widget.objectName}';

  /// Crea el objeto en el ambiente donde falta compilando el fuente completo
  /// del ambiente que sí lo tiene, y replica sus GRANTs y sinónimos.
  ///
  /// Para PACKAGE compila SPEC y luego BODY. El objeto se crea con
  /// `CREATE OR REPLACE`, por lo que queda compilado y registrado en el
  /// diccionario de la base destino.
  Future<void> _transferMissing() async {
    final destino = _missingAmbiente;
    if (destino == null || _transferring) return;
    final origenAmbiente = _presentAmbiente;
    final origen = _sourceMissing ? _targetData : _sourceData;
    if (origen == null) return;

    setState(() {
      _transferring = true;
      _compilationErrors = [];
    });
    AppLog.instance.info(
      'Transferencia ${widget.objectName} ($_objectTypeName): '
      '$origenAmbiente → $destino',
      source: 'Transferencia',
    );
    try {
      final errores =
          <({int line, int position, String text, String attribute})>[];

      // ── 1. Objeto ────────────────────────────────────────────────────────
      if (_isPackage) {
        if (origen.spec.trim().isNotEmpty) {
          errores.addAll(
            await SchemaService.instance.compileObject(
              origen.spec,
              widget.objectName,
              'PACKAGE',
              ambiente: destino,
            ),
          );
        }
        final body = origen.body ?? '';
        if (errores.isEmpty && body.trim().isNotEmpty) {
          errores.addAll(
            await SchemaService.instance.compileObject(
              body,
              widget.objectName,
              'PACKAGE BODY',
              ambiente: destino,
            ),
          );
        }
      } else {
        final texto = _extract(origen);
        if (texto.trim().isEmpty) {
          throw Exception('No hay fuente para transferir.');
        }
        errores.addAll(
          await SchemaService.instance.compileObject(
            texto,
            widget.objectName,
            widget.objectType,
            ambiente: destino,
          ),
        );
      }

      if (errores.isNotEmpty) {
        AppLog.instance.compilation(
          objectName: widget.objectName,
          objectType: widget.objectType,
          ambiente: destino,
          errors: errores,
          source: 'Transferencia',
        );
        if (!mounted) return;
        setState(() {
          _transferring = false;
          _compilationErrors = errores;
        });
        AppToast.error(
          'La transferencia a $destino terminó con errores de compilación '
          '— ver consola',
        );
        return;
      }
      AppLog.instance.compilation(
        objectName: widget.objectName,
        objectType: widget.objectType,
        ambiente: destino,
        errors: const [],
        source: 'Transferencia',
      );

      // ── 2. GRANTs y sinónimos ────────────────────────────────────────────
      final extras = await _transferGrantsAndSynonyms(
        origenAmbiente: origenAmbiente,
        destino: destino,
      );

      if (!mounted) return;
      setState(() => _transferring = false);

      final resumen = StringBuffer('${widget.objectName} creado en $destino');
      if (extras.grants > 0) {
        resumen.write(' · ${extras.grants} grant(s)');
      }
      if (extras.synonyms > 0) {
        resumen.write(' · ${extras.synonyms} sinónimo(s)');
      }
      AppToast.success(resumen.toString(), source: 'Transferencia');
      if (extras.fallos.isNotEmpty) {
        AppToast.errorWithDetail(
          'No se pudieron aplicar ${extras.fallos.length} sentencia(s) '
          'en $destino',
          extras.fallos.join('\n'),
          source: 'Transferencia',
        );
      }
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _transferring = false);
      AppLog.instance.exception(
        'Transferir ${widget.objectName} a $destino',
        e,
        stack: st,
        source: 'Transferencia',
        datos: {
          'Objeto': '${widget.objectName} ($_objectTypeName)',
          'Origen': origenAmbiente,
          'Destino': destino,
        },
      );
      AppToast.error(
        'Falló la transferencia a $destino: ${AppLog.describe(e)} '
        '— ver consola',
      );
    }
  }

  /// Replica en [destino] los privilegios y sinónimos que el objeto tiene en
  /// [origenAmbiente].
  ///
  /// Genera y ejecuta sentencias del estilo:
  /// ```sql
  /// GRANT EXECUTE ON INTEGRACION.OBJ_RECIBOS TO PUBLIC;
  /// CREATE OR REPLACE PUBLIC SYNONYM OBJ_RECIBOS FOR INTEGRACION.OBJ_RECIBOS;
  /// ```
  /// Nunca aborta la transferencia: los fallos se acumulan y se informan.
  Future<({int grants, int synonyms, List<String> fallos})>
  _transferGrantsAndSynonyms({
    required String origenAmbiente,
    required String destino,
  }) async {
    final fallos = <String>[];
    var grantsOk = 0;
    var synonymsOk = 0;
    if (!_transferGrants && !_transferSynonyms) {
      return (grants: 0, synonyms: 0, fallos: fallos);
    }

    // El owner se resuelve en el destino (ya se creó el objeto allí); si no se
    // puede, se usa el del origen.
    var owner = await _resolveOwner(destino);
    if (owner.isEmpty) owner = await _resolveOwner(origenAmbiente);
    final target = _qualified(owner);

    Future<void> run(String ddl) async {
      try {
        await SchemaService.instance.executeDdl(
          ddl,
          objectName: widget.objectName,
          objectType: widget.objectType,
          ambiente: destino,
        );
        AppLog.instance.ddl(ddl, ambiente: destino, source: 'Transferencia');
      } catch (e) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        AppLog.instance.ddl(
          ddl,
          ambiente: destino,
          errorMessage: msg,
          source: 'Transferencia',
        );
        fallos.add('$ddl → $msg');
      }
    }

    if (_transferGrants) {
      final privs = await SchemaService.instance.getObjectPrivileges(
        widget.objectName,
        ambiente: origenAmbiente,
      );
      for (final p in privs) {
        if (p.privilege.isEmpty || p.grantee.isEmpty) continue;
        final ddl =
            'GRANT ${p.privilege} ON $target TO ${p.grantee}'
            '${p.grantable ? ' WITH GRANT OPTION' : ''}';
        final antes = fallos.length;
        await run(ddl);
        if (fallos.length == antes) grantsOk++;
      }
    }

    if (_transferSynonyms) {
      final syns = await SchemaService.instance.getSynonyms(
        widget.objectName,
        ambiente: origenAmbiente,
      );
      for (final s in syns) {
        if (s.synonymName.isEmpty) continue;
        final nombre = s.isPublic || s.owner.isEmpty || s.owner == 'PUBLIC'
            ? s.synonymName
            : '${s.owner}.${s.synonymName}';
        final ddl =
            'CREATE OR REPLACE ${s.isPublic ? 'PUBLIC ' : ''}'
            'SYNONYM $nombre FOR $target';
        final antes = fallos.length;
        await run(ddl);
        if (fallos.length == antes) synonymsOk++;
      }
    }

    return (grants: grantsOk, synonyms: synonymsOk, fallos: fallos);
  }

  Future<void> _compile() async {
    final code = _modifiedText;
    setState(() {
      _compiling = true;
      _compilationErrors = [];
    });
    try {
      final errors = await SchemaService.instance.compileObject(
        code,
        widget.objectName,
        widget.objectType,
        ambiente: _targetAmbiente,
      );
      if (!mounted) return;
      setState(() {
        _compiling = false;
        _compilationErrors = errors;
      });
      AppLog.instance.compilation(
        objectName: widget.objectName,
        objectType: widget.objectType,
        ambiente: _targetAmbiente,
        part: _isPackage ? _part : null,
        errors: errors,
      );
      if (errors.isEmpty) {
        AppToast.success('Compilado correctamente en $_targetAmbiente');
      } else {
        AppToast.error(
          'Compilación con ${errors.length} error(es) — ver consola',
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _compiling = false);
      AppLog.instance.exception(
        'Compilar ${widget.objectName} en $_targetAmbiente',
        e,
        stack: st,
        source: 'Compilación',
        datos: {
          'Objeto': '${widget.objectName} (${widget.objectType})',
          'Ambiente': _targetAmbiente,
          if (_isPackage) 'Parte': _part,
        },
      );
      AppToast.error(
        'No se pudo compilar en $_targetAmbiente: '
        '${AppLog.describe(e)} — ver consola',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Backup
  // ─────────────────────────────────────────────────────────────────────────

  /// Exporta [text] al disco como backup .sql del objeto de esquema.
  /// [isSource] distingue el label del toast y el nombre del archivo.
  Future<void> _backup({required String text, required bool isSource}) async {
    final ambiente = isSource ? _sourceAmbiente : _targetAmbiente;
    final label = isSource ? 'Origen' : 'Destino';
    // Para PACKAGE indicamos la parte actual (SPEC / BODY)
    final part = _isPackage ? _part : null;
    try {
      final savedPath = await BackupService.exportarDdl(
        objectName: widget.objectName,
        objectType: widget.objectType,
        ambiente: ambiente,
        source: text,
        part: part,
      );
      if (savedPath != null) {
        AppToast.successWithAction(
          'Backup $label exportado correctamente',
          detail: savedPath,
          actionLabel: 'Abrir ubicación',
          onAction: () => BackupService.revealInExplorer(savedPath),
        );
      }
    } catch (e) {
      AppToast.error('Error al exportar backup: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Vista SPEC / BODY
  // ─────────────────────────────────────────────────────────────────────────

  void _switchPart(String part) {
    if (_part == part || _sourceData == null) return;
    // Pasar `forPart: part` para que _extract use el NUEVO part, no el actual
    final src = _extract(_sourceData!, forPart: part);
    final tgt = _extract(_targetData!, forPart: part);
    final procs = _parseProcFuncs(src);
    _sidebarFilterCtrl.clear();
    // Preservar el foco si el mismo proc/func existe en la nueva parte
    final preservedFocus =
        _focusedProcName != null && procs.any((p) => p.name == _focusedProcName)
        ? _focusedProcName
        : null;
    setState(() {
      _part = part;
      _sourceCode = src;
      _modifiedText = tgt;
      _currentOriginal = src;
      _history.clear();
      _compilationErrors = [];
      _procItems = procs;
      _focusedProcName = preservedFocus;
      _sidebarFilter = '';
      _sidebarActiveIdx = preservedFocus != null
          ? procs.indexWhere((p) => p.name == preservedFocus)
          : (procs.isNotEmpty ? 0 : -1);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Navegación
  // ─────────────────────────────────────────────────────────────────────────

  void _nextChange() => _diffCtrl.nextChange();
  void _prevChange() => _diffCtrl.previousChange();

  // ─────────────────────────────────────────────────────────────────────────
  // Aplicar cambios — por HUNK
  // ─────────────────────────────────────────────────────────────────────────

  /// Aplica el hunk [idx] copiando ORIGEN → DESTINO.
  void _applyHunkToTarget(int idx) {
    final oFrag = _viewOrig;
    final mFrag = _viewMod;
    final hunks = computeHunks(oFrag, mFrag);
    if (idx < 0 || idx >= hunks.length) return;
    final h = hunks[idx];
    final oL = oFrag.split('\n');
    final dL = mFrag.split('\n');
    final newFrag = [
      ...dL.sublist(0, h.modStart),
      ...oL.sublist(h.origStart, h.origEnd),
      ...dL.sublist(h.modEnd),
    ].join('\n');
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _modifiedText = _spliceMod(newFrag);
    });
  }

  /// Aplica el hunk [idx] copiando DESTINO → ORIGEN.
  void _applyHunkToSource(int idx) {
    final oFrag = _viewOrig;
    final mFrag = _viewMod;
    final hunks = computeHunks(oFrag, mFrag);
    if (idx < 0 || idx >= hunks.length) return;
    final h = hunks[idx];
    final oL = oFrag.split('\n');
    final dL = mFrag.split('\n');
    final newFrag = [
      ...oL.sublist(0, h.origStart),
      ...dL.sublist(h.modStart, h.modEnd),
      ...oL.sublist(h.origEnd),
    ].join('\n');
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _currentOriginal = _spliceOrig(newFrag);
    });
  }

  void _applyCurrentHunkToTarget() => _applyHunkToTarget(_diffCtrl.currentHunk);
  void _applyCurrentHunkToSource() => _applyHunkToSource(_diffCtrl.currentHunk);

  void _applyAllToTarget() {
    final orig = _viewOrig;
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _modifiedText = _spliceMod(orig);
    });
  }

  void _applyAllToSource() {
    final mod = _viewMod;
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _currentOriginal = _spliceOrig(mod);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Aplicar cambios — por LÍNEA (callbacks del viewer)
  // ─────────────────────────────────────────────────────────────────────────

  /// Copia la línea [hunkRow] del hunk [hunkIdx] de ORIGEN → DESTINO.
  void _applyLineToTarget(int hunkIdx, int hunkRow) {
    final oFrag = _viewOrig;
    final mFrag = _viewMod;
    final hunks = computeHunks(oFrag, mFrag);
    if (hunkIdx >= hunks.length) return;
    final h = hunks[hunkIdx];
    final oC = h.origEnd - h.origStart;
    final mC = h.modEnd - h.modStart;
    final hasO = hunkRow < oC;
    final hasM = hunkRow < mC;
    final oL = oFrag.split('\n');
    final dL = List<String>.from(mFrag.split('\n'));

    if (hasO && hasM) {
      dL[h.modStart + hunkRow] = oL[h.origStart + hunkRow];
    } else if (hasO && !hasM) {
      final at = (h.modEnd + (hunkRow - mC)).clamp(0, dL.length);
      dL.insert(at, oL[h.origStart + hunkRow]);
    } else if (!hasO && hasM) {
      final ri = h.modStart + hunkRow;
      if (ri >= 0 && ri < dL.length) dL.removeAt(ri);
    }

    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _modifiedText = _spliceMod(dL.join('\n'));
    });
  }

  /// Copia la línea [hunkRow] del hunk [hunkIdx] de DESTINO → ORIGEN.
  void _applyLineToSource(int hunkIdx, int hunkRow) {
    final oFrag = _viewOrig;
    final mFrag = _viewMod;
    final hunks = computeHunks(oFrag, mFrag);
    if (hunkIdx >= hunks.length) return;
    final h = hunks[hunkIdx];
    final oC = h.origEnd - h.origStart;
    final mC = h.modEnd - h.modStart;
    final hasO = hunkRow < oC;
    final hasM = hunkRow < mC;
    final oL = List<String>.from(oFrag.split('\n'));
    final dL = mFrag.split('\n');

    if (hasO && hasM) {
      oL[h.origStart + hunkRow] = dL[h.modStart + hunkRow];
    } else if (hasO && !hasM) {
      final ri = h.origStart + hunkRow;
      if (ri >= 0 && ri < oL.length) oL.removeAt(ri);
    } else if (!hasO && hasM) {
      final at = (h.origEnd + (hunkRow - oC)).clamp(0, oL.length);
      oL.insert(at, dL[h.modStart + hunkRow]);
    }

    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _currentOriginal = _spliceOrig(oL.join('\n'));
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Undo
  // ─────────────────────────────────────────────────────────────────────────

  void _undo() {
    if (_history.isEmpty) return;
    final prev = _history.last;
    setState(() {
      _history.removeLast();
      _currentOriginal = prev.original;
      _modifiedText = prev.modified;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Editar origen / destino (reutilizable)
  // ─────────────────────────────────────────────────────────────────────────

  /// Editor de texto plano del código origen/destino.
  ///
  /// Se abre como ventana flotante (no `showDialog`) porque el comparador vive
  /// en el overlay raíz: un diálogo montado como ruta del Navigator quedaría
  /// por detrás y no se podría usar.
  void _openEditDialog({required bool isSource}) {
    final cs = Theme.of(context).colorScheme;
    final color = isSource
        ? AmbienteSelector.colorForAmbiente(_sourceAmbiente)
        : AmbienteSelector.colorForAmbiente(_targetAmbiente);
    final label = isSource
        ? 'ORIGEN — ${_sourceAmbiente.toUpperCase()}'
        : 'DESTINO — ${_targetAmbiente.toUpperCase()}';
    final ec = TextEditingController(
      text: isSource ? _currentOriginal : _modifiedText,
    );

    showFloatingWindow(context, barrierColor: Colors.black54, (dismiss) {
      void close() {
        dismiss();
        ec.dispose();
      }

      return Padding(
        padding: const EdgeInsets.all(24),
        child: Material(
          color: cs.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(10),
          elevation: 16,
          child: Column(
            children: [
              ConstellationHeader(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                lineColor: color.withValues(alpha: 0.35),
                decoration: BoxDecoration(color: cs.surfaceContainerHigh),
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editar $label · ${widget.objectName}$_bodyNote',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(onPressed: close, child: const Text('Cancelar')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: color),
                      onPressed: () {
                        setState(() {
                          if (isSource) {
                            _history.add((
                              original: _currentOriginal,
                              modified: _modifiedText,
                            ));
                            _currentOriginal = ec.text;
                          } else {
                            _modifiedText = ec.text;
                          }
                        });
                        close();
                      },
                      icon: const Icon(Icons.check, size: 14),
                      label: const Text('Aplicar'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: ec,
                  maxLines: null,
                  expands: true,
                  autofocus: true,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sidebar: parseo de PROCEDURE / FUNCTION en paquetes
  // ─────────────────────────────────────────────────────────────────────────

  static final _plsqlRe = RegExp(
    r'^\s*(PROCEDURE|FUNCTION)\s+([A-Za-z_][A-Za-z0-9_$#]*)',
    caseSensitive: false,
  );

  /// Parsea el código fuente y devuelve lista de (name, type, lineNum, lineEnd).
  /// [lineEnd] es el número de línea exclusivo del fin del procedimiento (0-based count).
  List<({String name, String type, int lineNum, int lineEnd})> _parseProcFuncs(
    String source,
  ) {
    final lines = source.split('\n');
    final raw = <({String name, String type, int lineNum})>[];
    final seen = <String>{};
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('--')) continue;
      final m = _plsqlRe.firstMatch(lines[i]);
      if (m == null) continue;
      final name = m.group(2)!.toUpperCase();
      final type = m.group(1)!.toUpperCase();
      if (!seen.contains(name)) {
        seen.add(name);
        raw.add((name: name, type: type, lineNum: i + 1));
      }
    }
    return List.generate(raw.length, (i) {
      final end = i + 1 < raw.length ? raw[i + 1].lineNum - 1 : lines.length;
      return (
        name: raw[i].name,
        type: raw[i].type,
        lineNum: raw[i].lineNum,
        lineEnd: end,
      );
    });
  }

  /// Busca los límites de un procedimiento/función por nombre en [text].
  /// Parsea [text] de forma independiente para obtener rangos precisos.
  /// Retorna null si el nombre no se encuentra en el texto.
  ({int lineNum, int lineEnd})? _findProcBounds(String name, String text) {
    final items = _parseProcFuncs(text);
    final found = items.where((p) => p.name == name).firstOrNull;
    if (found == null) return null;
    return (lineNum: found.lineNum, lineEnd: found.lineEnd);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final srcColor = AmbienteSelector.colorForAmbiente(_sourceAmbiente);
    final tgtColor = AmbienteSelector.colorForAmbiente(_targetAmbiente);
    final size = MediaQuery.sizeOf(context);
    final gripColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.18,
    );

    // Ventana contenida por defecto (nunca a pantalla completa).
    if (_maximized) {
      _winW = (size.width - 48).clamp(320.0, size.width);
      _winH = (size.height - 48).clamp(280.0, size.height);
    } else {
      _winW ??= (size.width * 0.80).clamp(_kMinW, 1180.0);
      _winH ??= (size.height * 0.80).clamp(420.0, 860.0);
    }
    // Nunca más grande que la pantalla (evita clamps invertidos al posicionar).
    if (_winW! > size.width) _winW = size.width;
    if (_winH! > size.height) _winH = size.height;

    // Geometría efectiva: minimizada ocupa solo la barra de título.
    final double w, h, left, top;
    if (_minimized) {
      w = FloatingWindowSlots.barW;
      h = FloatingWindowSlots.barH;
      final (l, t) = FloatingWindowSlots.offsetFor(_slot ?? 0, size);
      left = l;
      top = t;
    } else {
      w = _winW!;
      h = _winH!;
      left = ((size.width - w) / 2 + _position.dx).clamp(
        0.0,
        (size.width - w).clamp(0.0, double.infinity),
      );
      top = ((size.height - h) / 2 + _position.dy).clamp(
        0.0,
        (size.height - h).clamp(0.0, double.infinity),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        // Minimizada no debe retener el teclado: el foco vuelve a la app.
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
                  // El contenido se mantiene SIEMPRE montado con el tamaño de
                  // la ventana restaurada: al minimizar sólo se recorta. Si se
                  // quitara del árbol, al restaurar se perdería el scroll del
                  // visor y se reconstruiría todo el diff.
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: SizedBox(
                      width: _winW,
                      height: _winH,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Column(
                              children: [
                                // Hueco reservado para la barra de título.
                                const SizedBox(height: _kHeaderH),
                                Expanded(
                                  child: _buildBody(
                                    isDark,
                                    cs,
                                    srcColor,
                                    tgtColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // La barra de título usa el ancho *visible* para que
                          // al minimizar siga viéndose completa.
                          Positioned(
                            left: 0,
                            top: 0,
                            width: w,
                            child: _buildHeader(isDark, cs),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Resize: borde derecho ─────────────────────────────────────
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 5,
                top: top + 44,
                width: 10,
                height: (h - 54).clamp(0.0, double.infinity),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(
                        _kMinW,
                        size.width - 40,
                      );
                    }),
                  ),
                ),
              ),

            // ── Resize: borde inferior ────────────────────────────────────
            if (!_maximized && !_minimized)
              Positioned(
                left: left + 16,
                top: top + h - 5,
                width: (w - 32).clamp(0.0, double.infinity),
                height: 10,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winH = (_winH! + d.delta.dy).clamp(
                        360.0,
                        size.height - 40,
                      );
                    }),
                  ),
                ),
              ),

            // ── Resize: esquina inferior derecha (grip) ───────────────────
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
                      _winW = (_winW! + d.delta.dx).clamp(
                        _kMinW,
                        size.width - 40,
                      );
                      _winH = (_winH! + d.delta.dy).clamp(
                        360.0,
                        size.height - 40,
                      );
                    }),
                    child: CustomPaint(painter: WindowGripPainter(gripColor)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Barra de título (arrastrable) ──────────────────────────────────────────

  Widget _buildHeader(bool isDark, ColorScheme cs) {
    final divColor = cs.outlineVariant;

    return MouseRegion(
      cursor: (_maximized || _minimized)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (_maximized || _minimized)
            ? null
            : (d) => setState(() {
                _anim = Duration.zero;
                _position += d.delta;
              }),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 940;
            return ConstellationHeader(
              height: _kHeaderH,
              // Sin padding a la derecha: los botones de ventana deben quedar
              // pegados al borde, como en una ventana nativa.
              padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF161B22)
                    : const Color(0xFFF6F8FA),
                border: _minimized
                    ? null
                    : Border(bottom: BorderSide(color: divColor)),
              ),
              child: Row(
                children: [
                  // Título: un único hijo flexible que absorbe todo el espacio
                  // libre. (Si se usara `Flexible` + `Spacer` ambos se
                  // repartirían el espacio y el sobrante del título quedaría
                  // sin asignar, despegando los botones del borde derecho.)
                  //
                  // El doble clic (maximizar) se limita a esta zona: si
                  // cubriera los botones, su `onTap` esperaría el timeout del
                  // doble clic (~300 ms) antes de responder.
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _minimized
                          ? _toggleMinimized
                          : _toggleMaximized,
                      child: Row(
                        children: [
                          if (!compact && !_minimized) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.blue.shade400,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                'SCHEMA DIFF',
                                style: TextStyle(
                                  color: Colors.blue.shade400,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              widget.objectName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              widget.objectType + _bodyNote,
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Controles de ventana: pegados al borde derecho ──────
                  WindowButton.titleBar(
                    icon: _minimized
                        ? Icons.expand_less_rounded
                        : Icons.remove_rounded,
                    tooltip: _minimized ? 'Restaurar' : 'Minimizar',
                    onTap: _toggleMinimized,
                  ),
                  WindowButton.titleBar(
                    icon: _maximized
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    tooltip: _maximized
                        ? 'Restaurar tamaño  (F11)'
                        : 'Maximizar  (F11)',
                    size: 13,
                    onTap: () {
                      if (_minimized) {
                        _toggleMinimized();
                      } else {
                        _toggleMaximized();
                      }
                    },
                  ),
                  WindowButton.titleBar(
                    icon: Icons.close_rounded,
                    tooltip: 'Cerrar  (Esc)',
                    isClose: true,
                    size: 16,
                    onTap: _close,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Controles de comparación (van en la toolbar, no en la barra de título) ─

  List<Widget> _compareControls(ColorScheme cs, {bool compact = false}) => [
    // SPEC / BODY (solo PACKAGE con body)
    if (_isPackage && (_sourceData?.body?.isNotEmpty ?? false)) ...[
      SegmentedButton<String>(
        style: SegmentedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 26),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 11),
        ),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'SPEC', label: Text('Spec')),
          ButtonSegment(value: 'BODY', label: Text('Body')),
        ],
        selected: {_part},
        onSelectionChanged: (s) => _switchPart(s.first),
      ),
      const SizedBox(width: 8),
    ],
    // Comparar
    Tooltip(
      message: compact
          ? 'Volver a comparar  ($_sourceAmbiente vs $_targetAmbiente)'
          : '',
      child: FilledButton.icon(
        onPressed: _loading ? null : _load,
        icon: _loading
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.compare_arrows, size: 13),
        label: compact
            ? const SizedBox.shrink()
            : const Text('Comparar', style: TextStyle(fontSize: 11)),
        style: FilledButton.styleFrom(
          padding: compact
              ? const EdgeInsets.fromLTRB(8, 4, 4, 4)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    ),
  ];

  /// Botón para intercambiar los ambientes origen y destino.
  Widget _swapButton(ColorScheme cs) => Tooltip(
    message: 'Intercambiar origen y destino',
    child: InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: _swapAmbientes,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(Icons.swap_horiz, size: 15, color: cs.onSurfaceVariant),
      ),
    ),
  );

  /// Menú de dos opciones (Origen / Destino) para las acciones de la toolbar.
  ///
  /// Usa [MenuAnchor] en vez de `PopupMenuButton`: la ventana vive en el
  /// overlay raíz por encima de las rutas del Navigator, así que un menú
  /// abierto como ruta quedaría detrás de la ventana.
  Widget _srcTgtMenu(
    ColorScheme cs, {
    required String tooltip,
    required IconData icon,
    required IconData srcIcon,
    required IconData tgtIcon,
    required String srcLabel,
    required String tgtLabel,
    required void Function(bool isSource) onSelected,
  }) {
    Widget item({
      required bool isSource,
      required IconData ic,
      required String label,
    }) {
      final amb = isSource ? _sourceAmbiente : _targetAmbiente;
      final color = AmbienteSelector.colorForAmbiente(amb);
      return MenuItemButton(
        onPressed: () => onSelected(isSource),
        leadingIcon: Icon(ic, size: 15, color: color),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(
              amb.toUpperCase(),
              style: TextStyle(fontSize: 10, color: color),
            ),
          ],
        ),
      );
    }

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        item(isSource: true, ic: srcIcon, label: srcLabel),
        item(isSource: false, ic: tgtIcon, label: tgtLabel),
      ],
      builder: (context, controller, _) => Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Icon(icon, size: 15, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody(
    bool isDark,
    ColorScheme cs,
    Color srcColor,
    Color tgtColor,
  ) {
    // La toolbar (con los controles de comparación) está siempre visible;
    // debajo cambia el contenido según el estado.
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _history.isEmpty ? () {} : _undo,
        SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _prevChange,
        SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): _nextChange,
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            _applyCurrentHunkToSource,
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            _applyCurrentHunkToTarget,
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true, shift: true):
            _applyAllToSource,
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true, shift: true):
            _applyAllToTarget,
      },
      child: Focus(
        autofocus: false,
        child: Column(
          children: [
            _buildToolbar(isDark, cs, srcColor, tgtColor),
            Expanded(child: _buildContent(isDark, cs)),
          ],
        ),
      ),
    );
  }

  /// Contenido bajo la toolbar: carga, error, placeholder o el visor de diff.
  Widget _buildContent(bool isDark, ColorScheme cs) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0078D4)),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 36, color: Colors.orange.shade400),
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: cs.onSurface, fontSize: 13)),
          ],
        ),
      );
    }
    if (_sourceCode == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.compare_arrows,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              'Seleccioná el ambiente y presioná Comparar',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              _objectTypeName,
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        // Sidebar de procedimientos/funciones (solo PACKAGE)
        if (_isPackage && _sidebarVisible) _buildSidebar(isDark, cs),
        // Visor principal
        Expanded(
          child: Column(
            children: [
              if (_missingAmbiente != null) _buildMissingBanner(isDark, cs),
              Expanded(
                child: NativeDiffViewer(
                  origText: _viewOrig,
                  modText: _viewMod,
                  sideBySide: _sideBySide,
                  showAllLines: _showAllLines,
                  lineOffset: _viewLineOffset,
                  controller: _diffCtrl,
                  onApplyLineToTarget: _applyLineToTarget,
                  onApplyLineToSource: _applyLineToSource,
                ),
              ),
              if (_compilationErrors.isNotEmpty) _buildErrorsPanel(isDark, cs),
            ],
          ),
        ),
      ],
    );
  }

  /// Aviso cuando el objeto existe en un ambiente pero no en el otro, con la
  /// acción para transferirlo (crearlo) en el ambiente donde falta.
  Widget _buildMissingBanner(bool isDark, ColorScheme cs) {
    final destino = _missingAmbiente!;
    final accent = Colors.orange.shade400;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.10 : 0.14),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_objectTypeName ${widget.objectName} no existe en $destino. '
              'Podés transferirlo desde $_presentAmbiente.',
              style: TextStyle(color: cs.onSurface, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _transferring ? null : _confirmTransfer,
            icon: _transferring
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_upload_outlined, size: 14),
            label: Text(
              _transferring ? 'Transfiriendo…' : 'Transferir a $destino',
              style: const TextStyle(fontSize: 11),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  /// Pide confirmación antes de crear el objeto en el ambiente destino y
  /// permite elegir si se replican los GRANTs y los sinónimos.
  Future<void> _confirmTransfer() async {
    final destino = _missingAmbiente;
    if (destino == null) return;
    var grants = _transferGrants;
    var synonyms = _transferSynonyms;
    // `showDialog` montaría la ruta por DEBAJO del overlay donde vive esta
    // ventana flotante (quedaría tapada), por eso se usa showFloatingDialog.
    final ok = await showFloatingDialog<bool>(
      context,
      (ctx, close) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Transferir objeto'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se va a crear y compilar ${widget.objectName} '
                  '($_objectTypeName) en $destino usando el fuente de '
                  '$_presentAmbiente.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: grants,
                  onChanged: (v) => setDlg(() => grants = v ?? false),
                  title: const Text(
                    'Copiar privilegios (GRANT)',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'GRANT EXECUTE ON … TO PUBLIC',
                    style: TextStyle(fontSize: 11, fontFamily: 'Consolas'),
                  ),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: synonyms,
                  onChanged: (v) => setDlg(() => synonyms = v ?? false),
                  title: const Text(
                    'Copiar sinónimos (públicos y privados)',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'CREATE OR REPLACE PUBLIC SYNONYM … FOR …',
                    style: TextStyle(fontSize: 11, fontFamily: 'Consolas'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => close(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => close(true),
              child: Text('Transferir a $destino'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() {
      _transferGrants = grants;
      _transferSynonyms = synonyms;
    });
    await _transferMissing();
  }

  // ── Toolbar ────────────────────────────────────────────────────────────────

  Widget _buildToolbar(
    bool isDark,
    ColorScheme cs,
    Color srcColor,
    Color tgtColor,
  ) {
    final divColor = cs.outlineVariant;
    final hasDiff = _sourceCode != null && _error == null && !_loading;

    // Sin comparación cargada: toolbar reducida con sólo los controles para
    // lanzar la comparación.
    if (!hasDiff) {
      return Container(
        height: 38,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
          border: Border(bottom: BorderSide(color: divColor)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            _ambBadgeSelector(
              amb: _sourceAmbiente,
              color: srcColor,
              role: 'ORIGEN',
              isSource: true,
            ),
            _swapButton(cs),
            _ambBadgeSelector(
              amb: _targetAmbiente,
              color: tgtColor,
              role: 'DESTINO',
              isSource: false,
            ),
            const Spacer(),
            ..._compareControls(cs),
            const SizedBox(width: 8),
          ],
        ),
      );
    }

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
        border: Border(bottom: BorderSide(color: divColor)),
      ),
      child: Row(
        children: [
          // ── Lado izquierdo: ORIGEN ────────────────────────────────────────
          const SizedBox(width: 8),
          _ambBadgeSelector(
            amb: _sourceAmbiente,
            color: srcColor,
            role: 'ORIGEN',
            isSource: true,
          ),
          const SizedBox(width: 4),

          // ←← copia todo DESTINO→ORIGEN
          _tbBtn(
            tooltip: 'Copiar TODO: DESTINO→ORIGEN  (Alt+Shift+←)',
            icon: Icons.keyboard_double_arrow_left,
            color: srcColor,
            onTap: _applyAllToSource,
          ),

          // ← copia hunk actual DESTINO→ORIGEN
          _tbBtn(
            tooltip: 'Aplicar cambio actual: DESTINO→ORIGEN  (Alt+←)',
            icon: Icons.chevron_left,
            color: srcColor,
            size: 20,
            onTap: _applyCurrentHunkToSource,
          ),

          // ── Navegación central ────────────────────────────────────────────
          _vSep(divColor),
          _tbBtn(
            tooltip: 'Cambio anterior  (Alt+↑)',
            icon: Icons.keyboard_arrow_up,
            onTap: _prevChange,
          ),

          // Contador de hunks
          ListenableBuilder(
            listenable: _diffCtrl,
            builder: (_, __) {
              final tot = _diffCtrl.totalHunks;
              final cur = _diffCtrl.currentHunk;
              return Container(
                constraints: const BoxConstraints(minWidth: 52),
                alignment: Alignment.center,
                child: tot == 0
                    ? Text(
                        '✓ Sin cambios',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Text(
                        '${cur + 1} / $tot',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              );
            },
          ),

          _tbBtn(
            tooltip: 'Siguiente cambio  (Alt+↓)',
            icon: Icons.keyboard_arrow_down,
            onTap: _nextChange,
          ),
          _vSep(divColor),

          // → copia hunk actual ORIGEN→DESTINO
          _tbBtn(
            tooltip: 'Aplicar cambio actual: ORIGEN→DESTINO  (Alt+→)',
            icon: Icons.chevron_right,
            color: tgtColor,
            size: 20,
            onTap: _applyCurrentHunkToTarget,
          ),

          // →→ copia todo ORIGEN→DESTINO
          _tbBtn(
            tooltip: 'Copiar TODO: ORIGEN→DESTINO  (Alt+Shift+→)',
            icon: Icons.keyboard_double_arrow_right,
            color: tgtColor,
            onTap: _applyAllToTarget,
          ),

          const SizedBox(width: 4),
          _ambBadgeSelector(
            amb: _targetAmbiente,
            color: tgtColor,
            role: 'DESTINO',
            isSource: false,
          ),

          // ── Separador principal ───────────────────────────────────────────
          const Spacer(),

          // Chip de foco activo (solo PACKAGE, cuando hay foco)
          if (_focusedProcName != null) ...[
            _vSep(divColor),
            Tooltip(
              message:
                  'Viendo solo: $_focusedProcName  –  Clic × para ver el paquete completo',
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                padding: const EdgeInsets.fromLTRB(7, 2, 4, 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.center_focus_strong,
                      size: 11,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _focusedProcName!,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 3),
                    GestureDetector(
                      onTap: _clearFocus,
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: cs.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          _vSep(divColor),

          // Toggle sidebar (solo PACKAGE)
          if (_isPackage) ...[
            Tooltip(
              message: _sidebarVisible
                  ? 'Ocultar panel de navegación'
                  : 'Mostrar panel de navegación',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => setState(() => _sidebarVisible = !_sidebarVisible),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Icon(
                    _sidebarVisible
                        ? Icons.view_sidebar
                        : Icons.view_sidebar_outlined,
                    size: 14,
                    color: _sidebarVisible
                        ? Theme.of(context).colorScheme.primary
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            _vSep(divColor),
          ],

          // Solo diffs / Código completo
          Tooltip(
            message: _showAllLines
                ? 'Mostrar solo diffs'
                : 'Mostrar código completo',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => setState(() => _showAllLines = !_showAllLines),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _showAllLines
                          ? Icons.article_outlined
                          : Icons.difference_outlined,
                      size: 14,
                      color: _showAllLines
                          ? Colors.amber.shade600
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showAllLines ? 'Completo' : 'Solo diffs',
                      style: TextStyle(
                        fontSize: 11,
                        color: _showAllLines
                            ? Colors.amber.shade600
                            : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          _vSep(divColor),

          // SBS / Unified
          Tooltip(
            message: _sideBySide ? 'Vista unificada' : 'Vista lado a lado',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => setState(() => _sideBySide = !_sideBySide),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _sideBySide
                          ? Icons.view_agenda_outlined
                          : Icons.view_sidebar_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _sideBySide ? 'Dividida' : 'Unificada',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          _vSep(divColor),

          // Editar origen / destino — menú, oculto en modo foco
          if (_focusedProcName == null) ...[
            _srcTgtMenu(
              cs,
              tooltip: 'Editar código (Origen / Destino)',
              icon: Icons.edit_outlined,
              srcIcon: Icons.edit_note_outlined,
              tgtIcon: Icons.edit_outlined,
              srcLabel: 'Editar Origen',
              tgtLabel: 'Editar Destino',
              onSelected: (isSource) => _openEditDialog(isSource: isSource),
            ),
            _vSep(divColor),
          ],

          // Undo con badge
          Tooltip(
            message: _history.isEmpty
                ? 'Nada que deshacer'
                : 'Deshacer  Ctrl+Z  (${_history.length} operaciones)',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _history.isEmpty ? null : _undo,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.undo,
                      size: 16,
                      color: _history.isEmpty
                          ? cs.onSurfaceVariant.withValues(alpha: 0.3)
                          : Colors.amber.shade600,
                    ),
                    if (_history.isNotEmpty)
                      Positioned(
                        top: -4,
                        right: -6,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: Colors.amber.shade600,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${_history.length}',
                              style: const TextStyle(
                                fontSize: 7,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          _vSep(divColor),

          // Backup — menú con Origen y Destino (oculto en modo foco)
          if (_focusedProcName == null) ...[
            _srcTgtMenu(
              cs,
              tooltip: 'Backup del objeto (Origen / Destino)',
              icon: Icons.save_alt_outlined,
              srcIcon: Icons.download_outlined,
              tgtIcon: Icons.download_outlined,
              srcLabel: 'Backup Origen',
              tgtLabel: 'Backup Destino',
              onSelected: (isSource) => isSource
                  ? _backup(text: _currentOriginal, isSource: true)
                  : _backup(text: _modifiedText, isSource: false),
            ),
          ], // fin if _focusedProcName == null (backup)

          _vSep(divColor),

          // Controles de comparación (re-comparar / cambiar ambiente o parte)
          ..._compareControls(cs, compact: true),

          _vSep(divColor),

          // Compilar — oculto cuando hay foco en un procedimiento puntual
          if (_focusedProcName != null)
            Tooltip(
              message:
                  'Estás viendo solo "$_focusedProcName".\n'
                  'Salí del foco (×) para compilar el destino completo.',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: Colors.orange.shade400,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Salir del foco para compilar',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _clearFocus,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade400.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.orange.shade400,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.zoom_out_map,
                              size: 11,
                              color: Colors.orange.shade400,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Ver todo',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange.shade400,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: tgtColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  textStyle: const TextStyle(fontSize: 11),
                ),
                onPressed: _compiling ? null : _compile,
                icon: _compiling
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.build_outlined, size: 13),
                label: Text(
                  'Compilar $_targetAmbiente',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  // ── Helpers toolbar ────────────────────────────────────────────────────────

  Widget _tbBtn({
    required String tooltip,
    required IconData icon,
    Color? color,
    double size = 16,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Icon(
            icon,
            size: size,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _vSep(Color color) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: color,
  );

  // ── Menú contextual de procedimiento ─────────────────────────────────────

  /// Opciones del menú contextual de un procedimiento del sidebar.
  ///
  /// Se usan con [MenuAnchor] (no `showMenu`) para que el menú quede por
  /// encima de la ventana flotante.
  List<Widget> _procMenuItems(
    ColorScheme cs,
    ({String name, String type, int lineNum, int lineEnd}) item,
  ) => [
    MenuItemButton(
      onPressed: () => _focusProc(item.name),
      leadingIcon: Icon(Icons.center_focus_strong, size: 14, color: cs.primary),
      child: Text(
        'Ver solo: ${item.name}',
        style: const TextStyle(fontSize: 12),
      ),
    ),
    const Divider(height: 1),
    MenuItemButton(
      onPressed: () => _applyProcAllToTarget(item),
      leadingIcon: Icon(
        Icons.arrow_forward,
        size: 14,
        color: Colors.green.shade600,
      ),
      child: const Text(
        'Aplicar cambios → Destino',
        style: TextStyle(fontSize: 12),
      ),
    ),
    MenuItemButton(
      onPressed: () => _applyProcAllToSource(item),
      leadingIcon: Icon(
        Icons.arrow_back,
        size: 14,
        color: Colors.orange.shade600,
      ),
      child: const Text(
        'Aplicar cambios → Origen',
        style: TextStyle(fontSize: 12),
      ),
    ),
  ];

  /// Aplica TODOS los cambios del proc [item] de ORIGEN → DESTINO
  /// independientemente del foco activo.
  void _applyProcAllToTarget(
    ({String name, String type, int lineNum, int lineEnd}) item,
  ) {
    final oLines = _currentOriginal.split('\n');
    final mLines = _modifiedText.split('\n');
    // Límites del lado ORIGEN (del item, ya parseados correctamente)
    final os = (item.lineNum - 1).clamp(0, oLines.length);
    final oEnd = item.lineEnd.clamp(os, oLines.length);
    // Límites del lado DESTINO: buscar el mismo procedimiento en _modifiedText
    final mBounds = _findProcBounds(item.name, _modifiedText);
    final ms = mBounds != null
        ? (mBounds.lineNum - 1).clamp(0, mLines.length)
        : os;
    final mEnd = mBounds != null
        ? mBounds.lineEnd.clamp(ms, mLines.length)
        : item.lineEnd.clamp(ms, mLines.length);
    final origFrag = oLines.sublist(os, oEnd);
    final newMod = [
      ...mLines.sublist(0, ms),
      ...origFrag,
      ...mLines.sublist(mEnd),
    ].join('\n');
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _modifiedText = newMod;
    });
  }

  /// Aplica TODOS los cambios del proc [item] de DESTINO → ORIGEN
  /// independientemente del foco activo.
  void _applyProcAllToSource(
    ({String name, String type, int lineNum, int lineEnd}) item,
  ) {
    final oLines = _currentOriginal.split('\n');
    final mLines = _modifiedText.split('\n');
    // Límites del lado DESTINO: buscar el procedimiento en _modifiedText
    final mBounds = _findProcBounds(item.name, _modifiedText);
    final ms = mBounds != null
        ? (mBounds.lineNum - 1).clamp(0, mLines.length)
        : (item.lineNum - 1).clamp(0, mLines.length);
    final mEnd = mBounds != null
        ? mBounds.lineEnd.clamp(ms, mLines.length)
        : item.lineEnd.clamp(ms, mLines.length);
    // Límites del lado ORIGEN (del item, ya parseados correctamente)
    final os = (item.lineNum - 1).clamp(0, oLines.length);
    final oEnd = item.lineEnd.clamp(os, oLines.length);
    final modFrag = mLines.sublist(ms, mEnd);
    final newOrig = [
      ...oLines.sublist(0, os),
      ...modFrag,
      ...oLines.sublist(oEnd),
    ].join('\n');
    setState(() {
      _history.add((original: _currentOriginal, modified: _modifiedText));
      _currentOriginal = newOrig;
    });
  }

  // ── Sidebar navegación PACKAGE ─────────────────────────────────────────────

  Widget _buildSidebar(bool isDark, ColorScheme cs) {
    final q = _sidebarFilter.trim().toUpperCase();
    final items = q.isEmpty
        ? _procItems
        : _procItems
              .where((e) => e.name.contains(q) || e.type.contains(q))
              .toList();

    // Índice del ítem activo en la lista filtrada (cálculo seguro y limpio)
    int activeInFiltered = -1;
    if (_sidebarActiveIdx >= 0 && _sidebarActiveIdx < _procItems.length) {
      if (q.isEmpty) {
        activeInFiltered = _sidebarActiveIdx;
      } else {
        final activeName = _procItems[_sidebarActiveIdx].name;
        activeInFiltered = items.indexWhere((e) => e.name == activeName);
      }
    }

    return Stack(
      children: [
        // ── Contenido del sidebar ──────────────────────────────────────────
        SizedBox(
          width: _sidebarWidth,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
              border: Border(right: BorderSide(color: cs.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Encabezado
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: 13,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Estructura',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '${_procItems.length}',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                // Filtro
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: TextField(
                    controller: _sidebarFilterCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Filtrar...',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      suffixIcon: _sidebarFilter.isNotEmpty
                          ? GestureDetector(
                              onTap: _sidebarFilterCtrl.clear,
                              child: Icon(
                                Icons.close,
                                size: 13,
                                color: cs.onSurfaceVariant,
                              ),
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                    ),
                  ),
                ),
                // Lista
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'Sin resultados',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _sidebarListCtrl,
                          itemCount: items.length,
                          itemExtent: 38,
                          itemBuilder: (_, i) {
                            final item = items[i];
                            final isActive = i == activeInFiltered;
                            final isProc = item.type == 'PROCEDURE';
                            final badgeColor = isProc
                                ? Colors.blue.shade600
                                : Colors.purple.shade600;

                            return MenuAnchor(
                              menuChildren: _procMenuItems(cs, item),
                              builder: (ctx, controller, child) =>
                                  GestureDetector(
                                    onSecondaryTapDown: (d) => controller.open(
                                      position: d.localPosition,
                                    ),
                                    child: child,
                                  ),
                              child: Material(
                                color: isActive
                                    ? (isDark
                                          ? cs.primary.withValues(alpha: 0.18)
                                          : cs.primary.withValues(alpha: 0.10))
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    if (_focusedProcName != null &&
                                        _focusedProcName != item.name) {
                                      // Cambiar foco al proc tocado
                                      _focusProc(item.name);
                                    }
                                    _diffCtrl.scrollToOrigLine(item.lineNum);
                                  },
                                  child: Container(
                                    decoration: isActive
                                        ? BoxDecoration(
                                            border: Border(
                                              left: BorderSide(
                                                color: cs.primary,
                                                width: 3,
                                              ),
                                            ),
                                          )
                                        : null,
                                    padding: EdgeInsets.fromLTRB(
                                      isActive ? 7 : 10,
                                      0,
                                      8,
                                      0,
                                    ),
                                    child: Row(
                                      children: [
                                        // Badge tipo
                                        Container(
                                          width: 18,
                                          height: 16,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: badgeColor.withValues(
                                              alpha: isActive ? 0.25 : 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                            border: Border.all(
                                              color: badgeColor.withValues(
                                                alpha: 0.6,
                                              ),
                                              width: 0.7,
                                            ),
                                          ),
                                          child: Text(
                                            isProc ? 'P' : 'F',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              color: badgeColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Nombre
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'Consolas',
                                              fontWeight: isActive
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: isActive
                                                  ? cs.primary
                                                  : (isDark
                                                        ? Colors.white70
                                                        : Colors.black87),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Número de línea
                                        Text(
                                          'L${item.lineNum}',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontFamily: 'Consolas',
                                            color: isActive
                                                ? cs.primary.withValues(
                                                    alpha: 0.7,
                                                  )
                                                : cs.onSurfaceVariant
                                                      .withValues(alpha: 0.45),
                                          ),
                                        ),
                                      ],
                                    ), // Row
                                  ), // Container
                                ), // InkWell
                              ), // Material
                            ); // GestureDetector
                          },
                        ),
                ),
              ],
            ),
          ),
        ),

        // ── Handle de redimensionado (borde derecho) ───────────────────────
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 6,
          child: _ResizeHandle(
            onDrag: (dx) => setState(() {
              _sidebarWidth = (_sidebarWidth + dx).clamp(140.0, 480.0);
            }),
            color: cs.primary,
          ),
        ),
      ],
    );
  }

  // ── Panel de errores ───────────────────────────────────────────────────────

  Widget _buildErrorsPanel(bool isDark, ColorScheme cs) {
    final errColor = Colors.red.shade400;
    final warnColor = Colors.orange.shade400;
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFF0F0),
        border: Border(top: BorderSide(color: errColor.withValues(alpha: 0.4))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 13, color: errColor),
                const SizedBox(width: 6),
                Text(
                  '${_compilationErrors.length} error(es) de compilación',
                  style: TextStyle(
                    fontSize: 11,
                    color: errColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _compilationErrors = []),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              itemCount: _compilationErrors.length,
              itemBuilder: (_, i) {
                final e = _compilationErrors[i];
                final isErr = e.attribute == 'ERROR';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        alignment: Alignment.centerRight,
                        child: Text(
                          'L${e.line}',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Consolas',
                            color: isErr ? errColor : warnColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.text,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Consolas',
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Badge de ambiente ──────────────────────────────────────────────────────

  /// Badge de ambiente que además permite cambiarlo desde un menú.
  ///
  /// Se usa tanto para ORIGEN como para DESTINO: al elegir otro ambiente se
  /// recarga la comparación automáticamente si ya había uno cargado.
  ///
  /// Usa [MenuAnchor] (y no `PopupMenuButton`) porque la ventana vive en el
  /// overlay raíz por encima de las rutas del Navigator: un menú abierto como
  /// ruta quedaría *detrás* de la ventana y sería inaccesible.
  Widget _ambBadgeSelector({
    required String amb,
    required Color color,
    required String role,
    required bool isSource,
  }) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final a in AmbienteSelector.ambientes)
          MenuItemButton(
            onPressed: () => _changeAmbiente(a, isSource: isSource),
            leadingIcon: Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                color: AmbienteSelector.colorForAmbiente(a),
                shape: BoxShape.circle,
              ),
            ),
            trailingIcon: a == amb
                ? Icon(Icons.check, size: 14, color: color)
                : null,
            child: Text(
              a,
              style: TextStyle(
                fontSize: 12,
                fontWeight: a == amb ? FontWeight.bold : FontWeight.w500,
                color: AmbienteSelector.colorForAmbiente(a),
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Cambiar ambiente ${role.toLowerCase()}',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            padding: const EdgeInsets.fromLTRB(5, 2, 2, 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$role · $amb',
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 13, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Widget handle de redimensionado ───────────────────────────────────────────

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.onDrag, required this.color});
  final void Function(double dx) onDrag;
  final Color color;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 6,
          color: _hovering
              ? widget.color.withValues(alpha: 0.45)
              : Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _hovering ? 2 : 1,
              color: _hovering
                  ? widget.color
                  : widget.color.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}
