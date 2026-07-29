part of 'code_editor_panel.dart';

// ── Toolbar helpers ──────────────────────────────────────────────────────────────────────────────────────────────────

class _TbBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  const _TbBtn({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 28,
          height: 28,
          decoration: active
              ? BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                )
              : null,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: !enabled
                ? theme.colorScheme.onSurface.withValues(alpha: 0.25)
                : active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }
}

class _TbDivider extends StatelessWidget {
  const _TbDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).dividerColor,
    );
  }
}

class _ZoomSelector extends StatelessWidget {
  static const _levels = [50, 75, 90, 100, 110, 125, 150, 175, 200];

  final int value;
  final ValueChanged<int> onChanged;

  const _ZoomSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<int>(
      tooltip: 'Nivel de zoom',
      initialValue: value,
      itemBuilder: (_) => _levels
          .map(
            (p) => PopupMenuItem(
              value: p,
              height: 32,
              child: Text(
                '$p%',
                style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
              ),
            ),
          )
          .toList(),
      onSelected: onChanged,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          '$value%',
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Consolas',
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
