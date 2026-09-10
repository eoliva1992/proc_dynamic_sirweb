import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'app_toast.dart';
import 'constellation_background.dart';

/// Selector del ambiente Oracle contra el que trabaja la pantalla que lo usa.
///
/// Dos decisiones de arquitectura que resuelven los problemas habituales:
///
/// 1. **No usa `DropdownButton` ni `PopupMenuButton`**.
///    - `DropdownButton` guarda su ruta en el `State` y revienta con
///      `Failed assertion: '_dropdownRoute == null'` al reconstruirse por [onChanged].
///    - `PopupMenuButton` / `showMenu` empuja una ruta a la base del `Navigator`:
///      si el selector vive dentro de una ventana flotante (`OverlayEntry` en
///      el overlay raíz), el menú se dibuja **detrás** de la ventana.
///
/// 2. **Usa [OverlayPortal]**.
///    Flutter garantiza por diseño (ver docs de `OverlayPortal.paintOrder`) que
///    el hijo del portal se pinta **justo después de la [OverlayEntry] que lo
///    aloja** (en este caso, la ventana flotante) y por delante de ella. Además,
///    depende del mismo subárbol de temas y nunca sobrevive a su destrucción.
///
/// 3. **Se activa desde un [Listener]**. Los encabezados arrastrables con
///    `onPanUpdate` ganan la arena de gestos de los botones comunes; `Listener`
///    recibe el puntero crudo y nunca pierde el clic.
class AmbienteSelector extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;

  static const ambientes = ['Desa', 'Demo', 'QA', 'Replica', 'Prod'];

  const AmbienteSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static Color colorForAmbiente(String ambiente) {
    return switch (ambiente) {
      'Prod' => Colors.red.shade700,
      'QA' => Colors.orange.shade700,
      'Demo' => Colors.blue.shade600,
      'Replica' => Colors.purple.shade600,
      _ => Colors.teal.shade600, // Desa
    };
  }

  static IconData iconForAmbiente(String ambiente) {
    return switch (ambiente) {
      'Prod' => Icons.warning_rounded,
      'QA' => Icons.bug_report_outlined,
      'Demo' => Icons.slideshow_outlined,
      'Replica' => Icons.copy_all_outlined,
      _ => Icons.computer_outlined, // Desa
    };
  }

  @override
  State<AmbienteSelector> createState() => _AmbienteSelectorState();
}

class _AmbienteSelectorState extends State<AmbienteSelector> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  void _toggleMenu(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    if (_controller.isShowing) {
      _controller.hide();
    } else {
      _controller.show();
    }
  }

  void _handleChange(String newValue) {
    _controller.hide();
    if (newValue == widget.value) return;

    if (newValue == 'Prod') {
      final navigator = Navigator.of(context);
      Future.microtask(() {
        if (navigator.mounted) _confirmarProd(navigator.context);
      });
      return;
    }

    widget.onChanged(newValue);
    if (newValue == 'QA' || newValue == 'Replica') {
      AppToast.warning(
        '$newValue — los cambios pueden afectar datos compartidos',
        duration: const Duration(seconds: 4),
      );
    }
  }

  void _confirmarProd(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        title: const ConstellationDialogTitle(
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Cambiar a Producción'),
            ],
          ),
        ),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Estás a punto de cambiar al ambiente de Producción.\n'
            'Las modificaciones afectarán datos reales.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) widget.onChanged('Prod');
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final color = AmbienteSelector.colorForAmbiente(value);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFDDE2EA);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (context) {
          return Stack(
            children: [
              // Barrera invisible de pantalla completa para cerrar al tocar afuera.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (_) => _controller.hide(),
                ),
              ),
              // Menú posicionado relativo al botón, pintado SIEMPRE por delante
              // de la ventana flotante (garantía de OverlayPortal).
              Positioned(
                width: 155,
                child: CompositedTransformFollower(
                  link: _link,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: const Offset(0, 4),
                  child: Material(
                    color: surfaceColor,
                    elevation: 12,
                    borderRadius: BorderRadius.circular(6),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final a in AmbienteSelector.ambientes)
                            _AmbienteMenuItem(
                              ambiente: a,
                              selected: a == value,
                              color: AmbienteSelector.colorForAmbiente(a),
                              icon: AmbienteSelector.iconForAmbiente(a),
                              isDark: isDark,
                              onTap: () => _handleChange(a),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _toggleMenu,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AmbienteSelector.iconForAmbiente(value),
                    size: 13,
                    color: color,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: color, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmbienteMenuItem extends StatelessWidget {
  final String ambiente;
  final bool selected;
  final Color color;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _AmbienteMenuItem({
    required this.ambiente,
    required this.selected,
    required this.color,
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                ambiente,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            if (selected) Icon(Icons.check_rounded, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}
