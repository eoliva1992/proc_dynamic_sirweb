import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/sql_execution.dart';
import '../ambiente_selector.dart';
import '../editor_split_container.dart';
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
  SqlStatementKind.command =>
    isDark ? const Color(0xFF80DEEA) : const Color(0xFF0097A7),
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
  final VoidCallback? onCancel;
  final VoidCallback? onClearOutput;
  final VoidCallback? onNewFile;
  final VoidCallback? onOpenFile;
  final VoidCallback? onSaveFile;
  final VoidCallback? onSaveFileAs;
  final VoidCallback? onRevealInExplorer;
  final String? currentFilePath;
  final bool hasPendingChanges;
  final VoidCallback? onCommit;
  final VoidCallback? onRollback;
  final DateTime? runStartedAt;
  final bool hasUnexecutedChanges;
  final int timeoutSeconds;
  final ValueChanged<int>? onTimeoutChanged;
  final int maxRows;
  final ValueChanged<int>? onMaxRowsChanged;
  final EditorSplitMode splitMode;
  final ValueChanged<EditorSplitMode>? onSplitModeChanged;

  const SqlExecutorToolbar({
    super.key,
    required this.ambiente,
    required this.onAmbienteChanged,
    required this.statement,
    required this.running,
    required this.onExecuteCurrent,
    required this.onExecuteAll,
    required this.onExplainPlan,
    this.onCancel,
    required this.onClearOutput,
    this.onNewFile,
    this.onOpenFile,
    this.onSaveFile,
    this.onSaveFileAs,
    this.onRevealInExplorer,
    this.currentFilePath,
    this.hasPendingChanges = false,
    this.onCommit,
    this.onRollback,
    this.runStartedAt,
    this.hasUnexecutedChanges = false,
    this.timeoutSeconds = 60,
    this.onTimeoutChanged,
    this.maxRows = 1000,
    this.onMaxRowsChanged,
    this.splitMode = EditorSplitMode.none,
    this.onSplitModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final isProd = ambiente == 'Prod';

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: (isDark ? cs.surfaceContainerLow : cs.surface).withValues(
          alpha: 0.95,
        ),
        border: Border(
          bottom: BorderSide(
            color: isProd
                ? Colors.red.withValues(alpha: 0.6)
                : cs.outlineVariant.withValues(alpha: 0.7),
            width: isProd ? 2 : 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: 6,
          children: [
            AmbienteSelector(value: ambiente, onChanged: onAmbienteChanged),
            if (statement != null) _buildKindChip(statement!, cs, isDark),
            if (hasUnexecutedChanges) _buildUnrunChangesDot(cs),
            HeroExecuteBtn(
              running: running,
              onPressed: running ? null : onExecuteCurrent,
              onCancel: onCancel,
              tooltip: 'Ejecutar sentencia actual / selección (Ctrl+Enter)',
              runStartedAt: runStartedAt,
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
              icon: Icons.note_add_outlined,
              tooltip: 'Nuevo script limpio (Ctrl+N)',
              onPressed: running ? null : onNewFile,
            ),
            SqlToolBtn(
              icon: Icons.folder_open_rounded,
              tooltip: 'Abrir archivo local (.sql / .txt)',
              onPressed: running ? null : onOpenFile,
            ),
            SqlToolBtn(
              icon: Icons.save_outlined,
              tooltip: currentFilePath != null
                  ? 'Guardar en disco (Ctrl+S) — ${Uri.file(currentFilePath!).pathSegments.last}'
                  : 'Guardar archivo local (Ctrl+S)',
              onPressed: running ? null : onSaveFile,
            ),
            SqlToolBtn(
              icon: Icons.save_as_outlined,
              tooltip: 'Guardar como… (Ctrl+Shift+S)',
              onPressed: running ? null : onSaveFileAs,
            ),
            if (currentFilePath != null && currentFilePath!.isNotEmpty)
              SqlToolBtn(
                icon: Icons.folder_shared_outlined,
                tooltip: 'Abrir ubicación en el explorador\n$currentFilePath',
                onPressed: running ? null : onRevealInExplorer,
              ),
            SqlToolBtn(
              icon: Icons.code_rounded,
              tooltip: 'Snippets de usuario',
              onPressed: () => openSnippetsManager(context),
            ),
            SqlToolBtn(
              icon: Icons.keyboard_outlined,
              tooltip: 'Atajos de teclado',
              onPressed: () => showSqlShortcutsDialog(context),
            ),
            _SqlTimeoutSelector(
              timeoutSeconds: timeoutSeconds,
              enabled: !running,
              onChanged: onTimeoutChanged,
            ),
            _SqlMaxRowsControl(
              maxRows: maxRows,
              enabled: !running,
              onMaxRowsChanged: onMaxRowsChanged,
            ),
            const SizedBox(width: 8),
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
            _buildSplitMenuBtn(cs, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitMenuBtn(ColorScheme cs, bool isDark) {
    final hasSplit = splitMode != EditorSplitMode.none;
    return PopupMenuButton<EditorSplitMode>(
      tooltip: hasSplit
          ? (splitMode == EditorSplitMode.vertical
                ? 'División vertical activa — Cambiar o cerrar'
                : 'División horizontal activa — Cambiar o cerrar')
          : 'Dividir editor en 2 vistas (mismo documento)',
      icon: Icon(
        splitMode == EditorSplitMode.vertical
            ? Icons.vertical_split_rounded
            : (splitMode == EditorSplitMode.horizontal
                  ? Icons.horizontal_split_rounded
                  : Icons.splitscreen_rounded),
        size: 15,
        color: hasSplit ? cs.primary : cs.onSurfaceVariant,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE),
          width: 0.8,
        ),
      ),
      onSelected: (mode) => onSplitModeChanged?.call(mode),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: EditorSplitMode.vertical,
          child: Row(
            children: [
              Icon(
                Icons.vertical_split_rounded,
                size: 16,
                color: splitMode == EditorSplitMode.vertical
                    ? cs.primary
                    : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Dividir a la derecha (Lado a lado)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: splitMode == EditorSplitMode.vertical
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              if (splitMode == EditorSplitMode.vertical) ...[
                const Spacer(),
                Icon(Icons.check_rounded, size: 14, color: cs.primary),
              ],
            ],
          ),
        ),
        PopupMenuItem(
          value: EditorSplitMode.horizontal,
          child: Row(
            children: [
              Icon(
                Icons.horizontal_split_rounded,
                size: 16,
                color: splitMode == EditorSplitMode.horizontal
                    ? cs.primary
                    : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Dividir abajo (Arriba y abajo)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: splitMode == EditorSplitMode.horizontal
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              if (splitMode == EditorSplitMode.horizontal) ...[
                const Spacer(),
                Icon(Icons.check_rounded, size: 14, color: cs.primary),
              ],
            ],
          ),
        ),
        if (hasSplit) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: EditorSplitMode.none,
            child: Row(
              children: [
                const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Color(0xFFE5484D),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Cerrar división',
                  style: TextStyle(fontSize: 12, color: Color(0xFFE5484D)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUnrunChangesDot(ColorScheme cs) {
    return Tooltip(
      message: 'Hay cambios sin ejecutar',
      waitDuration: kSqlTooltipWait,
      decoration: kSqlTooltipDecoration,
      textStyle: kSqlTooltipTextStyle,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFFFFB74D),
          shape: BoxShape.circle,
        ),
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

/// Selector de tiempo límite de ejecución (timeout) para la sesión SQL.
class _SqlTimeoutSelector extends StatelessWidget {
  final int timeoutSeconds;
  final bool enabled;
  final ValueChanged<int>? onChanged;

  const _SqlTimeoutSelector({
    required this.timeoutSeconds,
    required this.enabled,
    required this.onChanged,
  });

  static const List<int> _presets = [30, 60, 120, 300, 600, 1800, 3600, 7200];

  String _formatTimeout(int seconds) {
    if (seconds >= 3600) {
      final hours = seconds ~/ 3600;
      final remSec = seconds % 3600;
      if (remSec == 0) return '${hours}h';
      final mins = remSec ~/ 60;
      return '${hours}h ${mins}m';
    }
    if (seconds >= 60) {
      final mins = seconds ~/ 60;
      final remSec = seconds % 60;
      if (remSec == 0) return '${mins}m';
      return '${mins}m ${remSec}s';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final label = _formatTimeout(timeoutSeconds);

    return Tooltip(
      message: 'Tiempo límite de ejecución: $label\n(Click para cambiar)',
      waitDuration: kSqlTooltipWait,
      decoration: kSqlTooltipDecoration,
      textStyle: kSqlTooltipTextStyle,
      child: PopupMenuButton<int>(
        tooltip: '',
        enabled: enabled && onChanged != null,
        initialValue: timeoutSeconds,
        onSelected: (val) => onChanged?.call(val),
        color: isDark ? const Color(0xFF252526) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
            width: 0.8,
          ),
        ),
        position: PopupMenuPosition.under,
        itemBuilder: (ctx) => [
          const PopupMenuItem<int>(
            enabled: false,
            height: 28,
            child: Text(
              'TIEMPO LÍMITE (TIMEOUT)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Colors.grey,
              ),
            ),
          ),
          ..._presets.map((sec) {
            final isSelected = sec == timeoutSeconds;
            final secLabel = _formatTimeout(sec);
            final desc = sec == 30
                ? '30 segundos (rápido)'
                : sec == 60
                ? '60 segundos (estándar)'
                : sec == 120
                ? '2 minutos (consultas pesadas)'
                : sec == 300
                ? '5 minutos (reportes / DDL)'
                : sec == 600
                ? '10 minutos (scripts largos)'
                : sec == 1800
                ? '30 minutos (procesos masivos)'
                : sec == 3600
                ? '1 hora (procesos muy largos)'
                : '2 horas (migraciones / batch)';
            return PopupMenuItem<int>(
              value: sec,
              height: 32,
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 15,
                    color: isSelected ? cs.primary : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    secLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected ? cs.primary : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '— $desc',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.15),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 14,
                color: enabled
                    ? (isDark ? Colors.grey.shade300 : Colors.grey.shade700)
                    : Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? (isDark ? Colors.grey.shade200 : Colors.grey.shade800)
                      : Colors.grey,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 14,
                color: enabled ? Colors.grey : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selector de límite de filas (máximo de filas o "Sin límite")
/// configurable en cualquier momento, incluso antes de ejecutar la consulta.
class _SqlMaxRowsControl extends StatefulWidget {
  final int maxRows;
  final bool enabled;
  final ValueChanged<int>? onMaxRowsChanged;

  const _SqlMaxRowsControl({
    required this.maxRows,
    required this.enabled,
    required this.onMaxRowsChanged,
  });

  @override
  State<_SqlMaxRowsControl> createState() => _SqlMaxRowsControlState();
}

class _SqlMaxRowsControlState extends State<_SqlMaxRowsControl> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  int _lastFiniteMaxRows = 1000;

  @override
  void initState() {
    super.initState();
    if (widget.maxRows > 0) {
      _lastFiniteMaxRows = widget.maxRows;
    }
    _ctrl = TextEditingController(
      text: widget.maxRows == -1 ? '$_lastFiniteMaxRows' : '${widget.maxRows}',
    );
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(_SqlMaxRowsControl old) {
    super.didUpdateWidget(old);
    if (widget.maxRows > 0) {
      _lastFiniteMaxRows = widget.maxRows;
    }
    if (old.maxRows != widget.maxRows && !_focusNode.hasFocus) {
      _ctrl.text = widget.maxRows == -1
          ? '$_lastFiniteMaxRows'
          : '${widget.maxRows}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    if (widget.maxRows == -1 || !widget.enabled) return;
    final value = int.tryParse(_ctrl.text.trim());
    if (value == null || value <= 0) {
      _ctrl.text = '${widget.maxRows}';
      return;
    }
    _lastFiniteMaxRows = value;
    widget.onMaxRowsChanged?.call(value);
  }

  void _toggleUnlimited() {
    if (!widget.enabled || widget.onMaxRowsChanged == null) return;
    if (widget.maxRows == -1) {
      final restoreVal = _lastFiniteMaxRows > 0 ? _lastFiniteMaxRows : 1000;
      _ctrl.text = '$restoreVal';
      widget.onMaxRowsChanged?.call(restoreVal);
    } else {
      final current = int.tryParse(_ctrl.text.trim());
      if (current != null && current > 0) {
        _lastFiniteMaxRows = current;
      }
      widget.onMaxRowsChanged?.call(-1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isUnlimited = widget.maxRows == -1;
    final canEdit = widget.enabled && widget.onMaxRowsChanged != null;

    final borderColor = isDark
        ? const Color(0xFF3E3E42)
        : cs.outlineVariant.withValues(alpha: 0.7);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Límite',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isUnlimited
                ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                : (canEdit
                      ? cs.onSurfaceVariant
                      : cs.onSurfaceVariant.withValues(alpha: 0.5)),
          ),
        ),
        const SizedBox(width: 5),
        Tooltip(
          message: isUnlimited
              ? 'Límite deshabilitado (consultará todas las filas)'
              : 'Cantidad máxima de filas a consultar (1 - 100.000)',
          waitDuration: kSqlTooltipWait,
          decoration: kSqlTooltipDecoration,
          textStyle: kSqlTooltipTextStyle,
          child: Container(
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: isUnlimited
                  ? (isDark
                        ? cs.surfaceContainerHighest.withValues(alpha: 0.25)
                        : cs.surfaceContainerHigh.withValues(alpha: 0.35))
                  : (isDark ? const Color(0xFF0F1318) : Colors.white),
              border: Border.all(
                color: isUnlimited
                    ? borderColor.withValues(alpha: 0.4)
                    : borderColor,
                width: 0.8,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IntrinsicWidth(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    enabled: canEdit && !isUnlimited,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: isUnlimited
                          ? cs.onSurface.withValues(alpha: 0.38)
                          : (canEdit
                                ? cs.onSurface
                                : cs.onSurface.withValues(alpha: 0.5)),
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    onSubmitted: (_) => _commit(),
                    onTapOutside: (_) {
                      _commit();
                      _focusNode.unfocus();
                    },
                  ),
                ),
                Text(
                  ' filas',
                  style: TextStyle(
                    fontSize: 10,
                    color: isUnlimited
                        ? cs.onSurfaceVariant.withValues(alpha: 0.4)
                        : cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 5),
        Tooltip(
          message: isUnlimited
              ? 'Desactivar modo sin límite (restaurar límite manual)'
              : 'Sin límite de filas (consultar todos los registros)',
          waitDuration: kSqlTooltipWait,
          decoration: kSqlTooltipDecoration,
          textStyle: kSqlTooltipTextStyle,
          child: InkWell(
            onTap: canEdit ? _toggleUnlimited : null,
            borderRadius: BorderRadius.circular(6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 25,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: isUnlimited
                    ? cs.primary.withValues(alpha: isDark ? 0.25 : 0.15)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isUnlimited
                      ? cs.primary.withValues(alpha: 0.6)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.15)),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.all_inclusive_rounded,
                    size: 13,
                    color: isUnlimited
                        ? cs.primary
                        : (canEdit
                              ? cs.onSurfaceVariant
                              : cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Sin límite',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isUnlimited
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isUnlimited
                          ? cs.primary
                          : (canEdit
                                ? cs.onSurfaceVariant
                                : cs.onSurfaceVariant.withValues(alpha: 0.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Botón de ejecución primario con animación de pulso y spinner.
/// Cuando una ejecución está activa (`running == true`), se transforma en
/// un botón interactivo para detener/cancelar la operación.
class HeroExecuteBtn extends StatefulWidget {
  final bool running;
  final VoidCallback? onPressed;
  final VoidCallback? onCancel;
  final String tooltip;
  final DateTime? runStartedAt;

  const HeroExecuteBtn({
    super.key,
    required this.running,
    required this.onPressed,
    this.onCancel,
    required this.tooltip,
    this.runStartedAt,
  });

  @override
  State<HeroExecuteBtn> createState() => _HeroExecuteBtnState();
}

class _HeroExecuteBtnState extends State<HeroExecuteBtn> {
  bool _hovered = false;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void didUpdateWidget(HeroExecuteBtn old) {
    super.didUpdateWidget(old);
    if (widget.running && !old.running) {
      _elapsed = Duration.zero;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final startedAt = widget.runStartedAt;
        if (!mounted || startedAt == null) return;
        setState(() => _elapsed = DateTime.now().difference(startedAt));
      });
    } else if (!widget.running && old.running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCancelAction = widget.running && widget.onCancel != null;
    final enabled =
        isCancelAction || (widget.onPressed != null && !widget.running);

    final tooltipMessage = widget.running
        ? 'Detener ejecución (Escape)'
        : widget.tooltip;

    final Color cancelColor = isDark
        ? const Color(0xFFF87171)
        : const Color(0xFFDC2626);

    return Tooltip(
      message: tooltipMessage,
      waitDuration: kSqlTooltipWait,
      preferBelow: false,
      decoration: kSqlTooltipDecoration,
      textStyle: kSqlTooltipTextStyle,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.running
              ? widget.onCancel
              : (enabled ? widget.onPressed : null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: widget.running
                  ? cancelColor.withValues(
                      alpha: _hovered
                          ? (isDark ? 0.28 : 0.2)
                          : (isDark ? 0.16 : 0.1),
                    )
                  : (_hovered && enabled
                        ? cs.primary.withValues(alpha: isDark ? 0.22 : 0.15)
                        : cs.primaryContainer.withValues(
                            alpha: isDark ? 0.2 : 0.35,
                          )),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.running
                    ? cancelColor.withValues(
                        alpha: _hovered
                            ? (isDark ? 0.85 : 0.75)
                            : (isDark ? 0.5 : 0.4),
                      )
                    : (_hovered && enabled
                          ? cs.primary.withValues(alpha: 0.7)
                          : cs.outlineVariant.withValues(alpha: 0.7)),
                width: 0.8,
              ),
              boxShadow: _hovered && enabled
                  ? [
                      BoxShadow(
                        color: (widget.running ? cancelColor : cs.primary)
                            .withValues(alpha: 0.2),
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
                            color: cancelColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.runStartedAt == null
                              ? 'Detener'
                              : 'Detener (${(_elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cancelColor,
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

const List<(String, String)> _kSqlShortcuts = [
  ('Ctrl + Enter', 'Ejecutar sentencia actual / selección'),
  ('F5', 'Ejecutar todo el script'),
  ('Escape', 'Detener / cancelar ejecución activa'),
  ('Ctrl + S', 'Guardar archivo local'),
  ('Ctrl + Shift + S', 'Guardar archivo local como…'),
  ('Ctrl + F', 'Buscar en el documento'),
  ('F12', 'Ir a definición'),
  ('Alt + I', 'Información del evento'),
  ('Alt + D', 'Información del dato'),
  ('Alt + R', 'Ejecutar procedimiento dinámico…'),
  ('Ctrl + Shift + E', 'Ejecutar objeto PL/SQL…'),
  ('Alt + E', 'Consultar evento…'),
  ('Alt + A', 'Consultar autorizaciones…'),
];

/// Muestra un diálogo con los atajos de teclado disponibles en el editor.
void showSqlShortcutsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Atajos de teclado'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (keys, desc) in _kSqlShortcuts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          ctx,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        keys,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(desc)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
