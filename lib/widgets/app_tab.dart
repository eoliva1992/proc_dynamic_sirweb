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

  AppTab({String? ambiente})
    : tabId = _counter++,
      searchState = SearchTabState(),
      ambiente = ambiente ?? procedimientosProvider.ambiente;

  bool get inSearchMode => procedimiento == null && !loading;
}
