part of 'code_editor_panel.dart';

// ── Folding SQL: BEGIN / IF / LOOP / CASE ──────────────────────────────────────────────────────────────────────────
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

// ── Builder combinado: variables + sintaxis ──────────────────────────────────────────────────────────────────────────
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

// ── Prompt personalizado para variables dinámicas ────────────────────────────────────────────────────────────────────

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

// ── Popup de autocomplete ──────────────────────────────────────────────────────────────────────────────────────────────

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
