import 'dart:async';
import 'package:mobx/mobx.dart';
import '../models/procedimiento.dart';
import '../models/configuracion_tipo.dart';
import '../models/variable_dinamica.dart';
import '../services/sirweb_service.dart';

part 'procedimientos_provider.g.dart';

enum ViewMode { busqueda, editor }

final procedimientosProvider = ProcedimientosProvider();

// ignore: library_private_types_in_public_api
class ProcedimientosProvider = _ProcedimientosProvider
    with _$ProcedimientosProvider;

abstract class _ProcedimientosProvider with Store {
  final SirwebService _service = SirwebService();

  String _lastBusqueda = '';
  String? _lastConfig;
  String? _lastEstado = '1';
  bool _configuracionesCargadas = false;
  bool _variablesCargadas = false;
  Map<String, String> _configMap = {};

  @observable
  String ambiente = 'Desa';

  @observable
  String cdUsuario = '';

  @observable
  ObservableList<Procedimiento> resultados = ObservableList();

  @observable
  Procedimiento? procedimientoActual;

  @observable
  ViewMode modo = ViewMode.busqueda;

  @observable
  bool cargando = false;

  @observable
  bool cargandoEditor = false;

  @observable
  bool cargandoMas = false;

  @observable
  String? error;

  @observable
  String? mensaje;

  // No observable — solo se lee sincrónicamente después de guardar()
  List<dynamic> lastCompileErrors = [];

  @observable
  int pagina = 1;

  @observable
  bool tieneSiguiente = false;

  @observable
  bool tienePrevio = false;

  @observable
  ObservableList<ConfiguracionTipo> configuraciones = ObservableList();

  @observable
  ObservableList<VariableDinamica> variablesDinamicas = ObservableList();

  @computed
  bool get haResultados => resultados.isNotEmpty;

  String descriptionForConfig(String cdModulo) =>
      _configMap[cdModulo] ?? cdModulo;

  @action
  Future<void> cargarConfiguraciones() async {
    if (_configuracionesCargadas) return;
    try {
      final result = await _service.obtenerConfiguraciones();
      runInAction(() {
        configuraciones = ObservableList.of(result);
        _configMap = {for (final c in result) c.cdModulo: c.deArgumento};
        _configuracionesCargadas = true;
      });
    } catch (_) {}
  }

  @action
  Future<void> cargarVariablesDinamicas() async {
    if (_variablesCargadas) return;
    try {
      final result = await _service.obtenerVariablesDinamicas(
        ambiente: ambiente,
      );
      runInAction(() {
        variablesDinamicas = ObservableList.of(result);
        _variablesCargadas = true;
      });
    } catch (_) {}
  }

  @action
  void setAmbiente(String value) {
    ambiente = value;
    _variablesCargadas = false;
  }

  @action
  void setCdUsuario(String value) => cdUsuario = value;

  @action
  void setProcedimientoActual(Procedimiento? proc) {
    procedimientoActual = proc;
    modo = proc != null ? ViewMode.editor : ViewMode.busqueda;
  }

  @action
  void limpiarMensajes() {
    error = null;
    mensaje = null;
  }

  @action
  void volver() {
    procedimientoActual = null;
    modo = ViewMode.busqueda;
    error = null;
    mensaje = null;
  }

  @action
  Future<void> buscar({
    String busqueda = '',
    String? config,
    String? estado = '1',
  }) async {
    _lastBusqueda = busqueda;
    _lastConfig = config;
    _lastEstado = estado;
    pagina = 1;
    await _ejecutarBusqueda();
  }

  @action
  Future<void> siguientePagina() async {
    if (!tieneSiguiente) return;
    pagina++;
    await _ejecutarBusqueda();
  }

  @action
  Future<void> paginaAnterior() async {
    if (!tienePrevio) return;
    pagina--;
    await _ejecutarBusqueda();
  }

  @action
  Future<void> cargarMas() async {
    if (!tieneSiguiente || cargandoMas || cargando) return;
    cargandoMas = true;
    final nextPage = pagina + 1;
    error = null;
    try {
      final resultado = await _service.listarProcedimientos(
        busqueda: _lastBusqueda,
        configuracion: _lastConfig,
        estado: _lastEstado,
        ambiente: ambiente,
        pagina: nextPage,
      );
      runInAction(() {
        pagina = nextPage;
        resultados = ObservableList.of([...resultados, ...resultado.items]);
        tieneSiguiente = resultado.tieneSiguiente;
        tienePrevio = resultado.tienePrevio;
        cargandoMas = false;
      });
    } catch (e) {
      runInAction(() {
        error = e.toString().replaceFirst('Exception: ', '');
        cargandoMas = false;
      });
    }
  }

  Future<void> _ejecutarBusqueda() async {
    runInAction(() {
      cargando = true;
      error = null;
      mensaje = null;
    });
    try {
      final resultado = await _service.listarProcedimientos(
        busqueda: _lastBusqueda,
        configuracion: _lastConfig,
        estado: _lastEstado,
        ambiente: ambiente,
        pagina: pagina,
      );
      runInAction(() {
        resultados = ObservableList.of(resultado.items);
        tieneSiguiente = resultado.tieneSiguiente;
        tienePrevio = resultado.tienePrevio;
        cargando = false;
      });
    } catch (e) {
      runInAction(() {
        error = e.toString().replaceFirst('Exception: ', '');
        cargando = false;
      });
    }
  }

  @action
  Future<void> seleccionar(Procedimiento proc) async {
    modo = ViewMode.editor;
    cargandoEditor = true;
    error = null;
    mensaje = null;
    procedimientoActual = proc;
    unawaited(cargarVariablesDinamicas());
    try {
      final completo = await _service.obtenerProcedimiento(
        proc.cdProcedimiento,
        ambiente: ambiente,
      );
      runInAction(() {
        procedimientoActual = completo;
        cargandoEditor = false;
      });
    } catch (e) {
      runInAction(() {
        error = e.toString().replaceFirst('Exception: ', '');
        procedimientoActual = null;
        cargandoEditor = false;
      });
    }
  }

  @action
  Future<bool> guardar({
    required String deTexto,
    String? inConfiguracion,
  }) async {
    if (procedimientoActual == null) return false;
    if (cdUsuario.trim().isEmpty) {
      error = 'Ingresa tu usuario antes de guardar.';
      return false;
    }
    cargando = true;
    error = null;
    mensaje = null;
    try {
      final compileErrors = await _service.actualizarProcedimiento(
        cdProcedimiento: procedimientoActual!.cdProcedimiento,
        deTexto: deTexto,
        cdUsuario: cdUsuario,
        inConfiguracion:
            inConfiguracion ?? procedimientoActual!.inConfiguracion,
        ambiente: ambiente,
      );
      lastCompileErrors = compileErrors;
      if (compileErrors.isNotEmpty) {
        // Compiló pero con errores — el procedimiento queda inválido
        runInAction(() {
          error = '${compileErrors.length} error(es) de compilación Oracle';
          cargando = false;
        });
        return false;
      }
      runInAction(() {
        procedimientoActual = procedimientoActual!.copyWith(
          deTexto: deTexto,
          inConfiguracion:
              inConfiguracion ?? procedimientoActual!.inConfiguracion,
          version: procedimientoActual!.version + 1,
        );
        mensaje =
            'Guardado correctamente. Version ${procedimientoActual!.version}';
        cargando = false;
      });
      return true;
    } catch (e) {
      lastCompileErrors = [];
      runInAction(() {
        error = e.toString().replaceFirst('Exception: ', '');
        cargando = false;
      });
      return false;
    }
  }

  Future<bool> activar() => _toggleEstado(activar: true);
  Future<bool> desactivar() => _toggleEstado(activar: false);

  Future<bool> compilar({required String deTexto}) async {
    if (procedimientoActual == null) return false;
    if (cdUsuario.trim().isEmpty) {
      error = 'Ingresa tu usuario antes de compilar.';
      return false;
    }
    cargando = true;
    error = null;
    mensaje = null;
    try {
      final compileErrors = await _service.compilarProcedimiento(
        cdProcedimiento: procedimientoActual!.cdProcedimiento,
        deTexto: deTexto,
        cdUsuario: cdUsuario,
        inConfiguracion: procedimientoActual!.inConfiguracion,
        ambiente: ambiente,
      );
      lastCompileErrors = compileErrors;
      if (compileErrors.isNotEmpty) {
        runInAction(() {
          error = '${compileErrors.length} error(es) de compilación Oracle';
          cargando = false;
        });
        return false;
      }
      // Compiló exitosamente → el servidor guardó el procedimiento; sincronizar versión
      runInAction(() {
        procedimientoActual = procedimientoActual!.copyWith(
          deTexto: deTexto,
          version: procedimientoActual!.version + 1,
        );
        mensaje = 'Compilado correctamente. Versión ${procedimientoActual!.version}';
        cargando = false;
      });
      return true;
    } catch (e) {
      lastCompileErrors = [];
      runInAction(() {
        error = e.toString().replaceFirst('Exception: ', '');
        cargando = false;
      });
      return false;
    }
  }

  @action
  Future<bool> _toggleEstado({required bool activar}) async {
    if (procedimientoActual == null) return false;
    if (cdUsuario.trim().isEmpty) {
      error = 'Ingresa tu usuario antes de continuar.';
      return false;
    }
    cargando = true;
    error = null;
    mensaje = null;
    try {
      if (activar) {
        await _service.activarProcedimiento(
          cdProcedimiento: procedimientoActual!.cdProcedimiento,
          cdUsuario: cdUsuario,
          ambiente: ambiente,
        );
      } else {
        await _service.desactivarProcedimiento(
          cdProcedimiento: procedimientoActual!.cdProcedimiento,
          cdUsuario: cdUsuario,
          ambiente: ambiente,
        );
      }
      runInAction(() {
        procedimientoActual = procedimientoActual!.copyWith(
          stProcedimiento: activar ? '1' : '0',
        );
        mensaje = activar
            ? 'Procedimiento activado.'
            : 'Procedimiento desactivado.';
        cargando = false;
      });
      return true;
    } catch (e) {
      runInAction(() {
        error = e.toString().replaceFirst('Exception: ', '');
        cargando = false;
      });
      return false;
    }
  }

  @action
  Future<bool> crear({
    required String cdProcedimiento,
    required String deTexto,
    required String inConfiguracion,
    required String cdUsuario,
  }) async {
    cargando = true;
    error = null;
    mensaje = null;
    try {
      await _service.crearProcedimiento(
        cdProcedimiento: cdProcedimiento,
        deTexto: deTexto,
        inConfiguracion: inConfiguracion,
        cdUsuario: cdUsuario,
        ambiente: ambiente,
      );
      runInAction(() {
        mensaje = 'Procedimiento "$cdProcedimiento" creado correctamente.';
        cargando = false;
      });
      return true;
    } catch (e) {
      runInAction(() {
        error = e.toString().replaceFirst('Exception: ', '');
        cargando = false;
      });
      return false;
    }
  }
}
