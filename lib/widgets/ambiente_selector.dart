import 'package:flutter/material.dart';

class AmbienteSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  static const _ambientes = ['Desa', 'Demo', 'QA', 'Replica', 'Prod'];

  const AmbienteSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  Color _colorForAmbiente(String ambiente) {
    return switch (ambiente) {
      'Prod' => Colors.red.shade700,
      'QA' => Colors.orange.shade700,
      'Demo' => Colors.blue.shade600,
      'Replica' => Colors.purple.shade600,
      _ => Colors.teal.shade600, // Desa
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _colorForAmbiente(value).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _colorForAmbiente(value), width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: const Color(0xFF2D2D2D),
          style: TextStyle(
            color: _colorForAmbiente(value),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          icon: Icon(Icons.arrow_drop_down, color: _colorForAmbiente(value), size: 18),
          items: _ambientes
              .map(
                (a) => DropdownMenuItem(
                  value: a,
                  child: Text(
                    a,
                    style: TextStyle(
                      color: _colorForAmbiente(a),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}
