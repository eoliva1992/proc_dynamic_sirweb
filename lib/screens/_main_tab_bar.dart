part of 'main_screen.dart';

class _MainTabBar extends StatefulWidget {
  final List<AppTab> tabs;
  final int activeTab;
  final ValueChanged<int> onActivate;
  final ValueChanged<int> onClose;
  final VoidCallback onAdd;
  final bool canAdd;
  final int maxTabs;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _MainTabBar({
    required this.tabs,
    required this.activeTab,
    required this.onActivate,
    required this.onClose,
    required this.onAdd,
    required this.canAdd,
    required this.maxTabs,
    required this.onReorder,
  });

  @override
  State<_MainTabBar> createState() => _MainTabBarState();
}

class _MainTabBarState extends State<_MainTabBar> {
  late List<AppTab> _tabs;
  late int _activeTab;
  final Set<int> _hoveredTabs = {};

  // ── Layout tipo Chrome ────────────────────────────────────────────────────
  /// Ancho máximo de un tab cuando sobra espacio.
  static const double _kMaxTabW = 230;

  /// Ancho mínimo antes de activar el scroll horizontal.
  static const double _kMinTabW = 92;

  /// Ancho del botón "+".
  static const double _kAddBtnW = 34;

  /// Ancho de cada flecha de scroll.
  static const double _kScrollBtnW = 22;

  final ScrollController _scrollCtrl = ScrollController();
  double _tabWidth = _kMaxTabW;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _tabs = widget.tabs;
    _activeTab = widget.activeTab;
    _scrollCtrl.addListener(_updateScrollFlags);
  }

  @override
  void didUpdateWidget(_MainTabBar old) {
    super.didUpdateWidget(old);
    _tabs = widget.tabs;
    final activeChanged = widget.activeTab != _activeTab;
    _activeTab = widget.activeTab;
    if (activeChanged || widget.tabs.length != old.tabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureActiveVisible();
        _updateScrollFlags();
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_updateScrollFlags);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _updateScrollFlags() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final left = pos.pixels > 1;
    final right = pos.pixels < pos.maxScrollExtent - 1;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  /// Desplaza para que el tab activo quede completamente visible (Chrome-like).
  void _ensureActiveVisible() {
    if (!_scrollCtrl.hasClients) return;
    if (_activeTab < 0 || _activeTab >= _tabs.length) return;
    final pos = _scrollCtrl.position;
    final start = _activeTab * _tabWidth;
    final end = start + _tabWidth;
    final viewStart = pos.pixels;
    final viewEnd = viewStart + pos.viewportDimension;
    double? target;
    if (start < viewStart) {
      target = start;
    } else if (end > viewEnd) {
      target = end - pos.viewportDimension;
    }
    if (target == null) return;
    _scrollCtrl.animateTo(
      target.clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  /// Convierte la rueda del mouse (vertical) en scroll horizontal.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent <= 0) return;
    final delta = event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    _scrollCtrl.jumpTo((pos.pixels + delta).clamp(0.0, pos.maxScrollExtent));
  }

  void _scrollBy(double amount) {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    _scrollCtrl.animateTo(
      (pos.pixels + amount).clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
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
    final barBorder = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFD0D7E2);

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: barBorder)),
      ),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final n = _tabs.length;
          if (n == 0) return _buildAddButton(cs);
          // Espacio disponible descontando el botón "+"
          var available = constraints.maxWidth - _kAddBtnW;
          // ¿Los tabs caben con el ancho mínimo?
          var needsScroll = n * _kMinTabW > available;
          if (needsScroll) available -= _kScrollBtnW * 2;
          final tabW = needsScroll
              ? _kMinTabW
              : (available / n).clamp(_kMinTabW, _kMaxTabW).toDouble();
          _tabWidth = tabW;

          final list = ReorderableListView.builder(
            scrollController: _scrollCtrl,
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            physics: const ClampingScrollPhysics(),
            itemCount: n,
            itemBuilder: (ctx, i) => ReorderableDragStartListener(
              key: ValueKey(_tabs[i].tabId),
              index: i,
              child: _buildTabItem(i, isDark, barBorder, cs, tabW),
            ),
            onReorderItem: (oldIndex, newIndex) {
              if (oldIndex >= _tabs.length) return;
              _handleReorder(oldIndex, newIndex);
            },
          );

          final scrollableList = Listener(
            onPointerSignal: _onPointerSignal,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(ctx).copyWith(
                scrollbars: false,
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: list,
            ),
          );

          return Row(
            children: [
              if (needsScroll)
                _buildScrollButton(
                  cs,
                  icon: Icons.chevron_left_rounded,
                  enabled: _canScrollLeft,
                  onTap: () => _scrollBy(-tabW * 2),
                ),
              if (needsScroll)
                Expanded(child: scrollableList)
              else
                SizedBox(width: n * tabW, child: scrollableList),
              if (needsScroll)
                _buildScrollButton(
                  cs,
                  icon: Icons.chevron_right_rounded,
                  enabled: _canScrollRight,
                  onTap: () => _scrollBy(tabW * 2),
                ),
              _buildAddButton(cs),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScrollButton(
    ColorScheme cs, {
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: _kScrollBtnW,
      height: 36,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Icon(
            icon,
            size: 17,
            color: cs.onSurfaceVariant.withValues(alpha: enabled ? 0.75 : 0.2),
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton(ColorScheme cs) {
    final canAdd = widget.canAdd;
    return MouseRegion(
      cursor: canAdd ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Tooltip(
        message: canAdd
            ? 'Nueva pestaña (Ctrl+T)'
            : 'Máximo de ${widget.maxTabs} pestañas abiertas',
        child: InkWell(
          onTap: canAdd ? widget.onAdd : null,
          child: SizedBox(
            width: _kAddBtnW,
            height: 36,
            child: Icon(
              Icons.add,
              size: 15,
              color: cs.onSurfaceVariant.withValues(alpha: canAdd ? 0.55 : 0.2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(
    int index,
    bool isDark,
    Color barBorder,
    ColorScheme cs,
    double tabW,
  ) {
    final tab = _tabs[index];
    final isActive = index == _activeTab;
    final isHovered = _hoveredTabs.contains(index);
    final inEditor = tab.loading || tab.procedimiento != null;
    final isDirty = tab.isDirty && tab.procedimiento != null;

    // Densidad adaptativa (Chrome-like): al encogerse, se ocultan elementos
    final showTypeLabel = tabW >= 175;
    final showAmbiente = tabW >= 140;
    final showClose =
        _tabs.length > 1 && (tabW >= 110 || isActive || isHovered);
    final showLabel = tabW >= 74;

    final activeBg = isDark ? const Color(0xFF252526) : Colors.white;
    final hoverBg = isDark ? const Color(0xFF2A2D2E) : const Color(0xFFF0F3F8);
    final activeText = isDark
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF1A1A1A);
    final inactiveText = isDark
        ? const Color(0xFF858585)
        : const Color(0xFF6E7681);

    final Color accentColor;
    final IconData icon;
    final String label;
    final String typeLabel;

    if (tab.inSourceViewMode) {
      final sv = tab.sourceViewer!;
      accentColor = _sourceTypeColor(sv.objectType);
      icon = _sourceTypeIcon(sv.objectType);
      label = sv.name;
      typeLabel = _sourceTypeLabel(sv.objectType);
    } else if (inEditor && tab.procedimiento != null) {
      accentColor = ConfigBadge.colorForConfig(
        tab.procedimiento!.inConfiguracion,
      );
      icon = tab.procedimiento?.inConfiguracion == 'J'
          ? Icons.code
          : Icons.storage;
      label = tab.procedimiento!.cdProcedimiento;
      typeLabel = 'Dynamic';
    } else {
      accentColor = const Color(0xFF0078D4);
      icon = Icons.search;
      label = 'Buscar';
      typeLabel = '';
    }

    final bg = isActive ? activeBg : (isHovered ? hoverBg : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredTabs.add(index)),
      onExit: (_) => setState(() => _hoveredTabs.remove(index)),
      child: Tooltip(
        message: typeLabel.isEmpty
            ? label
            : '$label — $typeLabel (${tab.ambiente})',
        waitDuration: const Duration(milliseconds: 600),
        child: Container(
          width: tabW,
          // Borde derecho fuera del clip
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: barBorder)),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            clipBehavior: Clip.antiAlias,
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
                      // ── Zona clickeable ───────────────────────────────────
                      Expanded(
                        child: InkWell(
                          onTap: () => widget.onActivate(index),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              showLabel ? 10 : 6,
                              0,
                              6,
                              0,
                            ),
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
                                if (showLabel) ...[
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      label,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isActive
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: isActive
                                            ? activeText
                                            : inactiveText,
                                      ),
                                    ),
                                  ),
                                ],
                                if (showTypeLabel && typeLabel.isNotEmpty) ...[
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
                                            : accentColor.withValues(
                                                alpha: 0.55,
                                              ),
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
                      // ── Ambiente badge ─────────────────────────────────────
                      if (showAmbiente)
                        _buildAmbienteBadge(tab, isActive)
                      else
                        _buildAmbienteDot(tab, isActive),
                      // ── Cerrar / dot dirty ─────────────────────────────────
                      if (showClose)
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
                                            color: Colors.orange.withValues(
                                              alpha: 0.45,
                                            ),
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
                                              : (isActive
                                                    ? activeText
                                                    : inactiveText),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        )
                      else if (isDirty)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade400,
                              shape: BoxShape.circle,
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
      ),
    );
  }

  /// Punto de color del ambiente para tabs angostos.
  Widget _buildAmbienteDot(AppTab tab, bool isActive) {
    final color = AmbienteSelector.colorForAmbiente(tab.ambiente);
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isActive ? 1.0 : 0.55),
        shape: BoxShape.circle,
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
    'TABLE' => const Color(0xFF0078D4),
    'VIEW' => const Color(0xFF107C10),
    'PROCEDURE' => const Color(0xFFCA5010),
    'FUNCTION' => const Color(0xFF8764B8),
    'PACKAGE' => const Color(0xFFC19C00),
    'TYPE' => const Color(0xFF2E7D9E),
    _ => const Color(0xFF2E7D9E),
  };

  static IconData _sourceTypeIcon(String objectType) => switch (objectType) {
    'TABLE' => Icons.table_chart_outlined,
    'VIEW' => Icons.visibility_outlined,
    'PROCEDURE' => Icons.code_rounded,
    'FUNCTION' => Icons.functions_rounded,
    'PACKAGE' => Icons.inventory_2_outlined,
    'TYPE' => Icons.data_object_outlined,
    _ => Icons.code_rounded,
  };

  static String _sourceTypeLabel(String objectType) => switch (objectType) {
    'TABLE' => 'Table',
    'VIEW' => 'View',
    'PROCEDURE' => 'Procedure',
    'FUNCTION' => 'Function',
    'PACKAGE' => 'Package',
    'TYPE' => 'Type',
    _ => objectType,
  };
}
