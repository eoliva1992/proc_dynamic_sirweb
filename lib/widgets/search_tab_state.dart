import 'package:flutter/foundation.dart';
import '../models/procedimiento.dart';
import '../services/sirweb_service.dart';

class SearchTabState extends ChangeNotifier {
  final SirwebService _service = SirwebService();

  String searchText = '';
  String? config;
  String? estado = '1';

  List<Procedimiento> resultados = const [];
  bool cargando = false;
  bool cargandoMas = false;
  String? error;
  int _pagina = 1;
  bool tieneSiguiente = false;

  Future<void> buscar({
    required String busqueda,
    String? cfg,
    String? est,
    required String ambiente,
  }) async {
    searchText = busqueda;
    config = cfg;
    estado = est;
    _pagina = 1;
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final r = await _service.listarProcedimientos(
        busqueda: busqueda,
        configuracion: cfg,
        estado: est,
        ambiente: ambiente,
        pagina: 1,
      );
      resultados = r.items;
      tieneSiguiente = r.tieneSiguiente;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> cargarMas({required String ambiente}) async {
    if (!tieneSiguiente || cargandoMas || cargando) return;
    _pagina++;
    cargandoMas = true;
    notifyListeners();
    try {
      final r = await _service.listarProcedimientos(
        busqueda: searchText,
        configuracion: config,
        estado: estado,
        ambiente: ambiente,
        pagina: _pagina,
      );
      resultados = [...resultados, ...r.items];
      tieneSiguiente = r.tieneSiguiente;
    } catch (e) {
      _pagina--;
      error = e.toString().replaceFirst('Exception: ', '');
    }
    cargandoMas = false;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
