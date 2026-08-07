import 'package:flutter/material.dart';
import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import 'procedure_card.dart';
import 'search_tab_state.dart';

class ProcedureList extends StatefulWidget {
  final SearchTabState tabState;
  final ValueChanged<Procedimiento>? onSelect;
  final ValueChanged<Procedimiento>? onOpenInNewTab;

  const ProcedureList({
    super.key,
    required this.tabState,
    this.onSelect,
    this.onOpenInNewTab,
  });

  @override
  State<ProcedureList> createState() => _ProcedureListState();
}

class _ProcedureListState extends State<ProcedureList>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _entranceCtrl;
  bool _prevCargando = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
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
    final start = (index * 0.07).clamp(0.0, 1.0);
    final end = (start + 0.4).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.05),
        end: Offset.zero,
      ).animate(curve),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.tabState,
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
                Text(
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
                Icon(Icons.search_off, color: Colors.grey.shade700, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Usa el buscador para encontrar procedimientos',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          itemCount: state.resultados.length + (state.tieneSiguiente ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == state.resultados.length) {
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
            final proc = state.resultados[index];
            final card = ProcedureCard(
              procedimiento: proc,
              onTap: () =>
                  (widget.onSelect ?? procedimientosProvider.seleccionar)(proc),
              onOpenInNewTab: widget.onOpenInNewTab != null
                  ? () => widget.onOpenInNewTab!(proc)
                  : null,
            );
            return _animatedCard(card, index);
          },
        );
      },
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
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween<double>(
      begin: 0.25,
      end: 0.65,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
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
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Card(
        color: cs.surface,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Opacity(
            opacity: _anim.value,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: 180,
                  decoration: BoxDecoration(
                    color: cs.onSurface,
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
                        color: cs.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 9,
                      width: 50,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
