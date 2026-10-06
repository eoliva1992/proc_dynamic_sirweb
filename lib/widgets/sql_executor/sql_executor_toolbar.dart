import 'package:flutter/material.dart';

import '../../models/sql_execution.dart';
import '../ambiente_selector.dart';
import '../monaco_snippets.dart' show openSnippetsManager;

// Mismo estilo de tooltip oscuro que usa el editor de procedimientos
// (`_editor_toolbar_widgets.dart`), para que ambos editores se vean iguales.
const kSqlTooltipDecoration = BoxDecoration(
  color: Color(0xFF2D2D30),
  borderRadius: BorderRadius.all(Radius.circular(6)),
  boxShadow: [
    BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 2)),
  ],
);
const kSqlTooltipTextStyle = TextStyle(color: Colors.white, fontSize: 12);
const kSqlTooltipWait = Duration(milliseconds: 400);

Color kindColor(SqlStatementKind kind, bool isDark) => switch (kind) {
  SqlStatementKind.select =>
    isDark ? const Color(0xFF4FC3F7) : const Color(0xFF0288D1),
  SqlStatementKind.dml =>
    isDark ? const Color(0xFFFFB74D) : const Color(0xFFF57C00),
  SqlStatementKind.ddl =>
    isDark ? const Color(0xFF4DB6AC) : const Color(0xFF00897B),
  SqlStatementKind.plsql =>
    isDark ? const Color(0xFFBA68C8) : const Color(0xFF7B1FA2),
  SqlStatementKind.explainPlan =>
    isDark ? const Color(0xFF9FA8DA) : const Color(0xFF3F51B5),
  SqlStatementKind.unknown =>
    isDark ? const Color(0xFFB0BEC5) : const Color(0xFF78909C),
};

/// Barra de herramientas superior del Ejecutor SQL.
class SqlExecutorToolbar extends StatelessWidget {
  final String ambiente;
  final ValueChanged<String> onAmbienteChanged;
  final SqlStatement? statement;
  final bool running;
  final VoidCallback? onExecuteCurrent;
  final VoidCallback? onExecuteAll;
  final VoidCallback? onExplainPlan;
  final VoidCallback? onClearOutput;
  final bool hasPendingChanges;
  final VoidCallback? onCommit;
  final VoidCallback? onRollback;

  const SqlExecutorToolbar({
    super.key,
    required this.ambiente,
    required this.onAmbienteChanged,
    required this.statement,
    required this.running,
    required this.onExecuteCurrent,
    required this.onExecuteAll,
    required this.onExplainPlan,
    required this.onClearOutput,
    this.hasPendingChanges = false,
    this.onCommit,
    this.onRollback,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: (isDark ? cs.surfaceContainerLow : cs.surface).withValues(
          alpha: 0.95,
        ),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        spacing: 6,
        children: [
          AmbienteSelector(value: ambiente, onChanged: onAmbienteChanged),
          if (statement != null) _buildKindChip(statement!, cs, isDark),
          HeroExecuteBtn(
            running: running,
            onPressed: running ? null : onExecuteCurrent,
            tooltip: 'Ejecutar sentencia actual / selección (Ctrl+Enter)',
          ),
          SqlToolBtn(
            icon: Icons.playlist_play_rounded,
            tooltip: 'Ejecutar todo el script (F5)',
            onPressed: running ? null : onExecuteAll,
          ),
          SqlToolBtn(
            icon: Icons.account_tree_outlined,
            tooltip: 'Plan de ejecución del SELECT bajo el cursor',
            onPressed: running ? null : onExplainPlan,
          ),
          SqlToolBtn(
            icon: Icons.code_rounded,
            tooltip: 'Snippets de usuario',
            onPressed: () => openSnippetsManager(context),
          ),
          const Spacer(),
          if (hasPendingChanges) ...[
            SqlToolBtn(
              icon: Icons.check_circle_outline_rounded,
              tooltip: 'Confirmar cambios (COMMIT)',
              color: const Color(0xFF3FB950),
              onPressed: running ? null : onCommit,
            ),
            SqlToolBtn(
              icon: Icons.undo_rounded,
              tooltip: 'Descartar cambios (ROLLBACK)',
              color: const Color(0xFFE5484D),
              onPressed: running ? null : onRollback,
            ),
          ],
          SqlToolBtn(
            icon: Icons.cleaning_services_outlined,
            tooltip: 'Limpiar salida',
            onPressed: onClearOutput,
          ),
        ],
      ),
    );
  }

  Widget _buildKindChip(SqlStatement stmt, ColorScheme cs, bool isDark) {
    final color = kindColor(stmt.kind, isDark);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey(stmt.kind),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.5 : 0.4),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              stmt.kind.label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón de ejecución primario con animación de pulso y spinner.
class HeroExecuteBtn extends StatefulWidget {
  final bool running;
  final VoidCallback? onPressed;
  final String tooltip;

  const HeroExecuteBtn({
    super.key,
    required this.running,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  State<HeroExecuteBtn> createState() => _HeroExecuteBtnState();
}

class _HeroExecuteBtnState extends State<HeroExecuteBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onPressed != null && !widget.running;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: kSqlTooltipWait,
      preferBelow: false,
      decoration: kSqlTooltipDecoration,
      textStyle: kSqlTooltipTextStyle,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: widget.running
                  ? cs.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.6)
                  : (_hovered && enabled
                        ? cs.primary.withValues(alpha: isDark ? 0.22 : 0.15)
                        : cs.primaryContainer.withValues(
                            alpha: isDark ? 0.2 : 0.35,
                          )),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.running
                    ? cs.primary.withValues(alpha: 0.6)
                    : (_hovered && enabled
                          ? cs.primary.withValues(alpha: 0.7)
                          : cs.outlineVariant.withValues(alpha: 0.7)),
                width: 0.8,
              ),
              boxShadow: _hovered && enabled
                  ? [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: widget.running
                  ? Row(
                      key: const ValueKey('running'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Ejecutando…',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      key: const ValueKey('idle'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 16,
                          color: enabled
                              ? cs.primary
                              : cs.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Ejecutar',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: enabled
                                ? cs.primary
                                : cs.onSurfaceVariant.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón de herramienta cuadrado estilizado.
class SqlToolBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const SqlToolBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  @override
  State<SqlToolBtn> createState() => _SqlToolBtnState();
}

class _SqlToolBtnState extends State<SqlToolBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onPressed != null;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: kSqlTooltipWait,
      preferBelow: false,
      decoration: kSqlTooltipDecoration,
      textStyle: kSqlTooltipTextStyle,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: _hovered && enabled
                  ? (isDark
                        ? cs.surfaceContainerHighest.withValues(alpha: 0.6)
                        : cs.surfaceContainerLow)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _hovered && enabled
                    ? cs.outlineVariant.withValues(alpha: 0.6)
                    : Colors.transparent,
                width: 0.5,
              ),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: enabled
                  ? (_hovered
                        ? (widget.color ?? cs.primary)
                        : (widget.color ?? cs.onSurfaceVariant))
                  : cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
