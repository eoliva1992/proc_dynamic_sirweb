part of 'main_screen.dart';

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  static const _shortcuts = [
    ('Ctrl + K', 'Búsqueda rápida de esquema'),
    ('Ctrl + S', 'Guardar procedimiento'),
    ('Ctrl + T', 'Nueva pestaña de búsqueda'),
    ('Ctrl + W', 'Cerrar pestaña activa'),
    ('Ctrl + Tab', 'Siguiente pestaña'),
    ('Ctrl + Shift + Tab', 'Pestaña anterior'),
    ('Ctrl + =', 'Aumentar tamaño de fuente'),
    ('Ctrl + −', 'Reducir tamaño de fuente'),
    ('Shift + Alt + F', 'Formatear documento'),
    ('F1', 'Mostrar atajos de teclado'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? cs.surfaceContainerHigh
                    : cs.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.keyboard_alt_outlined,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Atajos de teclado',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    for (final (keys, desc) in _shortcuts)
                      _ShortcutRow(keys: keys, description: desc),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String keys;
  final String description;
  const _ShortcutRow({required this.keys, required this.description});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              description,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              keys,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
