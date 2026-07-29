part of 'code_editor_panel.dart';

class _ConfigSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final bool isNuevo;

  static const _fallbackConfigs = [
    'D',
    'J',
    'A',
    'G',
    'S',
    'C',
    'F',
    'T',
    'V',
    'O',
    'I',
  ];

  const _ConfigSelector({
    required this.value,
    required this.onChanged,
    required this.isNuevo,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProcedimientosProvider>();
    final theme = Theme.of(context);
    final configs = provider.configuraciones;

    // Ensure the current value exists in the list
    final currentValue = configs.isEmpty
        ? (value.isEmpty ? _fallbackConfigs.first : value)
        : (configs.any((c) => c.cdModulo == value)
              ? value
              : configs.first.cdModulo);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.dividerColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isDense: true,
          dropdownColor: theme.colorScheme.surface,
          icon: Icon(
            Icons.arrow_drop_down,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            size: 18,
          ),
          items: configs.isEmpty
              ? _fallbackConfigs
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: ConfigBadge(config: c, small: false),
                      ),
                    )
                    .toList()
              : configs
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.cdModulo,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConfigBadge(config: c.cdModulo, small: true),
                            const SizedBox(width: 6),
                            Text(
                              c.deArgumento,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
          onChanged: isNuevo ? (v) => v != null ? onChanged(v) : null : null,
        ),
      ),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final bool activo;
  const _EstadoChip({required this.activo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: activo
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: activo ? Colors.green.shade700 : Colors.red.shade700,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: activo ? Colors.green.shade400 : Colors.red.shade400,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            activo ? 'Activo' : 'Inactivo',
            style: TextStyle(
              color: activo ? Colors.green.shade400 : Colors.red.shade400,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
