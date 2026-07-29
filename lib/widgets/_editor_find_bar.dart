part of 'code_editor_panel.dart';

// ── Find / Replace bar ──────────────────────────────────────────────────────────────────────────────────────────────

class _FindBar extends StatelessWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readonly;

  const _FindBar({required this.controller, required this.readonly});

  @override
  Size get preferredSize {
    final val = controller.value;
    if (val == null) return Size.zero;
    return Size.fromHeight(!readonly && val.replaceMode ? 78 : 38);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CodeFindValue?>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
        return Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFindRow(context, theme, value),
              if (!readonly && value.replaceMode) ...[
                const SizedBox(height: 2),
                _buildReplaceRow(context, theme),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFindRow(
    BuildContext context,
    ThemeData theme,
    CodeFindValue value,
  ) {
    final matchCount = value.result?.matches.length ?? 0;
    final matchIndex = value.result?.index ?? 0;
    final searched = value.result != null;
    final noMatches = searched && matchCount == 0;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 26,
            child: TextField(
              controller: controller.findInputController,
              focusNode: controller.findInputFocusNode,
              style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
              onSubmitted: (_) => controller.nextMatch(),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
                hintText: 'Buscar…',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        if (searched)
          SizedBox(
            width: 68,
            child: Text(
              noMatches ? 'Sin resultados' : '${matchIndex + 1} / $matchCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Consolas',
                color: noMatches
                    ? Colors.orange
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        _FindToggle(
          label: 'Aa',
          tooltip: 'Coincidir mayúsculas/minúsculas',
          active: value.option.caseSensitive,
          onTap: controller.toggleCaseSensitive,
        ),
        _FindToggle(
          label: '.*',
          tooltip: 'Expresión regular',
          active: value.option.regex,
          onTap: controller.toggleRegex,
        ),
        const SizedBox(width: 2),
        _FindNavBtn(
          icon: Icons.keyboard_arrow_up,
          tooltip: 'Coincidencia anterior',
          onTap: controller.previousMatch,
        ),
        _FindNavBtn(
          icon: Icons.keyboard_arrow_down,
          tooltip: 'Siguiente coincidencia',
          onTap: controller.nextMatch,
        ),
        const SizedBox(width: 2),
        if (!readonly)
          _FindNavBtn(
            icon: Icons.find_replace,
            tooltip: 'Alternar reemplazar',
            onTap: value.replaceMode
                ? controller.findMode
                : controller.replaceMode,
          ),
        _FindNavBtn(
          icon: Icons.close,
          tooltip: 'Cerrar (Esc)',
          onTap: controller.close,
        ),
      ],
    );
  }

  Widget _buildReplaceRow(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 26,
            child: TextField(
              controller: controller.replaceInputController,
              focusNode: controller.replaceInputFocusNode,
              style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
              onSubmitted: (_) => controller.replaceMatch(),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
                hintText: 'Reemplazar…',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _FindActionBtn(
          label: 'Reemplazar',
          tooltip: 'Reemplazar coincidencia actual',
          onTap: controller.replaceMatch,
          theme: theme,
        ),
        const SizedBox(width: 4),
        _FindActionBtn(
          label: 'Reemplazar todo',
          tooltip: 'Reemplazar todas las coincidencias',
          onTap: controller.replaceAllMatches,
          theme: theme,
        ),
      ],
    );
  }
}

class _FindToggle extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _FindToggle({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 26,
          height: 26,
          decoration: active
              ? BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                  ),
                )
              : null,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Consolas',
              fontWeight: FontWeight.bold,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _FindNavBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _FindNavBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _FindActionBtn extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final ThemeData theme;

  const _FindActionBtn({
    required this.label,
    required this.tooltip,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}
