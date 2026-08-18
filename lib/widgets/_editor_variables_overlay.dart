part of 'code_editor_panel.dart';

class _VarsMenuOverlay extends StatefulWidget {
  final double left;
  final double top;
  final double width;
  final List<VariableDinamica> vars;
  final Future<void> Function(VariableDinamica) onSelected;

  const _VarsMenuOverlay({
    required this.left,
    required this.top,
    required this.width,
    required this.vars,
    required this.onSelected,
  });

  @override
  State<_VarsMenuOverlay> createState() => _VarsMenuOverlayState();
}

class _VarsMenuOverlayState extends State<_VarsMenuOverlay> {
  final _search = TextEditingController();
  late List<VariableDinamica> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.vars;
    _search.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.vars
          : widget.vars
                .where(
                  (v) =>
                      v.cdVariable.toLowerCase().contains(q) ||
                      v.deVariable.toLowerCase().contains(q),
                )
                .toList();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF252526) : cs.surface;
    final borderColor = isDark ? const Color(0xFF3C3C3C) : cs.outlineVariant;

    return Stack(
      children: [
        Positioned(
          left: widget.left,
          top: widget.top,
          width: widget.width,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                    child: SizedBox(
                      height: 30,
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Buscar variable…',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 0,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1E1E1E)
                              : cs.surfaceContainerLowest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: borderColor,
                              width: 0.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: borderColor,
                              width: 0.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: cs.primary, width: 1),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: borderColor),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Sin resultados',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final v = _filtered[i];
                          return InkWell(
                            onTap: () async {
                              Navigator.of(context).pop();
                              await widget.onSelected(v);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          ':${v.cdVariable}',
                                          style: TextStyle(
                                            fontFamily: 'Consolas',
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: cs.primary,
                                          ),
                                        ),
                                        if (v.deVariable.isNotEmpty)
                                          Text(
                                            v.deVariable,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: cs.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_return,
                                    size: 12,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.4,
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
          ),
        ),
      ],
    );
  }
}

// ── Docked variables side panel ───────────────────────────────────────────────

class _VarsDockedPanel extends StatefulWidget {
  final List<VariableDinamica> vars;
  final Future<void> Function(VariableDinamica) onSelected;
  final VoidCallback onUnpin;

  const _VarsDockedPanel({
    required this.vars,
    required this.onSelected,
    required this.onUnpin,
  });

  @override
  State<_VarsDockedPanel> createState() => _VarsDockedPanelState();
}

class _VarsDockedPanelState extends State<_VarsDockedPanel> {
  final _search = TextEditingController();
  late List<VariableDinamica> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.vars;
    _search.addListener(_onSearch);
  }

  @override
  void didUpdateWidget(_VarsDockedPanel old) {
    super.didUpdateWidget(old);
    if (old.vars != widget.vars) _applyFilter();
  }

  void _onSearch() => _applyFilter();

  void _applyFilter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.vars
          : widget.vars
                .where(
                  (v) =>
                      v.cdVariable.toLowerCase().contains(q) ||
                      v.deVariable.toLowerCase().contains(q),
                )
                .toList();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 190,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : cs.surfaceContainerLow,
        border: Border(left: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Column(
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
                Icon(Icons.data_object, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Variables',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Desanclar panel',
                  child: InkWell(
                    onTap: widget.onUnpin,
                    borderRadius: BorderRadius.circular(3),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.push_pin_outlined,
                        size: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Buscar…',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 13,
                  color: cs.onSurfaceVariant,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 0,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF252526)
                    : cs.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: cs.primary, width: 1),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final v = _filtered[i];
                return InkWell(
                  onTap: () => widget.onSelected(v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ':${v.cdVariable}',
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            color: cs.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (v.deVariable.isNotEmpty)
                          Text(
                            v.deVariable,
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
    );
  }
}

// ── Theme picker dialog ───────────────────────────────────────────────────────

class _ThemePickerDialog extends StatelessWidget {
  final String currentThemeId;
  final Future<void> Function(String id) onSelected;

  const _ThemePickerDialog({
    required this.currentThemeId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final grouped = <String, List<EditorThemeMeta>>{};
    for (final t in kEditorThemes) {
      grouped.putIfAbsent(t.category, () => []).add(t);
    }

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          constraints: const BoxConstraints(maxHeight: 480),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252526) : cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined, size: 16, color: cs.onSurface),
                    const SizedBox(width: 8),
                    Text(
                      'Seleccionar tema',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final category in grouped.keys) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            category.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                        for (final theme in grouped[category]!)
                          InkWell(
                            onTap: () async {
                              Navigator.of(context).pop();
                              await onSelected(theme.id);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              color: theme.id == currentThemeId
                                  ? cs.primaryContainer.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              child: Row(
                                children: [
                                  // Color swatch
                                  Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: theme.swatch,
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(
                                        color: cs.outlineVariant,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    theme.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (theme.id == currentThemeId)
                                    Icon(
                                      Icons.check,
                                      size: 14,
                                      color: cs.primary,
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
