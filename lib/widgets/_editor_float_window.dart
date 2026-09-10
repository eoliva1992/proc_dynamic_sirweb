part of 'code_editor_panel.dart';

// ── Infraestructura de ventanas flotantes de los modales del editor ───────
//
// Los modales de consulta (InfoEvento, InfoDato, Autorizaciones…) se insertan
// en el overlay raíz en vez de usar `showDialog`. Así no hay barrera modal y
// la ventana puede minimizarse dejando el editor utilizable.

/// Inserta una ventana flotante en el overlay raíz.
///
/// [builder] recibe el callback para cerrarla. Devuelve ese mismo callback por
/// si el llamador necesita cerrarla programáticamente.
VoidCallback _showFloatingWindow(
  BuildContext context,
  Widget Function(VoidCallback close) builder,
) {
  late OverlayEntry entry;
  var removed = false;

  void close() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  // Sin `Material` envolvente de pantalla completa: cada ventana pone el suyo
  // sobre su propio rectángulo. Así el resto de la pantalla queda libre y los
  // clics llegan al editor y a las demás ventanas.
  // Se envuelve la ventana en un `Overlay` local:
  // Así los menús contextuales, popups y dropdowns abiertos desde ella
  // (p. ej. `AmbienteSelector`, `showMenu`, etc.) se dibujan en este Overlay
  // interno y quedan GARANTIZADAMENTE por delante del marco y contenido de
  // la ventana flotante, en vez de insertarse en el overlay raíz por detrás.
  entry = OverlayEntry(
    builder: (_) =>
        Overlay(initialEntries: [OverlayEntry(builder: (_) => builder(close))]),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return close;
}

/// Reparte posiciones para las ventanas minimizadas, de modo que no se
/// superpongan entre sí (se apilan como una barra de tareas).
class _MinimizedSlots {
  static final Set<int> _used = <int>{};

  /// Ancho y alto de una ventana minimizada.
  static const double barW = 300;
  static const double barH = 44;
  static const double _gap = 8;
  static const double _margin = 12;

  static int take() {
    var i = 0;
    while (_used.contains(i)) {
      i++;
    }
    _used.add(i);
    return i;
  }

  static void release(int? slot) {
    if (slot != null) _used.remove(slot);
  }

  /// Posición (left, top) de la ventana minimizada [slot] en pantalla.
  static (double, double) offsetFor(int slot, Size screen) {
    final perRow = ((screen.width - _margin * 2) / (barW + _gap)).floor().clamp(
      1,
      12,
    );
    final col = slot % perRow;
    final row = slot ~/ perRow;
    final left = _margin + col * (barW + _gap);
    final top = screen.height - _margin - barH - row * (barH + _gap);
    return (
      left.clamp(0.0, (screen.width - barW).clamp(0.0, double.infinity)),
      top.clamp(0.0, (screen.height - barH).clamp(0.0, double.infinity)),
    );
  }
}
