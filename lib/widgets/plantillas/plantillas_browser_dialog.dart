import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/plantilla.dart';
import '../../services/plantilla_service.dart';
import '../app_toast.dart';
import '../floating_window.dart' show showFloatingDialog;
import 'plantilla_editor_window.dart';

/// Abre la estación de trabajo y catálogo de plantillas de código predefinidas.
Future<void> showPlantillasBrowser(BuildContext context) {
  return showFloatingDialog<void>(
    context,
    (dialogContext, close) => PlantillasBrowserDialog(close: close),
  );
}

class PlantillasBrowserDialog extends StatefulWidget {
  final void Function([void]) close;

  const PlantillasBrowserDialog({super.key, required this.close});

  @override
  State<PlantillasBrowserDialog> createState() =>
      _PlantillasBrowserDialogState();
}

class _PlantillasBrowserDialogState extends State<PlantillasBrowserDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Plantilla> _items = [];
  bool _loading = true;
  String? _error;
  Timer? _searchDebounce;

  String _selectedCategoria = 'ALL';
  Plantilla? _selectedPlantilla;

  // Layout geometry
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    _loadPlantillas();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlantillas() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final catFilter = _selectedCategoria == 'ALL' ? null : _selectedCategoria;
      final q = _searchCtrl.text.trim();
      final items = await PlantillaService.instance.loadAll(
        categoria: catFilter,
        query: q.isEmpty ? null : q,
      );

      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
          if (_selectedPlantilla != null) {
            _selectedPlantilla =
                items
                    .where((p) => p.id == _selectedPlantilla!.id)
                    .firstOrNull ??
                (items.isNotEmpty ? items.first : null);
          } else if (items.isNotEmpty) {
            _selectedPlantilla = items.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadPlantillas();
    });
  }

  void _nuevaPlantilla() {
    showPlantillaEditorWindow(
      context,
      defaultCategoria: _selectedCategoria == 'ALL'
          ? Plantilla.catProcDinamico
          : _selectedCategoria,
      onSaved: (_) => _loadPlantillas(),
    );
  }

  void _editarPlantilla(Plantilla p) {
    showPlantillaEditorWindow(
      context,
      initialPlantilla: p,
      onSaved: (_) => _loadPlantillas(),
      onDeleted: () {
        setState(() {
          _selectedPlantilla = null;
        });
        _loadPlantillas();
      },
    );
  }

  void _duplicarPlantilla(Plantilla p) {
    final copia = p.copyWith(id: '', nombre: '${p.nombre} (Copia)');
    showPlantillaEditorWindow(
      context,
      initialPlantilla: copia,
      onSaved: (_) => _loadPlantillas(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final w = _maximized
        ? screenSize.width
        : 1080.0.clamp(700.0, screenSize.width);
    final h = _maximized
        ? screenSize.height
        : 680.0.clamp(480.0, screenSize.height);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xFF141820),
            borderRadius: BorderRadius.circular(_maximized ? 0 : 12),
            border: Border.all(color: const Color(0xFF2C3240), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.75),
                blurRadius: 36,
                spreadRadius: 4,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_maximized ? 0 : 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                _buildFiltersBar(),
                Expanded(
                  child: Row(
                    children: [
                      // Panel izquierdo: Lista de plantillas
                      Expanded(flex: 5, child: _buildListPanel()),
                      // Separador vertical
                      Container(width: 1, color: const Color(0xFF2C3240)),
                      // Panel derecho: Inspector / Preview
                      Expanded(flex: 6, child: _buildInspectorPanel()),
                    ],
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1B202C),
        border: Border(bottom: BorderSide(color: Color(0xFF2C3240))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF0078D4).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.auto_awesome_motion_rounded,
              color: Color(0xFF4FC3F7),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mantenimiento de Plantillas de Código',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                'Estructuras predefinidas para procedimientos dinámicos, DDL Oracle y funciones',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text(
              'Nueva Plantilla',
              style: TextStyle(fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0078D4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: _nuevaPlantilla,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _maximized
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
            ),
            color: Colors.white70,
            iconSize: 18,
            tooltip: 'Maximizar (F11)',
            onPressed: () => setState(() => _maximized = !_maximized),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            color: Colors.white70,
            iconSize: 18,
            tooltip: 'Cerrar (Esc)',
            onPressed: widget.close,
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersBar() {
    final categorias = ['ALL', ...Plantilla.categoriasValidas];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF161A23),
        border: Border(bottom: BorderSide(color: Color(0xFF262C3A))),
      ),
      child: Row(
        children: [
          // Buscador
          Expanded(
            flex: 4,
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText:
                      'Buscar plantilla por nombre, descripción o código...',
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: Colors.white54,
                  ),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            size: 14,
                            color: Colors.white54,
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            _loadPlantillas();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1F2430),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Chips de categorías
          Expanded(
            flex: 7,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categorias.map((cat) {
                  final isSelected = _selectedCategoria == cat;
                  final label = cat == 'ALL' ? 'Todas' : cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      selectedColor: const Color(0xFF0078D4),
                      backgroundColor: const Color(0xFF1E232F),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFF0078D4)
                            : const Color(0xFF323B4C),
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() => _selectedCategoria = cat);
                          _loadPlantillas();
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              size: 16,
              color: Colors.white70,
            ),
            tooltip: 'Refrescar',
            onPressed: _loadPlantillas,
          ),
        ],
      ),
    );
  }

  Widget _buildListPanel() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF0078D4),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.orangeAccent,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                'Error al consultar plantillas: $_error',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Reintentar', style: TextStyle(fontSize: 12)),
                onPressed: _loadPlantillas,
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.white24, size: 40),
            SizedBox(height: 10),
            Text(
              'No se encontraron plantillas',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (ctx, idx) {
        final item = _items[idx];
        final isSelected = _selectedPlantilla?.id == item.id;

        return InkWell(
          onTap: () => setState(() => _selectedPlantilla = item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF0078D4).withValues(alpha: 0.15)
                  : (idx % 2 == 0
                        ? const Color(0xFF141820)
                        : const Color(0xFF171B24)),
              border: Border(
                left: BorderSide(
                  color: isSelected
                      ? const Color(0xFF0078D4)
                      : Colors.transparent,
                  width: 3.5,
                ),
                bottom: const BorderSide(color: Color(0xFF222733), width: 0.8),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCategoriaIcon(item.categoria),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.nombre,
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF64B5F6)
                                    : Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF232A39),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF343E54),
                              ),
                            ),
                            child: Text(
                              item.categoria,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (item.descripcion != null &&
                          item.descripcion!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.descripcion!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoriaIcon(String cat) {
    IconData icon;
    Color color;
    switch (cat.toUpperCase()) {
      case Plantilla.catProcDinamico:
        icon = Icons.bolt_rounded;
        color = const Color(0xFF00BCD4);
        break;
      case Plantilla.catProcedure:
        icon = Icons.code_rounded;
        color = const Color(0xFFCA5010);
        break;
      case Plantilla.catFunction:
        icon = Icons.functions_rounded;
        color = const Color(0xFF8764B8);
        break;
      case Plantilla.catPackage:
      case Plantilla.catPackageBody:
        icon = Icons.inventory_2_outlined;
        color = const Color(0xFFC19C00);
        break;
      default:
        icon = Icons.description_outlined;
        color = const Color(0xFF90A4AE);
    }

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  Widget _buildInspectorPanel() {
    final p = _selectedPlantilla;
    if (p == null) {
      return const Center(
        child: Text(
          'Selecciona una plantilla para ver su detalle',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    return Container(
      color: const Color(0xFF13171F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Inspector Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF181C26),
              border: Border(bottom: BorderSide(color: Color(0xFF262C3A))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.nombre,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (p.descripcion != null && p.descripcion!.isNotEmpty)
                        Text(
                          p.descripcion!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  color: Colors.white70,
                  tooltip: 'Duplicar plantilla',
                  onPressed: () => _duplicarPlantilla(p),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  color: const Color(0xFF64B5F6),
                  tooltip: 'Editar plantilla',
                  onPressed: () => _editarPlantilla(p),
                ),
              ],
            ),
          ),
          // Código Preview
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1E27),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2C3240)),
              ),
              child: SelectableText(
                p.contenido,
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  color: Color(0xFFD4D4D4),
                  height: 1.4,
                ),
              ),
            ),
          ),
          // Barra de copia rápida
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF181C26),
              border: Border(top: BorderSide(color: Color(0xFF262C3A))),
            ),
            child: Row(
              children: [
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_copy_rounded, size: 14),
                  label: const Text(
                    'Copiar Código',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF3B4457)),
                  ),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: p.contenido));
                    AppToast.info('Código copiado al portapapeles');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFF161A23),
      child: Row(
        children: [
          Text(
            'Total: ${_items.length} plantilla(s)',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const Spacer(),
          const Text(
            'Endpoint: /tools/plantillas',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
