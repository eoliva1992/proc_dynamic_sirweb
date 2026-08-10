part of 'code_editor_panel.dart';

const _kTooltipDecoration = BoxDecoration(
  color: Color(0xFF2D2D30),
  borderRadius: BorderRadius.all(Radius.circular(6)),
  boxShadow: [
    BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 2)),
  ],
);
const _kTooltipTextStyle = TextStyle(color: Colors.white, fontSize: 12);
const _kTooltipWait = Duration(milliseconds: 400);

class _DocTab extends StatelessWidget {
  final Procedimiento proc;
  final bool isActive;
  final bool isModified;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _DocTab({
    required this.proc,
    required this.isActive,
    required this.isModified,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? cs.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isModified)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '●',
                  style: TextStyle(fontSize: 9, color: cs.primary, height: 1.2),
                ),
              ),
            Text(
              proc.cdProcedimiento,
              style: TextStyle(
                fontSize: 11,
                color: isActive ? cs.primary : cs.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                child: Icon(Icons.close, size: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ToolBtn({required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: _kTooltipWait,
      preferBelow: false,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onPressed;

  const _ToggleBtn({
    required this.icon,
    required this.tooltip,
    required this.active,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: _kTooltipWait,
      preferBelow: false,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? cs.primaryContainer.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 16,
            color: active
                ? cs.primary
                : cs.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

enum _EditorOption {
  wordWrap,
  renderWhitespace,
  bracketColorize,
  stickyScroll,
  smoothScrolling,
  mouseWheelZoom,
  formatOnPaste,
  quickSuggestions,
  parameterHints,
  hover,
  links,
  occurrences,
  contextMenu,
  resetDefaults,
}

class _ProblemCount extends StatelessWidget {
  final int count;
  final bool isError;
  const _ProblemCount({required this.count, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red[400]! : Colors.orange[400]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.warning_amber_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
