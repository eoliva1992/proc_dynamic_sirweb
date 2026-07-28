import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/procedimientos_provider.dart';

class SearchBarWidget extends StatefulWidget {
  const SearchBarWidget({super.key});

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final _searchCtrl = TextEditingController();
  String? _selectedConfig;
  String? _selectedEstado = '1';

  static const _estados = {
    '1': 'Activos',
    '0': 'Inactivos',
    '': 'Todos',
  };

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _buscar() {
    context.read<ProcedimientosProvider>().buscar(
          busqueda: _searchCtrl.text.trim(),
          config: _selectedConfig,
          estado: _selectedEstado,
        );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<ProcedimientosProvider>(
      builder: (context, provider, _) {
        return Container(
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: _buildSearchField(cs, isDark),
              ),
              const SizedBox(width: 8),
              _buildConfigFilter(provider, isDark),
              const SizedBox(width: 8),
              _buildEstadoFilter(isDark),
              const SizedBox(width: 8),
              _buildBuscarButton(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField(ColorScheme cs, bool isDark) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: _searchCtrl,
        style: TextStyle(
          color: isDark ? const Color(0xFFD4D4D4) : Colors.black87,
          fontSize: 13,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar por código o contenido del procedimiento…',
          hintStyle: TextStyle(
            color: isDark ? const Color(0xFF606060) : Colors.black45,
            fontSize: 12,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: isDark ? const Color(0xFF606060) : Colors.black45,
          ),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 16,
                      color: isDark ? const Color(0xFF606060) : Colors.black45),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: isDark ? const Color(0xFF3C3C3C) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF474747) : Colors.grey.shade300,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF474747) : Colors.grey.shade300,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFF0078D4), width: 1.5),
          ),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _buscar(),
      ),
    );
  }

  Widget _buildConfigFilter(ProcedimientosProvider provider, bool isDark) {
    final configs = provider.configuraciones;
    final fillColor = isDark ? const Color(0xFF3C3C3C) : Colors.white;
    final borderColor = isDark ? const Color(0xFF474747) : Colors.grey.shade300;
    final textColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final hintColor = isDark ? const Color(0xFF606060) : Colors.black45;
    final dropColor = isDark ? const Color(0xFF2D2D2D) : Colors.white;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedConfig,
          hint: Text(
            'Tipo',
            style: TextStyle(color: hintColor, fontSize: 12),
          ),
          dropdownColor: dropColor,
          isDense: true,
          style: TextStyle(color: textColor, fontSize: 12),
          icon: Icon(Icons.arrow_drop_down, color: hintColor, size: 18),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'Todos los tipos',
                style: TextStyle(color: hintColor),
              ),
            ),
            if (configs.isEmpty)
              // Fallback si no cargaron aún
              ...['D', 'J', 'A', 'G', 'S', 'C', 'F', 'T', 'V', 'O', 'I'].map(
                (c) => DropdownMenuItem<String?>(
                  value: c,
                  child: Text(c, style: TextStyle(color: textColor)),
                ),
              )
            else
              ...configs.map(
                (c) => DropdownMenuItem<String?>(
                  value: c.cdModulo,
                  child: Text(
                    '${c.cdModulo} — ${c.deArgumento}',
                    style: TextStyle(color: textColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
          onChanged: (v) => setState(() => _selectedConfig = v),
        ),
      ),
    );
  }

  Widget _buildEstadoFilter(bool isDark) {
    final fillColor = isDark ? const Color(0xFF3C3C3C) : Colors.white;
    final borderColor = isDark ? const Color(0xFF474747) : Colors.grey.shade300;
    final textColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final hintColor = isDark ? const Color(0xFF606060) : Colors.black45;
    final dropColor = isDark ? const Color(0xFF2D2D2D) : Colors.white;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedEstado,
          dropdownColor: dropColor,
          isDense: true,
          style: TextStyle(color: textColor, fontSize: 12),
          icon: Icon(Icons.arrow_drop_down, color: hintColor, size: 18),
          items: _estados.entries
              .map(
                (e) => DropdownMenuItem<String?>(
                  value: e.key,
                  child: Text(e.value),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedEstado = v),
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
}


