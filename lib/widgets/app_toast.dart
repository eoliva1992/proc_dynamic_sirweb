import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// Centralized toast notifications — uses ToastificationWrapper at app root.
abstract final class AppToast {
  static const _alignment = Alignment.bottomRight;
  static const _animDuration = Duration(milliseconds: 300);
  static const _style = ToastificationStyle.flatColored;

  static void success(String message, {Duration? duration}) {
    toastification.show(
      alignment: _alignment,
      animationDuration: _animDuration,
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
}
