import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// Centralized toast notifications — uses ToastificationWrapper at app root.
abstract final class AppToast {
  static const _alignment = Alignment.bottomRight;
  static const _animDuration = Duration(milliseconds: 420);
  static const _style = ToastificationStyle.flatColored;

  // Slide in from right + scale up + fade — smooth easeOutQuint entrance
  static Widget _buildAnimation(
    BuildContext context,
    Animation<double> animation,
    Alignment alignment,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutQuint,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.35, 0),
        end: Offset.zero,
      ).animate(curved),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
        alignment: Alignment.centerRight,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  static void success(String message, {Duration? duration}) {
    toastification.show(
      alignment: _alignment,
      animationDuration: _animDuration,
      animationBuilder: _buildAnimation,
      type: ToastificationType.success,
      style: _style,
      title: Text(message, style: const TextStyle(fontSize: 13)),
      autoCloseDuration: duration ?? const Duration(seconds: 3),
      showProgressBar: true,
      dragToClose: true,
      pauseOnHover: true,
      closeButton: const ToastCloseButton(
        showType: CloseButtonShowType.onHover,
      ),
    );
  }

  static void error(String message, {Duration? duration}) {
    toastification.show(
      alignment: _alignment,
      animationDuration: _animDuration,
      animationBuilder: _buildAnimation,
      type: ToastificationType.error,
      style: _style,
      title: Text(message, style: const TextStyle(fontSize: 13)),
      autoCloseDuration: duration ?? const Duration(seconds: 5),
      showProgressBar: true,
      dragToClose: true,
      pauseOnHover: true,
      closeButton: const ToastCloseButton(
        showType: CloseButtonShowType.onHover,
      ),
    );
  }

  static void warning(String message, {Duration? duration}) {
    toastification.show(
      alignment: _alignment,
      animationDuration: _animDuration,
      animationBuilder: _buildAnimation,
      type: ToastificationType.warning,
      style: _style,
      title: Text(message, style: const TextStyle(fontSize: 13)),
      autoCloseDuration: duration ?? const Duration(seconds: 4),
      showProgressBar: true,
      dragToClose: true,
      pauseOnHover: true,
      closeButton: const ToastCloseButton(
        showType: CloseButtonShowType.onHover,
      ),
    );
  }

  static void info(String message, {Duration? duration}) {
    toastification.show(
      alignment: _alignment,
      animationDuration: _animDuration,
      animationBuilder: _buildAnimation,
      type: ToastificationType.info,
      style: _style,
      title: Text(message, style: const TextStyle(fontSize: 13)),
      autoCloseDuration: duration ?? const Duration(seconds: 3),
      showProgressBar: true,
      dragToClose: true,
      pauseOnHover: true,
      closeButton: const ToastCloseButton(
        showType: CloseButtonShowType.onHover,
      ),
    );
  }

  // Shows a success toast with an action button (e.g. open file explorer).
  static void successWithAction(
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
    IconData actionIcon = Icons.folder_open_rounded,
    String? detail,
    Duration? duration,
  }) {
    ToastificationItem? item;
    item = toastification.show(
      alignment: _alignment,
      animationDuration: _animDuration,
      animationBuilder: _buildAnimation,
      type: ToastificationType.success,
      style: _style,
      title: Text(
        message,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (detail != null && detail.isNotEmpty)
            Text(
              detail,
              style: const TextStyle(fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                if (item != null) toastification.dismiss(item);
                onAction();
              },
              icon: Icon(actionIcon, size: 15),
              label: Text(actionLabel, style: const TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      autoCloseDuration: duration ?? const Duration(seconds: 6),
      showProgressBar: true,
      dragToClose: true,
      pauseOnHover: true,
      closeButton: const ToastCloseButton(showType: CloseButtonShowType.always),
    );
  }

  // Shows a warning with a tappable description that triggers an action.
  static void warningWithAction(
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
    Duration? duration,
  }) {
    ToastificationItem? item;
    item = toastification.show(
      alignment: _alignment,
      animationDuration: _animDuration,
      animationBuilder: _buildAnimation,
      type: ToastificationType.warning,
      style: ToastificationStyle.flat,
      primaryColor: Colors.amber.shade500,
      backgroundColor: const Color(0xFF252526),
      foregroundColor: const Color(0xFFD4D4D4),
      icon: Icon(Icons.account_circle_outlined, color: Colors.amber.shade400),
      title: Text(
        message,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      description: Row(
        children: [
          const Text(
            'Toca para configurar  ',
            style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
          ),
          Text(
            actionLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0078D4),
            ),
          ),
        ],
      ),
      autoCloseDuration: duration ?? const Duration(seconds: 10),
      showProgressBar: false,
      dragToClose: true,
      pauseOnHover: true,
      closeButton: const ToastCloseButton(showType: CloseButtonShowType.always),
      callbacks: ToastificationCallbacks(
        onTap: (_) {
          toastification.dismiss(item!);
          onAction();
        },
      ),
    );
  }

  // Shows an error with a short title and a longer technical detail below.
  static void errorWithDetail(
    String title,
    String detail, {
    Duration? duration,
  }) {
    toastification.show(
      alignment: _alignment,
      animationDuration: _animDuration,
      animationBuilder: _buildAnimation,
      type: ToastificationType.error,
      style: _style,
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      description: Text(
        detail,
        style: const TextStyle(fontSize: 11),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      autoCloseDuration: duration ?? const Duration(seconds: 7),
      showProgressBar: true,
      dragToClose: true,
      pauseOnHover: true,
      closeButton: const ToastCloseButton(showType: CloseButtonShowType.always),
    );
  }

  /// Error que permanece en pantalla hasta que se lo cierra explícitamente.
  ///
  /// Devuelve el item para poder descartarlo con [dismiss] cuando la condición
  /// que lo originó desaparece (p. ej. la conexión se restablece).
  static ToastificationItem persistentError(
    String title, {
    String? detail,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return toastification.show(
      alignment: _alignment,
      animationDuration: _animDuration,
      animationBuilder: _buildAnimation,
      type: ToastificationType.error,
      style: _style,
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      description: (detail == null && actionLabel == null)
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (detail != null && detail.isNotEmpty)
                  Text(detail, style: const TextStyle(fontSize: 11)),
                if (actionLabel != null && onAction != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: Text(
                        actionLabel,
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
              ],
            ),
      // Sin autoclose: la alerta vive mientras dure el problema.
      autoCloseDuration: null,
      showProgressBar: false,
      dragToClose: false,
      pauseOnHover: true,
      closeButton: const ToastCloseButton(showType: CloseButtonShowType.always),
    );
  }

  /// Cierra un toast obtenido de [persistentError].
  static void dismiss(ToastificationItem item) => toastification.dismiss(item);
}
