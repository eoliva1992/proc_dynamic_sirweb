import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/procedimientos_provider.dart';
import 'procedure_card.dart';

class ProcedureList extends StatefulWidget {
  const ProcedureList({super.key});

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
      context.read<ProcedimientosProvider>().cargarMas();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProcedimientosProvider>(
      builder: (context, provider, _) {
        if (provider.cargando) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0078D4)),
          );
        }

        if (provider.error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                const SizedBox(height: 8),
                Text(
                  provider.error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: provider.limpiarMensajes,
                  child: const Text('Cerrar', style: TextStyle(color: Color(0xFF0078D4))),
                ),
              ],
            ),
          );
        }

        if (provider.resultados.isEmpty) {
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
          itemCount: provider.resultados.length + (provider.tieneSiguiente ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == provider.resultados.length) {
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
            final proc = provider.resultados[index];
            return ProcedureCard(
              procedimiento: proc,
              onTap: () => provider.seleccionar(proc),
            );
          },
        );
      },
    );
  }
}
