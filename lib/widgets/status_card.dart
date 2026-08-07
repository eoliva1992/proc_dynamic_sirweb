import 'package:flutter/material.dart';

/// Card flotante de estado — mismo estilo que SchemaStatusOverlay.
/// Úsalo dentro de un Stack + Positioned(left:12, bottom:12).
class StatusCard extends StatelessWidget {
  final String message;
  final bool isSpinning;
  final bool isError;
  final IconData icon;

  const StatusCard({
    super.key,
    required this.message,
    this.isSpinning = true,
    this.isError = false,
    this.icon = Icons.cloud_download_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isError
        ? (isDark ? const Color(0xFF5A1A1A) : const Color(0xFFB71C1C))
        : (isDark ? const Color(0xFF1E2D3D) : const Color(0xFF0D47A1));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.25),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSpinning)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else
            Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
