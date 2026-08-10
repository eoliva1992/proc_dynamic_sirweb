import 'dart:async';

import 'package:flutter/material.dart';

import '../services/schema_recents_service.dart';
import '../services/schema_service.dart';
import 'schema_command_palette.dart';
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
const _kTypeLabels = {
  'TABLE': 'Tablas',
  'VIEW': 'Vistas',
  'PROCEDURE': 'Procs',
  'FUNCTION': 'Funciones',
  'PACKAGE': 'Paquetes',
  'TYPE': 'Types',
};

/// Sidebar persistente y colapsable del explorador de esquema.
class SchemaSidebar extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onToggle;
  final String ambiente;
  final double width;

  const SchemaSidebar({
    super.key,
    required this.isOpen,
    required this.onToggle,
    required this.ambiente,
    this.width = 290,
  });

  @override
  State<SchemaSidebar> createState() => _SchemaSidebarState();
}

class _SchemaSidebarState extends State<SchemaSidebar> {
  static const _collapsedWidth = 0.0;

  final _searchCtrl = TextEditingController();
  String _filter = '';
  Timer? _debounce;

  // Qué tipos mostrar (null = todos)
  final _activeFilters = <String>{};

  // Datos
  List<SchemaObjectRef> _recents = [];
  List<SchemaObjectRef> _favorites = [];
  Set<String> _favoriteKeys = {};
  SchemaMetadata? _meta;
  bool _metaLoaded = false;

  // Secciones plegadas por tipo
  final _collapsed = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    SchemaService.instance.status.addListener(_onSchemaStatus);
    _loadMeta();
    _loadSaved();
  }

  @override
  void didUpdateWidget(SchemaSidebar old) {
    super.didUpdateWidget(old);
    if (old.ambiente != widget.ambiente) {
      _loadMeta();
      _loadSaved();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    SchemaService.instance.status.removeListener(_onSchemaStatus);
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted)
        setState(() => _filter = _searchCtrl.text.trim().toLowerCase());
    });
  }

  void _onSchemaStatus() {
    final s = SchemaService.instance.status.value;
    if (s == SchemaLoadStatus.ready) _loadMeta();
  }

  void _loadMeta() {
    final cached = SchemaService.instance.getCached(ambiente: widget.ambiente);
    if (cached != null && mounted) {
      setState(() {
        _meta = cached;
        _metaLoaded = true;
      });
    } else if (!_metaLoaded) {
      SchemaService.instance
          .getMetadata(ambiente: widget.ambiente)
          .then((m) {
            if (mounted)
              setState(() {
                _meta = m;
                _metaLoaded = true;
              });
          })
          .catchError((_) {
            if (mounted) setState(() => _metaLoaded = true);
          });
    }
  }

  Future<void> _loadSaved() async {
    final recents = await SchemaRecentsService.instance.getRecents(
      ambiente: widget.ambiente,
    );
    final favs = await SchemaRecentsService.instance.getFavorites(
      ambiente: widget.ambiente,
    );
    if (!mounted) return;
    setState(() {
      _recents = recents;
      _favorites = favs;
      _favoriteKeys = {for (final f in favs) '${f.name}::${f.ambiente}'};
    });
  }

  bool _isFavorite(String name) =>
      _favoriteKeys.contains('$name::${widget.ambiente}');

  Future<void> _toggleFavorite(SchemaObjectRef ref) async {
    if (_isFavorite(ref.name)) {
      await SchemaRecentsService.instance.removeFavorite(ref);
    } else {
      await SchemaRecentsService.instance.addFavorite(ref);
    }
    await _loadSaved();
  }

  void _openObject(String name, String type, String owner) {
    SchemaRecentsService.instance.addRecent(
      SchemaObjectRef(
        name: name,
        type: type,
        owner: owner,
        ambiente: widget.ambiente,
      ),
    );
    showObjectDetails(
      context,
      name: name,
      type: type,
      ambiente: widget.ambiente,
    );
    _loadSaved();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: widget.isOpen ? widget.width : _collapsedWidth,
      child: widget.isOpen ? _buildContent(isDark) : const SizedBox.shrink(),
    );
  }

  Widget _buildContent(bool isDark) {
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(
        children: [
          _buildHeader(isDark),
          _buildSearch(isDark, border),
          _buildFilterChips(isDark),
          Expanded(child: _buildBody(isDark)),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0078D4), Color(0xFF005A9E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.schema_outlined, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Esquema',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Ctrl+K quick access
          Tooltip(
            message: 'Búsqueda rápida (Ctrl+K)',
            child: InkWell(
              onTap: () =>
                  showSchemaCommandPalette(context, ambiente: widget.ambiente),
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.search, size: 16, color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Refresh
          Tooltip(
            message: 'Recargar esquema',
            child: InkWell(
              onTap: _refreshSchema,
              borderRadius: BorderRadius.circular(4),
              child: ValueListenableBuilder<SchemaLoadStatus>(
                valueListenable: SchemaService.instance.status,
                builder: (context2, status, child) {
                  if (status == SchemaLoadStatus.refreshing ||
                      status == SchemaLoadStatus.loadingServer) {
                    return const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white60,
                        strokeWidth: 1.5,
                      ),
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.refresh, size: 16, color: Colors.white70),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Colapsar
          Tooltip(
            message: 'Cerrar sidebar',
            child: InkWell(
              onTap: widget.onToggle,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.chevron_left,
                  size: 16,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch(bool isDark, Color border) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 4),
      child: TextField(
        controller: _searchCtrl,
        style: TextStyle(
          fontSize: 12.5,
          color: isDark ? const Color(0xFFD4D4D4) : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: 'Filtrar objetos...',
          hintStyle: TextStyle(
            fontSize: 12.5,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 16,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          suffixIcon: _filter.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 14,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _filter = '');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                )
              : null,
          filled: true,
          fillColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF5F7FA),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFF0078D4), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    final types = ['TABLE', 'VIEW', 'PROCEDURE', 'FUNCTION', 'PACKAGE', 'TYPE'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: types.map((t) {
          final active = _activeFilters.contains(t);
          final color = _kTypeColors[t]!;
          final icon = _kTypeIcons[t]!;
          return Tooltip(
            message: _kTypeLabels[t]!,
            child: GestureDetector(
              onTap: () => setState(() {
                if (active) {
                  _activeFilters.remove(t);
                } else {
                  _activeFilters.add(t);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                width: 32,
                height: 28,
                decoration: BoxDecoration(
                  color: active
                      ? color.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: active
                        ? color.withValues(alpha: 0.8)
                        : (isDark
                              ? const Color(0xFF3A3A3A)
                              : const Color(0xFFDDE2EA)),
                    width: active ? 1.4 : 0.8,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 14,
                  color: active
                      ? color
                      : (isDark ? Colors.white38 : Colors.black38),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (!_metaLoaded) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF0078D4),
          strokeWidth: 2,
        ),
      );
    }
    final meta = _meta;
    if (meta == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 32,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              const SizedBox(height: 8),
              Text(
                'No se pudo cargar el esquema',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _refreshSchema,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Reintentar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        if (_filter.isEmpty && _favorites.isNotEmpty)
          ..._buildSavedSection(
            'FAVORITOS',
            _favorites,
            Icons.star_rounded,
            const Color(0xFFF4C430),
            isDark,
            isFavoriteSection: true,
          ),
        if (_filter.isEmpty && _recents.isNotEmpty)
          ..._buildSavedSection(
            'RECIENTES',
            _recents,
            Icons.history,
            const Color(0xFF0078D4),
            isDark,
            isFavoriteSection: false,
          ),
        ..._buildSchemaTree(meta, isDark),
      ],
    );
  }

  List<Widget> _buildSavedSection(
    String title,
    List<SchemaObjectRef> items,
    IconData sectionIcon,
    Color sectionColor,
    bool isDark, {
    required bool isFavoriteSection,
  }) {
    const maxShow = 5;
    final shown = items.take(maxShow).toList();
    return [
      SliverToBoxAdapter(
        child: _savedSectionHeader(
          title,
          sectionIcon,
          sectionColor,
          isDark,
          count: items.length,
          onClear: isFavoriteSection
              ? null
              : () async {
                  await SchemaRecentsService.instance.clearRecents(
                    ambiente: widget.ambiente,
                  );
                  _loadSaved();
                },
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _buildSavedCard(
            shown[i],
            isDark,
            isFavoriteSection: isFavoriteSection,
          ),
          childCount: shown.length,
        ),
      ),
    ];
  }

  Widget _savedSectionHeader(
    String title,
    IconData icon,
    Color color,
    bool isDark, {
    required int count,
    VoidCallback? onClear,
  }) {
    final divBg = isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA);
    final divLine = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE8E8E8);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: divBg,
        border: Border(
          top: BorderSide(color: divLine),
          bottom: BorderSide(color: divLine),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            title,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const Spacer(),
          if (onClear != null)
            Tooltip(
              message: 'Limpiar recientes',
              child: InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_sweep_outlined,
                    size: 13,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSavedCard(
    SchemaObjectRef ref,
    bool isDark, {
    required bool isFavoriteSection,
  }) {
    final color = _kTypeColors[ref.type] ?? Colors.grey;
    final typeIcon = _kTypeIcons[ref.type] ?? Icons.storage_outlined;
    final isFav = _isFavorite(ref.name);
    return _SavedCard(
      ref: ref,
      color: color,
      typeIcon: typeIcon,
      isDark: isDark,
      isFavorite: isFav,
      isFavoriteSection: isFavoriteSection,
      onTap: () => _openObject(ref.name, ref.type, ref.owner),
      onFavoriteToggle: () => _toggleFavorite(ref),
      onRemove: isFavoriteSection
          ? null
          : () async {
              await SchemaRecentsService.instance.removeRecent(ref);
              _loadSaved();
            },
    );
  }

  List<Widget> _buildSchemaTree(SchemaMetadata meta, bool isDark) {
    final sections = [
      ('TABLE', meta.tables),
      ('VIEW', meta.views),
      (
        'PROCEDURE',
        meta.objects
            .where((o) => o.type == 'PROCEDURE')
            .map((o) => o.name)
            .toList(),
      ),
      (
        'FUNCTION',
        meta.objects
            .where((o) => o.type == 'FUNCTION')
            .map((o) => o.name)
            .toList(),
      ),
      (
        'PACKAGE',
        meta.objects
            .where((o) => o.type == 'PACKAGE')
            .map((o) => o.name)
            .toList(),
      ),
      (
        'TYPE',
        meta.objects.where((o) => o.type == 'TYPE').map((o) => o.name).toList(),
      ),
    ];

    final result = <Widget>[];
    for (final (type, names) in sections) {
      if (_activeFilters.isNotEmpty && !_activeFilters.contains(type)) continue;

      final filtered = _filter.isEmpty
          ? names
          : names.where((n) => n.toLowerCase().contains(_filter)).toList();
      if (filtered.isEmpty) continue;

      final isCollapsed = _collapsed[type] ?? true; // collapsed by default
      result.add(
        SliverToBoxAdapter(
          child: _buildTypeSection(type, filtered.length, isCollapsed, isDark),
        ),
      );
      if (!isCollapsed) {
        result.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _buildObjectRow(filtered[i], type, isDark),
              childCount: filtered.length,
            ),
          ),
        );
      }
    }
    return result;
  }

  Widget _buildTypeSection(
    String type,
    int count,
    bool isCollapsed,
    bool isDark,
  ) {
    final color = _kTypeColors[type] ?? Colors.grey;
    final label = _kTypeLabels[type] ?? type;
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA);
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE8E8E8);
    return Material(
      color: bg,
      child: InkWell(
        onTap: () => setState(() => _collapsed[type] = !isCollapsed),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: border),
              bottom: isCollapsed ? BorderSide(color: border) : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isCollapsed ? Icons.chevron_right : Icons.expand_more,
                size: 14,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 4),
              Icon(_kTypeIcons[type]!, size: 13, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObjectRow(String name, String type, bool isDark) {
    final color = _kTypeColors[type] ?? Colors.grey;
    final typeIcon = _kTypeIcons[type] ?? Icons.storage_outlined;
    final isFav = _isFavorite(name);
    // Build owner lookup from cached metadata
    final meta = _meta;
    String owner = '';
    if (meta != null) {
      owner =
          meta.tableOwners[name] ??
          meta.viewOwners[name] ??
          meta.objects.where((o) => o.name == name).firstOrNull?.owner ??
          '';
    }
    return _SidebarRow(
      icon: typeIcon,
      color: color,
      name: name,
      type: type,
      isDark: isDark,
      isFavorite: isFav,
      onTap: () => _openObject(name, type, owner),
      onFavoriteToggle: () => _toggleFavorite(
        SchemaObjectRef(
          name: name,
          type: type,
          owner: owner,
          ambiente: widget.ambiente,
        ),
      ),
    );
  }

  Future<void> _refreshSchema() async {
    setState(() => _metaLoaded = false);
    try {
      final fresh = await SchemaService.instance.refreshAmbiente(
        widget.ambiente,
      );
      if (mounted)
        setState(() {
          _meta = fresh;
          _metaLoaded = true;
        });
    } catch (_) {
      if (mounted) setState(() => _metaLoaded = true);
    }
  }
}

// ── Tarjeta de reciente / favorito ───────────────────────────────────────────

class _SavedCard extends StatefulWidget {
  final SchemaObjectRef ref;
  final Color color;
  final IconData typeIcon;
  final bool isDark;
  final bool isFavorite;
  final bool isFavoriteSection;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback? onRemove;

  const _SavedCard({
    required this.ref,
    required this.color,
    required this.typeIcon,
    required this.isDark,
    required this.isFavorite,
    required this.isFavoriteSection,
    required this.onTap,
    required this.onFavoriteToggle,
    this.onRemove,
  });

  @override
  State<_SavedCard> createState() => _SavedCardState();
}

class _SavedCardState extends State<_SavedCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovered
        ? (widget.isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEFF4FF))
        : (widget.isDark ? const Color(0xFF232323) : const Color(0xFFFAFAFB));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                // Type icon badge
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(widget.typeIcon, size: 13, color: widget.color),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.ref.name,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w600,
                          color: widget.isDark
                              ? const Color(0xFFD4D4D4)
                              : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _kTypeLabels[widget.ref.type] ?? widget.ref.type,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: widget.color,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_hovered) ...[
                  // Toggle favorite star
                  GestureDetector(
                    onTap: widget.onFavoriteToggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(
                        widget.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 15,
                        color: widget.isFavorite
                            ? const Color(0xFFF4C430)
                            : (widget.isDark ? Colors.white38 : Colors.black38),
                      ),
                    ),
                  ),
                  // Remove from recents (not shown for favorites section)
                  if (widget.onRemove != null)
                    GestureDetector(
                      onTap: widget.onRemove,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Icon(
                          Icons.close,
                          size: 13,
                          color: widget.isDark
                              ? Colors.white24
                              : Colors.black26,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Fila individual de objeto ──────────────────────────────────────────────

class _SidebarRow extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String name;
  final String type;
  final bool isDark;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const _SidebarRow({
    required this.icon,
    required this.color,
    required this.name,
    required this.type,
    required this.isDark,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovered
        ? (widget.isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEFF4FF))
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: widget.onTap,
          child: Row(
            children: [
              // Left accent bar — visible on hover
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: _hovered ? widget.color : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(widget.icon, size: 13, color: widget.color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Consolas',
                    color: widget.isDark
                        ? const Color(0xFFD4D4D4)
                        : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_hovered)
                GestureDetector(
                  onTap: widget.onFavoriteToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      widget.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 14,
                      color: widget.isFavorite
                          ? const Color(0xFFF4C430)
                          : (widget.isDark ? Colors.white38 : Colors.black38),
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

/// Botón delgado de toggle para abrir el sidebar cuando está cerrado.
class SchemaSidebarToggle extends StatelessWidget {
  final VoidCallback onToggle;
  const SchemaSidebarToggle({super.key, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: 'Abrir explorador de esquema',
      child: InkWell(
        onTap: onToggle,
        child: Container(
          width: 20,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252526) : const Color(0xFFF0F2F5),
            border: Border(
              right: BorderSide(
                color: isDark
                    ? const Color(0xFF3A3A3A)
                    : const Color(0xFFDDE2EA),
              ),
            ),
          ),
          child: Center(
            child: Icon(
              Icons.chevron_right,
              size: 16,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
      ),
    );
  }
}
