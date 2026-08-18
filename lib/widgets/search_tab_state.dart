import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/procedimiento.dart';
import '../services/favorites_service.dart';
import '../services/sirweb_service.dart';

enum SortBy { fechaDesc, fechaAsc, nombre, version }

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
  bool hasSearched = false;
  SortBy sortBy = SortBy.fechaDesc;

  // Memoization fields — invalidated when inputs change
  List<Procedimiento>? _cachedSorted;
  List<Procedimiento>? _sortedInput;
  SortBy? _sortedBy;
  List<Procedimiento>? _cachedFiltered;
  List<Procedimiento>? _filteredInput;
  bool? _filteredShowFavorites;

  List<Procedimiento> get resultadosOrdenados {
    if (!identical(_sortedInput, resultados) || _sortedBy != sortBy) {
      _sortedInput = resultados;
      _sortedBy = sortBy;
      _filteredInput = null; // invalidate downstream
      final list = [...resultados];
      switch (sortBy) {
        case SortBy.fechaAsc:
          list.sort(
            (a, b) =>
                (a.feModificacion ?? '').compareTo(b.feModificacion ?? ''),
          );
        case SortBy.fechaDesc:
          list.sort(
            (a, b) =>
                (b.feModificacion ?? '').compareTo(a.feModificacion ?? ''),
          );
        case SortBy.nombre:
          list.sort((a, b) => a.cdProcedimiento.compareTo(b.cdProcedimiento));
        case SortBy.version:
          list.sort((a, b) => b.version.compareTo(a.version));
      }
      _cachedSorted = list;
    }
    return _cachedSorted!;
  }

  List<Procedimiento> get resultadosFiltrados {
    final sorted = resultadosOrdenados;
    if (!identical(_filteredInput, sorted) ||
        _filteredShowFavorites != showFavoritesOnly) {
      _filteredInput = sorted;
      _filteredShowFavorites = showFavoritesOnly;
      _cachedFiltered = showFavoritesOnly
          ? sorted
                .where((p) => FavoritesService.isFavorite(p.cdProcedimiento))
                .toList()
          : sorted;
    }
    return _cachedFiltered!;
  }

  void setSortBy(SortBy s) {
    sortBy = s;
    notifyListeners();
  }

  void updateResult(Procedimiento updated) {
    final idx = resultados.indexWhere(
      (p) => p.cdProcedimiento == updated.cdProcedimiento,
    );
    if (idx == -1) return;
    resultados = [
      for (var i = 0; i < resultados.length; i++)
        if (i == idx) updated else resultados[i],
    ];
    notifyListeners();
  }

  // Search history (last 8 non-empty queries, persisted globally)
  List<String> history = [];
  bool showFavoritesOnly = false;
  bool cargandoFavoritos = false;
  String? _lastAmbiente;

  static const _historyKey = 'search_history';

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    history = prefs.getStringList(_historyKey) ?? [];
    notifyListeners();
  }

  void addToHistory(String query) {
    if (query.trim().isEmpty) return;
    history = [query, ...history.where((h) => h != query)].take(8).toList();
    notifyListeners();
    SharedPreferences.getInstance().then(
      (p) => p.setStringList(_historyKey, history),
    );
  }

  void removeFromHistory(String query) {
    history = history.where((h) => h != query).toList();
    notifyListeners();
    SharedPreferences.getInstance().then(
      (p) => p.setStringList(_historyKey, history),
    );
  }

  void toggleFavorites() {
    showFavoritesOnly = !showFavoritesOnly;
    notifyListeners();
    if (showFavoritesOnly) _loadMissingFavorites();
  }

  Future<void> _loadMissingFavorites() async {
    final favIds = FavoritesService.current;
    if (favIds.isEmpty) return;
    final inResults = {for (final p in resultados) p.cdProcedimiento};
    final missing = favIds.difference(inResults);
    if (missing.isEmpty) return;

    cargandoFavoritos = true;
    notifyListeners();
    final results = await Future.wait([
      for (final id in missing)
        _service
            .obtenerProcedimiento(id, ambiente: _lastAmbiente)
            .then<Procedimiento?>((p) => p)
            .catchError((_) => null),
    ]);
    final loaded = results.whereType<Procedimiento>().toList();
    if (loaded.isNotEmpty) resultados = [...resultados, ...loaded];
    cargandoFavoritos = false;
    notifyListeners();
  }

  Future<void> buscar({
    required String busqueda,
    String? cfg,
    String? est,
    required String ambiente,
  }) async {
    searchText = busqueda;
    config = cfg;
    estado = est;
    _lastAmbiente = ambiente;
    _pagina = 1;
    cargando = true;
    hasSearched = true;
    error = null;
    notifyListeners();
    addToHistory(busqueda);
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
    _lastAmbiente = ambiente;
    cargandoMas = true;
    final nextPage = _pagina + 1;
    notifyListeners();
    try {
      final r = await _service.listarProcedimientos(
        busqueda: searchText,
        configuracion: config,
        estado: estado,
        ambiente: ambiente,
        pagina: nextPage,
      );
      _pagina = nextPage;
      resultados = [...resultados, ...r.items];
      tieneSiguiente = r.tieneSiguiente;
    } catch (e) {
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
