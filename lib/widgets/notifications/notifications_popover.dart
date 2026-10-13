import 'package:flutter/material.dart';
import '../../models/app_notification.dart';
import '../../services/notification_service.dart';

/// Popover / Menú desplegable para ver y gestionar la campana de notificaciones.
class NotificationsMenuButton extends StatefulWidget {
  final Color? color;

  const NotificationsMenuButton({super.key, this.color});

  @override
  State<NotificationsMenuButton> createState() =>
      _NotificationsMenuButtonState();
}

class _NotificationsMenuButtonState extends State<NotificationsMenuButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final fg =
        theme.appBarTheme.iconTheme?.color ?? theme.colorScheme.onSurface;
    final baseColor = widget.color ?? fg.withValues(alpha: 0.7);

    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.instance.unreadCount,
      builder: (context, unread, _) {
        return MenuAnchor(
          style: MenuStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            elevation: const WidgetStatePropertyAll(8),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          menuChildren: [
            SizedBox(
              width: 360,
              height: 440,
              child: _NotificationsListContent(
                isDark: isDark,
                primary: primary,
              ),
            ),
          ],
          builder: (context, controller, child) {
            return Tooltip(
              message: unread > 0
                  ? 'Notificaciones ($unread nuevas)'
                  : 'Notificaciones',
              waitDuration: const Duration(milliseconds: 350),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E24),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 0.8,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: controller.isOpen
                        ? primary.withValues(alpha: 0.18)
                        : (_isHovered
                              ? fg.withValues(alpha: 0.10)
                              : Colors.transparent),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: controller.isOpen
                          ? primary.withValues(alpha: 0.40)
                          : (_isHovered
                                ? fg.withValues(alpha: 0.18)
                                : Colors.transparent),
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                    hoverColor: Colors.transparent,
                    splashColor: fg.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                    child: Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            unread > 0
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_none_rounded,
                            color: controller.isOpen
                                ? primary
                                : (_isHovered ? fg : baseColor),
                            size: 17,
                          ),
                          if (unread > 0)
                            Positioned(
                              right: -5,
                              top: -5,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 13,
                                  minHeight: 13,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color:
                                        theme.appBarTheme.backgroundColor ??
                                        theme.colorScheme.surface,
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    unread > 99 ? '99+' : '$unread',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      height: 1.2,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
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
          },
        );
      },
    );
  }
}

class _NotificationsListContent extends StatelessWidget {
  final bool isDark;
  final Color primary;

  const _NotificationsListContent({
    required this.isDark,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AppNotification>>(
      valueListenable: NotificationService.instance.notifications,
      builder: (context, items, _) {
        return Column(
          children: [
            // Cabecera
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_rounded, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    'Notificaciones',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<bool>(
                    valueListenable: NotificationService.instance.isLoading,
                    builder: (context, loading, _) {
                      if (loading) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return IconButton(
                        tooltip: 'Recargar del servidor',
                        iconSize: 15,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () =>
                            NotificationService.instance.fetchNotifications(),
                        icon: const Icon(Icons.refresh_rounded),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  if (items.isNotEmpty) ...[
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () =>
                          NotificationService.instance.markAllAsRead(),
                      child: const Text(
                        'Marcar leídas',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Limpiar lista local',
                      iconSize: 14,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => NotificationService.instance.clearAll(),
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                  ],
                ],
              ),
            ),
            // Contenido / Lista
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 36,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No hay notificaciones',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                      itemBuilder: (context, index) {
                        final notif = items[index];
                        return _buildNotificationTile(context, notif);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNotificationTile(BuildContext context, AppNotification notif) {
    final noteId = notif.data?['noteId']?.toString();
    final iconData = switch (notif.kind) {
      AppNotificationKind.success => Icons.check_circle_rounded,
      AppNotificationKind.warning => Icons.warning_rounded,
      AppNotificationKind.error => Icons.error_rounded,
      AppNotificationKind.info => Icons.info_rounded,
    };
    final iconColor = switch (notif.kind) {
      AppNotificationKind.success => Colors.green,
      AppNotificationKind.warning => Colors.orange,
      AppNotificationKind.error => Colors.redAccent,
      AppNotificationKind.info => Colors.blueAccent,
    };

    return InkWell(
      onTap: () {
        NotificationService.instance.markAsRead(notif.id);
        if (noteId != null && noteId.isNotEmpty) {
          NotificationService.instance.onOpenNoteRequested?.call(noteId);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        color: notif.read
            ? Colors.transparent
            : (isDark
                  ? Colors.blue.withValues(alpha: 0.08)
                  : Colors.blue.withValues(alpha: 0.05)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(iconData, size: 16, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: notif.read
                                ? FontWeight.w500
                                : FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        _formatTime(notif.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notif.message,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  if (noteId != null && noteId.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Toca para abrir la nota →',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Botón eliminar notificación
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 14),
              color: isDark ? Colors.white30 : Colors.black26,
              hoverColor: Colors.red.withValues(alpha: 0.1),
              tooltip: 'Eliminar notificación',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              onPressed: () {
                NotificationService.instance.deleteNotification(notif.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${dt.day}/${dt.month}';
  }
}
