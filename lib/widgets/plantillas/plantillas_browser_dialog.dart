import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/plantilla.dart';
import '../../services/plantilla_service.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart' show showFloatingDialog;
import 'plantilla_editor_window.dart';

/// Abre la estación de trabajo y catálogo de plantillas de código predefinidas.
Future<void> showPlantillasBrowser(BuildContext context) {
  return showFloatingDialog<void>(
    context,
    (dialogContext, close) => PlantillasBrowserDialog(close: close),
  );
}

/// Ámbito de autoría para filtrar plantillas
enum PlantillaScope { all, mine, team }

/// Criterio de ordenamiento de plantillas
enum PlantillaSort {
  recent('Más recientes', Icons.update_rounded),
  alphabetical('Nombre (A - Z)', Icons.sort_by_alpha_rounded),
  category('Categoría', Icons.category_rounded);

  final String label;
  final IconData icon;
  const PlantillaSort(this.label, this.icon);
}

/// Modo de visualización del catálogo
enum PlantillaViewMode {
  grid('Cuadrícula', Icons.grid_view_rounded),
  list('Lista detallada', Icons.view_agenda_outlined);

  final String label;
  final IconData icon;
  const PlantillaViewMode(this.label, this.icon);
}

/// Metadata visual de una categoría de plantilla
class PlantillaCategoryMeta {
  final String code;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const PlantillaCategoryMeta({
    required this.code,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

const List<PlantillaCategoryMeta> kPlantillaCategories = [
  PlantillaCategoryMeta(
    code: Plantilla.catProcDinamico,
    title: 'Procedimiento Dinámico',
    description: 'Regla de negocio, validación o cálculo del motor SirWeb',
    icon: Icons.flash_on_rounded,
    color: Color(0xFF0078D4),
  ),
  PlantillaCategoryMeta(
    code: Plantilla.catProcedure,
    title: 'Stored Procedure',
    description: 'Procedimiento almacenado estándar PL/SQL de base de datos',
    icon: Icons.terminal_rounded,
    color: Color(0xFF107C41),
  ),
  PlantillaCategoryMeta(
    code: Plantilla.catFunction,
    title: 'Función PL/SQL',
    description: 'Función con valor de retorno (escalar o compuesto)',
    icon: Icons.functions_rounded,
    color: Color(0xFF5C2D91),
  ),
  PlantillaCategoryMeta(
    code: Plantilla.catPackage,
    title: 'Package (Spec)',
    description: 'Especificación de paquete PL/SQL con signaturas públicas',
    icon: Icons.folder_zip_rounded,
    color: Color(0xFFB4A0FF),
  ),
  PlantillaCategoryMeta(
    code: Plantilla.catPackageBody,
    title: 'Package Body',
    description: 'Implementación y cuerpo de paquete PL/SQL',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFFE81123),
  ),
  PlantillaCategoryMeta(
    code: Plantilla.catTrigger,
    title: 'Trigger',
    description: 'Disparador automático asociado a eventos de tabla (DML)',
    icon: Icons.bolt_rounded,
    color: Color(0xFFFF8C00),
  ),
  PlantillaCategoryMeta(
    code: Plantilla.catType,
    title: 'Type (Objeto)',
    description: 'Tipo de dato objeto Oracle compuesto o estructurado',
    icon: Icons.category_rounded,
    color: Color(0xFF0288D1),
  ),
  PlantillaCategoryMeta(
    code: Plantilla.catOtro,
    title: 'Otro / Script / Bloque',
    description: 'Bloque anónimo, script utilitario, migración o DDL libre',
    icon: Icons.code_rounded,
    color: Color(0xFF888888),
  ),
];

PlantillaCategoryMeta categoriaMetaFor(String code) {
  final normalized = code.trim().toUpperCase();
  for (final meta in kPlantillaCategories) {
    if (meta.code.toUpperCase() == normalized) {
      return meta;
    }
  }
  return PlantillaCategoryMeta(
    code: code,
    title: code,
    description: 'Plantilla de código personalizada',
    icon: Icons.description_outlined,
    color: const Color(0xFF0078D4),
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
  String get _currentUser => PlantillaService.currentUser;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Plantilla> _items = [];
  bool _loading = true;
  String? _error;
  Timer? _searchDebounce;

  String _selectedCategoria = 'ALL';
  PlantillaScope _scope = PlantillaScope.all;
  PlantillaSort _sort = PlantillaSort.recent;
  PlantillaViewMode _viewMode = PlantillaViewMode.grid;

  // Sidebar animado
  bool _sidebarOpen = false;
  static const double _sidebarWidth = 240.0;

  // Inspector lateral
  bool _inspectorOpen = true;
  static const double _inspectorWidth = 340.0;
  Plantilla? _selectedPlantilla;

  // Claves para persistir preferencias
  static const String _prefKeyViewMode = 'plantillas_browser_view_mode';
  static const String _prefKeySort = 'plantillas_browser_sort';
  static const String _prefKeyInspectorOpen =
      'plantillas_browser_inspector_open';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadPlantillas();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedView = prefs.getString(_prefKeyViewMode);
      final savedSort = prefs.getString(_prefKeySort);
      final savedInspector = prefs.getBool(_prefKeyInspectorOpen);

      if (!mounted) return;
      setState(() {
        if (savedView != null) {
          _viewMode = PlantillaViewMode.values.firstWhere(
            (v) => v.name == savedView,
            orElse: () => PlantillaViewMode.grid,
          );
        }
        if (savedSort != null) {
          _sort = PlantillaSort.values.firstWhere(
            (s) => s.name == savedSort,
            orElse: () => PlantillaSort.recent,
          );
        }
        if (savedInspector != null) {
          _inspectorOpen = savedInspector;
        }
      });
    } catch (_) {}
  }

  Future<void> _savePreference(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is String) await prefs.setString(key, value);
      if (value is bool) await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _loadPlantillas() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final catFilter = _selectedCategoria == 'ALL' ? null : _selectedCategoria;
      final q = _searchCtrl.text.trim();
      final ownerParam = switch (_scope) {
        PlantillaScope.mine => _currentUser,
        _ => null,
      };

      final items = await PlantillaService.instance.loadAll(
        categoria: catFilter,
        query: q.isEmpty ? null : q,
        ownerUser: ownerParam,
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
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadPlantillas();
    });
  }

  List<Plantilla> get _filteredAndSortedItems {
    var list = _items.where((p) {
      if (_scope == PlantillaScope.team) {
        if (p.ownerUser.isNotEmpty &&
            p.ownerUser.toUpperCase() == _currentUser.toUpperCase()) {
          return false;
        }
      }
      return true;
    }).toList();

    switch (_sort) {
      case PlantillaSort.recent:
        list.sort((a, b) {
          final timeA = a.updatedAt ?? DateTime(1970);
          final timeB = b.updatedAt ?? DateTime(1970);
          return timeB.compareTo(timeA);
        });
      case PlantillaSort.alphabetical:
        list.sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        );
      case PlantillaSort.category:
        list.sort(
          (a, b) =>
              a.categoria.toLowerCase().compareTo(b.categoria.toLowerCase()),
        );
    }
    return list;
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
    final copia = p.copyWith(
      id: '',
      nombre: '${p.nombre} (Copia)',
      ownerUser: _currentUser,
      modifiedBy: null,
      updatedAt: null,
    );
    showPlantillaEditorWindow(
      context,
      initialPlantilla: copia,
      onSaved: (_) => _loadPlantillas(),
    );
  }

  Future<void> _copiarCodigo(Plantilla p) async {
    final codeToCopy = p.prepararParaInsercionSnippet(
      usuario: PlantillaService.currentUser,
    );
    await Clipboard.setData(ClipboardData(text: codeToCopy));
    AppToast.success('Código de la plantilla copiado al portapapeles');
  }

  Future<void> _eliminarPlantilla(Plantilla p) async {
    final currentUser = PlantillaService.currentUser;
    if (!p.esPropietario(currentUser)) {
      AppToast.warning(
        'Solo el autor (${p.ownerUser.isNotEmpty ? p.ownerUser : "creador"}) puede eliminar esta plantilla',
      );
      return;
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmar = await showFloatingDialog<bool>(
      context,
      (ctx, close) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 440,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E22) : cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.6),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstellationHeader(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onDark: true,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.red.shade800,
                        Color.lerp(Colors.red.shade800, Colors.black, 0.4)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Eliminar Plantilla',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Text(
                    '¿Estás seguro de que deseas eliminar permanentemente la plantilla "${p.nombre}"?',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => close(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        icon: const Icon(
                          Icons.delete_forever_rounded,
                          size: 16,
                        ),
                        label: const Text(
                          'Eliminar',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => close(true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmar != true) return;

    try {
      final ok = await PlantillaService.instance.delete(p);
      if (ok) {
        AppToast.success('Plantilla eliminada correctamente');
        setState(() {
          if (_selectedPlantilla?.id == p.id) {
            _selectedPlantilla = null;
          }
        });
        _loadPlantillas();
      } else {
        AppToast.error('No se pudo eliminar la plantilla');
      }
    } catch (e) {
      AppToast.error('Error al eliminar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context);

    final dialogW = (screen.width * 0.85).clamp(860.0, 1260.0);
    final dialogH = (screen.height * 0.85).clamp(560.0, 820.0);

    final divColor = isDark ? const Color(0xFF333333) : cs.outlineVariant;
    final bg = isDark ? const Color(0xFF1E1E1E) : cs.surface;

    final displayItems = _filteredAndSortedItems;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _nuevaPlantilla,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            setState(() => _sidebarOpen = !_sidebarOpen),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
          setState(() {
            _inspectorOpen = !_inspectorOpen;
            _savePreference(_prefKeyInspectorOpen, _inspectorOpen);
          });
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocus.requestFocus();
          _searchCtrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchCtrl.text.length,
          );
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_sidebarOpen) {
            setState(() => _sidebarOpen = false);
          } else {
            widget.close();
          }
        },
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: dialogW,
            height: dialogH,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.6),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    children: [
                      _buildHeader(cs, divColor, isDark),
                      _buildToolbar(cs, divColor, displayItems.length),
                      if (_error != null) _buildErrorBanner(cs),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _loading
                                  ? Center(
                                      child: SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: cs.primary,
                                        ),
                                      ),
                                    )
                                  : displayItems.isEmpty
                                  ? _buildEmptyState(cs)
                                  : _viewMode == PlantillaViewMode.grid
                                  ? _buildGridView(displayItems, cs, divColor)
                                  : _buildListView(displayItems, cs, divColor),
                            ),
                            if (_inspectorOpen && _selectedPlantilla != null)
                              Container(width: 0.5, color: divColor),
                            if (_inspectorOpen && _selectedPlantilla != null)
                              SizedBox(
                                width: _inspectorWidth,
                                child: _buildInspector(
                                  _selectedPlantilla!,
                                  cs,
                                  divColor,
                                  isDark,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _buildFooter(cs, divColor, displayItems.length),
                    ],
                  ),
                ),
                // Overlay backdrop para el sidebar
                if (_sidebarOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _sidebarOpen = false),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                // Sidebar flotante con drawer animado
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: _sidebarOpen ? 0 : -_sidebarWidth,
                  top: 50,
                  bottom: 0,
                  width: _sidebarWidth,
                  child: Material(
                    elevation: 12,
                    color: isDark
                        ? const Color(0xFF252526)
                        : cs.surfaceContainerLowest,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: divColor, width: 0.5),
                        ),
                      ),
                      child: _buildSidebar(cs, divColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, Color divColor, bool isDark) {
    return ConstellationHeader(
      height: 50,
      padding: const EdgeInsets.only(left: 14, right: 10),
      lineColor: cs.primary.withValues(alpha: 0.3),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
            icon: Icon(
              _sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
              size: 20,
              color: _sidebarOpen ? cs.primary : cs.onSurfaceVariant,
            ),
            tooltip: 'Filtros y categorías (Ctrl+B)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              Icons.auto_awesome_motion_rounded,
              size: 16,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Plantillas de Código',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _selectedCategoria == 'ALL'
                            ? 'Todas'
                            : _selectedCategoria,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Catálogo de estructuras base para procedimientos dinámicos, DDL Oracle y funciones',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: _nuevaPlantilla,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text(
              'Nueva plantilla',
              style: TextStyle(fontSize: 12),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              setState(() {
                _inspectorOpen = !_inspectorOpen;
                _savePreference(_prefKeyInspectorOpen, _inspectorOpen);
              });
            },
            icon: Icon(
              _inspectorOpen
                  ? Icons.chrome_reader_mode_rounded
                  : Icons.chrome_reader_mode_outlined,
              size: 18,
              color: _inspectorOpen ? cs.primary : cs.onSurfaceVariant,
            ),
            tooltip: _inspectorOpen
                ? 'Ocultar inspector (Ctrl+I)'
                : 'Mostrar inspector (Ctrl+I)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: widget.close,
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Cerrar (Esc)',
            hoverColor: Colors.red.withValues(alpha: 0.12),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ColorScheme cs, Color divColor, int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText:
                      'Buscar por nombre, categoría, descripción o contenido… (Ctrl+F)',
                  hintStyle: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: cs.primary,
                  ),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 14),
                          onPressed: () {
                            _searchCtrl.clear();
                            _loadPlantillas();
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: divColor, width: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: divColor, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: cs.primary, width: 1.2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Selector de orden con MenuAnchor
          MenuAnchor(
            menuChildren: [
              for (final s in PlantillaSort.values)
                MenuItemButton(
                  leadingIcon: Icon(s.icon, size: 15),
                  trailingIcon: s == _sort
                      ? Icon(Icons.check, size: 14, color: cs.primary)
                      : null,
                  onPressed: () {
                    setState(() => _sort = s);
                    _savePreference(_prefKeySort, s.name);
                  },
                  child: Text(s.label, style: const TextStyle(fontSize: 11.5)),
                ),
            ],
            builder: (ctx, menu, _) => OutlinedButton.icon(
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
              icon: Icon(_sort.icon, size: 14, color: cs.primary),
              label: Text(_sort.label, style: const TextStyle(fontSize: 11.5)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Vista Cuadrícula / Lista
          SegmentedButton<PlantillaViewMode>(
            segments: const [
              ButtonSegment(
                value: PlantillaViewMode.grid,
                icon: Icon(Icons.grid_view_rounded, size: 14),
                tooltip: 'Vista en cuadrícula',
              ),
              ButtonSegment(
                value: PlantillaViewMode.list,
                icon: Icon(Icons.view_agenda_outlined, size: 14),
                tooltip: 'Vista en lista detallada',
              ),
            ],
            selected: {_viewMode},
            onSelectionChanged: (set) {
              setState(() => _viewMode = set.first);
              _savePreference(_prefKeyViewMode, set.first.name);
            },
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            tooltip: 'Refrescar catálogo',
            onPressed: _loadPlantillas,
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(ColorScheme cs, Color divColor) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      children: [
        Row(
          children: [
            Icon(Icons.filter_list_rounded, size: 15, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'FILTROS Y CATEGORÍAS',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _sidebarOpen = false),
              icon: const Icon(Icons.chevron_left_rounded, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildSidebarCategory(
          title: 'ÁMBITO DE PROPIEDAD',
          children: [
            _buildSidebarOption(
              label: 'Todas las plantillas',
              icon: Icons.all_inbox_rounded,
              selected: _scope == PlantillaScope.all,
              onTap: () {
                setState(() => _scope = PlantillaScope.all);
                _loadPlantillas();
              },
            ),
            _buildSidebarOption(
              label: 'Mis plantillas',
              icon: Icons.person_rounded,
              selected: _scope == PlantillaScope.mine,
              onTap: () {
                setState(() => _scope = PlantillaScope.mine);
                _loadPlantillas();
              },
            ),
            _buildSidebarOption(
              label: 'Plantillas del equipo',
              icon: Icons.group_outlined,
              selected: _scope == PlantillaScope.team,
              onTap: () {
                setState(() => _scope = PlantillaScope.team);
                _loadPlantillas();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSidebarCategory(
          title: 'CATEGORÍA DE OBJETO',
          children: [
            _buildSidebarOption(
              label: 'Todas las categorías',
              icon: Icons.layers_outlined,
              selected: _selectedCategoria == 'ALL',
              onTap: () {
                setState(() => _selectedCategoria = 'ALL');
                _loadPlantillas();
              },
            ),
            for (final cat in kPlantillaCategories)
              _buildSidebarOption(
                label: cat.title,
                icon: cat.icon,
                color: cat.color,
                selected: _selectedCategoria == cat.code,
                onTap: () {
                  setState(() => _selectedCategoria = cat.code);
                  _loadPlantillas();
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSidebarCategory({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildSidebarOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? cs.primary : (color ?? cs.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? cs.primary : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView(List<Plantilla> items, ColorScheme cs, Color divColor) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 175,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final plantilla = items[i];
        final isSelected = _selectedPlantilla?.id == plantilla.id;
        final meta = categoriaMetaFor(plantilla.categoria);

        return _PlantillaGridCard(
          plantilla: plantilla,
          meta: meta,
          isSelected: isSelected,
          onTap: () => setState(() => _selectedPlantilla = plantilla),
          onDoubleTap: () => _editarPlantilla(plantilla),
          onCopy: () => _copiarCodigo(plantilla),
        );
      },
    );
  }

  Widget _buildListView(List<Plantilla> items, ColorScheme cs, Color divColor) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        final plantilla = items[i];
        final isSelected = _selectedPlantilla?.id == plantilla.id;
        final meta = categoriaMetaFor(plantilla.categoria);

        return _PlantillaListRow(
          plantilla: plantilla,
          meta: meta,
          isSelected: isSelected,
          onTap: () => setState(() => _selectedPlantilla = plantilla),
          onDoubleTap: () => _editarPlantilla(plantilla),
          onCopy: () => _copiarCodigo(plantilla),
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 40,
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              'No se encontraron plantillas',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Intenta ajustar los filtros de búsqueda o crea una nueva plantilla.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _nuevaPlantilla,
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text(
                'Crear plantilla',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspector(
    Plantilla plantilla,
    ColorScheme cs,
    Color divColor,
    bool isDark,
  ) {
    final meta = categoriaMetaFor(plantilla.categoria);
    final lines = '\n'.allMatches(plantilla.contenido).length + 1;
    final esPropietario = plantilla.esPropietario(_currentUser);

    return Container(
      color: isDark ? const Color(0xFF222222) : cs.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera Inspector
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
            ),
            child: Row(
              children: [
                Icon(meta.icon, size: 16, color: meta.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plantilla.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _editarPlantilla(plantilla),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  tooltip: 'Abrir en editor Monaco',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  onPressed: () => _duplicarPlantilla(plantilla),
                  icon: const Icon(Icons.copy_all_rounded, size: 15),
                  tooltip: 'Duplicar plantilla',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                if (plantilla.isPersisted &&
                    !plantilla.id.startsWith('seed-') &&
                    esPropietario)
                  IconButton(
                    onPressed: () => _eliminarPlantilla(plantilla),
                    icon: const Icon(Icons.delete_outline_rounded, size: 15),
                    tooltip: 'Eliminar plantilla',
                    color: Colors.redAccent,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
              ],
            ),
          ),
          // Metadatos y Auditoría
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: meta.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(meta.icon, size: 11, color: meta.color),
                          const SizedBox(width: 4),
                          Text(
                            meta.code,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: meta.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        plantilla.monacoLanguage.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$lines línea${lines == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (plantilla.descripcion != null &&
                    plantilla.descripcion!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    plantilla.descripcion!,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 10),
                // Auditoría
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: divColor, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 12,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Autor: ',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            plantilla.ownerUser.isNotEmpty
                                ? plantilla.ownerUser
                                : 'Fábrica / Sistema',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Consolas',
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                      if (plantilla.modifiedBy != null &&
                          plantilla.modifiedBy!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              size: 13,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Modificado por: ',
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              plantilla.modifiedBy!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Consolas',
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Código Preview
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Text(
                  'ESTRUCTURA DE CÓDIGO',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _copiarCodigo(plantilla),
                  child: Row(
                    children: [
                      Icon(Icons.copy_rounded, size: 12, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Copiar código',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF181818)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: divColor, width: 0.5),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  plantilla.contenido,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'Consolas',
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ColorScheme cs, Color divColor, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        border: Border(top: BorderSide(color: divColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            'Total: $count plantilla(s)',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '•  Ctrl+N: Nueva  •  Ctrl+B: Filtros  •  Ctrl+I: Inspector  •  Esc: Salir',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Endpoint: /tools/plantillas',
            style: TextStyle(
              fontSize: 10.5,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: Colors.orange.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 14, color: Colors.orange[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(fontSize: 11, color: Colors.orange[800]),
            ),
          ),
          TextButton(
            onPressed: _loadPlantillas,
            child: const Text('Reintentar', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _PlantillaGridCard extends StatefulWidget {
  final Plantilla plantilla;
  final PlantillaCategoryMeta meta;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onCopy;

  const _PlantillaGridCard({
    required this.plantilla,
    required this.meta,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onCopy,
  });

  @override
  State<_PlantillaGridCard> createState() => _PlantillaGridCardState();
}

class _PlantillaGridCardState extends State<_PlantillaGridCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.plantilla;

    final bg = widget.isSelected
        ? cs.primary.withValues(alpha: 0.13)
        : _hover
        ? (isDark
              ? const Color(0xFF2B2B2B)
              : cs.surfaceContainerHighest.withValues(alpha: 0.5))
        : (isDark ? const Color(0xFF252526) : cs.surfaceContainerLowest);

    final borderColor = widget.isSelected
        ? cs.primary
        : _hover
        ? cs.outlineVariant
        : (isDark
              ? const Color(0xFF333333)
              : cs.outlineVariant.withValues(alpha: 0.6));

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: widget.isSelected ? 1.5 : 0.8,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.meta.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.meta.icon,
                          size: 11,
                          color: widget.meta.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.meta.code,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: widget.meta.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      p.monacoLanguage.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                p.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: widget.isSelected ? cs.primary : cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1B1B1B)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    p.contenido,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontFamily: 'Consolas',
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 10,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      p.ownerUser.isNotEmpty ? p.ownerUser : 'Sistema',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                    ),
                  ),
                  InkWell(
                    onTap: widget.onCopy,
                    child: Icon(
                      Icons.copy_rounded,
                      size: 12,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantillaListRow extends StatefulWidget {
  final Plantilla plantilla;
  final PlantillaCategoryMeta meta;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onCopy;

  const _PlantillaListRow({
    required this.plantilla,
    required this.meta,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onCopy,
  });

  @override
  State<_PlantillaListRow> createState() => _PlantillaListRowState();
}

class _PlantillaListRowState extends State<_PlantillaListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.plantilla;

    final bg = widget.isSelected
        ? cs.primary.withValues(alpha: 0.14)
        : _hover
        ? (isDark
              ? const Color(0xFF282828)
              : cs.surfaceContainerHighest.withValues(alpha: 0.5))
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: widget.isSelected ? cs.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.meta.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  widget.meta.icon,
                  size: 16,
                  color: widget.meta.color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: widget.isSelected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    if (p.descripcion != null && p.descripcion!.isNotEmpty)
                      Text(
                        p.descripcion!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.meta.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.meta.code,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: widget.meta.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: Text(
                  p.ownerUser.isNotEmpty ? p.ownerUser : 'Sistema',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ),
              IconButton(
                onPressed: widget.onCopy,
                icon: const Icon(Icons.copy_rounded, size: 13),
                tooltip: 'Copiar código',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
