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
}
