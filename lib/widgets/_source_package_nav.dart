part of 'object_source_page.dart';

extension _ObjectSourcePackageNav on _ObjectSourcePageState {
  Widget _buildPackageNav(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);
    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);
    final query = _navSearchCtrl.text.toLowerCase();
    final filtered = query.isEmpty
        ? _subprograms
        : _subprograms
              .where((s) => s.name.toLowerCase().contains(query))
              .toList();

    void navigateTo(({String name, String kind, int line}) sub) {
      final onSpec = _tabCtrl == null || _tabCtrl!.index == 0;
      final targetLine = onSpec
          ? (_specSubprograms
                    .where(
                      (s) => s.name.toUpperCase() == sub.name.toUpperCase(),
                    )
                    .firstOrNull
                    ?.line ??
                sub.line)
          : sub.line;

      _specCtrl?.revealLine(targetLine, center: true);
      // Select the full declaration line so it's visually highlighted
      _specCtrl?.runJavaScript(
        'try{'
        'var m=editor.getModel();'
        'editor.setSelection({'
        'startLineNumber:$targetLine,startColumn:1,'
        'endLineNumber:$targetLine,endColumn:m.getLineMaxColumn($targetLine)'
        '});'
        '}catch(e){}',
      );
      setState(() => _activeSubprogram = sub.name);
    }

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1F22) : cs.surfaceContainerLow,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: isDark
                ? const Color(0xFF252526)
                : cs.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 13, color: typeColor),
                const SizedBox(width: 6),
                Text(
                  'Subprogramas',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${filtered.length}/${_subprograms.length}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _navSearchCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
                decoration: InputDecoration(
                  hintText: 'Filtrar…',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  suffixIcon: _navSearchCtrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _navSearchCtrl.clear();
                            setState(() {});
                          },
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 28,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF2D2D30)
                      : cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: cs.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: typeColor, width: 1.2),
                  ),
                ),
              ),
            ),
          ),
          // List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'Sin resultados',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final sub = filtered[i];
                      final isProcedure = sub.kind == 'PROCEDURE';
                      final kindColor = isProcedure
                          ? const Color(0xFFCA5010)
                          : const Color(0xFF8764B8);
                      final isActive = _activeSubprogram == sub.name;
                      return InkWell(
                        onTap: () => navigateTo(sub),
                        mouseCursor: SystemMouseCursors.click,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: isActive
                                ? kindColor.withValues(alpha: 0.12)
                                : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: isActive
                                    ? kindColor
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            isActive ? 6 : 8,
                            5,
                            8,
                            5,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 16,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: kindColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  isProcedure ? 'P' : 'F',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: kindColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Tooltip(
                                  message: sub.name,
                                  waitDuration: const Duration(
                                    milliseconds: 600,
                                  ),
                                  child: Text(
                                    sub.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'Consolas',
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              Text(
                                '${sub.line}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: isActive ? 0.8 : 0.5,
                                  ),
                                  fontFamily: 'Consolas',
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
    );
  }
}
