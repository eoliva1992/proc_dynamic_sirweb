import 'package:flutter/material.dart';
import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import '../services/favorites_service.dart';
import 'procedure_card.dart';
import 'search_tab_state.dart';

class ProcedureList extends StatefulWidget {
  final SearchTabState tabState;
  final ValueChanged<Procedimiento>? onSelect;
  final ValueChanged<Procedimiento>? onOpenInNewTab;
  final VoidCallback? onClearFilters;

  const ProcedureList({
    super.key,
    required this.tabState,
    this.onSelect,
    this.onOpenInNewTab,
    this.onClearFilters,
  });

  @override
  State<ProcedureList> createState() => _ProcedureListState();
}

class _ProcedureListState extends State<ProcedureList>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _entranceCtrl;
  bool _prevCargando = false;
  late List<Animation<Offset>> _entranceAnims;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _entranceAnims = List.generate(8, (i) {
      final start = (i * 0.07).clamp(0.0, 1.0);
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<Offset>(
        begin: const Offset(0, 0.05),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _entranceCtrl,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      );
    });
    _prevCargando = widget.tabState.cargando;
    widget.tabState.addListener(_onTabStateChange);
  }

  @override
  void didUpdateWidget(ProcedureList old) {
    super.didUpdateWidget(old);
    if (old.tabState != widget.tabState) {
      old.tabState.removeListener(_onTabStateChange);
      _prevCargando = widget.tabState.cargando;
      widget.tabState.addListener(_onTabStateChange);
    }
  }

  void _onTabStateChange() {
    final st = widget.tabState;
    if (!_prevCargando && st.cargando && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (_prevCargando &&
        !st.cargando &&
        st.resultados.isNotEmpty &&
        st.error == null) {
      _entranceCtrl.forward(from: 0);
    }
    _prevCargando = st.cargando;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _entranceCtrl.dispose();
    widget.tabState.removeListener(_onTabStateChange);
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      widget.tabState.cargarMas(ambiente: procedimientosProvider.ambiente);
    }
  }

  Widget _animatedCard(Widget child, int index) {
    if (index >= 8) return child;
    return SlideTransition(position: _entranceAnims[index], child: child);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.tabState,
        FavoritesService.listenable,
      ]),
      builder: (context, _) {
        final state = widget.tabState;

        if (state.cargando) {
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            itemCount: 5,
            itemBuilder: (_, i) => _SkeletonCard(delay: i * 80),
          );
        }

        if (state.error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 40,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  state.error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: state.clearError,
                      child: const Text(
                        'Cerrar',
                        style: TextStyle(color: Color(0xFF0078D4)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => state.buscar(
                        busqueda: state.searchText,
                        cfg: state.config,
                        est: state.estado,
                        ambiente: procedimientosProvider.ambiente,
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        if (state.resultados.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    state.hasSearched
                        ? Icons.search_off_rounded
                        : Icons.manage_search_rounded,
                    color: Colors.grey.shade500,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                if (state.hasSearched) ...[
                  Text(
                    'Sin resultados',
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'para «${state.searchText}»',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Probá con otro término o cambiá los filtros',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  if (widget.onClearFilters != null &&
                      (state.config != null ||
                          (state.estado ?? '1') != '1')) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: widget.onClearFilters,
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 14),
                      label: const Text(
                        'Limpiar filtros',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0078D4),
                        side: const BorderSide(color: Color(0xFF0078D4)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  Text(
                    'Buscá un procedimiento',
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (state.history.isNotEmpty) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 12,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Búsquedas recientes',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: state.history
                          .take(6)
                          .map(
                            (q) => ActionChip(
                              label: Text(
                                q,
                                style: const TextStyle(fontSize: 11),
                              ),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onPressed: () => state.buscar(
                                busqueda: q,
                                cfg: state.config,
                                est: state.estado,
                                ambiente: procedimientosProvider.ambiente,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: FavoritesService.listenable,
                    builder: (_, favs, _) {
                      if (favs.isEmpty) return const SizedBox.shrink();
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: Colors.amber.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Favoritos',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: favs
                                .take(5)
                                .map(
                                  (id) => ActionChip(
                                    label: Text(
                                      id,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'Consolas',
                                      ),
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => state.buscar(
                                      busqueda: id,
                                      cfg: null,
                                      est: '1',
                                      ambiente: procedimientosProvider.ambiente,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                  ),
                  if (state.history.isEmpty)
                    Text(
                      'Ingresá un código o término en el campo de búsqueda',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                ],
              ],
            ),
          );
        }

        final displayList = state.resultadosFiltrados;
        final countLabel = state.showFavoritesOnly
            ? '${displayList.length} favorito${displayList.length == 1 ? '' : 's'}'
            : state.tieneSiguiente
            ? '${state.resultados.length}+ resultados'
            : '${state.resultados.length} resultado${state.resultados.length == 1 ? '' : 's'}';

        if (state.showFavoritesOnly && displayList.isEmpty) {
          if (state.cargandoFavoritos) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_border_rounded,
                  color: Colors.grey.shade600,
                  size: 52,
                ),
                const SizedBox(height: 12),
                Text(
                  'No hay favoritos en esta búsqueda',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0078D4).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF0078D4).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      countLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF0078D4),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _SortPicker(value: state.sortBy, onChanged: state.setSortBy),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                itemCount:
                    displayList.length +
                    ((!state.showFavoritesOnly && state.tieneSiguiente)
                        ? 1
                        : 0),
                itemBuilder: (context, index) {
                  if (index == displayList.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0078D4),
                          ),
                        ),
                      ),
                    );
                  }
                  final proc = displayList[index];
                  final card = ProcedureCard(
                    procedimiento: proc,
                    searchQuery: state.searchText,
                    onTap: () =>
                        (widget.onSelect ?? procedimientosProvider.seleccionar)(
                          proc,
                        ),
                    onOpenInNewTab: widget.onOpenInNewTab != null
                        ? () => widget.onOpenInNewTab!(proc)
                        : null,
                  );
                  return _animatedCard(card, index);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _SortLabel {
  fechaDesc('Más reciente', SortBy.fechaDesc),
  fechaAsc('Más antiguo', SortBy.fechaAsc),
  nombre('Nombre A-Z', SortBy.nombre),
  version('Versión', SortBy.version);

  const _SortLabel(this.label, this.sortBy);
  final String label;
  final SortBy sortBy;
}

class _SortPicker extends StatelessWidget {
  final SortBy value;
  final ValueChanged<SortBy> onChanged;
  const _SortPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = _SortLabel.values.firstWhere((e) => e.sortBy == value);
    return DropdownButtonHideUnderline(
      child: DropdownButton<SortBy>(
        value: value,
        isDense: true,
        dropdownColor: cs.surfaceContainerHigh,
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        icon: Icon(Icons.sort_rounded, size: 14, color: cs.onSurfaceVariant),
        selectedItemBuilder: (_) => _SortLabel.values
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text(
                  current.label,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
            )
            .toList(),
        items: _SortLabel.values
            .map(
              (e) => DropdownMenuItem(
                value: e.sortBy,
                child: Text(
                  e.label,
                  style: TextStyle(fontSize: 12, color: cs.onSurface),
                ),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  final int delay;
  const _SkeletonCard({this.delay = 0});

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmerBase = isDark
        ? cs.surfaceContainerLow
        : const Color(0xFFEEEEEE);
    final shimmerHigh = isDark
        ? cs.surfaceContainerHigh
        : const Color(0xFFF8F8F8);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t = _ctrl.value;
        // Gradient band sweeps left→right across the widget
        final begin = Alignment(-2 + t * 4, 0);
        final end = Alignment(-1 + t * 4, 0);
        return Card(
          color: cs.surface,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => LinearGradient(
                colors: [shimmerBase, shimmerHigh, shimmerBase],
                stops: const [0.0, 0.5, 1.0],
                begin: begin,
                end: end,
              ).createShader(rect),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width: 180,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        height: 9,
                        width: 70,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        height: 9,
                        width: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
