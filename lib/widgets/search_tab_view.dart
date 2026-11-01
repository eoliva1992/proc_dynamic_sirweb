import 'package:flutter/material.dart';
import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import 'search_tab_state.dart';
import 'search_bar_widget.dart';
import 'procedure_list.dart';

class SearchTabView extends StatelessWidget {
  final SearchTabState state;
  final String ambiente;
  final ValueChanged<String> onAmbienteChanged;
  final VoidCallback? onNewProcedure;
  final ValueChanged<Procedimiento>? onSelect;
  final ValueChanged<Procedimiento>? onOpenInNewTab;
  final VoidCallback? onOpenBlank;
  final VoidCallback? onOpenSqlExecutor;
  final VoidCallback? onBatchTransfer;
  final VoidCallback? onDeployTickets;
  final VoidCallback? onNewNote;
  final VoidCallback? onCompare;

  const SearchTabView({
    super.key,
    required this.state,
    required this.ambiente,
    required this.onAmbienteChanged,
    this.onNewProcedure,
    this.onSelect,
    this.onOpenInNewTab,
    this.onOpenBlank,
    this.onOpenSqlExecutor,
    this.onBatchTransfer,
    this.onDeployTickets,
    this.onNewNote,
    this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SearchBarWidget(
          tabState: state,
          ambiente: ambiente,
          onAmbienteChanged: onAmbienteChanged,
          onNewProcedure: onNewProcedure,
        ),
        Expanded(
          child: ProcedureList(
            tabState: state,
            onSelect: onSelect,
            onOpenInNewTab: onOpenInNewTab,
            onOpenBlank: onOpenBlank,
            onOpenSqlExecutor: onOpenSqlExecutor,
            onBatchTransfer: onBatchTransfer,
            onDeployTickets: onDeployTickets,
            onNewNote: onNewNote,
            onCompare: onCompare,
            onClearFilters: () {
              state.config = null;
              state.estado = '1';
              state.buscar(
                busqueda: state.searchText,
                cfg: null,
                est: '1',
                ambiente: procedimientosProvider.ambiente,
              );
            },
          ),
        ),
      ],
    );
  }
}
