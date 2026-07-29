import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:re_highlight/styles/github.dart';
import 'package:provider/provider.dart';
import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import 'config_badge.dart';

part '_editor_status_bar.dart';
part '_editor_autocomplete.dart';
part '_editor_config_widgets.dart';
part '_editor_syntax_checker.dart';
part '_editor_toolbar.dart';
part '_editor_find_bar.dart';

class CodeEditorPanel extends StatefulWidget {
  final Procedimiento procedimiento;

  const CodeEditorPanel({super.key, required this.procedimiento});

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
  late CodeLineEditingController _codeController;
  late String _selectedConfig;

  // Notifier directo para que el gutter escuche cambios sin depender
  // de la cadena de reconstrucción de widgets de CodeEditor.
  final ValueNotifier<List<_SyntaxError>> _errorsNotifier = ValueNotifier([]);

  List<_SyntaxError> get _syntaxErrors => _errorsNotifier.value;

  Timer? _debounceTimer;

  // ── Toolbar state ─────────────────────────────────────────────────────────
  int _zoomPercent = 100;
  bool _showSpaces = false;
  bool _showTabs = false;
  bool _showLineEndings = false;

  // Capturado desde findBuilder; CodeEditor gestiona el ciclo de vida.
  CodeFindController? _internalFindCtrl;

  CodeChunkController? _chunkController;

  double get _effectiveFontSize => 13.0 * _zoomPercent / 100;

  @override
  void initState() {
    super.initState();
    _selectedConfig = widget.procedimiento.inConfiguracion;
    _codeController = CodeLineEditingController(
      codeLines: CodeLines.fromText(widget.procedimiento.deTexto),
      spanBuilder: _buildWhitespaceSpan,
    );
    _codeController.addListener(_onCodeChanged);
    _runCheck();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _internalFindCtrl?.removeListener(_onFindChanged);
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _errorsNotifier.dispose();
    super.dispose();
  }

  void _onFindChanged() {
    // Defer to avoid markNeedsBuild during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _onCodeChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), _runCheck);
  }

  void _runCheck() {
    if (!mounted) return;
    final errors = _SyntaxChecker.check(
      _codeController.text,
      isJs: _selectedConfig == 'J',
    );
    // Actualiza el notifier → el gutter repinta directamente
    _errorsNotifier.value = errors;
    // Actualiza el estado → el panel de errores se reconstruye
    setState(() {});
  }

  Mode _languageForConfig(String config) {
    return config == 'J' ? langJavascript : langSql;
  }

  void _onConfigChanged(String newConfig) {
    setState(() {
      _selectedConfig = newConfig;
    });
    _runCheck();
  }

  // ── Whitespace span builder ───────────────────────────────────────────────

  TextSpan _buildWhitespaceSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    if (!_showSpaces && !_showTabs && !_showLineEndings) return textSpan;
    // Unused: context is kept for future theme-aware adjustments.
    // High-contrast teal — stays vivid on both dark and light backgrounds.
    const Color wsColor = Color(0xFF4EC9B0);
    final double baseSize = style.fontSize ?? _effectiveFontSize;
    // Tabs and enters are 15% larger + bold so they stand out immediately.
    final TextStyle bigStyle = TextStyle(
      color: wsColor,
      fontFamily: 'Consolas',
      fontSize: baseSize * 1.15,
      fontWeight: FontWeight.bold,
    );
    final TextStyle dotStyle = TextStyle(
      color: wsColor,
      fontFamily: 'Consolas',
      fontSize: baseSize,
    );
    TextSpan result = (_showSpaces || _showTabs)
        ? _annotateSpanTree(textSpan, dotStyle, bigStyle)
        : textSpan;
    if (_showLineEndings) {
      result = TextSpan(
        children: [
          result,
          TextSpan(text: '↵', style: bigStyle),
        ],
      );
    }
    return result;
  }

  TextSpan _annotateSpanTree(
    TextSpan span,
    TextStyle dotStyle,
    TextStyle bigStyle,
  ) {
    if (span.children == null || span.children!.isEmpty) {
      return _annotateLeafSpan(span, dotStyle, bigStyle);
    }
    final newChildren = span.children!.map((child) {
      if (child is TextSpan) {
        return _annotateSpanTree(child, dotStyle, bigStyle);
      }
      return child;
    }).toList();
    return TextSpan(text: span.text, style: span.style, children: newChildren);
  }

  TextSpan _annotateLeafSpan(
    TextSpan span,
    TextStyle dotStyle,
    TextStyle bigStyle,
  ) {
    final text = span.text ?? '';
    if (text.isEmpty) return span;
    final bool needsSpace = _showSpaces && text.contains(' ');
    final bool needsTab = _showTabs && text.contains('\t');
    if (!needsSpace && !needsTab) return span;
    final List<InlineSpan> parts = [];
    int start = 0;
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      final isWs = (ch == ' ' && _showSpaces) || (ch == '\t' && _showTabs);
      if (isWs) {
        if (i > start) {
          parts.add(
            TextSpan(text: text.substring(start, i), style: span.style),
          );
        }
        // Space → middle-dot (·), Tab → bold arrow (→)
        parts.add(
          TextSpan(
            text: ch == ' ' ? '·' : '→',
            style: ch == ' ' ? dotStyle : bigStyle,
          ),
        );
        start = i + 1;
      }
    }
    if (start < text.length) {
      parts.add(TextSpan(text: text.substring(start), style: span.style));
    }
    if (parts.length == 1 && parts.first is TextSpan) {
      return parts.first as TextSpan;
    }
    return TextSpan(children: parts);
  }

  // ── Comment formatter per config ─────────────────────────────────────────

  CodeCommentFormatter get _commentFormatter => DefaultCodeCommentFormatter(
    singleLinePrefix: _selectedConfig == 'J' ? '//' : '--',
  );

  // ── Toolbar action methods ────────────────────────────────────────────────

  void _toggleComment() {
    final newValue = _commentFormatter.format(
      _codeController.value,
      _codeController.options.indent,
      true,
    );
    _codeController.runRevocableOp(() => _codeController.value = newValue);
  }

  void _toUpperCase() {
    final sel = _codeController.selectedText;
    if (sel.isEmpty) return;
    _codeController.runRevocableOp(
      () => _codeController.replaceSelection(sel.toUpperCase()),
    );
  }

  void _toLowerCase() {
    final sel = _codeController.selectedText;
    if (sel.isEmpty) return;
    _codeController.runRevocableOp(
      () => _codeController.replaceSelection(sel.toLowerCase()),
    );
  }

  void _collapseAll() {
    final ctrl = _chunkController;
    if (ctrl == null) return;
    final chunks = List.of(ctrl.value);
    for (final chunk in chunks.reversed) {
      if (ctrl.canCollapse(chunk.index)) ctrl.collapse(chunk.index);
    }
  }

  void _expandAll() {
    final ctrl = _chunkController;
    if (ctrl == null) return;
    final lines = _codeController.codeLines;
    for (int i = lines.length - 1; i >= 0; i--) {
      if (lines[i].chunkParent) ctrl.expand(i);
    }
  }

  void _toggleShowSpaces() {
    setState(() => _showSpaces = !_showSpaces);
    _codeController.forceRepaint();
  }

  void _toggleShowTabs() {
    setState(() => _showTabs = !_showTabs);
    _codeController.forceRepaint();
  }

  void _toggleShowLineEndings() {
    setState(() => _showLineEndings = !_showLineEndings);
    _codeController.forceRepaint();
  }

  static const _zoomLevels = [50, 75, 90, 100, 110, 125, 150, 175, 200];

  void _decreaseZoom() {
    final idx = _zoomLevels.indexOf(_zoomPercent);
    if (idx > 0) setState(() => _zoomPercent = _zoomLevels[idx - 1]);
  }

  void _increaseZoom() {
    final idx = _zoomLevels.indexOf(_zoomPercent);
    if (idx < _zoomLevels.length - 1) {
      setState(() => _zoomPercent = _zoomLevels[idx + 1]);
    }
  }

  void _showVariablesModal() {
    final provider = context.read<ProcedimientosProvider>();
    final vars = provider.variablesDinamicas
        .where((v) => v.inConfiguracion == _selectedConfig)
        .toList();
    final isJs = _selectedConfig == 'J';
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    border: Border(
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.data_object,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Variables — ${isJs ? 'JavaScript' : 'PL/SQL'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${vars.length} variable${vars.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, size: 16),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(28, 28),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                // List
                if (vars.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Sin variables para esta configuración.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(8),
                      shrinkWrap: true,
                      itemCount: vars.length,
                      separatorBuilder: (context2, index2) =>
                          Divider(height: 1, color: theme.dividerColor),
                      itemBuilder: (ctx, i) {
                        final v = vars[i];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFD7BA7D,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              ':${v.cdVariable}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'Consolas',
                                color: Color(0xFFD7BA7D),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          title: Text(
                            v.deVariable.isEmpty ? '—' : v.deVariable,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ),
                          trailing: Tooltip(
                            message: 'Insertar en el cursor',
                            child: IconButton(
                              onPressed: () {
                                _codeController.replaceSelection(
                                  ':${v.cdVariable}',
                                );
                                Navigator.pop(ctx);
                              },
                              icon: const Icon(Icons.add, size: 14),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(28, 28),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Find bar builder ─────────────────────────────────────────────────────

  PreferredSizeWidget _buildFindBar(
    BuildContext context,
    CodeFindController controller,
    bool readonly,
  ) {
    // Capture the internal find controller provided by CodeEditor.
    // This runs during CodeEditor's build(), so we must NOT call setState here.
    // We swap the listener reference if the controller instance changes.
    if (_internalFindCtrl != controller) {
      _internalFindCtrl?.removeListener(_onFindChanged);
      _internalFindCtrl = controller;
      _internalFindCtrl!.addListener(_onFindChanged);
    }
    return _FindBar(controller: controller, readonly: readonly);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProcedimientosProvider>(
      builder: (context, provider, _) {
        if (provider.cargandoEditor) {
          return Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          );
        }

        return Column(
          children: [
            _buildHeader(context, provider),
            if (provider.error != null || provider.mensaje != null)
              _buildBanner(provider),
            _buildToolbar(context),
            Expanded(child: _buildEditor(context)),
          ],
        );
      },
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────────────────

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final toolbarBg = isDark
        ? const Color(0xFF2D2D2D)
        : const Color(0xFFF0F0F0);
    final isJs = _selectedConfig == 'J';

    // Read state directly — toolbar is rebuilt whenever setState is called
    // (from _onCodeChanged, _onFindChanged, or whitespace toggles).
    final canUndo = _codeController.canUndo;
    final canRedo = _codeController.canRedo;
    final hasSel = !_codeController.selection.isCollapsed;
    final findVal = _internalFindCtrl?.value;
    final findOpen = findVal != null && !findVal.replaceMode;
    final replaceOpen = findVal?.replaceMode == true;

    return Container(
      height: 36,
      color: toolbarBg,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          // ── Historial ─────────────────────────────────────────────
          _TbBtn(
            icon: Icons.undo,
            tooltip: 'Deshacer (Ctrl+Z)',
            onPressed: canUndo ? _codeController.undo : null,
          ),
          _TbBtn(
            icon: Icons.redo,
            tooltip: 'Rehacer (Ctrl+Y)',
            onPressed: canRedo ? _codeController.redo : null,
          ),
          const _TbDivider(),
          // ── Portapapeles ──────────────────────────────────────────
          _TbBtn(
            icon: Icons.content_copy,
            tooltip: 'Copiar (Ctrl+C)',
            onPressed: () => _codeController.copy(),
          ),
          _TbBtn(
            icon: Icons.content_cut,
            tooltip: 'Cortar (Ctrl+X)',
            onPressed: _codeController.cut,
          ),
          _TbBtn(
            icon: Icons.content_paste,
            tooltip: 'Pegar (Ctrl+V)',
            onPressed: _codeController.paste,
          ),
          const _TbDivider(),
          // ── Edición ───────────────────────────────────────────────
          _TbBtn(
            icon: Icons.code,
            tooltip: isJs
                ? 'Comentar/Descomentar // (Ctrl+/)'
                : 'Comentar/Descomentar -- (Ctrl+/)',
            onPressed: _toggleComment,
          ),
          _TbBtn(
            icon: Icons.format_indent_increase,
            tooltip: 'Indentar (Tab)',
            onPressed: _codeController.applyIndent,
          ),
          const _TbDivider(),
          // ── Transformar ───────────────────────────────────────────
          _TbBtn(
            icon: Icons.text_fields,
            tooltip: 'Convertir a MAYÚSCULAS',
            onPressed: hasSel ? _toUpperCase : null,
          ),
          _TbBtn(
            icon: Icons.text_format,
            tooltip: 'Convertir a minúsculas',
            onPressed: hasSel ? _toLowerCase : null,
          ),
          const _TbDivider(),
          // ── Blancos ───────────────────────────────────────────────
          _TbBtn(
            icon: Icons.space_bar,
            tooltip: 'Mostrar espacios',
            onPressed: _toggleShowSpaces,
            active: _showSpaces,
          ),
          _TbBtn(
            icon: Icons.keyboard_return,
            tooltip: 'Mostrar saltos de línea',
            onPressed: _toggleShowLineEndings,
            active: _showLineEndings,
          ),
          _TbBtn(
            icon: Icons.keyboard_tab,
            tooltip: 'Mostrar tabulaciones',
            onPressed: _toggleShowTabs,
            active: _showTabs,
          ),
          const _TbDivider(),
          // ── Pliegue ───────────────────────────────────────────────
          _TbBtn(
            icon: Icons.unfold_less,
            tooltip: 'Colapsar todo',
            onPressed: _collapseAll,
          ),
          _TbBtn(
            icon: Icons.unfold_more,
            tooltip: 'Expandir todo',
            onPressed: _expandAll,
          ),
          const _TbDivider(),
          // ── Buscar / Reemplazar ───────────────────────────────────
          _TbBtn(
            icon: Icons.search,
            tooltip: 'Buscar (Ctrl+F)',
            onPressed: _internalFindCtrl == null
                ? null
                : findOpen
                ? _internalFindCtrl!.close
                : _internalFindCtrl!.findMode,
            active: findOpen,
          ),
          _TbBtn(
            icon: Icons.find_replace,
            tooltip: 'Buscar y reemplazar (Ctrl+H)',
            onPressed: _internalFindCtrl == null
                ? null
                : replaceOpen
                ? _internalFindCtrl!.close
                : _internalFindCtrl!.replaceMode,
            active: replaceOpen,
          ),
          const _TbDivider(),
          // ── Variables ─────────────────────────────────────────────
          _TbBtn(
            icon: Icons.data_object,
            tooltip: 'Variables dinámicas disponibles',
            onPressed: _showVariablesModal,
          ),
          const Spacer(),
          // ── Zoom ──────────────────────────────────────────────────
          _TbBtn(
            icon: Icons.remove,
            tooltip: 'Reducir zoom',
            onPressed: _zoomPercent > _zoomLevels.first ? _decreaseZoom : null,
          ),
          _ZoomSelector(
            value: _zoomPercent,
            onChanged: (p) => setState(() => _zoomPercent = p),
          ),
          _TbBtn(
            icon: Icons.add,
            tooltip: 'Aumentar zoom',
            onPressed: _zoomPercent < _zoomLevels.last ? _increaseZoom : null,
          ),
          const _TbDivider(),
          // ── Indicador de lenguaje ─────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: (isJs ? const Color(0xFFF7DF1E) : const Color(0xFF336791))
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color:
                    (isJs ? const Color(0xFFF7DF1E) : const Color(0xFF336791))
                        .withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              isJs ? 'JavaScript' : 'PL/SQL',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w600,
                color: isJs ? const Color(0xFFC8A800) : const Color(0xFF5596C0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ProcedimientosProvider provider) {
    final proc = widget.procedimiento;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => provider.volver(),
            icon: const Icon(Icons.arrow_back, size: 20),
            color: onSurface.withValues(alpha: 0.5),
            tooltip: 'Volver a la lista',
            style: IconButton.styleFrom(
              minimumSize: const Size(32, 32),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proc.cdProcedimiento,
                  style: TextStyle(
                    color: onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'Consolas',
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'v${proc.version}',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 11,
                      ),
                    ),
                    if (proc.feModificacion != null) ...[
                      Text(
                        '  ·  ',
                        style: TextStyle(color: theme.dividerColor),
                      ),
                      Text(
                        proc.feModificacion!,
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (proc.cdUsuario != null) ...[
                      Text(
                        '  ·  ',
                        style: TextStyle(color: theme.dividerColor),
                      ),
                      Text(
                        proc.cdUsuario!,
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Config selector
          _ConfigSelector(
            value: _selectedConfig,
            onChanged: _onConfigChanged,
            isNuevo: proc.version == 0,
          ),
          const SizedBox(width: 12),
          // Estado badge
          _EstadoChip(activo: proc.activo),
          const SizedBox(width: 12),
          // Action buttons
          _buildActionButtons(context, provider),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    ProcedimientosProvider provider,
  ) {
    final proc = widget.procedimiento;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: provider.cargando
              ? null
              : () async {
                  await provider.guardar(
                    deTexto: _codeController.text,
                    inConfiguracion: _selectedConfig,
                  );
                },
          icon: provider.cargando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save, size: 16),
          label: const Text('Guardar', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0078D4),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
        const SizedBox(width: 8),
        if (!proc.activo)
          OutlinedButton.icon(
            onPressed: provider.cargando ? null : () => provider.activar(),
            icon: const Icon(Icons.play_circle_outline, size: 16),
            label: const Text('Activar', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green.shade400,
              side: BorderSide(color: Colors.green.shade700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: provider.cargando ? null : () => provider.desactivar(),
            icon: const Icon(Icons.pause_circle_outline, size: 16),
            label: const Text('Desactivar', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange.shade400,
              side: BorderSide(color: Colors.orange.shade700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
      ],
    );
  }

  Widget _buildBanner(ProcedimientosProvider provider) {
    final isError = provider.error != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: isError
          ? Colors.red.withValues(alpha: 0.1)
          : Colors.green.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: isError ? Colors.red.shade400 : Colors.green.shade400,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isError ? provider.error! : provider.mensaje!,
              style: TextStyle(
                color: isError ? Colors.red.shade700 : Colors.green.shade700,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            onPressed: provider.limpiarMensajes,
            icon: const Icon(Icons.close, size: 14),
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
            style: IconButton.styleFrom(
              minimumSize: const Size(24, 24),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final gutterBg = isDark ? const Color(0xFF252526) : const Color(0xFFF0F0F0);
    final gutterColor = theme.colorScheme.onSurface.withValues(alpha: 0.35);
    final provider = context.read<ProcedimientosProvider>();

    return Column(
      children: [
        Expanded(
          child: CodeAutocomplete(
            viewBuilder: (context, notifier, onSelect) {
              return _AutocompletePopup(notifier: notifier, onSelect: onSelect);
            },
            promptsBuilder: _VarAwarePromptsBuilder(
              provider: provider,
              selectedConfig: _selectedConfig,
              syntaxBuilder: DefaultCodeAutocompletePromptsBuilder(
                language: _languageForConfig(_selectedConfig),
              ),
            ),
            child: CodeEditor(
              controller: _codeController,
              findBuilder: _buildFindBar,
              commentFormatter: _commentFormatter,
              wordWrap: false,
              style: CodeEditorStyle(
                fontSize: _effectiveFontSize,
                fontFamily: 'Consolas',
                fontHeight: 1.5,
                backgroundColor: theme.scaffoldBackgroundColor,
                codeTheme: CodeHighlightTheme(
                  languages: {
                    'sql': CodeHighlightThemeMode(mode: langSql),
                    'javascript': CodeHighlightThemeMode(mode: langJavascript),
                  },
                  theme: isDark ? vs2015Theme : githubTheme,
                ),
              ),
              chunkAnalyzer: _selectedConfig == 'J'
                  ? const DefaultCodeChunkAnalyzer()
                  : const _SqlChunkAnalyzer(),
              indicatorBuilder: (ctx, editCtrl, chunkCtrl, notifier) {
                _chunkController = chunkCtrl;
                return Row(
                  children: [
                    Container(
                      color: gutterBg,
                      child: DefaultCodeLineNumber(
                        controller: editCtrl,
                        notifier: notifier,
                        textStyle: TextStyle(
                          color: gutterColor,
                          fontSize: 12,
                          fontFamily: 'Consolas',
                        ),
                        focusedTextStyle: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),
                    Container(
                      color: gutterBg,
                      child: DefaultCodeChunkIndicator(
                        width: 14,
                        controller: chunkCtrl,
                        notifier: notifier,
                      ),
                    ),
                    Container(
                      color: gutterBg,
                      child: _ErrorGutterIndicator(
                        errorsNotifier: _errorsNotifier,
                        notifier: notifier,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        if (_syntaxErrors.isNotEmpty) _buildErrorPanel(context),
        _EditorStatusBar(controller: _codeController),
      ],
    );
  }

  Widget _buildErrorPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);

    return Container(
      constraints: const BoxConstraints(maxHeight: 130),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 13,
                  color: Color(0xFFFF6B6B),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_syntaxErrors.length} error${_syntaxErrors.length == 1 ? '' : 'es'} de sintaxis',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFF6B6B),
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _syntaxErrors.length,
              itemBuilder: (ctx, i) {
                final e = _syntaxErrors[i];
                return InkWell(
                  onTap: () {
                    final maxIndex = _codeController.codeLines.length - 1;
                    final lineIndex = (e.line - 1).clamp(0, maxIndex);
                    final lineText = _codeController.codeLines[lineIndex].text;
                    final col = (e.col - 1).clamp(0, lineText.length);
                    _codeController.selection = CodeLineSelection.collapsed(
                      index: lineIndex,
                      offset: col,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            'L${e.line}:${e.col}',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Consolas',
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            e.message,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Consolas',
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.75,
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status Bar del editor ─────────────────────────────────────────────────────

// ── Folding SQL: BEGIN / IF / LOOP / CASE ────────────────────────────────────
// Reglas Oracle PL/SQL:
//   Abren bloque : BEGIN  |  IF...THEN  |  ...LOOP (al final de línea)  |  CASE (inicio de línea)
//   Cierran bloque: cualquier línea que empiece con END
//   NO abren bloque: ELSIF, ELSE, EXCEPTION, DECLARE, THEN, WHEN

// ── Builder combinado: variables + sintaxis ───────────────────────────────────
// El DefaultCodeAutocompletePromptsBuilder extrae input usando solo [A-Za-z_],
// por lo que el ':' nunca llega al match(). Este builder lo detecta manualmente.
//
// El editor aplica el resultado así:
//   controller.replaceSelection(result.word, selection con startOffset = cursor - result.input.length)
//   controller.selection = selection + result.selection (relativo a la posición post-reemplazo)

// ── Prompt personalizado para variables dinámicas ────────────────────────────

// ── Popup de autocomplete ────────────────────────────────────────────────────

// ── Modelo y checker de errores de sintaxis ───────────────────────────────────

class _SyntaxChecker {
  static List<_SyntaxError> check(String code, {required bool isJs}) =>
      isJs ? _checkJs(code) : _checkSql(code);

  // ── PL/SQL ──────────────────────────────────────────────────────────────────

  static List<_SyntaxError> _checkSql(String code) {
    final errors = <_SyntaxError>[];
    final lines = code.split('\n');

    final parenStack = <(int, int)>[];
    bool inString = false;
    bool inBlockComment = false;

    for (int li = 0; li < lines.length; li++) {
      final line = lines[li];
      int ci = 0;
      while (ci < line.length) {
        if (inBlockComment) {
          if (ci + 1 < line.length && line[ci] == '*' && line[ci + 1] == '/') {
            inBlockComment = false;
            ci += 2;
          } else {
            ci++;
          }
          continue;
        }
        if (inString) {
          if (line[ci] == '\'') {
            if (ci + 1 < line.length && line[ci + 1] == '\'') {
              ci += 2; // escaped ''
            } else {
              inString = false;
              ci++;
            }
          } else {
            ci++;
          }
          continue;
        }
        if (ci + 1 < line.length && line[ci] == '/' && line[ci + 1] == '*') {
          inBlockComment = true;
          ci += 2;
          continue;
        }
        if (ci + 1 < line.length && line[ci] == '-' && line[ci + 1] == '-') {
          break; // rest is line comment
        }
        switch (line[ci]) {
          case '\'':
            inString = true;
          case '(':
            parenStack.add((li + 1, ci + 1));
          case ')':
            if (parenStack.isEmpty) {
              errors.add(
                _SyntaxError(
                  line: li + 1,
                  col: ci + 1,
                  message: ") sin ( correspondiente",
                ),
              );
            } else {
              parenStack.removeLast();
            }
        }
        ci++;
      }
      // PL/SQL strings don't span lines
      if (inString) {
        errors.add(
          _SyntaxError(
            line: li + 1,
            col: line.length,
            message: "Cadena no cerrada — falta '",
          ),
        );
        inString = false;
      }
    }

    for (final p in parenStack) {
      errors.add(
        _SyntaxError(line: p.$1, col: p.$2, message: "( sin ) correspondiente"),
      );
    }
    if (inBlockComment) {
      errors.add(
        _SyntaxError(
          line: lines.length,
          col: 1,
          message: 'Comentario /* no cerrado',
        ),
      );
    }
    errors.addAll(_checkSqlBeginEnd(lines));
    errors.sort((a, b) => a.line.compareTo(b.line));
    return errors;
  }

  static List<_SyntaxError> _checkSqlBeginEnd(List<String> lines) {
    final errors = <_SyntaxError>[];
    final stack = <(int, String)>[];

    final beginRe = RegExp(r'^\s*BEGIN\b', caseSensitive: false);
    // IF on its own line or starting a line (not ELSIF)
    final ifRe = RegExp(r'^\s*IF\b', caseSensitive: false);
    // LOOP at the end of a line (FOR/WHILE/bare LOOP)
    final loopRe = RegExp(r'\bLOOP\s*$', caseSensitive: false);
    final caseRe = RegExp(r'^\s*CASE\b', caseSensitive: false);
    final endRe = RegExp(r'^\s*END\b', caseSensitive: false);
    // Lines that start with these keywords never open a new block
    final skipRe = RegExp(
      r'^\s*(ELSIF|ELSE\b|EXCEPTION\b|THEN\b|WHEN\b|DECLARE\b)',
      caseSensitive: false,
    );
    final lineCommentRe = RegExp(r'^\s*--');

    bool inBlockComment = false;

    for (int li = 0; li < lines.length; li++) {
      final rawText = lines[li];

      // Track /* */ block comments and extract the effective portion of the line
      String effectiveText;
      if (inBlockComment) {
        final closeIdx = rawText.indexOf('*/');
        if (closeIdx >= 0) {
          inBlockComment = false;
          effectiveText = rawText.substring(closeIdx + 2);
        } else {
          effectiveText = ''; // whole line is inside block comment
        }
      } else {
        effectiveText = rawText;
      }

      // Open a block comment mid-line → truncate effective text
      final openIdx = effectiveText.indexOf('/*');
      if (openIdx >= 0) {
        final afterOpen = effectiveText.substring(openIdx + 2);
        final closeIdx2 = afterOpen.indexOf('*/');
        if (closeIdx2 >= 0) {
          // Opened and closed on the same line — remove that span
          effectiveText =
              effectiveText.substring(0, openIdx) +
              afterOpen.substring(closeIdx2 + 2);
        } else {
          inBlockComment = true;
          effectiveText = effectiveText.substring(0, openIdx);
        }
      }

      // Strip inline -- comment
      final dashIdx = effectiveText.indexOf('--');
      if (dashIdx >= 0) effectiveText = effectiveText.substring(0, dashIdx);

      if (effectiveText.isEmpty) continue;
      if (lineCommentRe.hasMatch(effectiveText)) continue;
      if (skipRe.hasMatch(effectiveText)) continue;

      if (endRe.hasMatch(effectiveText)) {
        if (stack.isNotEmpty) {
          stack.removeLast();
        } else {
          errors.add(
            _SyntaxError(
              line: li + 1,
              col: 1,
              message: 'END sin bloque abierto correspondiente',
            ),
          );
        }
      } else {
        String? keyword;
        if (beginRe.hasMatch(effectiveText)) {
          keyword = 'BEGIN';
        } else if (ifRe.hasMatch(effectiveText)) {
          keyword = 'IF';
        } else if (caseRe.hasMatch(effectiveText)) {
          keyword = 'CASE';
        } else if (loopRe.hasMatch(effectiveText)) {
          keyword = 'LOOP';
        }
        if (keyword != null) stack.add((li + 1, keyword));
      }
    }

    for (final s in stack) {
      errors.add(
        _SyntaxError(
          line: s.$1,
          col: 1,
          message: '${s.$2} sin END correspondiente',
        ),
      );
    }
    return errors;
  }

  // ── JavaScript ──────────────────────────────────────────────────────────────

  static List<_SyntaxError> _checkJs(String code) {
    final errors = <_SyntaxError>[];
    final lines = code.split('\n');

    final braceStack = <(int, int)>[];
    final parenStack = <(int, int)>[];
    final bracketStack = <(int, int)>[];
    String? stringChar; // ', ", or `
    bool inBlockComment = false;

    for (int li = 0; li < lines.length; li++) {
      final line = lines[li];
      int ci = 0;
      while (ci < line.length) {
        if (inBlockComment) {
          if (ci + 1 < line.length && line[ci] == '*' && line[ci + 1] == '/') {
            inBlockComment = false;
            ci += 2;
          } else {
            ci++;
          }
          continue;
        }
        if (stringChar != null) {
          if (line[ci] == '\\') {
            ci += 2;
            continue;
          }
          if (line[ci] == stringChar) stringChar = null;
          ci++;
          continue;
        }
        if (ci + 1 < line.length && line[ci] == '/' && line[ci + 1] == '/') {
          break;
        }
        if (ci + 1 < line.length && line[ci] == '/' && line[ci + 1] == '*') {
          inBlockComment = true;
          ci += 2;
          continue;
        }
        switch (line[ci]) {
          case '\'':
          case '"':
          case '`':
            stringChar = line[ci];
          case '{':
            braceStack.add((li + 1, ci + 1));
          case '}':
            if (braceStack.isEmpty) {
              errors.add(
                _SyntaxError(
                  line: li + 1,
                  col: ci + 1,
                  message: "} sin { correspondiente",
                ),
              );
            } else {
              braceStack.removeLast();
            }
          case '(':
            parenStack.add((li + 1, ci + 1));
          case ')':
            if (parenStack.isEmpty) {
              errors.add(
                _SyntaxError(
                  line: li + 1,
                  col: ci + 1,
                  message: ") sin ( correspondiente",
                ),
              );
            } else {
              parenStack.removeLast();
            }
          case '[':
            bracketStack.add((li + 1, ci + 1));
          case ']':
            if (bracketStack.isEmpty) {
              errors.add(
                _SyntaxError(
                  line: li + 1,
                  col: ci + 1,
                  message: "] sin [ correspondiente",
                ),
              );
            } else {
              bracketStack.removeLast();
            }
        }
        ci++;
      }
      // Non-template strings don't span lines
      if (stringChar != null && stringChar != '`') {
        errors.add(
          _SyntaxError(
            line: li + 1,
            col: line.length,
            message: "Cadena no cerrada — falta $stringChar",
          ),
        );
        stringChar = null;
      }
    }

    for (final b in braceStack) {
      errors.add(
        _SyntaxError(line: b.$1, col: b.$2, message: "{ sin } correspondiente"),
      );
    }
    for (final p in parenStack) {
      errors.add(
        _SyntaxError(line: p.$1, col: p.$2, message: "( sin ) correspondiente"),
      );
    }
    for (final b in bracketStack) {
      errors.add(
        _SyntaxError(line: b.$1, col: b.$2, message: "[ sin ] correspondiente"),
      );
    }
    if (inBlockComment) {
      errors.add(
        _SyntaxError(
          line: lines.length,
          col: 1,
          message: 'Comentario /* no cerrado',
        ),
      );
    }
    if (stringChar != null) {
      errors.add(
        _SyntaxError(
          line: lines.length,
          col: 1,
          message: 'Cadena de texto no cerrada',
        ),
      );
    }

    errors.sort((a, b) => a.line.compareTo(b.line));
    return errors;
  }
}

// ── Indicador de errores en el gutter ────────────────────────────────────────
// Usa un ValueNotifier para escuchar cambios directamente desde el RenderObject,
// sin depender de la cadena de reconstrucción de widgets de CodeEditor.


// ── Toolbar helpers ───────────────────────────────────────────────────────────


// ── Find / Replace bar ────────────────────────────────────────────────────────

