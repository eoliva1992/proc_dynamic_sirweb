import 'package:flutter/material.dart';
import '../providers/procedimientos_provider.dart';
import 'procedure_card.dart';
import 'search_tab_state.dart';

class ProcedureList extends StatefulWidget {
  final SearchTabState tabState;
  const ProcedureList({super.key, required this.tabState});

  @override
  State<ProcedureList> createState() => _ProcedureListState();
}

class _ProcedureListState extends State<ProcedureList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      widget.tabState.cargarMas(ambiente: procedimientosProvider.ambiente);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.tabState,
      builder: (context, _) {
        final state = widget.tabState;
        if (state.cargando) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0078D4)),
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
                TextButton(
                  onPressed: state.clearError,
                  child: const Text(
                    'Cerrar',
                    style: TextStyle(color: Color(0xFF0078D4)),
                  ),
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
            return ProcedureCard(
              procedimiento: proc,
              onTap: () => procedimientosProvider.seleccionar(proc),
            );
          },
        );
      },
    );
  }
}
