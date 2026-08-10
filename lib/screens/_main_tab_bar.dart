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
    // Update local state immediately for a seamless visual
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
    final divider = cs.outlineVariant;

    return Container(
      height: 35,
      color: cs.surfaceContainer,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        // +1 for the non-draggable add button appended after the last tab
        itemCount: _tabs.length + 1,
        itemBuilder: (ctx, i) {
          if (i == _tabs.length) {
            return InkWell(
              key: const ValueKey('_add_tab_'),
              onTap: widget.onAdd,
              child: SizedBox(
                width: 32,
                height: 35,
                child: Icon(Icons.add, size: 16, color: cs.onSurfaceVariant),
              ),
            );
          }
          return ReorderableDragStartListener(
            key: ValueKey(_tabs[i].tabId),
            index: i,
            child: _buildTabItem(i, isDark, divider, cs),
          );
        },
        onReorderItem: (oldIndex, newIndex) {
          if (oldIndex >= _tabs.length) return;
          _handleReorder(oldIndex, newIndex);
        },
      ),
    );
  }

  Widget _buildTabItem(int index, bool isDark, Color divider, ColorScheme cs) {
    final tab = _tabs[index];
    final isActive = index == _activeTab;
    final activeBg = isDark ? cs.surfaceContainerLow : cs.surface;
    final inactiveBg = cs.surfaceContainerHigh;
    final activeText = cs.onSurface;
    final inactiveText = cs.onSurfaceVariant;

    final inEditor = tab.loading || tab.procedimiento != null;
    // Acento dinámico: color del tipo cuando hay procedimiento, azul para búsqueda
    final accentColor = (inEditor && tab.procedimiento != null)
        ? ConfigBadge.colorForConfig(tab.procedimiento!.inConfiguracion)
        : const Color(0xFF0078D4);
    final icon = inEditor
        ? (tab.procedimiento?.inConfiguracion == 'J'
              ? Icons.code
              : Icons.storage)
        : Icons.search;
    final label = tab.procedimiento?.cdProcedimiento ?? 'Buscar';

    return Container(
      height: 35,
      constraints: const BoxConstraints(minWidth: 80, maxWidth: 180),
      decoration: BoxDecoration(
        color: isActive ? activeBg : inactiveBg,
        border: Border(
          top: BorderSide(
            color: isActive ? accentColor : Colors.transparent,
            width: 2,
          ),
          right: BorderSide(color: divider),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: InkWell(
              onTap: () => widget.onActivate(index),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
                child: Row(
                  children: [
                    if (tab.loading)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xFF0078D4),
                        ),
                      )
                    else
                      Icon(
                        icon,
                        size: 14,
                        color: isActive && inEditor
                            ? accentColor.withValues(alpha: 0.85)
                            : (isActive ? activeText : inactiveText),
                      ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isActive ? activeText : inactiveText,
                        ),
                      ),
                    ),
                    if (tab.isDirty && tab.procedimiento != null)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade400,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withValues(alpha: 0.5),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _buildAmbienteBadge(tab),
          if (_tabs.length > 1)
            InkWell(
              onTap: () => widget.onClose(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 11,
                ),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: isActive ? activeText : inactiveText,
                ),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildAmbienteBadge(AppTab tab) {
    final color = AmbienteSelector.colorForAmbiente(tab.ambiente);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        tab.ambiente,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
