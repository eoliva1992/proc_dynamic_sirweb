import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

/// Abre un diálogo de pantalla completa con el diff de un procedimiento.
Future<void> showProcedureDiff(
  BuildContext context, {
  required String title,
  required String original,
  required String modified,
  required String language, // 'sql' | 'javascript'
}) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
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
  bool _sideBySide = true;
  MonacoDiffController? _ctrl;

  Future<void> _onReady(MonacoDiffController ctrl) async {
    _ctrl = ctrl;
    // MonacoDiffController no expone defineTheme — usar tema predefinido vía options
  }

  Future<void> _toggleLayout() async {
    final next = !_sideBySide;
    setState(() => _sideBySide = next);
    await _ctrl?.updateDiffOptions(MonacoDiffOptions(renderSideBySide: next));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      child: Column(
        children: [
          // ── Barra del diff
          Container(
            height: 40,
            color: isDark ? cs.surfaceContainerHighest : cs.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cerrar',
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  icon: Icon(
                    _sideBySide ? Icons.view_compact_alt : Icons.view_sidebar,
                    size: 14,
                  ),
                  label: Text(_sideBySide ? 'Inline' : 'Side by side'),
                  onPressed: _toggleLayout,
                ),
              ],
            ),
          ),
          // ── Diff editor
          Expanded(
            child: MonacoDiffEditor(
              original: widget.original,
              modified: widget.modified,
              language: MonacoLanguage(widget.language),
              diffOptions: MonacoDiffOptions(
                renderSideBySide: _sideBySide,
                ignoreTrimWhitespace: false,
              ),
              options: EditorOptions(
                theme: isDark ? MonacoTheme.vsDark : MonacoTheme.vs,
                fontSize: 13,
                minimap: const MonacoMinimapOptions(enabled: false),
                lineNumbers: MonacoLineNumbers.on,
                wordWrap: MonacoWordWrap.off,
              ),
              onReady: _onReady,
            ),
          ),
        ],
      ),
    );
  }
}
