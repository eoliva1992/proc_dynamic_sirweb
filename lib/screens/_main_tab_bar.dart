part of 'main_screen.dart';

class _MainTabBar extends StatefulWidget {
  final List<AppTab> tabs;
  final int activeTab;
  final ValueChanged<int> onActivate;
  final ValueChanged<int> onClose;
  final VoidCallback onAdd;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _MainTabBar({
    required this.tabs,
    required this.activeTab,
    required this.onActivate,
    required this.onClose,
    required this.onAdd,
    required this.onReorder,
  });

  @override
  State<_MainTabBar> createState() => _MainTabBarState();
}

class _MainTabBarState extends State<_MainTabBar> {
  late List<AppTab> _tabs;
  late int _activeTab;
  final Set<int> _hoveredTabs = {};

  @override
  void initState() {
    super.initState();
    _tabs = widget.tabs;
    _activeTab = widget.activeTab;
  }

  @override
  void didUpdateWidget(_MainTabBar old) {
    super.didUpdateWidget(old);
    _tabs = widget.tabs;
    _activeTab = widget.activeTab;
  }

  void _handleReorder(int oldIndex, int newIndex) {
    final clamped = newIndex.clamp(0, _tabs.length - 1);
    setState(() {
      final tab = _tabs.removeAt(oldIndex);
      _tabs.insert(clamped, tab);
      if (_activeTab == oldIndex) {
        _activeTab = clamped;
      } else if (_activeTab > oldIndex && _activeTab <= clamped) {
        _activeTab--;
      } else if (_activeTab < oldIndex && _activeTab >= clamped) {
        _activeTab++;
      }
    });
    widget.onReorder(oldIndex, clamped);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFECEFF4);
    final barBorder = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD0D7E2);

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: barBorder)),
      ),
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: _tabs.length + 1,
        itemBuilder: (ctx, i) {
          if (i == _tabs.length) {
            return MouseRegion(
              key: const ValueKey('_add_tab_'),
              cursor: SystemMouseCursors.click,
              child: InkWell(
                onTap: widget.onAdd,
                child: SizedBox(
                  width: 34,
                  height: 36,
                  child: Icon(
                    Icons.add,
                    size: 15,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                ),
              ),
            );
          }
          return ReorderableDragStartListener(
            key: ValueKey(_tabs[i].tabId),
            index: i,
            child: _buildTabItem(i, isDark, barBorder, cs),
          );
        },
        onReorderItem: (oldIndex, newIndex) {
          if (oldIndex >= _tabs.length) return;
          _handleReorder(oldIndex, newIndex);
        },
      ),
    );
  }

  Widget _buildTabItem(int index, bool isDark, Color barBorder, ColorScheme cs) {
    final tab       = _tabs[index];
    final isActive  = index == _activeTab;
    final isHovered = _hoveredTabs.contains(index);
    final inEditor  = tab.loading || tab.procedimiento != null;
    final isDirty   = tab.isDirty && tab.procedimiento != null;

    final activeBg     = isDark ? const Color(0xFF252526) : Colors.white;
    final hoverBg      = isDark ? const Color(0xFF2A2D2E) : const Color(0xFFF0F3F8);
    final activeText   = isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1A1A1A);
    final inactiveText = isDark ? const Color(0xFF858585) : const Color(0xFF6E7681);

    final Color accentColor;
    final IconData icon;
    final String label;
    final String typeLabel;

    if (tab.inSourceViewMode) {
      final sv = tab.sourceViewer!;
      accentColor = _sourceTypeColor(sv.objectType);
      icon        = _sourceTypeIcon(sv.objectType);
      label       = sv.name;
      typeLabel   = _sourceTypeLabel(sv.objectType);
    } else if (inEditor && tab.procedimiento != null) {
      accentColor = ConfigBadge.colorForConfig(tab.procedimiento!.inConfiguracion);
      icon        = tab.procedimiento?.inConfiguracion == 'J' ? Icons.code : Icons.storage;
      label       = tab.procedimiento!.cdProcedimiento;
      typeLabel   = 'Dynamic';
    } else {
      accentColor = const Color(0xFF0078D4);
      icon        = Icons.search;
      label       = 'Buscar';
      typeLabel   = '';
    }

    final bg = isActive ? activeBg : (isHovered ? hoverBg : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredTabs.add(index)),
      onExit:  (_) => setState(() => _hoveredTabs.remove(index)),
      child: Container(
        // Borde derecho fuera del clip
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: barBorder)),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          clipBehavior: Clip.antiAlias,
          constraints: const BoxConstraints(minWidth: 80, maxWidth: 230),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(7),
              topRight: Radius.circular(7),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              // Barra de acento superior
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 2,
                color: isActive ? accentColor : Colors.transparent,
              ),
              // Fila de contenido — ocupa el espacio restante
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Zona clickeable ─────────────────────────────────────
                    Flexible(
                      child: InkWell(
                        onTap: () => widget.onActivate(index),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
                          child: Row(
                            children: [
                              if (tab.loading)
                                SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: accentColor,
                                  ),
                                )
                              else
                                Icon(
                                  icon,
                                  size: 13,
                                  color: isActive
                                      ? accentColor
                                      : inactiveText.withValues(alpha: 0.75),
                                ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isActive
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isActive ? activeText : inactiveText,
                                  ),
                                ),
                              ),
                              if (typeLabel.isNotEmpty) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(
                                      alpha: isActive ? 0.14 : 0.07,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: accentColor.withValues(
                                        alpha: isActive ? 0.40 : 0.20,
                                      ),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    typeLabel,
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: isActive
                                          ? accentColor
                                          : accentColor.withValues(alpha: 0.55),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    // ── Ambiente badge ───────────────────────────────────────
                    _buildAmbienteBadge(tab, isActive),
                    // ── Cerrar / dot dirty ───────────────────────────────────
                    if (_tabs.length > 1)
                      SizedBox(
                        width: 22,
                        height: 34,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: isDirty && !isHovered && !isActive
                              ? Center(
                                  key: const ValueKey('dot'),
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade400,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.orange.withValues(alpha: 0.45),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : AnimatedOpacity(
                                  key: const ValueKey('close'),
                                  duration: const Duration(milliseconds: 120),
                                  opacity: isActive || isHovered ? 1.0 : 0.0,
                                  child: InkWell(
                                    onTap: () => widget.onClose(index),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Center(
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 12,
                                        color: isDirty
                                            ? Colors.orange.shade400
                                            : (isActive ? activeText : inactiveText),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmbienteBadge(AppTab tab, bool isActive) {
    final color = AmbienteSelector.colorForAmbiente(tab.ambiente);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isActive ? 0.18 : 0.09),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: color.withValues(alpha: isActive ? 1.0 : 0.40),
          width: 0.8,
        ),
      ),
      child: Text(
        tab.ambiente,
        style: TextStyle(
          color: color.withValues(alpha: isActive ? 1.0 : 0.60),
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static Color _sourceTypeColor(String objectType) => switch (objectType) {
    'TABLE'     => const Color(0xFF0078D4),
    'VIEW'      => const Color(0xFF107C10),
    'PROCEDURE' => const Color(0xFFCA5010),
    'FUNCTION'  => const Color(0xFF8764B8),
    'PACKAGE'   => const Color(0xFFC19C00),
    'TYPE'      => const Color(0xFF2E7D9E),
    _           => const Color(0xFF2E7D9E),
  };

  static IconData _sourceTypeIcon(String objectType) => switch (objectType) {
    'TABLE'     => Icons.table_chart_outlined,
    'VIEW'      => Icons.visibility_outlined,
    'PROCEDURE' => Icons.code_rounded,
    'FUNCTION'  => Icons.functions_rounded,
    'PACKAGE'   => Icons.inventory_2_outlined,
    'TYPE'      => Icons.data_object_outlined,
    _           => Icons.code_rounded,
  };

  static String _sourceTypeLabel(String objectType) => switch (objectType) {
    'TABLE'     => 'Table',
    'VIEW'      => 'View',
    'PROCEDURE' => 'Procedure',
    'FUNCTION'  => 'Function',
    'PACKAGE'   => 'Package',
    'TYPE'      => 'Type',
    _           => objectType,
  };
}
