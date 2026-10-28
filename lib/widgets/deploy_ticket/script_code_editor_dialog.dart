import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_toast.dart';
import '../floating_window.dart' show showFloatingDialog;
import '../monaco_editor_widget.dart';

/// Diálogo flotante para edición de scripts (SQL / Bloques Lógicos BLK)
/// utilizando `MonacoEditorWidget` para la edición manual de código.
class ScriptCodeEditorDialog extends StatefulWidget {
  final String? initialCode;
  final String? initialFilePath;
  final String? scriptName;
  final String title;
  final String language; // 'plsql', 'sql'
  final Color themeColor;
  final IconData icon;
  final void Function(String codeContent, String? filePath, String scriptName)?
  onSave;

  const ScriptCodeEditorDialog({
    super.key,
    this.initialCode,
    this.initialFilePath,
    this.scriptName,
    this.title = 'Editor de Script',
    this.language = 'plsql',
    this.themeColor = Colors.teal,
    this.icon = Icons.code_rounded,
    this.onSave,
  });

  /// Muestra el diálogo como ventana flotante modal.
  static Future<void> show(
    BuildContext context, {
    String? initialCode,
    String? initialFilePath,
    String? scriptName,
    String title = 'Editor de Script',
    String language = 'plsql',
    Color themeColor = Colors.teal,
    IconData icon = Icons.code_rounded,
    void Function(String codeContent, String? filePath, String scriptName)?
    onSave,
  }) {
    return showFloatingDialog<void>(
      context,
      (dialogContext, close) => ScriptCodeEditorDialog(
        initialCode: initialCode,
        initialFilePath: initialFilePath,
        scriptName: scriptName,
        title: title,
        language: language,
        themeColor: themeColor,
        icon: icon,
        onSave: onSave,
      ),
    );
  }

  @override
  State<ScriptCodeEditorDialog> createState() => _ScriptCodeEditorDialogState();
}

class _ScriptCodeEditorDialogState extends State<ScriptCodeEditorDialog> {
  late final MonacoEditorController _monacoCtrl;
  late String _codeContent;
  String? _currentFilePath;
  late String _currentScriptName;
  late final TextEditingController _nameController;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _monacoCtrl = MonacoEditorController();
    _currentFilePath = widget.initialFilePath;
    _currentScriptName =
        widget.scriptName ??
        (widget.initialFilePath != null
            ? widget.initialFilePath!.split(Platform.pathSeparator).last
            : 'script.sql');

    _nameController = TextEditingController(text: _currentScriptName);

    final content = widget.initialCode?.trim();
    if (content != null && content.isNotEmpty) {
      _codeContent = widget.initialCode!;
    } else {
      _codeContent = '';
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
        final resolved = File(
          '${Directory.current.path}${Platform.pathSeparator}$candidatePath',
        );
        if (resolved.existsSync()) {
          file = resolved;
        }
      }

      if (file.existsSync()) {
        final content = await file.readAsString();
        if (mounted) {
          setState(() {
            _codeContent = content;
            _currentFilePath = file.path;
            _currentScriptName = file.path.split(Platform.pathSeparator).last;
            _nameController.text = _currentScriptName;
          });
          _monacoCtrl.setText(content);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAndOpenFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['sql', 'pls', 'plsql', 'txt', 'prc', 'pck'],
        dialogTitle: 'Seleccionar archivo de script',
      );

      final path = result?.files.single.path;
      if (path == null) return;

      final file = File(path);
      final content = await file.readAsString();
      final fileName = path.split(Platform.pathSeparator).last;

      setState(() {
        _currentFilePath = path;
        _currentScriptName = fileName;
        _nameController.text = fileName;
        _codeContent = content;
        _isDirty = true;
      });

      _monacoCtrl.setText(content);

      AppToast.info('Archivo cargado: $fileName');
    } catch (e) {
      AppToast.error('Error al abrir archivo de script: $e');
    }
  }

  Future<void> _saveToFile() async {
    try {
      final currentCode = await _monacoCtrl.getText() ?? _codeContent;
      String? savePath = _currentFilePath;

      savePath ??= await FilePicker.saveFile(
        dialogTitle: 'Guardar script en disco',
        fileName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : 'script.sql',
        type: FileType.custom,
        allowedExtensions: const ['sql', 'txt', 'pls'],
      );

      if (savePath == null) return;

      final file = File(savePath);
      await file.writeAsString(currentCode);
      final fileName = savePath.split(Platform.pathSeparator).last;

      setState(() {
        _currentFilePath = savePath;
        _currentScriptName = fileName;
        _nameController.text = fileName;
        _isDirty = false;
        _codeContent = currentCode;
      });

      widget.onSave?.call(currentCode, savePath, fileName);
      AppToast.success('Script guardado en disco: $fileName');
    } catch (e) {
      AppToast.error('Error al guardar archivo: $e');
    }
  }

  Future<void> _onConfirm() async {
    final finalCode = await _monacoCtrl.getText() ?? _codeContent;
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : _currentScriptName;
    widget.onSave?.call(finalCode, _currentFilePath, name);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1F25) : Colors.white;
    final borderColor = isDark ? const Color(0xFF33353F) : Colors.grey.shade300;

    return Container(
      color: bg,
      child: Column(
        children: [
          // Barra de cabecera y herramientas
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF26262B) : const Color(0xFFF6F8FA),
              border: Border(
                bottom: BorderSide(color: borderColor, width: 0.8),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: widget.themeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(widget.icon, size: 16, color: widget.themeColor),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 14),
                // Input estilizado para renombrar / ver nombre del artefacto
                SizedBox(
                  width: 250,
                  height: 32,
                  child: TextField(
                    controller: _nameController,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Consolas, monospace',
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      isDense: true,
                      hintText: 'Nombre del archivo',
                      prefixIcon: const Icon(Icons.edit_note_rounded, size: 16),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E1F25)
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: widget.themeColor,
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
                IconButton(
                  tooltip: 'Cargar desde archivo en disco',
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  onPressed: _pickAndOpenFile,
                ),
                IconButton(
                  tooltip: 'Guardar archivo en disco',
                  icon: const Icon(Icons.save_as_rounded, size: 18),
                  onPressed: _saveToFile,
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Área del editor de código Monaco
          Expanded(
            child: MonacoEditorWidget(
              controller: _monacoCtrl,
              initialCode: _codeContent,
              language: widget.language,
              darkTheme: isDark,
              onChanged: (text) {
                _codeContent = text;
                if (!_isDirty) {
                  setState(() => _isDirty = true);
                }
              },
            ),
          ),

          // Barra inferior de confirmación
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF25262E) : Colors.grey.shade50,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                if (_currentFilePath != null)
                  Expanded(
                    child: Text(
                      'Ruta: $_currentFilePath',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Text(
                      'Este contenido se enviará en el ticket al servicio para guardarse en la BD.',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.themeColor,
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Aplicar y Guardar Cuerpo'),
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
