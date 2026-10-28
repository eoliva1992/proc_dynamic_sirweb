import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_toast.dart';
import '../monaco_editor_widget.dart';

/// Editor de código Monaco para YAML con barra de herramientas profesional,
/// validación básica, copiado y restablecimiento de plantilla.
class ReverseSqlYamlEditor extends StatefulWidget {
  final String yamlContent;
  final ValueChanged<String> onChanged;
  final VoidCallback? onResetTemplate;

  const ReverseSqlYamlEditor({
    super.key,
    required this.yamlContent,
    required this.onChanged,
    this.onResetTemplate,
  });

  @override
  State<ReverseSqlYamlEditor> createState() => _ReverseSqlYamlEditorState();
}

class _ReverseSqlYamlEditorState extends State<ReverseSqlYamlEditor> {
  late final MonacoEditorController _monacoCtrl;
  String _currentText = '';

  @override
  void initState() {
    super.initState();
    _monacoCtrl = MonacoEditorController();
    _currentText = widget.yamlContent;
  }

  @override
  void didUpdateWidget(ReverseSqlYamlEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.yamlContent != oldWidget.yamlContent &&
        widget.yamlContent != _currentText) {
      _currentText = widget.yamlContent;
      _monacoCtrl.setText(widget.yamlContent);
    }
  }

  @override
  void dispose() {
    _monacoCtrl.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    final text = await _monacoCtrl.getText() ?? _currentText;
    await Clipboard.setData(ClipboardData(text: text));
    AppToast.info('Contenido YAML copiado al portapapeles');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? const Color(0xFF33353F) : Colors.grey.shade300;

    return Column(
      children: [
        // Barra de acciones superiores del editor YAML
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF25262E) : Colors.grey.shade100,
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(
                  Icons.data_object_rounded,
                  size: 15,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'reverseSql.yaml',
                style: TextStyle(
                  fontFamily: 'Consolas, monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.teal.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: const Text(
                  'Monaco YAML',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal,
                  ),
                ),
              ),
              const Spacer(),
              if (widget.onResetTemplate != null)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(60, 28),
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 14),
                  label: const Text(
                    'Plantilla Guía',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () {
                    widget.onResetTemplate?.call();
                  },
                ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Copiar todo al portapapeles',
                icon: const Icon(Icons.copy_all_rounded, size: 16),
                onPressed: _copyToClipboard,
              ),
            ],
          ),
        ),

        // Área del editor Monaco
        Expanded(
          child: MonacoEditorWidget(
            controller: _monacoCtrl,
            initialCode: _currentText,
            language: 'yaml',
            darkTheme: isDark,
            onChanged: (text) {
              _currentText = text;
              widget.onChanged(text);
            },
          ),
        ),
      ],
    );
  }
}
