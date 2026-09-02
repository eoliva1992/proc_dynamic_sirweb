import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_diff_viewer.dart';

/// Abre un modal con el diff de un procedimiento.
///
/// Usa el mismo visor nativo (`NativeDiffViewer`) que el diff del editor de
/// fuentes de procedimientos/packages, por lo que comparte sus características:
/// navegación entre hunks, colapsado de secciones sin cambios, resaltado
/// intra-línea, vista dividida/unificada y atajos de teclado.
Future<void> showProcedureDiff(
  BuildContext context, {
  required String title,
  required String original,
  required String modified,
  required String language, // 'sql' | 'javascript'
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'diff-dismiss',
    barrierColor: Colors.black54,
    builder: (_) => _DiffDialog(
      title: title,
      original: original,
      modified: modified,
      language: language,
    ),
  );
}

class _DiffDialog extends StatefulWidget {
  final String title;
  final String original;
  final String modified;
  final String language;

  const _DiffDialog({
    required this.title,
    required this.original,
    required this.modified,
    required this.language,
  });

  @override
  State<_DiffDialog> createState() => _DiffDialogState();
}

class _DiffDialogState extends State<_DiffDialog> {
  // Claves de persistencia (mismo estilo que las prefs del editor: 'editor_*').
  static const _kPrefSideBySide = 'diff_side_by_side';
  static const _kPrefShowAllLines = 'diff_show_all_lines';

  // Por defecto: vista unificada y código completo (no solo los diffs).
  // Si el usuario cambió la vista antes, se restaura desde SharedPreferences.
  bool _sideBySide = false;
  bool _showAllLines = true;

  /// Modal contenido (false) vs. ocupando toda la ventana (true).
  bool _maximized = false;

  final _diffCtrl = NativeDiffController();
  late final ({int added, int removed}) _stats;

  /// Conteo de líneas agregadas/eliminadas usando los mismos hunks que dibuja
  /// el visor, para que el badge coincida exactamente con lo mostrado.
  static ({int added, int removed}) _computeStats(String a, String b) {
    if (a == b) return (added: 0, removed: 0);
    var added = 0, removed = 0;
    for (final h in computeHunks(a, b)) {
      removed += h.origEnd - h.origStart;
      added += h.modEnd - h.modStart;
    }
    return (added: added, removed: removed);
  }

  @override
  void initState() {
    super.initState();
    _stats = _computeStats(widget.original, widget.modified);
    _loadPrefs();
  }

  @override
  void dispose() {
    _diffCtrl.dispose();
    super.dispose();
  }

  // ── Persistencia de la vista elegida ─────────────────────────────────────

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final sideBySide = prefs.getBool(_kPrefSideBySide);
      final showAllLines = prefs.getBool(_kPrefShowAllLines);
      if (sideBySide == null && showAllLines == null) return;
      setState(() {
        _sideBySide = sideBySide ?? _sideBySide;
        _showAllLines = showAllLines ?? _showAllLines;
      });
    } catch (_) {
      // Sin storage disponible — se mantienen los valores por defecto.
    }
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefSideBySide, _sideBySide);
      await prefs.setBool(_kPrefShowAllLines, _showAllLines);
    } catch (_) {
      // Persistencia best-effort: no debe romper la UI del diff.
    }
  }

  void _toggleShowAllLines() {
    setState(() => _showAllLines = !_showAllLines);
    _savePrefs();
  }

  void _toggleSideBySide() {
    setState(() => _sideBySide = !_sideBySide);
    _savePrefs();
  }

  void _nextChange() => _diffCtrl.nextChange();
  void _prevChange() => _diffCtrl.previousChange();

  void _toggleMaximized() => setState(() => _maximized = !_maximized);

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('$label copiado al portapapeles'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);

    // Modal contenido: ocupa el 90% de la ventana con un tope razonable en
    // pantallas grandes. "Maximizar" lo lleva a pantalla completa.
    final width = _maximized ? screen.width : (screen.width * 0.9).clamp(360.0, 1600.0);
    final height = _maximized ? screen.height : (screen.height * 0.9).clamp(320.0, 1100.0);
    final radius = _maximized ? 0.0 : 10.0;

    return Dialog(
      insetPadding: _maximized
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints.tight(Size(width, height)),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
                _prevChange,
            const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                _nextChange,
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).maybePop(),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                _buildToolbar(isDark, cs),
                Expanded(
                  child: NativeDiffViewer(
                    origText: widget.original,
                    modText: widget.modified,
                    sideBySide: _sideBySide,
                    showAllLines: _showAllLines,
                    controller: _diffCtrl,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────────────────

  Widget _buildToolbar(bool isDark, ColorScheme cs) {
    final divColor = cs.outlineVariant;

    // En ventanas angostas los controles con etiqueta no entran: se colapsan
    // a sólo icono (el tooltip conserva la descripción completa).
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 880;
        return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
        border: Border(bottom: BorderSide(color: divColor)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Cerrar',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              widget.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                widget.language.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          _buildStats(),

          const Spacer(),

          // ── Navegación entre hunks (igual que el diff de fuentes) ────────
          _vSep(divColor),
          _tbBtn(
            tooltip: 'Cambio anterior  (Alt+↑)',
            icon: Icons.keyboard_arrow_up,
            onTap: _prevChange,
          ),
          ListenableBuilder(
            listenable: _diffCtrl,
            builder: (_, _) {
              final tot = _diffCtrl.totalHunks;
              final cur = _diffCtrl.currentHunk;
              return Container(
                constraints: BoxConstraints(minWidth: compact ? 46 : 62),
                alignment: Alignment.center,
                child: tot == 0
                    ? Text(
                        '✓ Sin cambios',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text(
                        '${cur + 1} / $tot',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              );
            },
          ),
          _tbBtn(
            tooltip: 'Siguiente cambio  (Alt+↓)',
            icon: Icons.keyboard_arrow_down,
            onTap: _nextChange,
          ),
          _vSep(divColor),

          // ── Solo diffs / Código completo ────────────────────────────────
          Tooltip(
            message: _showAllLines
                ? 'Mostrar solo diffs'
                : 'Mostrar código completo',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _toggleShowAllLines,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _showAllLines
                          ? Icons.article_outlined
                          : Icons.difference_outlined,
                      size: 14,
                      color: _showAllLines
                          ? Colors.amber.shade600
                          : cs.onSurfaceVariant,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 4),
                      Text(
                        _showAllLines ? 'Completo' : 'Solo diffs',
                        style: TextStyle(
                          fontSize: 11,
                          color: _showAllLines
                              ? Colors.amber.shade600
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _vSep(divColor),

          // ── Vista dividida / unificada ──────────────────────────────────
          Tooltip(
            message: _sideBySide ? 'Vista unificada' : 'Vista lado a lado',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _toggleSideBySide,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _sideBySide
                          ? Icons.view_agenda_outlined
                          : Icons.view_sidebar_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 4),
                      Text(
                        _sideBySide ? 'Dividida' : 'Unificada',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _vSep(divColor),

          // ── Copiar versiones ────────────────────────────────────────────
          Tooltip(
            message: 'Copiar código (guardado / actual)',
            child: PopupMenuButton<String>(
              tooltip: '',
              icon: Icon(Icons.copy_rounded, size: 15, color: cs.onSurfaceVariant),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              onSelected: (v) => v == 'orig'
                  ? _copy(widget.original, 'Código guardado')
                  : _copy(widget.modified, 'Código actual'),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'orig',
                  child: Text('Copiar versión guardada',
                      style: TextStyle(fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'mod',
                  child: Text('Copiar versión actual (editor)',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          _vSep(divColor),
          _tbBtn(
            tooltip: _maximized ? 'Restaurar tamaño' : 'Maximizar',
            icon: _maximized
                ? Icons.close_fullscreen_rounded
                : Icons.open_in_full_rounded,
            onTap: _toggleMaximized,
            size: 14,
          ),
          const SizedBox(width: 4),
        ],
      ),
        );
      },
    );
  }

  Widget _buildStats() {
    if (_stats.added == 0 && _stats.removed == 0) {
      return Text(
        'sin cambios',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade600,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_stats.added > 0)
          Text(
            '+${_stats.added}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.green.shade500,
              fontWeight: FontWeight.w600,
              fontFamily: 'Consolas',
            ),
          ),
        if (_stats.removed > 0) ...[
          const SizedBox(width: 4),
          Text(
            '-${_stats.removed}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.red.shade400,
              fontWeight: FontWeight.w600,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ],
    );
  }

  Widget _vSep(Color c) => Container(
        width: 1,
        height: 18,
        color: c,
        margin: const EdgeInsets.symmetric(horizontal: 2),
      );

  Widget _tbBtn({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    double size = 16,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Icon(
            icon,
            size: size,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
