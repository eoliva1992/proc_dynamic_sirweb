import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/schema_recents_service.dart';
import '../services/schema_service.dart';
import 'schema_object_details_sheet.dart';

const _kTypeColors = {
  'TABLE': Color(0xFF0078D4),
  'VIEW': Color(0xFF107C10),
  'PROCEDURE': Color(0xFFCA5010),
  'FUNCTION': Color(0xFF8764B8),
  'PACKAGE': Color(0xFFC19C00),
  'TYPE': Color(0xFF2E7D9E),
};
const _kTypeIcons = {
  'TABLE': Icons.table_chart_outlined,
  'VIEW': Icons.visibility_outlined,
  'PROCEDURE': Icons.code_rounded,
  'FUNCTION': Icons.functions_rounded,
  'PACKAGE': Icons.inventory_2_outlined,
  'TYPE': Icons.data_object_outlined,
};

class _PaletteItem {
  final String name;
  final String type;
  final String owner;
  final bool isRecent;
  const _PaletteItem({
    required this.name,
    required this.type,
    this.owner = '',
    this.isRecent = false,
  });
}

/// Abre la command palette de esquema (estilo VS Code) para búsqueda rápida.
Future<void> showSchemaCommandPalette(
  BuildContext context, {
  required String ambiente,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'schema-palette',
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -0.04),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ),
    pageBuilder: (ctx, _, anim2) => _SchemaCommandPalette(ambiente: ambiente),
  );
}

class _SchemaCommandPalette extends StatefulWidget {
  final String ambiente;
  const _SchemaCommandPalette({required this.ambiente});

  @override
  State<_SchemaCommandPalette> createState() => _SchemaCommandPaletteState();
}

class _SchemaCommandPaletteState extends State<_SchemaCommandPalette> {
  final _ctrl = TextEditingController();
  final _keyboardFocus = FocusNode();
  String _query = '';
  List<SchemaObjectRef>? _recents;
  SchemaMetadata? _meta;
  Timer? _debounce;
  int _focusedIdx = 0;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _meta = SchemaService.instance.getCached(ambiente: widget.ambiente);
    _loadRecents();
    _ctrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _keyboardFocus.dispose();
    _debounce?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 80), () {
      if (mounted) {
        setState(() {
          _query = _ctrl.text.trim().toLowerCase();
          _focusedIdx = 0;
        });
      }
    });
  }

  Future<void> _loadRecents() async {
    final r = await SchemaRecentsService.instance.getRecents(
      ambiente: widget.ambiente,
    );
    if (mounted) setState(() => _recents = r);
  }

  List<_PaletteItem> get _results {
    if (_query.isEmpty) {
      return (_recents ?? [])
          .map(
            (r) => _PaletteItem(
              name: r.name,
              type: r.type,
              owner: r.owner,
              isRecent: true,
            ),
          )
          .toList();
    }
    final meta = _meta;
    if (meta == null) return [];
    final results = <_PaletteItem>[];
    for (final t in meta.tables) {
      if (t.toLowerCase().contains(_query)) {
        results.add(_PaletteItem(name: t, type: 'TABLE'));
      }
    }
    for (final v in meta.views) {
      if (v.toLowerCase().contains(_query)) {
        results.add(_PaletteItem(name: v, type: 'VIEW'));
      }
    }
    for (final o in meta.objects) {
      if (o.name.toLowerCase().contains(_query)) {
        results.add(_PaletteItem(name: o.name, type: o.type, owner: o.owner));
      }
    }
    return results.take(60).toList();
  }

  void _select(_PaletteItem item) {
    if (!mounted) return;
    Navigator.of(context).pop();
    SchemaRecentsService.instance.addRecent(
      SchemaObjectRef(
        name: item.name,
        type: item.type,
        owner: item.owner,
        ambiente: widget.ambiente,
      ),
    );
    showObjectDetails(
      context,
      name: item.name,
      type: item.type,
      ambiente: widget.ambiente,
    );
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final items = _results;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(
          () => _focusedIdx = (_focusedIdx + 1).clamp(0, items.length - 1),
        );
        _scrollToFocused(items.length);
        return true;
      case LogicalKeyboardKey.arrowUp:
        setState(
          () => _focusedIdx = (_focusedIdx - 1).clamp(0, items.length - 1),
        );
        _scrollToFocused(items.length);
        return true;
      case LogicalKeyboardKey.enter:
        if (_focusedIdx >= 0 && _focusedIdx < items.length) {
          _select(items[_focusedIdx]);
        }
        return true;
    }
    return false;
  }

  void _scrollToFocused(int total) {
    if (total == 0) return;
    final rowH = 38.0;
    final target = _focusedIdx * rowH;
    _scrollCtrl.animateTo(
      target.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _results;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: KeyboardListener(
          focusNode: _keyboardFocus,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Container(
            width: 620,
            constraints: const BoxConstraints(maxHeight: 500),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.18),
                  blurRadius: 48,
                  offset: const Offset(0, 16),
                ),
              ],
              border: Border.all(
                color: isDark
                    ? const Color(0xFF3A3A3A)
                    : const Color(0xFFDDE2EA),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSearchField(isDark),
                Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF3A3A3A)
                      : const Color(0xFFE8E8E8),
                ),
                if (items.isEmpty && _query.isEmpty)
                  _buildEmptyState(isDark)
                else if (items.isEmpty)
                  _buildNoResults(isDark)
                else
                  _buildList(items, isDark),
                _buildFooter(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        style: TextStyle(
          fontSize: 14,
          fontFamily: 'Consolas',
          color: isDark ? const Color(0xFFD4D4D4) : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar tablas, vistas, procedimientos...',
          hintStyle: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white38 : Colors.black38,
            fontFamily: 'Consolas',
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 16,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() => _query = '');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF5F7FA),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<_PaletteItem> items, bool isDark) {
    String? lastType;
    final rows = <Widget>[];

    if (_query.isEmpty && items.isNotEmpty) {
      rows.add(_sectionLabel('RECIENTES', isDark));
    }

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (_query.isNotEmpty && item.type != lastType) {
        rows.add(_sectionLabel(item.type, isDark));
        lastType = item.type;
      }
      rows.add(_buildRow(item, i, isDark));
    }

    return Flexible(
      child: ListView(
        controller: _scrollCtrl,
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 4),
        children: rows,
      ),
    );
  }

  Widget _sectionLabel(String label, bool isDark) {
    final color = _kTypeColors[label];
    final icon = color != null ? _kTypeIcons[label] : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color!.withValues(alpha: 0.7)),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFEEEEEE),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(_PaletteItem item, int idx, bool isDark) {
    final color = _kTypeColors[item.type] ?? Colors.grey;
    final icon = _kTypeIcons[item.type] ?? Icons.storage_outlined;
    final isSelected = idx == _focusedIdx;

    return Material(
      color: isSelected
          ? (isDark ? const Color(0xFF094771) : const Color(0xFFE5F2FF))
          : Colors.transparent,
      child: InkWell(
        onTap: () => _select(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(icon, size: 13, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HighlightedText(
                  text: item.name,
                  query: _query,
                  isDark: isDark,
                ),
              ),
              if (item.isRecent) ...[
                Icon(
                  Icons.history,
                  size: 13,
                  color: isDark
                      ? Colors.white24
                      : Colors.black.withValues(alpha: 0.24),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: color.withValues(alpha: 0.35),
                    width: 0.7,
                  ),
                ),
                child: Text(
                  item.type,
                  style: TextStyle(
                    fontSize: 9,
                    color: color,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.history_toggle_off_outlined,
          size: 32,
          color: isDark ? Colors.white24 : Colors.black26,
        ),
        const SizedBox(height: 10),
        Text(
          'Sin objetos visitados recientemente',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    ),
  );

  Widget _buildNoResults(bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Text(
      'Sin resultados para "$_query"',
      style: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white38 : Colors.black38,
      ),
    ),
  );

  Widget _buildFooter(bool isDark) {
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFE8E8E8);
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
        color: bg,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          _footerKey('↑↓', 'navegar', isDark),
          const SizedBox(width: 12),
          _footerKey('↵', 'abrir', isDark),
          const SizedBox(width: 12),
          _footerKey('Esc', 'cerrar', isDark),
          const Spacer(),
          Text(
            widget.ambiente,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerKey(String key, String label, bool isDark) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Text(
          key,
          style: TextStyle(
            fontSize: 10,
            fontFamily: 'Consolas',
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    ],
  );
}

// ── Texto con porción coincidente resaltada ──────────────────────────────────

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final bool isDark;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final highlightColor = const Color(0xFF0078D4);

    if (query.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontFamily: 'Consolas',
          color: baseColor,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    final lower = text.toLowerCase();
    final idx = lower.indexOf(query.toLowerCase());
    if (idx < 0) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontFamily: 'Consolas',
          color: baseColor,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          if (idx > 0) TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + query.length),
            style: TextStyle(
              color: highlightColor,
              fontWeight: FontWeight.w700,
              backgroundColor: highlightColor.withValues(alpha: 0.12),
            ),
          ),
          if (idx + query.length < text.length)
            TextSpan(text: text.substring(idx + query.length)),
        ],
        style: TextStyle(
          fontSize: 13,
          fontFamily: 'Consolas',
          color: baseColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}
