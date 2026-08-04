// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'procedimientos_provider.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ProcedimientosProvider on _ProcedimientosProvider, Store {
  Computed<bool>? _$haResultadosComputed;

  @override
  bool get haResultados => (_$haResultadosComputed ??= Computed<bool>(
    () => super.haResultados,
    name: '_ProcedimientosProvider.haResultados',
  )).value;

  late final _$ambienteAtom = Atom(
    name: '_ProcedimientosProvider.ambiente',
    context: context,
  );

  @override
  String get ambiente {
    _$ambienteAtom.reportRead();
    return super.ambiente;
  }

  @override
  set ambiente(String value) {
    _$ambienteAtom.reportWrite(value, super.ambiente, () {
      super.ambiente = value;
    });
  }

  late final _$cdUsuarioAtom = Atom(
    name: '_ProcedimientosProvider.cdUsuario',
    context: context,
  );

  @override
  String get cdUsuario {
    _$cdUsuarioAtom.reportRead();
    return super.cdUsuario;
  }

  @override
  set cdUsuario(String value) {
    _$cdUsuarioAtom.reportWrite(value, super.cdUsuario, () {
      super.cdUsuario = value;
    });
  }

  late final _$resultadosAtom = Atom(
    name: '_ProcedimientosProvider.resultados',
    context: context,
  );

  @override
  ObservableList<Procedimiento> get resultados {
    _$resultadosAtom.reportRead();
    return super.resultados;
  }

  @override
  set resultados(ObservableList<Procedimiento> value) {
    _$resultadosAtom.reportWrite(value, super.resultados, () {
      super.resultados = value;
    });
  }

  late final _$procedimientoActualAtom = Atom(
    name: '_ProcedimientosProvider.procedimientoActual',
    context: context,
  );

  @override
  Procedimiento? get procedimientoActual {
    _$procedimientoActualAtom.reportRead();
    return super.procedimientoActual;
  }

  @override
  set procedimientoActual(Procedimiento? value) {
    _$procedimientoActualAtom.reportWrite(value, super.procedimientoActual, () {
      super.procedimientoActual = value;
    });
  }

  late final _$modoAtom = Atom(
    name: '_ProcedimientosProvider.modo',
    context: context,
  );

  @override
  ViewMode get modo {
    _$modoAtom.reportRead();
    return super.modo;
  }

  @override
  set modo(ViewMode value) {
    _$modoAtom.reportWrite(value, super.modo, () {
      super.modo = value;
    });
  }

  late final _$cargandoAtom = Atom(
    name: '_ProcedimientosProvider.cargando',
    context: context,
  );

  @override
  bool get cargando {
    _$cargandoAtom.reportRead();
    return super.cargando;
  }

  @override
  set cargando(bool value) {
    _$cargandoAtom.reportWrite(value, super.cargando, () {
      super.cargando = value;
    });
  }

  late final _$cargandoEditorAtom = Atom(
    name: '_ProcedimientosProvider.cargandoEditor',
    context: context,
  );

  @override
  bool get cargandoEditor {
    _$cargandoEditorAtom.reportRead();
    return super.cargandoEditor;
  }

  @override
  set cargandoEditor(bool value) {
    _$cargandoEditorAtom.reportWrite(value, super.cargandoEditor, () {
      super.cargandoEditor = value;
    });
  }

  late final _$cargandoMasAtom = Atom(
    name: '_ProcedimientosProvider.cargandoMas',
    context: context,
  );

  @override
  bool get cargandoMas {
    _$cargandoMasAtom.reportRead();
    return super.cargandoMas;
  }

  @override
  set cargandoMas(bool value) {
    _$cargandoMasAtom.reportWrite(value, super.cargandoMas, () {
      super.cargandoMas = value;
    });
  }

  late final _$errorAtom = Atom(
    name: '_ProcedimientosProvider.error',
    context: context,
  );

  @override
  String? get error {
    _$errorAtom.reportRead();
    return super.error;
  }

  @override
  set error(String? value) {
    _$errorAtom.reportWrite(value, super.error, () {
      super.error = value;
    });
  }

  late final _$mensajeAtom = Atom(
    name: '_ProcedimientosProvider.mensaje',
    context: context,
  );

  @override
  String? get mensaje {
    _$mensajeAtom.reportRead();
    return super.mensaje;
  }

  @override
  set mensaje(String? value) {
    _$mensajeAtom.reportWrite(value, super.mensaje, () {
      super.mensaje = value;
    });
  }

  late final _$paginaAtom = Atom(
    name: '_ProcedimientosProvider.pagina',
    context: context,
  );

  @override
  int get pagina {
    _$paginaAtom.reportRead();
    return super.pagina;
  }

  @override
  set pagina(int value) {
    _$paginaAtom.reportWrite(value, super.pagina, () {
      super.pagina = value;
    });
  }

  late final _$tieneSiguienteAtom = Atom(
    name: '_ProcedimientosProvider.tieneSiguiente',
    context: context,
  );

  @override
  bool get tieneSiguiente {
    _$tieneSiguienteAtom.reportRead();
    return super.tieneSiguiente;
  }

  @override
  set tieneSiguiente(bool value) {
    _$tieneSiguienteAtom.reportWrite(value, super.tieneSiguiente, () {
      super.tieneSiguiente = value;
    });
  }

  late final _$tienePrevioAtom = Atom(
    name: '_ProcedimientosProvider.tienePrevio',
    context: context,
  );

  @override
  bool get tienePrevio {
    _$tienePrevioAtom.reportRead();
    return super.tienePrevio;
  }

  @override
  set tienePrevio(bool value) {
    _$tienePrevioAtom.reportWrite(value, super.tienePrevio, () {
      super.tienePrevio = value;
    });
  }

  late final _$configuracionesAtom = Atom(
    name: '_ProcedimientosProvider.configuraciones',
    context: context,
  );

  @override
  ObservableList<ConfiguracionTipo> get configuraciones {
    _$configuracionesAtom.reportRead();
    return super.configuraciones;
  }

  @override
  set configuraciones(ObservableList<ConfiguracionTipo> value) {
    _$configuracionesAtom.reportWrite(value, super.configuraciones, () {
      super.configuraciones = value;
    });
  }

  late final _$variablesDinamicasAtom = Atom(
    name: '_ProcedimientosProvider.variablesDinamicas',
    context: context,
  );

  @override
  ObservableList<VariableDinamica> get variablesDinamicas {
    _$variablesDinamicasAtom.reportRead();
    return super.variablesDinamicas;
  }

  @override
  set variablesDinamicas(ObservableList<VariableDinamica> value) {
    _$variablesDinamicasAtom.reportWrite(value, super.variablesDinamicas, () {
      super.variablesDinamicas = value;
    });
  }

  late final _$cargarConfiguracionesAsyncAction = AsyncAction(
    '_ProcedimientosProvider.cargarConfiguraciones',
    context: context,
  );

  @override
  Future<void> cargarConfiguraciones() {
    return _$cargarConfiguracionesAsyncAction.run(
      () => super.cargarConfiguraciones(),
    );
  }

  late final _$cargarVariablesDinamicasAsyncAction = AsyncAction(
    '_ProcedimientosProvider.cargarVariablesDinamicas',
    context: context,
  );

  @override
  Future<void> cargarVariablesDinamicas() {
    return _$cargarVariablesDinamicasAsyncAction.run(
      () => super.cargarVariablesDinamicas(),
    );
  }

  late final _$buscarAsyncAction = AsyncAction(
    '_ProcedimientosProvider.buscar',
    context: context,
  );

  @override
  Future<void> buscar({
    String busqueda = '',
    String? config,
    String? estado = '1',
  }) {
    return _$buscarAsyncAction.run(
      () => super.buscar(busqueda: busqueda, config: config, estado: estado),
    );
  }

  late final _$siguientePaginaAsyncAction = AsyncAction(
    '_ProcedimientosProvider.siguientePagina',
    context: context,
  );

  @override
  Future<void> siguientePagina() {
    return _$siguientePaginaAsyncAction.run(() => super.siguientePagina());
  }

  late final _$paginaAnteriorAsyncAction = AsyncAction(
    '_ProcedimientosProvider.paginaAnterior',
    context: context,
  );

  @override
  Future<void> paginaAnterior() {
    return _$paginaAnteriorAsyncAction.run(() => super.paginaAnterior());
  }

  late final _$cargarMasAsyncAction = AsyncAction(
    '_ProcedimientosProvider.cargarMas',
    context: context,
  );

  @override
  Future<void> cargarMas() {
    return _$cargarMasAsyncAction.run(() => super.cargarMas());
  }

  late final _$seleccionarAsyncAction = AsyncAction(
    '_ProcedimientosProvider.seleccionar',
    context: context,
  );

  @override
  Future<void> seleccionar(Procedimiento proc) {
    return _$seleccionarAsyncAction.run(() => super.seleccionar(proc));
  }

  late final _$guardarAsyncAction = AsyncAction(
    '_ProcedimientosProvider.guardar',
    context: context,
  );

  @override
  Future<bool> guardar({required String deTexto, String? inConfiguracion}) {
    return _$guardarAsyncAction.run(
      () => super.guardar(deTexto: deTexto, inConfiguracion: inConfiguracion),
    );
  }

  late final _$_toggleEstadoAsyncAction = AsyncAction(
    '_ProcedimientosProvider._toggleEstado',
    context: context,
  );

  @override
  Future<bool> _toggleEstado({required bool activar}) {
    return _$_toggleEstadoAsyncAction.run(
      () => super._toggleEstado(activar: activar),
    );
  }

  late final _$crearAsyncAction = AsyncAction(
    '_ProcedimientosProvider.crear',
    context: context,
  );

  @override
  Future<bool> crear({
    required String cdProcedimiento,
    required String deTexto,
    required String inConfiguracion,
    required String cdUsuario,
  }) {
    return _$crearAsyncAction.run(
      () => super.crear(
        cdProcedimiento: cdProcedimiento,
        deTexto: deTexto,
        inConfiguracion: inConfiguracion,
        cdUsuario: cdUsuario,
      ),
    );
  }

  late final _$_ProcedimientosProviderActionController = ActionController(
    name: '_ProcedimientosProvider',
    context: context,
  );

  @override
  void setAmbiente(String value) {
    final _$actionInfo = _$_ProcedimientosProviderActionController.startAction(
      name: '_ProcedimientosProvider.setAmbiente',
    );
    try {
      return super.setAmbiente(value);
    } finally {
      _$_ProcedimientosProviderActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setCdUsuario(String value) {
    final _$actionInfo = _$_ProcedimientosProviderActionController.startAction(
      name: '_ProcedimientosProvider.setCdUsuario',
    );
    try {
      return super.setCdUsuario(value);
    } finally {
      _$_ProcedimientosProviderActionController.endAction(_$actionInfo);
    }
  }

  @override
  void limpiarMensajes() {
    final _$actionInfo = _$_ProcedimientosProviderActionController.startAction(
      name: '_ProcedimientosProvider.limpiarMensajes',
    );
    try {
      return super.limpiarMensajes();
    } finally {
      _$_ProcedimientosProviderActionController.endAction(_$actionInfo);
    }
  }

  @override
  void volver() {
    final _$actionInfo = _$_ProcedimientosProviderActionController.startAction(
      name: '_ProcedimientosProvider.volver',
    );
    try {
      return super.volver();
    } finally {
      _$_ProcedimientosProviderActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
ambiente: ${ambiente},
cdUsuario: ${cdUsuario},
resultados: ${resultados},
procedimientoActual: ${procedimientoActual},
modo: ${modo},
cargando: ${cargando},
cargandoEditor: ${cargandoEditor},
cargandoMas: ${cargandoMas},
error: ${error},
mensaje: ${mensaje},
pagina: ${pagina},
tieneSiguiente: ${tieneSiguiente},
tienePrevio: ${tienePrevio},
configuraciones: ${configuraciones},
variablesDinamicas: ${variablesDinamicas},
haResultados: ${haResultados}
    ''';
  }
}
