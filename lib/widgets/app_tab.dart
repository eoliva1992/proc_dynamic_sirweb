import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import 'search_tab_state.dart';

class AppTab {
  static int _counter = 0;
  final int tabId;
  final SearchTabState searchState;
  Procedimiento? procedimiento;
  bool _loading = false;
  bool get loading => _loading;
  set loading(bool v) {
    if (v == _loading) return;
    _loading = v;
  }

  String ambiente;
  bool isDirty = false;
  String? currentEditorCode;

  /// Ruta del archivo en disco cuando este tab proviene de "Abrir archivo".
  /// Si no es `null`, guardar escribe al disco en vez de persistir en BD.
  String? localFilePath;

  /// Cuando está seteado, este tab muestra el visor de código fuente Oracle
  /// en lugar del editor de procedimientos dinámicos o la vista de búsqueda.
  ({
    String name,
    String objectType,
    String ambiente,
    int? initialLine,
    String? initialSearchTerm,
  })?
  sourceViewer;

  /// Cuando es `true`, este tab muestra el Ejecutor SQL/PL-SQL.
  bool isSqlExecutor = false;

  AppTab({String? ambiente})
    : tabId = _counter++,
      searchState = SearchTabState(),
      ambiente = ambiente ?? procedimientosProvider.ambiente;

  /// Tab en modo búsqueda (sin procedimiento ni visor de fuente cargado).
  bool get inSearchMode =>
      procedimiento == null &&
      !loading &&
      sourceViewer == null &&
      !isSqlExecutor;

  /// Tab en modo visor de código fuente Oracle.
  bool get inSourceViewMode => sourceViewer != null;

  /// Tab en modo Ejecutor SQL/PL-SQL.
  bool get inSqlExecutorMode => isSqlExecutor;
}
