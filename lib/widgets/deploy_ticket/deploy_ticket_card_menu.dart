import 'package:flutter/material.dart';

import '../../models/deploy_ticket.dart';

/// Menú desplegable usando [OverlayPortal] para tarjetas de DeployTicket.
///
/// Dado que las ventanas flotantes de la app (`showFloatingWindow`) se montan
/// en un [OverlayEntry] propio, `PopupMenuButton` y `showMenu` insertan una ruta
/// en la base del Navigator que queda pintada **detrás** de la ventana flotante.
/// [OverlayPortal] garantiza que el menú se pinte por delante de la ventana flotante.
class DeployTicketCardMenu extends StatefulWidget {
  final DeployTicket ticket;
  final VoidCallback onCreateHotfix;
  final VoidCallback onPushHotfix;
  final VoidCallback onExport;
  final VoidCallback onCopyIndex;
  final bool canPush;

  const DeployTicketCardMenu({
    super.key,
    required this.ticket,
    required this.onCreateHotfix,
    required this.onPushHotfix,
    required this.onExport,
    required this.onCopyIndex,
    this.canPush = true,
  });

  @override
  State<DeployTicketCardMenu> createState() => _DeployTicketCardMenuState();
}

class _DeployTicketCardMenuState extends State<DeployTicketCardMenu> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  void _toggleMenu() {
    if (_controller.isShowing) {
      _controller.hide();
    } else {
      _controller.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF222630) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF383E4C)
        : const Color(0xFFDDE2EA);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (context) {
          return Stack(
            children: [
              // Barrera transparente para cerrar al pulsar afuera
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (_) => _controller.hide(),
                ),
              ),
              // Menú flotante posicionado sobre el botón
              Positioned(
                width: 200,
                child: CompositedTransformFollower(
                  link: _link,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomRight,
                  followerAnchor: Alignment.topRight,
                  offset: const Offset(0, 4),
                  child: Material(
                    color: surfaceColor,
                    elevation: 14,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor, width: 0.9),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.5 : 0.18,
                            ),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MenuItem(
                            icon: Icons.bolt_rounded,
                            iconColor: Colors.amber.shade700,
                            label: 'Crear / Enlazar Hotfix',
                            onTap: () {
                              _controller.hide();
                              widget.onCreateHotfix();
                            },
                          ),
                          if (widget.canPush)
                            _MenuItem(
                              icon: Icons.rocket_launch_rounded,
                              iconColor: Colors.greenAccent.shade700,
                              label: 'Push Hotfix',
                              onTap: () {
                                _controller.hide();
                                widget.onPushHotfix();
                              },
                            )
                          else
                            _MenuItem(
                              icon: Icons.rocket_launch_outlined,
                              iconColor: isDark
                                  ? Colors.white38
                                  : Colors.black38,
                              label: 'Push Hotfix (sin configurar)',
                              enabled: false,
                              onTap: () {},
                            ),
                          Divider(
                            height: 8,
                            thickness: 0.8,
                            color: borderColor,
                          ),
                          _MenuItem(
                            icon: Icons.file_download_outlined,
                            iconColor: Colors.blueAccent,
                            label: 'Exportar Pase',
                            onTap: () {
                              _controller.hide();
                              widget.onExport();
                            },
                          ),
                          _MenuItem(
                            icon: Icons.copy_rounded,
                            iconColor: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                            label: 'Copiar index.txt',
                            onTap: () {
                              _controller.hide();
                              widget.onCopyIndex();
                            },
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
        child: IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Acciones de Git y Pase',
          icon: const Icon(Icons.more_vert_rounded, size: 16),
          padding: EdgeInsets.zero,
          onPressed: _toggleMenu,
        ),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEnabled = widget.enabled;

    return MouseRegion(
      onEnter: (_) => isEnabled ? setState(() => _hovered = true) : null,
      onExit: (_) => isEnabled ? setState(() => _hovered = false) : null,
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isEnabled ? widget.onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          color: _hovered && isEnabled
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05))
              : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: isEnabled
                    ? widget.iconColor
                    : (isDark ? Colors.white30 : Colors.black26),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isEnabled
                        ? null
                        : (isDark ? Colors.white38 : Colors.black38),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
