import 'package:flutter/widgets.dart';

/// Firma de la función que abre una fuente Oracle como tab.
typedef OpenSourceTab =
    void Function({
      required String name,
      required String objectType,
      required String ambiente,
    });

/// InheritedWidget que provee una función para abrir una fuente Oracle como
/// tab en la pantalla principal, en lugar de como ventana OS separada.
///
/// Uso:
///   SourceTabController.maybeOf(context)?.openTab(name: ..., objectType: ..., ambiente: ...);
///
/// Si el contexto no tiene un [SourceTabController] en el árbol (p.ej. desde
/// la sub-ventana del visor de fuente), el método retorna null y el caller
/// puede hacer fallback a ventana nativa u overlay.
class SourceTabController extends InheritedWidget {
  final OpenSourceTab openTab;

  const SourceTabController({
    super.key,
    required this.openTab,
    required super.child,
  });

  static OpenSourceTab? _global;

  /// Registra el handler global (lo hace la pantalla principal al montarse).
  /// Necesario porque los diálogos abiertos con `useRootNavigator: true` se
  /// montan como rutas hermanas de la pantalla principal, por lo que su
  /// contexto NO es descendiente de este InheritedWidget.
  static void registerGlobal(OpenSourceTab openTab) => _global = openTab;

  /// Quita el handler global si sigue siendo el registrado.
  static void unregisterGlobal(OpenSourceTab openTab) {
    if (_global == openTab) _global = null;
  }

  /// Retorna el [SourceTabController] más cercano en el árbol, o null si no hay.
  static SourceTabController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SourceTabController>();

  /// Resuelve la función para abrir un tab: primero el handler global (seguro,
  /// no toca el árbol) y, si no hay, el lookup por contexto.
  ///
  /// Es seguro llamarla con un contexto desmontado o desactivado.
  static OpenSourceTab? openTabOf(BuildContext context) {
    if (_global != null) return _global;
    if (!context.mounted) return null;
    try {
      return context
          .getInheritedWidgetOfExactType<SourceTabController>()
          ?.openTab;
    } catch (_) {
      // "Looking up a deactivated widget's ancestor is unsafe": sin controller.
      return null;
    }
  }

  @override
  bool updateShouldNotify(SourceTabController old) => openTab != old.openTab;
}
