part of 'code_editor_panel.dart';

// ── Opciones & Preferencias ───────────────────────────────────────────────────

extension _EditorOptionsMethods on _CodeEditorPanelState {
  void _resetAllOptions() {
    setState(() {
      _minimap = true;
      _lineNumbers = true;
      _folding = true;
      _readOnly = false;
      _fontSize = 14.0;
      _wordWrap = false;
      _renderWhitespace = false;
      _bracketPairColorization = true;
      _stickyScroll = true;
      _smoothScrolling = false;
      _mouseWheelZoom = false;
      _formatOnPaste = false;
      _quickSuggestions = true;
      _parameterHints = true;
      _hover = true;
      _links = true;
      _occurrencesHighlight = true;
      _contextMenu = true;
    });
    _applyEditorOptions();
    _savePrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _minimap = prefs.getBool('editor_minimap') ?? true;
      _lineNumbers = prefs.getBool('editor_line_numbers') ?? true;
      _folding = prefs.getBool('editor_folding') ?? true;
      _readOnly = prefs.getBool('editor_readonly') ?? false;
      _fontSize = prefs.getDouble('editor_font_size') ?? 14.0;
      _wordWrap = prefs.getBool('editor_word_wrap') ?? false;
      _renderWhitespace = prefs.getBool('editor_render_whitespace') ?? false;
      _bracketPairColorization =
          prefs.getBool('editor_bracket_colorization') ?? true;
      _stickyScroll = prefs.getBool('editor_sticky_scroll') ?? true;
      _smoothScrolling = prefs.getBool('editor_smooth_scrolling') ?? false;
      _mouseWheelZoom = prefs.getBool('editor_mouse_wheel_zoom') ?? false;
      _formatOnPaste = prefs.getBool('editor_format_on_paste') ?? false;
      _quickSuggestions = prefs.getBool('editor_quick_suggestions') ?? true;
      _parameterHints = prefs.getBool('editor_parameter_hints') ?? true;
      _hover = prefs.getBool('editor_hover') ?? true;
      _links = prefs.getBool('editor_links') ?? true;
      _occurrencesHighlight =
          prefs.getBool('editor_occurrences_highlight') ?? true;
      _contextMenu = prefs.getBool('editor_context_menu') ?? true;
      _problemsPanelHeight = prefs.getDouble('editor_problems_height') ?? 180.0;
      _showOutline = prefs.getBool('editor_show_outline') ?? false;
      _varsDocked = prefs.getBool('editor_vars_docked') ?? false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('editor_minimap', _minimap);
    await prefs.setBool('editor_line_numbers', _lineNumbers);
    await prefs.setBool('editor_folding', _folding);
    await prefs.setBool('editor_readonly', _readOnly);
    await prefs.setDouble('editor_font_size', _fontSize);
    await prefs.setBool('editor_word_wrap', _wordWrap);
    await prefs.setBool('editor_render_whitespace', _renderWhitespace);
    await prefs.setBool(
      'editor_bracket_colorization',
      _bracketPairColorization,
    );
    await prefs.setBool('editor_sticky_scroll', _stickyScroll);
    await prefs.setBool('editor_smooth_scrolling', _smoothScrolling);
    await prefs.setBool('editor_mouse_wheel_zoom', _mouseWheelZoom);
    await prefs.setBool('editor_format_on_paste', _formatOnPaste);
    await prefs.setBool('editor_quick_suggestions', _quickSuggestions);
    await prefs.setBool('editor_parameter_hints', _parameterHints);
    await prefs.setBool('editor_hover', _hover);
    await prefs.setBool('editor_links', _links);
    await prefs.setBool('editor_occurrences_highlight', _occurrencesHighlight);
    await prefs.setBool('editor_context_menu', _contextMenu);
    await prefs.setDouble('editor_problems_height', _problemsPanelHeight);
    await prefs.setBool('editor_show_outline', _showOutline);
    await prefs.setBool('editor_vars_docked', _varsDocked);
  }

  void _applyEditorOptions() {
    // _loadPrefs() es async: al volver, el panel puede haberse cerrado y el
    // controller estar destruido — _withCtrl absorbe MonacoDisposedError.
    unawaited(
      _withCtrl(
        (ctrl) => ctrl.updateOptions(
          EditorOptions(
            minimap: MonacoMinimapOptions(enabled: _minimap),
            lineNumbers: _lineNumbers
                ? MonacoLineNumbers.on
                : MonacoLineNumbers.off,
            folding: _folding,
            readOnly: _readOnly,
            fontSize: _fontSize,
            wordWrap: _wordWrap ? MonacoWordWrap.on : MonacoWordWrap.off,
            renderWhitespace: _renderWhitespace
                ? RenderWhitespace.all
                : RenderWhitespace.none,
            bracketPairColorization: _bracketPairColorization,
            stickyScroll: MonacoStickyScroll(enabled: _stickyScroll),
            smoothScrolling: _smoothScrolling,
            mouseWheelZoom: _mouseWheelZoom,
            formatOnPaste: _formatOnPaste,
            quickSuggestions: _quickSuggestions,
            parameterHints: _parameterHints,
            hover: _hover,
            links: _links,
            occurrencesHighlight: _occurrencesHighlight,
            contextMenu: _contextMenu,
          ),
        ),
      ),
    );
  }

  void _toggle(VoidCallback fn) {
    setState(fn);
    _applyEditorOptions();
    _savePrefs();
  }
}
