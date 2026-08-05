import 'package:flutter/material.dart';
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

  static const _estados = {'1': 'Activos', '0': 'Inactivos', '': 'Todos'};

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.tabState.searchText);
    _selectedConfig = widget.tabState.config;
    _selectedEstado = widget.tabState.estado;
    _searchCtrl.addListener(
      () => widget.tabState.searchText = _searchCtrl.text,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Observer(
      builder: (context) {
        final provider = procedimientosProvider;
        return Container(
          color: cs.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Expanded(child: _buildSearchField(cs)),
              const SizedBox(width: 8),
              _buildConfigFilter(provider, cs),
              const SizedBox(width: 8),
              _buildEstadoFilter(cs),
              const SizedBox(width: 8),
              _buildBuscarButton(),
              const SizedBox(width: 8),
              AmbienteSelector(
                value: widget.ambiente,
                onChanged: widget.onAmbienteChanged,
              ),
              if (widget.onNewProcedure != null) ..._buildNewProcButton(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField(ColorScheme cs) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: _searchCtrl,
        style: TextStyle(color: cs.onSurface, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Buscar por código o contenido del procedimiento…',
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
      child: DropdownButtonHideUnderline(
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
              ...['D', 'J', 'A', 'G', 'S', 'C', 'F', 'T', 'V', 'O', 'I'].map(
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
          },
        ),
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
