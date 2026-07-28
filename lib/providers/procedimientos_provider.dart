import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/procedimiento.dart';
import '../models/configuracion_tipo.dart';
import '../models/variable_dinamica.dart';
import '../services/sirweb_service.dart';

enum ViewMode { busqueda, editor }

class ProcedimientosProvider extends ChangeNotifier {
  final SirwebService _service = SirwebService();

  String _ambiente = 'Desa';
  String _cdUsuario = '';

  List<Procedimiento> _resultados = [];
  Procedimiento? _procedimientoActual;
  ViewMode _modo = ViewMode.busqueda;

  bool _cargando = false;
  bool _cargandoEditor = false;
  bool _cargandoMas = false;
  String? _error;
  String? _mensaje;

  // Pagination
  int _pagina = 1;
  bool _tieneSiguiente = false;
  bool _tienePrevio = false;

  // Last search params
  String _lastBusqueda = '';
  String? _lastConfig;
  String? _lastEstado = '1';

  // Configuraciones reales del sistema
  List<ConfiguracionTipo> _configuraciones = [];
  bool _configuracionesCargadas = false;

  // Variables dinámicas para autocomplete
  List<VariableDinamica> _variablesDinamicas = [];
  bool _variablesCargadas = false;

  String get ambiente => _ambiente;
  String get cdUsuario => _cdUsuario;
  List<Procedimiento> get resultados => _resultados;
  Procedimiento? get procedimientoActual => _procedimientoActual;
  ViewMode get modo => _modo;
  bool get cargando => _cargando;
  bool get cargandoEditor => _cargandoEditor;
  bool get cargandoMas => _cargandoMas;
  String? get error => _error;
  String? get mensaje => _mensaje;
  bool get tieneSiguiente => _tieneSiguiente;
  bool get tienePrevio => _tienePrevio;
  int get pagina => _pagina;
  bool get haResultados => _resultados.isNotEmpty;
  List<ConfiguracionTipo> get configuraciones => _configuraciones;
  List<VariableDinamica> get variablesDinamicas => _variablesDinamicas;

  String descriptionForConfig(String cdModulo) {
    final match = _configuraciones
        .where((c) => c.cdModulo == cdModulo)
        .firstOrNull;
    return match?.deArgumento ?? cdModulo;
  }

  Future<void> cargarConfiguraciones() async {
    if (_configuracionesCargadas) return;
    try {
      _configuraciones = await _service.obtenerConfiguraciones();
      _configuracionesCargadas = true;
      notifyListeners();
    } catch (_) {
      // Si falla, se usan los valores hardcoded en los widgets
    }
  }

  Future<void> cargarVariablesDinamicas() async {
    if (_variablesCargadas) return;
    try {
      _variablesDinamicas = await _service.obtenerVariablesDinamicas(
        ambiente: _ambiente,
      );
      _variablesCargadas = true;
      notifyListeners();
    } catch (_) {
      // Silently fail — autocomplete seguirá sin variables
    }
  }

  void setAmbiente(String value) {
    _ambiente = value;
    _variablesCargadas = false; // reset on ambiente change
    notifyListeners();
  }

  void setCdUsuario(String value) {
    _cdUsuario = value;
    notifyListeners();
  }

  void limpiarMensajes() {
    _error = null;
    _mensaje = null;
    notifyListeners();
  }

  void volver() {
    _procedimientoActual = null;
    _modo = ViewMode.busqueda;
    _error = null;
    _mensaje = null;
    notifyListeners();
  }

  Future<void> buscar({
    String busqueda = '',
    String? config,
    String? estado = '1',
  }) async {
    _lastBusqueda = busqueda;
    _lastConfig = config;
    _lastEstado = estado;
    _pagina = 1;
    await _ejecutarBusqueda();
  }

  Future<void> siguientePagina() async {
    if (!_tieneSiguiente) return;
    _pagina++;
    await _ejecutarBusqueda();
  }

  Future<void> paginaAnterior() async {
    if (!_tienePrevio) return;
    _pagina--;
    await _ejecutarBusqueda();
  }

  Future<void> cargarMas() async {
    if (!_tieneSiguiente || _cargandoMas || _cargando) return;
    _pagina++;
    _cargandoMas = true;
    _error = null;
    notifyListeners();

    try {
      final resultado = await _service.listarProcedimientos(
        busqueda: _lastBusqueda,
        configuracion: _lastConfig,
        estado: _lastEstado,
        ambiente: _ambiente,
        pagina: _pagina,
      );
      _resultados = [..._resultados, ...resultado.items];
      _tieneSiguiente = resultado.tieneSiguiente;
      _tienePrevio = resultado.tienePrevio;
    } catch (e) {
      _pagina--;
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _cargandoMas = false;
      notifyListeners();
    }
  }

  Future<void> _ejecutarBusqueda() async {
    _cargando = true;
    _error = null;
    _mensaje = null;
    notifyListeners();

    try {
      final resultado = await _service.listarProcedimientos(
        busqueda: _lastBusqueda,
        configuracion: _lastConfig,
        estado: _lastEstado,
        ambiente: _ambiente,
        pagina: _pagina,
      );
      _resultados = resultado.items;
      _tieneSiguiente = resultado.tieneSiguiente;
      _tienePrevio = resultado.tienePrevio;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  Future<void> seleccionar(Procedimiento proc) async {
    _modo = ViewMode.editor;
    _cargandoEditor = true;
    _error = null;
    _mensaje = null;
    _procedimientoActual = proc;
    notifyListeners();

    unawaited(cargarVariablesDinamicas()); // carga en background para autocomplete

    try {
      final completo = await _service.obtenerProcedimiento(
        proc.cdProcedimiento,
        ambiente: _ambiente,
      );
      _procedimientoActual = completo;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _cargandoEditor = false;
      notifyListeners();
    }
  }

  Future<bool> guardar({
    required String deTexto,
    String? inConfiguracion,
  }) async {
    if (_procedimientoActual == null) return false;
    if (_cdUsuario.trim().isEmpty) {
      _error = 'Ingresa tu usuario antes de guardar.';
      notifyListeners();
      return false;
    }

    _cargando = true;
    _error = null;
    _mensaje = null;
    notifyListeners();

    try {
      await _service.actualizarProcedimiento(
        cdProcedimiento: _procedimientoActual!.cdProcedimiento,
        deTexto: deTexto,
        cdUsuario: _cdUsuario,
        inConfiguracion: inConfiguracion,
        ambiente: _ambiente,
      );
      _procedimientoActual = _procedimientoActual!.copyWith(
        deTexto: deTexto,
        inConfiguracion: inConfiguracion ?? _procedimientoActual!.inConfiguracion,
        version: _procedimientoActual!.version + 1,
      );
      _mensaje = 'Guardado correctamente. Versión ${_procedimientoActual!.version}';
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  Future<bool> activar() async {
    return _toggleEstado(activar: true);
  }

  Future<bool> desactivar() async {
    return _toggleEstado(activar: false);
  }

  Future<bool> _toggleEstado({required bool activar}) async {
    if (_procedimientoActual == null) return false;
    if (_cdUsuario.trim().isEmpty) {
      _error = 'Ingresa tu usuario antes de continuar.';
      notifyListeners();
      return false;
    }

    _cargando = true;
    _error = null;
    _mensaje = null;
    notifyListeners();

    try {
      if (activar) {
        await _service.activarProcedimiento(
          cdProcedimiento: _procedimientoActual!.cdProcedimiento,
          cdUsuario: _cdUsuario,
          ambiente: _ambiente,
        );
      } else {
        await _service.desactivarProcedimiento(
          cdProcedimiento: _procedimientoActual!.cdProcedimiento,
          cdUsuario: _cdUsuario,
          ambiente: _ambiente,
        );
      }
      _procedimientoActual = _procedimientoActual!.copyWith(
        stProcedimiento: activar ? '1' : '0',
      );
      _mensaje = activar ? 'Procedimiento activado.' : 'Procedimiento desactivado.';
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  Future<bool> crear({
    required String cdProcedimiento,
    required String deTexto,
    required String inConfiguracion,
    required String cdUsuario,
  }) async {
    _cargando = true;
    _error = null;
    _mensaje = null;
    notifyListeners();

    try {
      await _service.crearProcedimiento(
        cdProcedimiento: cdProcedimiento,
        deTexto: deTexto,
        inConfiguracion: inConfiguracion,
        cdUsuario: cdUsuario,
        ambiente: _ambiente,
      );
      _mensaje = 'Procedimiento "$cdProcedimiento" creado correctamente.';
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }
}
