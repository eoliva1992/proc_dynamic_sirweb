import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import '../models/procedimiento.dart';

class CodeEditorPanel extends StatefulWidget {
  final Procedimiento procedimiento;

  const CodeEditorPanel({super.key, required this.procedimiento});

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Two frames ensure DWM/DirectComposition is ready before WebView2 init.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _ready = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    return MonacoEditor(
      initialText: widget.procedimiento.deTexto,
      options: EditorOptions(
        language: widget.procedimiento.inConfiguracion == 'J'
            ? MonacoLanguage.javascript
            : MonacoLanguage.sql,
        theme: Theme.of(context).brightness == Brightness.dark
            ? MonacoTheme.vsDark
            : MonacoTheme.vs,
        fontSize: 14,
        minimap: const MonacoMinimapOptions(enabled: true),
        wordWrap: MonacoWordWrap.off,
        lineNumbers: MonacoLineNumbers.on,
        renderWhitespace: RenderWhitespace.none,
        tabSize: 2,
      ),
      // contentDebounce: const Duration(milliseconds: 800),
      onError: (err, _) => debugPrint('Monaco error: $err'),
    );
  }
}
