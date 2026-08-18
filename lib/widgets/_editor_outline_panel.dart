part of 'code_editor_panel.dart';

// ── Outline data model ────────────────────────────────────────────────────────

enum _OutlineItemType {
  variable,
  cursor,
  procedure,
  function,
  exception,
  call,
  dml,
}

class _OutlineItem {
  final _OutlineItemType type;
  final String name;
  final int line;
  const _OutlineItem({
    required this.type,
    required this.name,
    required this.line,
  });
}

// ── Outline parser ────────────────────────────────────────────────────────────

// Word-boundary match — works for inline definitions and CREATE OR REPLACE
final _reProcFunc = RegExp(
  r'\b(PROCEDURE|FUNCTION)\s+(\w+)',
  caseSensitive: false,
);
final _reCursor = RegExp(r'\bCURSOR\s+(\w+)', caseSensitive: false);
// Marks the start of the PL/SQL exception-handling section
final _reExceptionSection = RegExp(r'^\s*EXCEPTION\b', caseSensitive: false);
// Matches WHEN <name> THEN allowing any whitespace/newlines between tokens
final _reWhenThen = RegExp(r'\bWHEN\s+(\w+)\s+THEN\b', caseSensitive: false);
final _reEndBlock = RegExp(r'^\s*END\b', caseSensitive: false);
final _reKeywords = RegExp(
  r'^(BEGIN|END|IF|THEN|ELSE|ELSIF|FOR|LOOP|WHILE|DECLARE|EXCEPTION|WHEN|CURSOR|RETURN|PROCEDURE|FUNCTION|TYPE|SUBTYPE|PRAGMA|SELECT|UPDATE|DELETE|INSERT|INTO|FROM|WHERE|NULL|RAISE|COMMIT|ROLLBACK|AND|OR|NOT|IN|OUT|IS|AS)$',
  caseSensitive: false,
);
final _reDeclare = RegExp(r'^\s*DECLARE\b', caseSensitive: false);
// IS/AS at end of a proc/function header signals the start of its declare section
final _reIsAs = RegExp(r'\bIS\s*$|\bAS\s*$', caseSensitive: false);
final _reBegin = RegExp(r'^\s*BEGIN\b', caseSensitive: false);

// Detects any identifier≥4 chars followed by ( — catches function/procedure calls
final _reCall = RegExp(r'\b([A-Za-z_]\w{3,})\s*\(', caseSensitive: false);

// Oracle SQL/PL/SQL built-ins to exclude from call detection
const _sqlBuiltins = {
  'CASE', 'WHEN', 'THEN', 'ELSE', 'ELSIF', 'LOOP', 'WHILE',
  'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'FROM', 'WHERE', 'INTO',
  'EXECUTE', 'IMMEDIATE', 'OPEN', 'CLOSE', 'FETCH', 'RAISE', 'RETURN',
  'BEGIN', 'DECLARE', 'EXCEPTION', 'PROCEDURE', 'FUNCTION', 'PRAGMA',
  'NULL', 'TRUE', 'FALSE', 'COMMIT', 'ROLLBACK',
  // Oracle built-in functions (4+ chars)
  'COALESCE', 'NULLIF', 'DECODE', 'LNNVL',
  'TO_CHAR', 'TO_DATE', 'TO_NUMBER', 'TO_CLOB', 'TO_BLOB', 'TO_NCHAR',
  'SUBSTR', 'INSTR', 'LENGTH', 'UPPER', 'LOWER', 'INITCAP',
  'TRIM', 'LTRIM', 'RTRIM', 'REPLACE', 'TRANSLATE', 'LPAD', 'RPAD',
  'SYSDATE', 'SYSTIMESTAMP', 'TRUNC', 'ROUND', 'CEIL', 'FLOOR',
  'MONTHS_BETWEEN', 'ADD_MONTHS', 'NEXT_DAY', 'LAST_DAY', 'EXTRACT',
  'POWER', 'SQRT', 'SIGN', 'SQLCODE', 'SQLERRM',
  'COUNT', 'OVER', 'PARTITION', 'RANK', 'DENSE_RANK', 'ROWNUM',
  'RAISE_APPLICATION_ERROR', 'DBMS_OUTPUT', 'DBMS_SQL', 'DBMS_LOCK',
  'UTL_FILE', 'UTL_RAW', 'TYPE', 'RECORD', 'TABLE',
};

// Matches a user-defined exception declaration: `exc_name EXCEPTION`
final _reExceptionDecl = RegExp(
  r'^\s*(\w+)\s+EXCEPTION\s*$',
  caseSensitive: false,
);
// Matches DML statements that start a line: INSERT INTO, UPDATE, DELETE FROM, MERGE INTO
final _reDmlStart = RegExp(
  r'^\s*(INSERT\s+INTO|UPDATE|DELETE\s+FROM|MERGE\s+INTO)\s+(\w[\w\.]*)',
  caseSensitive: false,
);

List<_OutlineItem> _parseOutlineItems(String code) {
  final items = <_OutlineItem>[];
  final lines = code.split('\n');
  bool inDeclare = false;
  bool inException = false;
  final excBuffer = StringBuffer();
  final varBuffer = StringBuffer();
  final seenExceptions = <String>{};

  for (int i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final lineNum = i + 1;

    // Skip comment lines
    if (raw.trimLeft().startsWith('--')) continue;

    // PROCEDURE / FUNCTION — detected anywhere on the line
    final procFuncMatch = _reProcFunc.firstMatch(raw);
    if (procFuncMatch != null) {
      final isProcedure = procFuncMatch.group(1)!.toUpperCase() == 'PROCEDURE';
      items.add(
        _OutlineItem(
          type: isProcedure
              ? _OutlineItemType.procedure
              : _OutlineItemType.function,
          name: procFuncMatch.group(2)!,
          line: lineNum,
        ),
      );
      // Header ending with IS/AS → the following lines are the declare section
      if (_reIsAs.hasMatch(raw)) inDeclare = true;
      continue;
    }

    // DECLARE keyword (anonymous blocks / nested blocks)
    if (_reDeclare.hasMatch(raw)) {
      inDeclare = true;
      varBuffer.clear();
      continue;
    }

    // BEGIN ends the declare section and any exception block
    if (_reBegin.hasMatch(raw)) {
      inDeclare = false;
      inException = false;
      excBuffer.clear();
      varBuffer.clear();
      continue;
    }

    // EXCEPTION keyword marks the start of the exception-handling section
    if (_reExceptionSection.hasMatch(raw)) {
      inDeclare = false;
      inException = true;
      excBuffer.clear();
      // Handle content on the same line after EXCEPTION (rare but valid)
      final afterKw = raw.replaceFirstMapped(_reExceptionSection, (_) => '');
      if (afterKw.trim().isNotEmpty) excBuffer.write(afterKw);
      continue;
    }

    // END closes the exception section
    if (inException && _reEndBlock.hasMatch(raw)) {
      inException = false;
      excBuffer.clear();
    }

    // Accumulate lines inside the exception block; extract WHEN x THEN (multiline)
    if (inException) {
      excBuffer.write(' ');
      excBuffer.write(raw);
      final accumulated = excBuffer.toString();
      final matches = _reWhenThen.allMatches(accumulated).toList();
      if (matches.isNotEmpty) {
        for (final m in matches) {
          final name = m.group(1)!;
          if (!_reKeywords.hasMatch(name) &&
              seenExceptions.add(name.toUpperCase())) {
            items.add(
              _OutlineItem(
                type: _OutlineItemType.exception,
                name: name,
                line: lineNum,
              ),
            );
          }
        }
        excBuffer.clear();
        excBuffer.write(accumulated.substring(matches.last.end));
      }
      continue;
    }

    // Declare section: accumulate lines and split on ';' — the only declaration delimiter
    if (inDeclare) {
      // Strip inline comment before buffering
      final stripped = raw.contains('--')
          ? raw.substring(0, raw.indexOf('--'))
          : raw;
      varBuffer.write(' ');
      varBuffer.write(stripped);

      final accumulated = varBuffer.toString();
      if (!accumulated.contains(';')) continue;

      final segments = accumulated.split(';');
      final incomplete = segments.removeLast(); // text after the last ';'

      for (final seg in segments) {
        final t = seg.trim();
        if (t.isEmpty) continue;

        // CURSOR declaration
        final cursorMatch = _reCursor.firstMatch(t);
        if (cursorMatch != null) {
          items.add(
            _OutlineItem(
              type: _OutlineItemType.cursor,
              name: cursorMatch.group(1)!,
              line: lineNum,
            ),
          );
          continue;
        }

        // User-defined exception declaration: `exc_name EXCEPTION`
        final excDeclMatch = _reExceptionDecl.firstMatch(t);
        if (excDeclMatch != null) {
          final name = excDeclMatch.group(1)!;
          if (seenExceptions.add(name.toUpperCase())) {
            items.add(
              _OutlineItem(
                type: _OutlineItemType.exception,
                name: name,
                line: lineNum,
              ),
            );
          }
          continue;
        }

        // Variable: first identifier of the declaration
        final firstIdent = RegExp(r'^\s*(\w+)').firstMatch(t);
        if (firstIdent != null) {
          final name = firstIdent.group(1)!;
          if (!_reKeywords.hasMatch(name)) {
            items.add(
              _OutlineItem(
                type: _OutlineItemType.variable,
                name: name,
                line: lineNum,
              ),
            );
          }
        }
      }

      varBuffer.clear();
      varBuffer.write(incomplete);
      continue;
    }

    // Standalone IS/AS at end of line — multi-line proc signatures like `) IS`
    if (_reIsAs.hasMatch(raw) && !_reCursor.hasMatch(raw)) {
      inDeclare = true;
      varBuffer.clear();
      continue;
    }
  }

  // Second pass: collect function/procedure calls (any identifier followed by `(`)
  final knownNames = items.map((i) => i.name.toUpperCase()).toSet();
  final seenCalls = <String>{};
  for (int i = 0; i < lines.length; i++) {
    final raw = lines[i];
    if (raw.trimLeft().startsWith('--')) continue;
    for (final m in _reCall.allMatches(raw)) {
      final upper = m.group(1)!.toUpperCase();
      if (!_sqlBuiltins.contains(upper) &&
          !knownNames.contains(upper) &&
          !seenCalls.contains(upper)) {
        seenCalls.add(upper);
        items.add(
          _OutlineItem(
            type: _OutlineItemType.call,
            name: m.group(1)!,
            line: i + 1,
          ),
        );
      }
    }
  }

  // Third pass: DML statements — one entry per verb, cycling navigates all occurrences
  final seenDml = <String>{};
  for (int i = 0; i < lines.length; i++) {
    final raw = lines[i];
    if (raw.trimLeft().startsWith('--')) continue;
    final m = _reDmlStart.firstMatch(raw);
    if (m != null) {
      final verb = m.group(1)!.split(RegExp(r'\s+')).first.toUpperCase();
      if (seenDml.add(verb)) {
        items.add(
          _OutlineItem(type: _OutlineItemType.dml, name: verb, line: i + 1),
        );
      }
    }
  }

  return items;
}

// ── Outline panel widget ──────────────────────────────────────────────────────

class _EditorOutlinePanel extends StatefulWidget {
  final List<_OutlineItem> items;
  final Future<void> Function(int line) onItemTap;
  final VoidCallback onClose;
  // name.toUpperCase() → object type (PROCEDURE/FUNCTION/PACKAGE/...)
  final Map<String, String>? schemaObjects;
  final String ambiente;
  final String code;

  const _EditorOutlinePanel({
    required this.items,
    required this.onItemTap,
    required this.onClose,
    required this.ambiente,
    required this.code,
    this.schemaObjects,
  });

  @override
  State<_EditorOutlinePanel> createState() => _EditorOutlinePanelState();
}

class _EditorOutlinePanelState extends State<_EditorOutlinePanel> {
  final _groups = <_OutlineItemType, bool>{};
  String? _usageItemKey;
  List<int> _usageLines = [];
  int _usageIndex = 0;
  bool _varsShowAll = false;

  static const _kVarsPreview = 5;

  // Variables expand by default; everything else collapses
  bool _isExpanded(_OutlineItemType type) =>
      _groups[type] ?? (type == _OutlineItemType.variable);

  void _toggleGroup(_OutlineItemType type) {
    setState(() => _groups[type] = !_isExpanded(type));
  }

  Future<void> _handleItemTap(_OutlineItem item) async {
    final key = item.name.toUpperCase();
    if (_usageItemKey == key && _usageLines.isNotEmpty) {
      setState(() => _usageIndex = (_usageIndex + 1) % _usageLines.length);
    } else {
      final usages = _findUsages(item.name, widget.code);
      setState(() {
        _usageItemKey = key;
        _usageLines = usages;
        _usageIndex = 0;
      });
    }
    if (_usageLines.isNotEmpty) {
      await widget.onItemTap(_usageLines[_usageIndex]);
    }
  }

  // Returns 1-based line numbers of every word-boundary match for [name]
  List<int> _findUsages(String name, String code) {
    final pattern = RegExp(
      r'\b' + RegExp.escape(name) + r'\b',
      caseSensitive: false,
    );
    final result = <int>[];
    final lines = code.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (!lines[i].trimLeft().startsWith('--') && pattern.hasMatch(lines[i])) {
        result.add(i + 1);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final grouped = <_OutlineItemType, List<_OutlineItem>>{};
    for (final item in widget.items) {
      // Skip calls not found in the schema — only verified invocations are shown
      if (item.type == _OutlineItemType.call &&
          (widget.schemaObjects == null ||
              !widget.schemaObjects!.containsKey(item.name.toUpperCase()))) {
        continue;
      }
      grouped.putIfAbsent(item.type, () => []).add(item);
    }
    final order = [
      _OutlineItemType.procedure,
      _OutlineItemType.function,
      _OutlineItemType.cursor,
      _OutlineItemType.variable,
      _OutlineItemType.call,
      _OutlineItemType.exception,
      _OutlineItemType.dml,
    ];

    return Container(
      width: 190,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : cs.surfaceContainerLow,
        border: Border(left: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            height: 28,
            color: isDark
                ? cs.surfaceContainerHigh
                : cs.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 13,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Outline',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: widget.items.isEmpty
                ? Center(
                    child: Text(
                      'Sin símbolos detectados',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final type in order)
                        if (grouped.containsKey(type)) ...[
                          _GroupHeader(
                            type: type,
                            count: grouped[type]!.length,
                            expanded: _isExpanded(type),
                            onToggle: () => _toggleGroup(type),
                          ),
                          if (_isExpanded(type)) ...[
                            for (final item
                                in (type == _OutlineItemType.variable &&
                                        !_varsShowAll
                                    ? grouped[type]!.take(_kVarsPreview)
                                    : grouped[type]!)) ...[
                              Builder(
                                builder: (ctx) {
                                  final isCall =
                                      item.type == _OutlineItemType.call;
                                  final schema = widget.schemaObjects;
                                  final sType = isCall
                                      ? (schema != null
                                            ? schema[item.name.toUpperCase()]
                                            : null)
                                      : null;
                                  return _OutlineItemTile(
                                    item: item,
                                    onTap: () => _handleItemTap(item),
                                    schemaType: sType,
                                    usageLabel:
                                        _usageItemKey == item.name.toUpperCase()
                                        ? '${_usageIndex + 1}/${_usageLines.length}'
                                        : null,
                                    onGoToDefinition: sType != null
                                        ? (c) => openSourceWindow(
                                            c,
                                            name: item.name.toUpperCase(),
                                            objectType: sType,
                                            ambiente: widget.ambiente,
                                          )
                                        : null,
                                  );
                                },
                              ),
                            ],
                            if (type == _OutlineItemType.variable &&
                                !_varsShowAll &&
                                grouped[type]!.length > _kVarsPreview)
                              _VerMasButton(
                                remaining:
                                    grouped[type]!.length - _kVarsPreview,
                                onTap: () =>
                                    setState(() => _varsShowAll = true),
                              ),
                          ],
                        ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final _OutlineItemType type;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  const _GroupHeader({
    required this.type,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  static String _label(_OutlineItemType t) => switch (t) {
    _OutlineItemType.procedure => 'PROCEDIMIENTOS',
    _OutlineItemType.function => 'FUNCIONES',
    _OutlineItemType.cursor => 'CURSORES',
    _OutlineItemType.variable => 'VARIABLES',
    _OutlineItemType.exception => 'EXCEPCIONES',
    _OutlineItemType.call => 'INVOCACIONES',
    _OutlineItemType.dml => 'DML',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 13,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 2),
            Text(
              _label(type),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '($count)',
              style: TextStyle(
                fontSize: 9,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineItemTile extends StatelessWidget {
  final _OutlineItem item;
  final VoidCallback onTap;
  // Non-null for calls that exist in the schema — shows type badge + goto button
  final String? schemaType;
  final void Function(BuildContext ctx)? onGoToDefinition;
  // Non-null while cycling usages — shows current position e.g. "2/5"
  final String? usageLabel;

  const _OutlineItemTile({
    required this.item,
    required this.onTap,
    this.schemaType,
    this.onGoToDefinition,
    this.usageLabel,
  });

  static IconData _icon(_OutlineItemType t) => switch (t) {
    _OutlineItemType.procedure => Icons.settings_outlined,
    _OutlineItemType.function => Icons.functions,
    _OutlineItemType.cursor => Icons.compare_arrows,
    _OutlineItemType.variable => Icons.data_array,
    _OutlineItemType.exception => Icons.warning_amber_rounded,
    _OutlineItemType.call => Icons.call_made,
    _OutlineItemType.dml => Icons.storage_rounded,
  };

  static Color _color(_OutlineItemType t) => switch (t) {
    _OutlineItemType.procedure => const Color(0xFF569CD6),
    _OutlineItemType.function => const Color(0xFFDCDCAA),
    _OutlineItemType.cursor => const Color(0xFF4EC9B0),
    _OutlineItemType.variable => const Color(0xFF9CDCFE),
    _OutlineItemType.exception => const Color(0xFFCE9178),
    _OutlineItemType.call => const Color(0xFFB5CEA8),
    _OutlineItemType.dml => const Color(0xFFE06C75),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isVerifiedCall =
        item.type == _OutlineItemType.call && schemaType != null;
    final color = isVerifiedCall
        ? _color(item.type)
        : (item.type == _OutlineItemType.call
              ? cs.onSurfaceVariant.withValues(
                  alpha: 0.35,
                ) // unknown call — muted
              : _color(item.type));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 3, 4, 3),
        child: Row(
          children: [
            Icon(_icon(item.type), size: 12, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  overflow: TextOverflow.ellipsis,
                  color: item.type == _OutlineItemType.call && !isVerifiedCall
                      ? cs.onSurfaceVariant.withValues(alpha: 0.45)
                      : null,
                ),
                maxLines: 1,
              ),
            ),
            // Schema type badge for verified calls
            if (isVerifiedCall) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: _color(_OutlineItemType.call).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _color(_OutlineItemType.call).withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  schemaType!.substring(0, 3), // PRO / FUN / PAC
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: _color(_OutlineItemType.call),
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
            ],
            if (item.type != _OutlineItemType.call) ...[
              const SizedBox(width: 4),
              usageLabel != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        usageLabel!,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    )
                  : Text(
                      ':${item.line}',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                        fontFamily: 'Consolas',
                      ),
                    ),
            ],
            // Go-to-definition button for schema-verified calls
            if (onGoToDefinition != null)
              Tooltip(
                message: 'Ir a definición ($schemaType)',
                child: InkWell(
                  onTap: () => onGoToDefinition!(context),
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.open_in_new,
                      size: 11,
                      color: _color(_OutlineItemType.call),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _VerMasButton extends StatelessWidget {
  final int remaining;
  final VoidCallback onTap;

  const _VerMasButton({required this.remaining, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
        child: Row(
          children: [
            Icon(Icons.expand_more, size: 12, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              'ver más ($remaining más)',
              style: TextStyle(
                fontSize: 10,
                color: cs.primary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
