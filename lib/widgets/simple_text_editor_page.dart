import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

import '../services/backup_service.dart';
import '../services/local_file_service.dart';
import '_editor_themes.dart';
import 'app_toast.dart';
import 'code_editor_panel.dart'
    show
        showAutorizacionesWindow,
        showInfoDatoWindow,
        showInfoEventoWindow,
        showThemePickerDialog,
        showUsosProcedimientoWindow;
import 'monaco_snippets.dart';
import 'definition_navigation.dart';

/// Editor para archivos locales `.txt`/`.yaml`, alineado al tema de la aplicación
/// y equipado con herramientas de productividad:
/// - Snippets de usuario (gestor y autocompletado)
/// - Consulta de datos (InfoDato)
/// - Consulta de eventos (InfoEvento)
/// - Consulta de autorizaciones
/// - Usos de procedimiento
/// - Abrir archivos locales (.sql, .txt, .yaml, .yml)
/// - Guardar y Guardar como en disco local
class SimpleTextEditorPage extends StatefulWidget {
  final String filePath;
  final String initialText;
  final String ambiente;
  final ValueChanged<bool>? onDirtyChanged;
  final Future<void> Function(String code)? onSave;
  final ValueChanged<String>? onCodeChanged;
  final void Function(String path, String content)? onOpenLocalFile;
  final void Function(String newPath)? onFilePathChanged;

  const SimpleTextEditorPage({
    super.key,
    required this.filePath,
    required this.initialText,
    this.ambiente = 'Desa',
    this.onDirtyChanged,
    this.onSave,
    this.onCodeChanged,
    this.onOpenLocalFile,
    this.onFilePathChanged,
  });

  @override
  State<SimpleTextEditorPage> createState() => _SimpleTextEditorPageState();
}

class _SimpleTextEditorPageState extends State<SimpleTextEditorPage> {
  late String _currentFilePath;
  MonacoController? _ctrl;
  MonacoActionRegistration? _newAction;
  MonacoActionRegistration? _saveAction;
  MonacoActionRegistration? _saveAsAction;
  MonacoActionRegistration? _gotoDefinitionAction;
  MonacoActionRegistration? _infoDatoAction;
  MonacoActionRegistration? _infoEventoAction;
  MonacoActionRegistration? _autorizacionesAction;
  MonacoActionRegistration? _usosAction;
  MonacoCompletionRegistration? _snippetCompletions;
  bool _minimap = false;
  bool _wordWrap = true;
  bool _dirty = false;
  bool _saving = false;
  late String _currentText = widget.initialText;

  MonacoLanguage get _language {
    final path = widget.filePath.toLowerCase();
    if (path.endsWith('.yaml') || path.endsWith('.yml')) {
      return MonacoLanguage.yaml;
    }
    return MonacoLanguage.plaintext;
  }

  @override
  void initState() {
    super.initState();
    _currentFilePath = widget.filePath;
    editorThemeStore.addListener(_onThemeChanged);
    snippetsRevision.addListener(_onSnippetsUpdated);
  }

  @override
  void didUpdateWidget(SimpleTextEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _currentFilePath = widget.filePath;
    }
  }

  @override
  void dispose() {
    editorThemeStore.removeListener(_onThemeChanged);
    snippetsRevision.removeListener(_onSnippetsUpdated);
    try {
      _newAction?.dispose();
      _saveAction?.dispose();
      _saveAsAction?.dispose();
      _gotoDefinitionAction?.dispose();
      _infoDatoAction?.dispose();
      _infoEventoAction?.dispose();
      _autorizacionesAction?.dispose();
      _usosAction?.dispose();
      _snippetCompletions?.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _onThemeChanged() {
    _ctrl?.setTheme(editorThemeStore.monacoTheme);
    if (mounted) setState(() {});
  }

  Future<void> _onSnippetsUpdated() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    try {
      _snippetCompletions?.dispose();
      _snippetCompletions = await registerUserSnippetCompletions(
        ctrl,
        id: 'simple-text-snippets',
        isLocalDocumentEditor: true,
      );
    } catch (_) {}
  }

  Future<void> _onReady(MonacoController ctrl) async {
    _ctrl = ctrl;
    // Registrar todas las definiciones de temas personalizados en la instancia de Monaco
    // y aplicar de inmediato el tema configurado de la aplicación.
    await EditorThemeStore.defineAllThemes(ctrl);
    await ctrl.setTheme(editorThemeStore.monacoTheme);

    _newAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.new'),
        label: 'Nuevo documento',
        keybindings: [MonacoKeybinding(ctrlCmd: true, key: MonacoKey.keyN)],
      ),
      () async => _newDocument(),
    );

    _saveAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.save'),
        label: 'Guardar archivo',
        keybindings: [MonacoKeybinding(ctrlCmd: true, key: MonacoKey.keyS)],
      ),
      () async => _save(),
    );

    _saveAsAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.saveAs'),
        label: 'Guardar archivo como…',
        keybindings: [
          MonacoKeybinding(ctrlCmd: true, shift: true, key: MonacoKey.keyS),
        ],
      ),
      () async => _saveAs(),
    );

    _gotoDefinitionAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.goto.definition'),
        label: 'Ir a definición',
        keybindings: [MonacoKeybinding(key: MonacoKey.f12)],
        contextMenuGroupId: 'navigation',
        contextMenuOrder: 1.4,
      ),
      () async => _goToDefinitionAtCursor(),
    );

    _infoDatoAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.info.dato'),
        label: 'Consultar dato (InfoDato)',
        keybindings: [MonacoKeybinding(alt: true, key: MonacoKey.keyD)],
        contextMenuGroupId: 'navigation',
        contextMenuOrder: 1.5,
      ),
      () async => _openInfoDatoWindow(),
    );

    _infoEventoAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.info.evento'),
        label: 'Consultar evento (InfoEvento)',
        keybindings: [MonacoKeybinding(alt: true, key: MonacoKey.keyE)],
        contextMenuGroupId: 'navigation',
        contextMenuOrder: 1.6,
      ),
      () async => _openInfoEventoWindow(),
    );

    _autorizacionesAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.info.autorizaciones'),
        label: 'Consultar autorizaciones',
        keybindings: [MonacoKeybinding(alt: true, key: MonacoKey.keyA)],
        contextMenuGroupId: 'navigation',
        contextMenuOrder: 1.7,
      ),
      () async => _openAutorizacionesWindow(),
    );

    _usosAction = await ctrl.addAction(
      MonacoActionDescriptor(
        id: MonacoAction('custom.info.usos'),
        label: 'Usos del procedimiento',
        keybindings: [MonacoKeybinding(alt: true, key: MonacoKey.keyU)],
        contextMenuGroupId: 'navigation',
        contextMenuOrder: 1.8,
      ),
      () async => _openUsosProcedimientoWindow(),
    );

    _snippetCompletions = await registerUserSnippetCompletions(
      ctrl,
      id: 'simple-text-snippets',
      isLocalDocumentEditor: true,
    );
  }

  void _onContentChanged(String text) {
    _currentText = text;
    widget.onCodeChanged?.call(text);
    if (!_dirty) {
      setState(() => _dirty = true);
      widget.onDirtyChanged?.call(true);
    }
  }

  Future<String?> _getSelectedOrWordAtCursor() async {
    final ctrl = _ctrl;
    if (ctrl == null) return null;
    try {
      final js = await ctrl.evaluateJavaScript<String>(
        r'(()=>{'
        r'  try {'
        r'    const s = window.editor.getSelection();'
        r'    if (s && !s.isEmpty()) {'
        r'      const sel = window.editor.getModel().getValueInRange(s);'
        r'      if (sel && sel.trim().length > 0) return sel.trim();'
        r'    }'
        r'    const p = window.editor.getPosition();'
        r'    const m = window.editor.getModel();'
        r'    if (!p || !m) return null;'
        r'    const w = m.getWordAtPosition(p);'
        r'    return w ? w.word : null;'
        r'  } catch(e) { return null; }'
        r'})()',
      );
      if (js != null && js.trim().isNotEmpty) return js.trim();
    } catch (_) {}
    return null;
  }

  Future<void> _goToDefinitionAtCursor() async {
    if (!mounted) return;
    final word = await _getSelectedOrWordAtCursor();
    if (word == null || word.isEmpty) {
      AppToast.info('Seleccione o ubique el cursor sobre un objeto');
      return;
    }

    await navigateToDefinition(context, word, ambiente: widget.ambiente);
  }

  Future<void> _openInfoDatoWindow() async {
    if (!mounted) return;
    final word = (await _getSelectedOrWordAtCursor()) ?? '';
    final esCodigo = word.isNotEmpty && RegExp(r'^\d{3,}$').hasMatch(word);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showInfoDatoWindow(context, esCodigo ? word : '', widget.ambiente);
      }
    });
  }

  Future<void> _openInfoEventoWindow() async {
    if (!mounted) return;
    final word = (await _getSelectedOrWordAtCursor()) ?? '';
    final esCodigo = word.isNotEmpty && RegExp(r'^\d{3,}$').hasMatch(word);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showInfoEventoWindow(context, esCodigo ? word : '', widget.ambiente);
      }
    });
  }

  Future<void> _openAutorizacionesWindow() async {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showAutorizacionesWindow(context, widget.ambiente);
      }
    });
  }

  Future<void> _openUsosProcedimientoWindow() async {
    if (!mounted) return;
    final word = (await _getSelectedOrWordAtCursor()) ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showUsosProcedimientoWindow(context, word, widget.ambiente);
      }
    });
  }

  Future<void> _openSnippetsManager() async {
    await openSnippetsManager(context);
    await _onSnippetsUpdated();
  }

  Future<void> _newDocument() async {
    final hasContent = _currentText.trim().isNotEmpty;
    if (_dirty || hasContent) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nuevo documento'),
          content: const Text(
            'El documento actual tiene cambios o contenido sin guardar. '
            '¿Desea limpiar el editor para crear un documento nuevo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0078D4),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Limpiar editor'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    final ctrl = _ctrl;
    if (ctrl != null) {
      await ctrl.document.setText('');
    }
    setState(() {
      _currentText = '';
      _currentFilePath = '';
      _dirty = false;
    });
    widget.onCodeChanged?.call('');
    widget.onFilePathChanged?.call('');
    widget.onDirtyChanged?.call(false);
  }

  Future<void> _openLocalFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Abrir archivo',
      type: FileType.custom,
      allowedExtensions: const ['sql', 'txt', 'yaml', 'yml'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      widget.onOpenLocalFile?.call(path, content);
    } on IOException {
      if (mounted) AppToast.warning('No se pudo leer el archivo seleccionado');
    }
  }

  Future<void> _save() async {
    if (_currentFilePath.isEmpty) {
      await _saveAs();
      return;
    }
    final onSave = widget.onSave;
    if (onSave == null || _saving) return;
    setState(() => _saving = true);
    try {
      await onSave(_currentText);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      widget.onDirtyChanged?.call(false);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAs() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final defaultName = _currentFilePath.isNotEmpty
          ? Uri.file(_currentFilePath).pathSegments.last
          : 'documento.txt';
      final savedPath = await LocalFileService.saveFile(
        content: _currentText,
        currentPath: _currentFilePath.isNotEmpty ? _currentFilePath : null,
        saveAs: true,
        defaultFileName: defaultName,
        dialogTitle: 'Guardar archivo como…',
        allowedExtensions: const ['sql', 'txt', 'yaml', 'yml'],
      );
      if (savedPath != null && mounted) {
        setState(() {
          _currentFilePath = savedPath;
          _dirty = false;
          _saving = false;
        });
        widget.onFilePathChanged?.call(savedPath);
        widget.onDirtyChanged?.call(false);
      } else if (mounted) {
        setState(() => _saving = false);
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: MonacoEditor(
            initialText: widget.initialText,
            options: EditorOptions(
              language: _language,
              theme: editorThemeStore.monacoTheme,
              minimap: MonacoMinimapOptions(enabled: _minimap),
              lineNumbers: MonacoLineNumbers.on,
              wordWrap: _wordWrap ? MonacoWordWrap.on : MonacoWordWrap.off,
              extra: const {'fixedOverflowWidgets': true},
            ),
            contentDebounce: const Duration(milliseconds: 200),
            onReady: _onReady,
            onContentChanged: _onContentChanged,
          ),
        ),
        _buildStatusBar(),
      ],
    );
  }

  Widget _buildStatusBar() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ext = _language == MonacoLanguage.yaml ? 'YAML' : 'TEXTO';
    final hasFile = _currentFilePath.isNotEmpty;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLowest : cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              ext,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: cs.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 12,
            child: VerticalDivider(
              color: cs.outlineVariant.withValues(alpha: 0.5),
              width: 8,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Tooltip(
              message: hasFile
                  ? 'Archivo local: $_currentFilePath\n(Clic para abrir ubicación en el explorador)'
                  : 'Documento nuevo sin guardar en disco',
              child: InkWell(
                onTap: hasFile
                    ? () => unawaited(
                        BackupService.revealInExplorer(_currentFilePath),
                      )
                    : null,
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasFile
                            ? Icons.insert_drive_file_outlined
                            : Icons.note_add_outlined,
                        size: 12,
                        color: hasFile
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          hasFile
                              ? _currentFilePath
                              : 'Documento nuevo (sin guardar)',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: hasFile ? 'Consolas' : null,
                            color: hasFile ? cs.onSurface : cs.onSurfaceVariant,
                            fontStyle: hasFile
                                ? FontStyle.normal
                                : FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            _dirty ? Icons.circle : Icons.check_circle_outline_rounded,
            size: _dirty ? 7 : 11,
            color: _dirty ? Colors.orange.shade400 : Colors.green.shade600,
          ),
          const SizedBox(width: 4),
          Text(
            _dirty ? 'Sin guardar' : 'Guardado',
            style: TextStyle(
              fontSize: 10.5,
              color: _dirty ? Colors.orange.shade400 : cs.onSurfaceVariant,
              fontWeight: _dirty ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 12,
            child: VerticalDivider(
              color: cs.outlineVariant.withValues(alpha: 0.5),
              width: 8,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'UTF-8',
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 40,
      color: isDark ? cs.surfaceContainerLow : cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        spacing: 5,
        children: [
          _toolbarToggle(
            icon: Icons.map_outlined,
            tooltip: 'Minimap',
            active: _minimap,
            onPressed: () => setState(() => _minimap = !_minimap),
          ),
          _toolbarToggle(
            icon: Icons.wrap_text_rounded,
            tooltip: 'Ajustar líneas',
            active: _wordWrap,
            onPressed: () => setState(() => _wordWrap = !_wordWrap),
          ),
          SizedBox(
            height: 18,
            child: VerticalDivider(color: cs.outlineVariant, width: 12),
          ),
          _buildThemeSelector(cs),
          _buildThemeToggleBtn(cs),
          _toolbarButton(
            icon: Icons.code_rounded,
            tooltip: 'Snippets de usuario',
            onPressed: _openSnippetsManager,
          ),
          _toolbarButton(
            icon: Icons.data_object_rounded,
            tooltip: 'Consultar dato — InfoDato (Alt+D)',
            onPressed: () => unawaited(_openInfoDatoWindow()),
          ),
          _toolbarButton(
            icon: Icons.bolt_rounded,
            tooltip: 'Consultar evento — InfoEvento (Alt+E)',
            onPressed: () => unawaited(_openInfoEventoWindow()),
          ),
          _toolbarButton(
            icon: Icons.verified_user_outlined,
            tooltip: 'Consultar autorizaciones de proceso (Alt+A)',
            onPressed: () => unawaited(_openAutorizacionesWindow()),
          ),
          _toolbarButton(
            icon: Icons.travel_explore_rounded,
            tooltip: 'Usos del procedimiento — tabla y campo (Alt+U)',
            onPressed: () => unawaited(_openUsosProcedimientoWindow()),
          ),
          _toolbarButton(
            icon: Icons.call_made_rounded,
            tooltip: 'Ir a definición — tabla, proc, pkg, función, type (F12)',
            onPressed: () => unawaited(_goToDefinitionAtCursor()),
          ),
          _toolbarButton(
            icon: Icons.note_add_outlined,
            tooltip: 'Nuevo documento (Ctrl+N)',
            onPressed: () => unawaited(_newDocument()),
          ),
          _toolbarButton(
            icon: Icons.folder_open_rounded,
            tooltip: 'Abrir archivo (.sql / .txt / .yaml)',
            onPressed: () => unawaited(_openLocalFile()),
          ),
          const Spacer(),
          _toolbarButton(
            icon: Icons.format_align_left,
            tooltip: 'Formatear documento (Shift+Alt+F)',
            onPressed: () =>
                unawaited(_ctrl?.executeAction(MonacoAction.formatDocument)),
          ),
          _buildSaveButton(),
          _toolbarButton(
            icon: Icons.save_as_outlined,
            tooltip: 'Guardar como… (Ctrl+Shift+S)',
            onPressed: () => unawaited(_saveAs()),
          ),
          if (_currentFilePath.isNotEmpty)
            _toolbarButton(
              icon: Icons.folder_shared_outlined,
              tooltip: 'Abrir ubicación en el explorador\n$_currentFilePath',
              onPressed: () =>
                  unawaited(BackupService.revealInExplorer(_currentFilePath)),
            ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector(ColorScheme cs) {
    final meta = editorThemeStore.currentMeta;
    return Tooltip(
      message: 'Tema del editor: ${meta.name} (clic para cambiar)',
      waitDuration: const Duration(milliseconds: 400),
      preferBelow: false,
      child: InkWell(
        onTap: () {
          showThemePickerDialog(
            context,
            currentThemeId: editorThemeStore.themeId,
            onSelected: (id) async {
              await editorThemeStore.setTheme(id);
              _ctrl?.setTheme(editorThemeStore.monacoTheme);
            },
          );
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: meta.swatch,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: cs.outlineVariant, width: 0.5),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                meta.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 14, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeToggleBtn(ColorScheme cs) {
    final meta = editorThemeStore.currentMeta;
    final isDarkTheme = meta.isDark;
    return Tooltip(
      message: isDarkTheme ? 'Cambiar a tema claro' : 'Cambiar a tema oscuro',
      waitDuration: const Duration(milliseconds: 400),
      preferBelow: false,
      child: InkWell(
        onTap: () async {
          await editorThemeStore.setTheme(editorThemeStore.pairedThemeId);
          _ctrl?.setTheme(editorThemeStore.monacoTheme);
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Icon(
            isDarkTheme ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    if (_saving) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return _toolbarButton(
      icon: _dirty ? Icons.save : Icons.save_outlined,
      tooltip: 'Guardar (Ctrl+S)',
      onPressed: widget.onSave == null ? null : () => unawaited(_save()),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      preferBelow: false,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }

  Widget _toolbarToggle({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      preferBelow: false,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: active
              ? BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: Icon(icon, size: 16, color: active ? cs.primary : null),
        ),
      ),
    );
  }
}
