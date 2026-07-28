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
  final ValueNotifier<List<_SyntaxError>> _errorsNotifier =
      ValueNotifier([]);

  List<_SyntaxError> get _syntaxErrors => _errorsNotifier.value;

  Timer? _debounceTimer;

  // ── Toolbar state ─────────────────────────────────────────────────────────
  int _zoomPercent = 100;
  bool _showSpaces = false;
  bool _showTabs = false;
  bool _showLineEndings = false;
  late CodeFindController _findController;
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
    _findController = CodeFindController(_codeController);
    _runCheck();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _findController.dispose();
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _errorsNotifier.dispose();
    super.dispose();
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
    TextSpan result =
        (_showSpaces || _showTabs) ? _annotateSpanTree(textSpan) : textSpan;
    if (_showLineEndings) {
      result = TextSpan(
        children: [
          result,
          TextSpan(
            text: '↵',
            style: TextStyle(
              color: Colors.blueGrey.withValues(alpha: 0.45),
              fontFamily: 'Consolas',
              fontSize: style.fontSize,
            ),
          ),
        ],
      );
    }
    return result;
  }

  TextSpan _annotateSpanTree(TextSpan span) {
    if (span.children == null || span.children!.isEmpty) {
      return _annotateLeafSpan(span);
    }
    final newChildren = span.children!.map((child) {
      if (child is TextSpan) return _annotateSpanTree(child);
      return child;
    }).toList();
    return TextSpan(text: span.text, style: span.style, children: newChildren);
  }

  TextSpan _annotateLeafSpan(TextSpan span) {
    final text = span.text ?? '';
    if (text.isEmpty) return span;
    final bool needsSpace = _showSpaces && text.contains(' ');
    final bool needsTab = _showTabs && text.contains('\t');
    if (!needsSpace && !needsTab) return span;
    const Color wsColor = Color(0xFF7895A8); // blueGrey accent
    final List<InlineSpan> parts = [];
    int start = 0;
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      final isWs =
          (ch == ' ' && _showSpaces) || (ch == '\t' && _showTabs);
      if (isWs) {
        if (i > start) {
          parts.add(TextSpan(text: text.substring(start, i), style: span.style));
        }
        parts.add(TextSpan(
          text: ch == ' ' ? '·' : '→',
          style: TextStyle(
            color: wsColor.withValues(alpha: 0.5),
            fontFamily: 'Consolas',
          ),
        ));
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

  void _toggleShowSpaces() => setState(() => _showSpaces = !_showSpaces);
  void _toggleShowTabs() => setState(() => _showTabs = !_showTabs);
  void _toggleShowLineEndings() =>
      setState(() => _showLineEndings = !_showLineEndings);

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
                              color: const Color(0xFFD7BA7D).withValues(
                                alpha: 0.15,
                              ),
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
    final toolbarBg = isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF0F0F0);
    final isJs = _selectedConfig == 'J';

    return Container(
      height: 36,
      color: toolbarBg,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ListenableBuilder(
        listenable: Listenable.merge([_codeController, _findController]),
        builder: (context, _) {
          final canUndo = _codeController.canUndo;
          final canRedo = _codeController.canRedo;
          final hasSel = !_codeController.selection.isCollapsed;
          final findVal = _findController.value;
          final findOpen = findVal != null && !findVal.replaceMode;
          final replaceOpen = findVal?.replaceMode == true;

          return Row(
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
                onPressed: findOpen ? _findController.close : _findController.findMode,
                active: findOpen,
              ),
              _TbBtn(
                icon: Icons.find_replace,
                tooltip: 'Buscar y reemplazar (Ctrl+H)',
                onPressed: replaceOpen ? _findController.close : _findController.replaceMode,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: (isJs
                          ? const Color(0xFFF7DF1E)
                          : const Color(0xFF336791))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: (isJs
                            ? const Color(0xFFF7DF1E)
                            : const Color(0xFF336791))
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  isJs ? 'JavaScript' : 'PL/SQL',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.w600,
                    color: isJs
                        ? const Color(0xFFC8A800)
                        : const Color(0xFF5596C0),
                  ),
                ),
              ),
            ],
          );
        },
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
              findController: _findController,
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
                const Icon(Icons.error_outline, size: 13, color: Color(0xFFFF6B6B)),
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
                    final lineText =
                        _codeController.codeLines[lineIndex].text;
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

class _EditorStatusBar extends StatefulWidget {
  final CodeLineEditingController controller;
  const _EditorStatusBar({required this.controller});

  @override
  State<_EditorStatusBar> createState() => _EditorStatusBarState();
}

class _EditorStatusBarState extends State<_EditorStatusBar> {
  static const int _charLimit = 32500;

  _StatusMetrics _metrics = const _StatusMetrics();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
    _update();
  }

  @override
  void didUpdateWidget(covariant _EditorStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
      _update();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctrl = widget.controller;
      final text = ctrl.text; // texto completo, siempre fresco en el post-frame
      final sel = ctrl.selection;
      final indentSize = ctrl.options.indentSize;

      setState(() {
        _metrics = _StatusMetrics(
          ln: sel.extentIndex + 1,
          col: sel.extentOffset + 1,
          lines: ctrl.codeLines.length,
          chars: text.length,
          tabs: _countLeadingIndents(ctrl.codeLines, indentSize),
          enters: '\n'.allMatches(text).length,
          spaces: ' '.allMatches(text).length,
        );
      });
    });
  }

  /// Suma las unidades de indentación de inicio de línea en todo el documento.
  /// Cada `\t` cuenta como 1; cada bloque de [indentSize] espacios cuenta como 1.
  static int _countLeadingIndents(CodeLines lines, int indentSize) {
    int count = 0;
    for (int i = 0; i < lines.length; i++) {
      final lineText = lines[i].text;
      int j = 0;
      while (j < lineText.length) {
        if (lineText[j] == '\t') {
          count++;
          j++;
        } else if (lineText[j] == ' ') {
          int spaces = 0;
          while (j < lineText.length && lineText[j] == ' ') {
            spaces++;
            j++;
          }
          count += spaces ~/ indentSize;
          break; // solo whitespace inicial
        } else {
          break;
        }
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg = isDark ? const Color(0xFF007ACC) : const Color(0xFF0078D4);
    final m = _metrics;
    final overLimit = m.chars > _charLimit;

    return Container(
      height: 24,
      color: barBg,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // ── Izquierda: cursor + líneas ──
          _StatusItem('Ln ${m.ln}, Col ${m.col}'),
          _StatusDot(),
          _StatusItem('${_fmt(m.lines)} líneas'),
          const Spacer(),
          // ── Derecha: chars | tabs | enters | espacios ──
          if (overLimit) ...[
            const Icon(
              Icons.warning_amber_rounded,
              size: 13,
              color: Color(0xFFFFD700),
            ),
            const SizedBox(width: 4),
          ],
          _StatusItem(
            '${_fmt(m.chars)} / ${_fmt(_charLimit)} chars',
            color: overLimit ? const Color(0xFFFF6B6B) : null,
          ),
          _StatusDot(),
          _StatusItem('${_fmt(m.tabs)} tabs'),
          _StatusDot(),
          _StatusItem('${_fmt(m.enters)} enters'),
          _StatusDot(),
          _StatusItem('${_fmt(m.spaces)} espacios'),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    final str = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }
}

class _StatusMetrics {
  final int ln, col, lines, chars, tabs, enters, spaces;
  const _StatusMetrics({
    this.ln = 1,
    this.col = 1,
    this.lines = 0,
    this.chars = 0,
    this.tabs = 0,
    this.enters = 0,
    this.spaces = 0,
  });
}

class _StatusItem extends StatelessWidget {
  final String text;
  final Color? color;
  const _StatusItem(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color ?? Colors.white.withValues(alpha: 0.9),
        fontSize: 11,
        fontFamily: 'Consolas',
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '·',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 11,
        ),
      ),
    );
  }
}

// ── Folding SQL: BEGIN / IF / LOOP / CASE ────────────────────────────────────
// Reglas Oracle PL/SQL:
//   Abren bloque : BEGIN  |  IF...THEN  |  ...LOOP (al final de línea)  |  CASE (inicio de línea)
//   Cierran bloque: cualquier línea que empiece con END
//   NO abren bloque: ELSIF, ELSE, EXCEPTION, DECLARE, THEN, WHEN

class _SqlChunkAnalyzer implements CodeChunkAnalyzer {
  const _SqlChunkAnalyzer();

  static final _commentRe = RegExp(r'^\s*--');
  static final _beginRe = RegExp(r'^\s*BEGIN\b', caseSensitive: false);
  static final _ifRe = RegExp(r'^\s*IF\b', caseSensitive: false);
  static final _loopRe = RegExp(r'^\s*FOR\b|\bLOOP\s*$', caseSensitive: false);
  static final _caseRe = RegExp(r'^\s*CASE\b', caseSensitive: false);
  static final _endRe = RegExp(r'^\s*END\b', caseSensitive: false);
  // Continuaciones que NO abren bloque aunque contengan keywords
  static final _skipRe = RegExp(
    r'^\s*(ELSIF|ELSE|EXCEPTION|THEN|WHEN|DECLARE)\b',
    caseSensitive: false,
  );

  @override
  List<CodeChunk> run(CodeLines codeLines) {
    final chunks = <CodeChunk>[];
    final stack = <int>[];

    for (int i = 0; i < codeLines.length; i++) {
      final text = codeLines[i].text;
      if (_commentRe.hasMatch(text)) continue;

      if (_endRe.hasMatch(text)) {
        if (stack.isNotEmpty) {
          final start = stack.removeLast();
          if (i - start >= 1) chunks.add(CodeChunk(start, i));
        }
      } else if (!_skipRe.hasMatch(text)) {
        if (_beginRe.hasMatch(text) ||
            _ifRe.hasMatch(text) ||
            _loopRe.hasMatch(text) ||
            _caseRe.hasMatch(text)) {
          stack.add(i);
        }
      }
    }

    chunks.sort((a, b) => a.index - b.index);
    return chunks;
  }
}

// ── Builder combinado: variables + sintaxis ───────────────────────────────────
// El DefaultCodeAutocompletePromptsBuilder extrae input usando solo [A-Za-z_],
// por lo que el ':' nunca llega al match(). Este builder lo detecta manualmente.
//
// El editor aplica el resultado así:
//   controller.replaceSelection(result.word, selection con startOffset = cursor - result.input.length)
//   controller.selection = selection + result.selection (relativo a la posición post-reemplazo)

class _VarAwarePromptsBuilder implements CodeAutocompletePromptsBuilder {
  final ProcedimientosProvider provider;
  final String selectedConfig;
  final CodeAutocompletePromptsBuilder syntaxBuilder;

  _VarAwarePromptsBuilder({
    required this.provider,
    required this.selectedConfig,
    required this.syntaxBuilder,
  });

  static final _varTriggerRe = RegExp(r':([A-Za-z0-9_.]+|)$');

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    final text = codeLine.text;
    if (selection.extentOffset > text.length) return null;
    final before = text.substring(0, selection.extentOffset);
    final match = _varTriggerRe.firstMatch(before);

    if (match != null) {
      final prefix = match.group(1)!; // parte después del ':'
      // input = todo lo que hay desde ':' hasta el cursor (incluyendo el ':')
      final input = ':$prefix';

      final vars = provider.variablesDinamicas
          .where((v) => v.inConfiguracion == selectedConfig)
          .toList();

      final filtered = vars
          .where((v) {
            if (prefix.isEmpty) return true;
            return v.cdVariable.toUpperCase().contains(prefix.toUpperCase());
          })
          .map((v) => _VarPrompt(word: v.cdVariable, description: v.deVariable))
          .toList();

      if (filtered.isEmpty) return null;

      return CodeAutocompleteEditingValue(
        input: input,
        prompts: filtered,
        index: 0,
      );
    }

    // Sin trigger ':' → autocompletado de sintaxis normal
    return syntaxBuilder.build(context, codeLine, selection);
  }
}

// ── Prompt personalizado para variables dinámicas ────────────────────────────

class _VarPrompt extends CodeKeywordPrompt {
  final String description;

  const _VarPrompt({required super.word, this.description = ''});

  @override
  bool match(String input) => true; // el builder ya filtró

  @override
  CodeAutocompleteResult get autocomplete {
    final fullWord = ':$word';
    // El editor aplica:
    //   replaceSelection(word, [cursor-input.length, cursor])
    //   cursor_final = cursor + selection.baseOffset (después de que autocompleteEditingValue.autocomplete resta input.length)
    // Queremos cursor al final de la palabra → selection.offset = word.length (antes de la resta de input.length)
    return CodeAutocompleteResult(
      input: '',
      word: fullWord,
      selection: TextSelection.collapsed(offset: fullWord.length),
    );
  }
}

// ── Popup de autocomplete ────────────────────────────────────────────────────

class _AutocompletePopup extends StatelessWidget
    implements PreferredSizeWidget {
  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelect;

  static const double _itemH = 44;
  static const double _maxItems = 8;

  const _AutocompletePopup({required this.notifier, required this.onSelect});

  @override
  Size get preferredSize => const Size(320, _itemH * _maxItems);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final theme = Theme.of(context);

    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder: (context, value, _) {
        final prompts = value.prompts;
        if (prompts.isEmpty) return const SizedBox.shrink();

        final isVarMode = value.input.startsWith(':');

        return Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: _itemH * _maxItems,
              maxWidth: 320,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    isVarMode ? 'Variables dinámicas' : 'Autocompletado',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                      fontSize: 10,
                      fontFamily: 'Consolas',
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Divider(height: 1, color: theme.dividerColor),
                Flexible(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: prompts.length,
                    itemBuilder: (context, i) {
                      final p = prompts[i];
                      final isVar = p is _VarPrompt;
                      final isSelected = i == value.index;
                      return InkWell(
                        onTap: () =>
                            onSelect(value.copyWith(index: i).autocomplete),
                        child: Container(
                          height: _itemH,
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.15,
                                )
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              Icon(
                                isVar ? Icons.data_object : Icons.code,
                                size: 14,
                                color: isVar
                                    ? const Color(0xFFD7BA7D)
                                    : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      isVar ? ':${p.word}' : p.word,
                                      style: TextStyle(
                                        fontFamily: 'Consolas',
                                        fontSize: 13,
                                        color: isVar
                                            ? const Color(0xFFD7BA7D)
                                            : theme.colorScheme.onSurface,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (p case final _VarPrompt vp
                                        when vp.description.isNotEmpty)
                                      Text(
                                        vp.description,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
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
          ),
        );
      },
    );
  }
}

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

// ── Modelo y checker de errores de sintaxis ───────────────────────────────────

class _SyntaxError {
  final int line; // 1-based
  final int col; // 1-based
  final String message;
  const _SyntaxError({required this.line, required this.col, required this.message});
}

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
              errors.add(_SyntaxError(
                line: li + 1,
                col: ci + 1,
                message: ") sin ( correspondiente",
              ));
            } else {
              parenStack.removeLast();
            }
        }
        ci++;
      }
      // PL/SQL strings don't span lines
      if (inString) {
        errors.add(_SyntaxError(
          line: li + 1,
          col: line.length,
          message: "Cadena no cerrada — falta '",
        ));
        inString = false;
      }
    }

    for (final p in parenStack) {
      errors.add(_SyntaxError(line: p.$1, col: p.$2, message: "( sin ) correspondiente"));
    }
    if (inBlockComment) {
      errors.add(_SyntaxError(line: lines.length, col: 1, message: 'Comentario /* no cerrado'));
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
              effectiveText.substring(0, openIdx) + afterOpen.substring(closeIdx2 + 2);
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
          errors.add(_SyntaxError(
            line: li + 1,
            col: 1,
            message: 'END sin bloque abierto correspondiente',
          ));
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
      errors.add(_SyntaxError(
        line: s.$1,
        col: 1,
        message: '${s.$2} sin END correspondiente',
      ));
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
              errors.add(_SyntaxError(line: li + 1, col: ci + 1, message: "} sin { correspondiente"));
            } else {
              braceStack.removeLast();
            }
          case '(':
            parenStack.add((li + 1, ci + 1));
          case ')':
            if (parenStack.isEmpty) {
              errors.add(_SyntaxError(line: li + 1, col: ci + 1, message: ") sin ( correspondiente"));
            } else {
              parenStack.removeLast();
            }
          case '[':
            bracketStack.add((li + 1, ci + 1));
          case ']':
            if (bracketStack.isEmpty) {
              errors.add(_SyntaxError(line: li + 1, col: ci + 1, message: "] sin [ correspondiente"));
            } else {
              bracketStack.removeLast();
            }
        }
        ci++;
      }
      // Non-template strings don't span lines
      if (stringChar != null && stringChar != '`') {
        errors.add(_SyntaxError(
          line: li + 1,
          col: line.length,
          message: "Cadena no cerrada — falta $stringChar",
        ));
        stringChar = null;
      }
    }

    for (final b in braceStack) {
      errors.add(_SyntaxError(line: b.$1, col: b.$2, message: "{ sin } correspondiente"));
    }
    for (final p in parenStack) {
      errors.add(_SyntaxError(line: p.$1, col: p.$2, message: "( sin ) correspondiente"));
    }
    for (final b in bracketStack) {
      errors.add(_SyntaxError(line: b.$1, col: b.$2, message: "[ sin ] correspondiente"));
    }
    if (inBlockComment) {
      errors.add(_SyntaxError(line: lines.length, col: 1, message: 'Comentario /* no cerrado'));
    }
    if (stringChar != null) {
      errors.add(_SyntaxError(line: lines.length, col: 1, message: 'Cadena de texto no cerrada'));
    }

    errors.sort((a, b) => a.line.compareTo(b.line));
    return errors;
  }
}

// ── Indicador de errores en el gutter ────────────────────────────────────────
// Usa un ValueNotifier para escuchar cambios directamente desde el RenderObject,
// sin depender de la cadena de reconstrucción de widgets de CodeEditor.

class _ErrorGutterIndicator extends LeafRenderObjectWidget {
  final ValueNotifier<List<_SyntaxError>> errorsNotifier;
  final CodeIndicatorValueNotifier notifier;

  const _ErrorGutterIndicator({
    required this.errorsNotifier,
    required this.notifier,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ErrorGutterRenderObject(errorsNotifier: errorsNotifier, notifier: notifier);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ErrorGutterRenderObject renderObject,
  ) {
    renderObject
      ..errorsNotifier = errorsNotifier
      ..notifier = notifier;
  }
}

class _ErrorGutterRenderObject extends RenderBox {
  ValueNotifier<List<_SyntaxError>> _errorsNotifier;
  CodeIndicatorValueNotifier _notifier;

  static const double _kWidth = 10.0;
  static const double _kDotRadius = 3.0;

  _ErrorGutterRenderObject({
    required ValueNotifier<List<_SyntaxError>> errorsNotifier,
    required CodeIndicatorValueNotifier notifier,
  })  : _errorsNotifier = errorsNotifier,
        _notifier = notifier;

  set errorsNotifier(ValueNotifier<List<_SyntaxError>> value) {
    if (_errorsNotifier == value) return;
    if (attached) _errorsNotifier.removeListener(markNeedsPaint);
    _errorsNotifier = value;
    if (attached) _errorsNotifier.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set notifier(CodeIndicatorValueNotifier value) {
    if (_notifier == value) return;
    if (attached) _notifier.removeListener(markNeedsPaint);
    _notifier = value;
    if (attached) _notifier.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(covariant PipelineOwner owner) {
    _errorsNotifier.addListener(markNeedsPaint);
    _notifier.addListener(markNeedsPaint);
    super.attach(owner);
  }

  @override
  void detach() {
    _errorsNotifier.removeListener(markNeedsPaint);
    _notifier.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = Size(_kWidth, constraints.maxHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final value = _notifier.value;
    final errors = _errorsNotifier.value;
    if (value == null || errors.isEmpty) return;

    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height));

    final paint = Paint()
      ..color = const Color(0xFFFF6B6B)
      ..style = PaintingStyle.fill;

    // With wordWrap: false, paragraph.index + 1 == 1-based line number
    final errorLineSet = errors.map((e) => e.line).toSet();

    for (final paragraph in value.paragraphs) {
      if (errorLineSet.contains(paragraph.index + 1)) {
        final cy = offset.dy + paragraph.offset.dy + paragraph.preferredLineHeight / 2;
        final cx = offset.dx + _kWidth / 2;
        canvas.drawCircle(Offset(cx, cy), _kDotRadius, paint);
      }
    }

    canvas.restore();
  }
}

// ── Toolbar helpers ───────────────────────────────────────────────────────────

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

// ── Find / Replace bar ────────────────────────────────────────────────────────

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
              noMatches
                  ? 'Sin resultados'
                  : '${matchIndex + 1} / $matchCount',
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
