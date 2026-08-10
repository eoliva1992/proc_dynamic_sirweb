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
