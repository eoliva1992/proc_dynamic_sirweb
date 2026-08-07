import 'package:flutter/material.dart';

class AmbienteSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  static const ambientes = ['Desa', 'Demo', 'QA', 'Replica', 'Prod'];

  const AmbienteSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  void _handleChange(BuildContext context, String? newValue) {
    if (newValue == null) return;
    if (newValue == 'Prod') {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Cambiar a Producción'),
            ],
          ),
          content: const Text(
            'Estás a punto de cambiar al ambiente de Producción.\n'
            'Las modificaciones afectarán datos reales.',
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
        if (confirmed == true) onChanged(newValue);
      });
    } else {
      onChanged(newValue);
    }
  }

  static Color colorForAmbiente(String ambiente) {
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
    final surfaceColor = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorForAmbiente(value).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorForAmbiente(value), width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: surfaceColor,
          style: TextStyle(
            color: colorForAmbiente(value),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          icon: Icon(
            Icons.arrow_drop_down,
            color: colorForAmbiente(value),
            size: 18,
          ),
          items: ambientes
              .map(
                (a) => DropdownMenuItem(
                  value: a,
                  child: Text(
                    a,
                    style: TextStyle(
                      color: colorForAmbiente(a),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => _handleChange(context, v),
        ),
      ),
    );
  }
}
