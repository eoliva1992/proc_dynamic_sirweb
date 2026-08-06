import 'package:flutter/material.dart';
import '../models/procedimiento.dart';
import 'search_tab_state.dart';
import 'search_bar_widget.dart';
import 'procedure_list.dart';

class SearchTabView extends StatelessWidget {
  final SearchTabState state;
  final String ambiente;
  final ValueChanged<String> onAmbienteChanged;
  final VoidCallback? onNewProcedure;
  final ValueChanged<Procedimiento>? onSelect;

  const SearchTabView({
    super.key,
    required this.state,
    required this.ambiente,
    required this.onAmbienteChanged,
    this.onNewProcedure,
    this.onSelect,
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
          child: ProcedureList(tabState: state, onSelect: onSelect),
        ),
      ],
    );
  }
}
