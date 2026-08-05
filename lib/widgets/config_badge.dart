import 'package:flutter/material.dart';

class ConfigBadge extends StatelessWidget {
  final String config;
  final bool small;

  const ConfigBadge({super.key, required this.config, this.small = false});

  static const _labels = {
    'D': 'Delphi',
    'J': 'JavaScript',
    'A': 'Acción',
    'G': 'Global',
    'S': 'Siniestro',
    'C': 'Cotización',
    'F': 'Financiero',
    'T': 'Técnico',
    'V': 'Vigencia',
    'O': 'Otro',
    'I': 'Integración',
  };

  static Color colorForConfig(String config) =>
      _colors[config] ?? const Color(0xFF95A5A6);

  static const _colors = {
    'D': Color(0xFF9B59B6),
    'J': Color(0xFFF0DB4F),
    'A': Color(0xFF27AE60),
    'G': Color(0xFF2980B9),
    'S': Color(0xFFE74C3C),
    'C': Color(0xFF16A085),
    'F': Color(0xFFD35400),
    'T': Color(0xFF8E44AD),
    'V': Color(0xFF2ECC71),
    'O': Color(0xFF95A5A6),
    'I': Color(0xFF1ABC9C),
  };

  Widget _letterBadge(Color color, double fontSize) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 6,
        vertical: small ? 2 : 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        config,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _colors[config] ?? const Color(0xFF95A5A6);
    final description = _labels[config] ?? config;

    if (small) {
      return _letterBadge(color, 11);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _letterBadge(color, 12),
        const SizedBox(width: 6),
        Text(
          description,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
