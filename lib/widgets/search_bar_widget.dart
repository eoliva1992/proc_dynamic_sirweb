import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import '../providers/procedimientos_provider.dart';
import 'ambiente_selector.dart';
import 'search_tab_state.dart';

class SearchBarWidget extends StatefulWidget {
  final SearchTabState tabState;
  final String ambiente;
  final ValueChanged<String> onAmbienteChanged;
  final VoidCallback? onNewProcedure;

  const SearchBarWidget({
    super.key,
    required this.tabState,
    required this.ambiente,
    required this.onAmbienteChanged,
    this.onNewProcedure,
  });

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  late final TextEditingController _searchCtrl;
  late String? _selectedConfig;
  late String? _selectedEstado;
  final FocusNode _searchFocus = FocusNode();
  bool _filtersExpanded = false;

  static const _estados = {'1': 'Activos', '0': 'Inactivos', '': 'Todos'};

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.tabState.searchText);
    _selectedConfig = widget.tabState.config;
    _selectedEstado = widget.tabState.estado;
    _filtersExpanded =
        _selectedConfig != null || (_selectedEstado ?? '1') != '1';
    _searchCtrl.addListener(
      () => widget.tabState.searchText = _searchCtrl.text,
    );
    widget.tabState.loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(SearchBarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabState != oldWidget.tabState) {
      setState(() {
        _searchCtrl.text = widget.tabState.searchText;
        _selectedConfig = widget.tabState.config;
        _selectedEstado = widget.tabState.estado;
        _filtersExpanded =
            _selectedConfig != null || (_selectedEstado ?? '1') != '1';
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _buscar() {
    widget.tabState.buscar(
      busqueda: _searchCtrl.text.trim(),
      cfg: _selectedConfig,
      est: _selectedEstado,
      ambiente: procedimientosProvider.ambiente,
    );
  }

  bool get _hasActiveFilters =>
      _selectedConfig != null || _selectedEstado != '1';

  void _clearFilters() {
    setState(() {
      _selectedConfig = null;
      _selectedEstado = '1';
    });
    widget.tabState.config = null;
    widget.tabState.estado = '1';
    if (widget.tabState.hasSearched) _buscar();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: widget.tabState,
      builder: (context, child) => Observer(
        builder: (context) {
          final provider = procedimientosProvider;
          final hasSearched = widget.tabState.hasSearched;
          // Sync filter local state when mutated externally (e.g., clear from results panel)
          final stateConfig = widget.tabState.config;
          final stateEstado = widget.tabState.estado ?? '1';
          if (_selectedConfig != stateConfig) _selectedConfig = stateConfig;
          if (_selectedEstado != stateEstado) _selectedEstado = stateEstado;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: hasSearched
                      ? const Color(0xFF0078D4).withValues(alpha: 0.6)
                      : cs.outlineVariant.withValues(alpha: 0.4),
                  width: hasSearched ? 2 : 1,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildSearchField(cs)),
                    const SizedBox(width: 8),
                    _buildFavoritesButton(provider),
                    const SizedBox(width: 8),
                    _buildFiltersToggle(cs),
                    const SizedBox(width: 8),
                    _buildBuscarButton(),
                    const SizedBox(width: 8),
                    AmbienteSelector(
                      value: widget.ambiente,
                      onChanged: (v) {
                        widget.onAmbienteChanged(v);
                        // Re-ejecutar búsqueda en el nuevo ambiente
                        if (widget.tabState.hasSearched) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _buscar(),
                          );
                        }
                      },
                    ),
                    if (widget.onNewProcedure != null) ..._buildNewProcButton(),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: _filtersExpanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              _buildConfigFilter(provider, cs),
                              const SizedBox(width: 8),
                              _buildEstadoFilter(cs),
                              if (_hasActiveFilters)
                                ..._buildClearFiltersButton(cs),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                _buildHistoryRow(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFiltersToggle(ColorScheme cs) {
    final count =
        (_selectedConfig != null ? 1 : 0) + (_selectedEstado != '1' ? 1 : 0);
    return Tooltip(
      message: _filtersExpanded ? 'Ocultar filtros' : 'Mostrar filtros',
      child: Badge(
        isLabelVisible: count > 0,
        label: Text('$count', style: const TextStyle(fontSize: 9)),
        backgroundColor: const Color(0xFF0078D4),
        child: InkWell(
          onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
          borderRadius: BorderRadius.circular(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _filtersExpanded || count > 0
                  ? const Color(0xFF0078D4).withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _filtersExpanded || count > 0
                    ? const Color(0xFF0078D4)
                    : cs.outline,
              ),
            ),
            child: Icon(
              Icons.tune_rounded,
              size: 18,
              color: _filtersExpanded || count > 0
                  ? const Color(0xFF0078D4)
                  : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesButton(ProcedimientosProvider _) {
    return ListenableBuilder(
      listenable: widget.tabState,
      builder: (_, _) {
        final active = widget.tabState.showFavoritesOnly;
        return Tooltip(
          message: active ? 'Mostrando favoritos' : 'Filtrar por favoritos',
          child: InkWell(
            onTap: widget.tabState.toggleFavorites,
            borderRadius: BorderRadius.circular(4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: active
                    ? Colors.amber.shade600.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: active
                      ? Colors.amber.shade600
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Icon(
                active ? Icons.star_rounded : Icons.star_border_rounded,
                size: 18,
                color: active
                    ? Colors.amber.shade600
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryRow(ProcedimientosProvider _) {
    return ListenableBuilder(
      listenable: widget.tabState,
      builder: (_, _) {
        final hist = widget.tabState.history;
        if (hist.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final q in hist)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _HistoryChip(
                            query: q,
                            onTap: () {
                              _searchCtrl.text = q;
                              setState(() {});
                              widget.tabState.buscar(
                                busqueda: q,
                                cfg: _selectedConfig,
                                est: _selectedEstado,
                                ambiente: procedimientosProvider.ambiente,
                              );
                            },
                            onRemove: () =>
                                widget.tabState.removeFromHistory(q),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField(ColorScheme cs) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          FocusScope.of(context).nextFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          style: TextStyle(color: cs.onSurface, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar por código o contenido… (↵ Enter para buscar)',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {});
                    },
                  )
                : null,
          ),
          onChanged: (v) {
            widget.tabState.searchText = v;
            setState(() {});
          },
          onSubmitted: (_) => _buscar(),
        ),
      ),
    );
  }

  Widget _buildConfigFilter(ProcedimientosProvider provider, ColorScheme cs) {
    final configs = provider.configuraciones;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cs.outline),
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedConfig,
              hint: Text(
                'Tipo',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
              dropdownColor: cs.surfaceContainerHigh,
              isDense: true,
              style: TextStyle(color: cs.onSurface, fontSize: 12),
              icon: Icon(
                Icons.arrow_drop_down,
                color: cs.onSurfaceVariant,
                size: 18,
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Todos los tipos',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
                if (configs.isEmpty)
                  // Fallback si no cargaron aún
                  ...[
                    'D',
                    'J',
                    'A',
                    'G',
                    'S',
                    'C',
                    'F',
                    'T',
                    'V',
                    'O',
                    'I',
                  ].map(
                    (c) => DropdownMenuItem<String?>(
                      value: c,
                      child: Text(c, style: TextStyle(color: cs.onSurface)),
                    ),
                  )
                else
                  ...configs.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c.cdModulo,
                      child: Text(
                        '${c.cdModulo} — ${c.deArgumento}',
                        style: TextStyle(color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
              onChanged: (v) {
                setState(() => _selectedConfig = v);
                widget.tabState.config = v;
                if (widget.tabState.hasSearched) _buscar();
              },
            ),
          ),
          if (configs.isEmpty)
            const LinearProgressIndicator(
              minHeight: 2,
              color: Color(0xFF0078D4),
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
    );
  }

  Widget _buildEstadoFilter(ColorScheme cs) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cs.outline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedEstado,
          dropdownColor: cs.surfaceContainerHigh,
          isDense: true,
          style: TextStyle(color: cs.onSurface, fontSize: 12),
          icon: Icon(
            Icons.arrow_drop_down,
            color: cs.onSurfaceVariant,
            size: 18,
          ),
          items: _estados.entries
              .map(
                (e) => DropdownMenuItem<String?>(
                  value: e.key,
                  child: Text(e.value),
                ),
              )
              .toList(),
          onChanged: (v) {
            setState(() => _selectedEstado = v);
            widget.tabState.estado = v;
            if (widget.tabState.hasSearched) _buscar();
          },
        ),
      ),
    );
  }

  Widget _buildBuscarButton() {
    return SizedBox(
      height: 38,
      child: ElevatedButton.icon(
        onPressed: _buscar,
        icon: const Icon(Icons.search, size: 16),
        label: const Text('Buscar', style: TextStyle(fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0078D4),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  List<Widget> _buildClearFiltersButton(ColorScheme cs) {
    return [
      const SizedBox(width: 6),
      Tooltip(
        message: 'Limpiar filtros',
        child: InkWell(
          onTap: _clearFilters,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: cs.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.filter_alt_off_rounded,
                  size: 15,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Limpiar',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildNewProcButton() {
    return [
      const SizedBox(width: 8),
      const SizedBox(height: 24, child: VerticalDivider(width: 1)),
      const SizedBox(width: 8),
      SizedBox(
        height: 38,
        child: FilledButton.icon(
          onPressed: widget.onNewProcedure,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Nuevo', style: TextStyle(fontSize: 13)),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF107C10),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
        ),
      ),
    ];
  }
}

class _HistoryChip extends StatefulWidget {
  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _HistoryChip({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_HistoryChip> createState() => _HistoryChipState();
}

class _HistoryChipState extends State<_HistoryChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
          decoration: BoxDecoration(
            color: _hovered
                ? cs.surfaceContainerHighest
                : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? cs.outline : cs.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.query,
                style: TextStyle(
                  fontSize: 11,
                  color: _hovered ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              InkWell(
                onTap: widget.onRemove,
                borderRadius: BorderRadius.circular(8),
                child: Icon(Icons.close, size: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
