import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/reverse_sql_config.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart';
import 'reverse_sql_visual_form.dart';
import 'reverse_sql_yaml_editor.dart';

enum _ConfigMode { visual, yaml }

/// Diálogo modal / flotante para editar o visualizar archivos YAML de Reverse SQL (RSQL).
/// Permite alternar entre Formulario Visual Estructurado y Editor YAML con sincronización bidireccional.
class ReverseSqlConfigDialog extends StatefulWidget {
  /// Contenido inicial YAML si ya existe, o null para usar plantilla inicial.
  final String? initialYaml;

  /// Ruta inicial del archivo en disco si ya fue seleccionado previamente.
  final String? initialFilePath;

  /// Nombre del script / artefacto (ej. rev_insert.yaml)
  final String? scriptName;

  /// Título de la ventana flotante.
  final String title;

  /// Callback cuando el usuario guarda los cambios o selecciona guardar como archivo.
  final void Function(String yamlContent, String? filePath, String scriptName)?
  onSave;

  const ReverseSqlConfigDialog({
    super.key,
    this.initialYaml,
    this.initialFilePath,
    this.scriptName,
    this.title = 'Configuración de Extracción RSQL (YAML)',
    this.onSave,
  });

  /// Muestra el diálogo como ventana flotante integrada sobre el contexto.
  static Future<void> show(
    BuildContext context, {
    String? initialYaml,
    String? initialFilePath,
    String? scriptName,
    String title = 'Configuración de Extracción RSQL (YAML)',
    void Function(String yamlContent, String? filePath, String scriptName)?
    onSave,
  }) {
    return showFloatingDialog<void>(
      context,
      (dialogContext, close) => ReverseSqlConfigDialog(
        initialYaml: initialYaml,
        initialFilePath: initialFilePath,
        scriptName: scriptName,
        title: title,
        onSave: onSave,
      ),
    );
  }

  @override
  State<ReverseSqlConfigDialog> createState() => _ReverseSqlConfigDialogState();
}

class _ReverseSqlConfigDialogState extends State<ReverseSqlConfigDialog> {
  _ConfigMode _mode = _ConfigMode.visual;
  late String _yamlContent;
  late ReverseSqlConfig _config;
  String? _currentFilePath;
  late String _currentScriptName;
  late final TextEditingController _scriptNameCtrl;
  bool _isLoading = false;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _currentFilePath = widget.initialFilePath;
    _currentScriptName =
        widget.scriptName ??
        (widget.initialFilePath != null
            ? widget.initialFilePath!.split(Platform.pathSeparator).last
            : 'reverseSql.yaml');
    _scriptNameCtrl = TextEditingController(text: _currentScriptName);

    final content = widget.initialYaml?.trim();

    if (content != null && content.isNotEmpty) {
      _yamlContent = widget.initialYaml!;
      _config = ReverseSqlConfig.parseYaml(_yamlContent);
    } else {
      _config = const ReverseSqlConfig(
        tables: [
          ReverseSqlTableConfig(
            dml: ReverseSqlDml.merge,
            name: '',
            pkAdd: true,
            filters: {},
          ),
        ],
      );
      _yamlContent = _config.toYaml();

      // Si no trajo contenido en memoria pero se especificó una ruta o nombre,
      // intentamos cargar automáticamente el archivo físico desde el disco.
      if (widget.initialFilePath != null &&
          widget.initialFilePath!.isNotEmpty) {
        _tryLoadFromFile(widget.initialFilePath!);
      }
    }
  }

  Future<void> _tryLoadFromFile(String candidatePath) async {
    try {
      File file = File(candidatePath);
      if (!file.existsSync()) {
        // Probar relativa al directorio actual
        final resolved = File(
          '${Directory.current.path}${Platform.pathSeparator}$candidatePath',
        );
        if (resolved.existsSync()) {
          file = resolved;
        }
      }

      if (file.existsSync()) {
        setState(() => _isLoading = true);
        final content = await file.readAsString();
        if (mounted) {
          setState(() {
            _currentFilePath = file.path;
            _currentScriptName = file.path.split(Platform.pathSeparator).last;
            _scriptNameCtrl.text = _currentScriptName;
            _yamlContent = content;
            _config = ReverseSqlConfig.parseYaml(content);
            _isLoading = false;
          });
          AppToast.info('Configuración cargada desde: $_currentScriptName');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _scriptNameCtrl.dispose();
    super.dispose();
  }

  void _switchMode(_ConfigMode newMode) {
    if (_mode == newMode) return;

    if (_mode == _ConfigMode.visual && newMode == _ConfigMode.yaml) {
      // Sincronizar visual -> yaml
      _yamlContent = _config.toYaml();
    } else if (_mode == _ConfigMode.yaml && newMode == _ConfigMode.visual) {
      // Sincronizar yaml -> visual
      try {
        final parsed = ReverseSqlConfig.parseYaml(_yamlContent);
        _config = parsed;
      } catch (e) {
        AppToast.warning(
          'El YAML actual contiene errores de sintaxis; mostrando versión previa en modo visual.',
        );
      }
    }

    setState(() {
      _mode = newMode;
    });
  }

  Future<void> _pickAndOpenFile() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Seleccionar archivo de configuración RSQL (.yaml / .yml)',
        type: FileType.custom,
        allowedExtensions: const ['yaml', 'yml', 'txt'],
      );

      final path = result?.files.single.path;
      if (path == null) return;

      final file = File(path);
      final content = await file.readAsString();
      final fileName = path.split(Platform.pathSeparator).last;

      setState(() {
        _currentFilePath = path;
        _currentScriptName = fileName;
        _scriptNameCtrl.text = fileName;
        _yamlContent = content;
        _config = ReverseSqlConfig.parseYaml(content);
        _isDirty = true;
      });

      AppToast.info('Archivo cargado: $fileName');
    } catch (e) {
      AppToast.error('Error al abrir el archivo YAML: $e');
    }
  }

  Future<void> _saveToFile() async {
    try {
      final contentToSave = _mode == _ConfigMode.visual
          ? _config.toYaml()
          : _yamlContent;

      String? savePath = _currentFilePath;

      savePath ??= await FilePicker.saveFile(
        dialogTitle: 'Guardar configuración YAML',
        fileName: _currentScriptName.isNotEmpty
            ? _currentScriptName
            : 'reverseSql.yaml',
        type: FileType.custom,
        allowedExtensions: const ['yaml', 'yml'],
      );

      if (savePath == null) return;

      final file = File(savePath);
      await file.writeAsString(contentToSave);
      final fileName = savePath.split(Platform.pathSeparator).last;

      setState(() {
        _currentFilePath = savePath;
        _currentScriptName = fileName;
        _isDirty = false;
        _yamlContent = contentToSave;
      });

      widget.onSave?.call(contentToSave, savePath, fileName);
      AppToast.success('Archivo guardado correctamente');
    } catch (e) {
      AppToast.error('Error al guardar el archivo YAML: $e');
    }
  }

  void _onConfirm() {
    final finalYaml = _mode == _ConfigMode.visual
        ? _config.toYaml()
        : _yamlContent;

    widget.onSave?.call(finalYaml, _currentFilePath, _currentScriptName);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1F25) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // Cabecera ConstellationHeader
          ConstellationHeader(
            height: 54,
            onDark: isDark,
            lineColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.3),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF26262B) : const Color(0xFFF6F8FA),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF33353F)
                      : Colors.grey.shade300,
                  width: 0.8,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.settings_suggest_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: isDark ? Colors.white : const Color(0xFF1F2328),
                  ),
                ),
                const SizedBox(width: 12),
                // Input para el nombre de archivo / script
                SizedBox(
                  width: 240,
                  height: 32,
                  child: TextField(
                    controller: _scriptNameCtrl,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Consolas, monospace',
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      isDense: true,
                      hintText: 'Nombre de archivo .yaml',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      prefixIcon: const Icon(
                        Icons.description_outlined,
                        size: 15,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 32,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF16181D)
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0xFF33353F)
                              : Colors.grey.shade300,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0xFF33353F)
                              : Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.2,
                        ),
                      ),
                    ),
                    onChanged: (val) {
                      _currentScriptName = val.trim();
                      _isDirty = true;
                    },
                  ),
                ),
                if (_isDirty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.amber.shade700,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'Modificado',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                // Selector de vista: Visual vs YAML
                SegmentedButton<_ConfigMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _ConfigMode.visual,
                      label: Text('Visual', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.dashboard_customize_outlined, size: 14),
                    ),
                    ButtonSegment(
                      value: _ConfigMode.yaml,
                      label: Text('YAML', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.code_rounded, size: 14),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (set) {
                    if (set.isNotEmpty) _switchMode(set.first);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Cargar desde archivo .yaml',
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  onPressed: _pickAndOpenFile,
                ),
                IconButton(
                  tooltip: 'Guardar como archivo .yaml',
                  icon: const Icon(Icons.save_as_rounded, size: 18),
                  onPressed: _saveToFile,
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Cuerpo interactivo (Visual o YAML)
          Expanded(
            child: _mode == _ConfigMode.visual
                ? ReverseSqlVisualForm(
                    config: _config,
                    onChanged: (updated) {
                      setState(() {
                        _config = updated;
                        _yamlContent = updated.toYaml();
                        _isDirty = true;
                      });
                    },
                  )
                : ReverseSqlYamlEditor(
                    yamlContent: _yamlContent,
                    onChanged: (text) {
                      _yamlContent = text;
                      _isDirty = true;
                      try {
                        _config = ReverseSqlConfig.parseYaml(text);
                      } catch (_) {
                        // Ignorar errores parciales mientras escribe
                      }
                    },
                    onResetTemplate: () {
                      setState(() {
                        _config = const ReverseSqlConfig(
                          tables: [
                            ReverseSqlTableConfig(
                              dml: ReverseSqlDml.merge,
                              name: 'procedimientodinamico',
                              pkAdd: true,
                              filters: {'cd_procedimiento': "= 'EJEMPLO'"},
                            ),
                          ],
                        );
                        _yamlContent = _config.toYaml();
                        _isDirty = true;
                      });
                    },
                  ),
          ),

          // Barra inferior de confirmación
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF262831) : Colors.grey.shade100,
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF33353F)
                      : Colors.grey.shade300,
                ),
              ),
            ),
            child: Row(
              children: [
                if (_isDirty)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.amber),
                      SizedBox(width: 6),
                      Text(
                        'Cambios pendientes',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Aplicar a Ticket'),
                  onPressed: _onConfirm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
