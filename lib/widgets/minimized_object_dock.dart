import 'package:flutter/material.dart';

import '../app_navigator.dart';
import 'ambiente_selector.dart';

const _kTypeColors = {
  'TABLE': Color(0xFF0078D4),
  'VIEW': Color(0xFF107C10),
  'PROCEDURE': Color(0xFFCA5010),
  'FUNCTION': Color(0xFF8764B8),
  'PACKAGE': Color(0xFFC19C00),
  'TYPE': Color(0xFF2E7D9E),
};
const _kTypeIcons = {
  'TABLE': Icons.table_chart_outlined,
  'VIEW': Icons.visibility_outlined,
  'PROCEDURE': Icons.code_rounded,
  'FUNCTION': Icons.functions_rounded,
  'PACKAGE': Icons.inventory_2_outlined,
  'TYPE': Icons.data_object_outlined,
};

class _DockItem {
  final String name;
  final String type;
  final String ambiente;

  /// Vuelve a abrir el modal. Recibe un contexto vivo con Navigator.
  final void Function(BuildContext context) onRestore;

  const _DockItem({
    required this.name,
    required this.type,
    required this.ambiente,
    required this.onRestore,
  });

  String get key => '$name::$type::$ambiente';
}

/// Dock flotante (abajo a la derecha) con los modales de objeto minimizados.
///
/// Se dibuja sobre un [OverlayEntry] del overlay raíz, de modo que —a
/// diferencia de un diálogo— no bloquea la interacción con el editor: solo
/// ocupa el área de los chips.
class MinimizedObjectDock {
  MinimizedObjectDock._();

  static final List<_DockItem> _items = [];
  static OverlayEntry? _entry;

  /// Minimiza un objeto al dock. Si ya estaba minimizado, no lo duplica.
  ///
  /// [context] es solo un fallback: se prefiere el overlay del Navigator raíz
  /// para no hacer lookups sobre un contexto potencialmente desactivado.
  static void add(
    BuildContext context, {
    required String name,
    required String type,
    required String ambiente,
    required void Function(BuildContext context) onRestore,
  }) {
    final item = _DockItem(
      name: name,
      type: type,
      ambiente: ambiente,
      onRestore: onRestore,
    );
    _items.removeWhere((i) => i.key == item.key);
    _items.add(item);

    if (_entry == null) {
      final overlay =
          rootNavigatorKey.currentState?.overlay ??
          Overlay.of(context, rootOverlay: true);
      _entry = OverlayEntry(builder: (_) => _DockLayer(items: List.of(_items)));
      overlay.insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  static void _close(_DockItem item) {
    _items.removeWhere((i) => i.key == item.key);
    if (_items.isEmpty) {
      _entry?.remove();
      _entry = null;
    } else {
      _entry!.markNeedsBuild();
    }
  }
}

class _DockLayer extends StatelessWidget {
  /// Copia de la lista: una instancia nueva en cada rebuild garantiza que el
  /// overlay no reutilice el widget anterior (un `const` idéntico se saltaría).
  final List<_DockItem> items;
  const _DockLayer({required this.items});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _DockChip(key: ValueKey(item.key), item: item),
            ),
        ],
      ),
    );
  }
}

class _DockChip extends StatefulWidget {
  final _DockItem item;
  const _DockChip({super.key, required this.item});

  @override
  State<_DockChip> createState() => _DockChipState();
}

class _DockChipState extends State<_DockChip> {
  bool _hovered = false;

  void _restore() {
    // Capturamos el contexto del Navigator antes de remover el chip: sigue
    // vivo aunque el OverlayEntry desaparezca.
    final navContext =
        rootDialogContext ?? Navigator.of(context, rootNavigator: true).context;
    final item = widget.item;
    MinimizedObjectDock._close(item);
    item.onRestore(navContext);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.item;
    final color = _kTypeColors[item.type] ?? Colors.grey;
    final icon = _kTypeIcons[item.type] ?? Icons.storage_outlined;
    final ambColor = AmbienteSelector.colorForAmbiente(item.ambiente);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: Tooltip(
          message: 'Restaurar ${item.name}',
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(
            onTap: _restore,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
              decoration: BoxDecoration(
                color: isDark
                    ? (_hovered
                          ? const Color(0xFF2D2D2D)
                          : const Color(0xFF252526))
                    : (_hovered ? const Color(0xFFEFF4FF) : Colors.white),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hovered
                      ? color.withValues(alpha: 0.6)
                      : (isDark
                            ? const Color(0xFF3A3A3A)
                            : const Color(0xFFDDE2EA)),
                  width: 0.9,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(icon, size: 12, color: color),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      item.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFD4D4D4)
                            : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: ambColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: ambColor.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      item.ambiente,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: ambColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Tooltip(
                    message: 'Cerrar',
                    child: InkWell(
                      onTap: () => MinimizedObjectDock._close(item),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
