part of 'code_editor_panel.dart';

// ── Status Bar del editor ───────────────────────────────────────────────────────────────────────────────────────────

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
