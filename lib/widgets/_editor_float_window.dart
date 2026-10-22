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
  return showFloatingWindow(context, builder);
}

/// Reparte posiciones para las ventanas minimizadas.
/// Redirige a [FloatingWindowSlots] para mantener sincronía global en un solo lugar.
typedef _MinimizedSlots = FloatingWindowSlots;
