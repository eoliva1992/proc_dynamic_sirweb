import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/snippet.dart';
import '../../services/snippet_service.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart' show showFloatingDialog;
import 'snippet_editor_window.dart';

/// Abre la estación de trabajo y consulta profesional de snippets de usuario:
/// filtros avanzados, soporte para grandes volúmenes con paginación server-side,
/// vista en cuadrícula y lista detallada, e inspector lateral interactivo.
Future<void> showSnippetsBrowser(BuildContext context) {
  return showFloatingDialog<void>(
    context,
    (dialogContext, close) => SnippetsBrowserDialog(close: close),
  );
}

/// Ámbito de autoría para filtrar snippets
enum SnippetScope { all, mine, team }

/// Ordenamiento de snippets
enum SnippetSort {
  recent('Más recientes', Icons.update_rounded),
  alphabetical('Nombre (A - Z)', Icons.sort_by_alpha_rounded),
  prefix('Prefix / Trigger', Icons.code_rounded);

  final String label;
  final IconData icon;
  const SnippetSort(this.label, this.icon);
}

/// Modo de visualización
enum SnippetViewMode {
  grid('Cuadrícula', Icons.grid_view_rounded),
  list('Lista detallada', Icons.view_agenda_outlined);

  final String label;
  final IconData icon;
  const SnippetViewMode(this.label, this.icon);
}

class SnippetsBrowserDialog extends StatefulWidget {
  final void Function([void]) close;

  const SnippetsBrowserDialog({super.key, required this.close});

  @override
  State<SnippetsBrowserDialog> createState() => SnippetsBrowserDialogState();
}

class SnippetsBrowserDialogState extends State<SnippetsBrowserDialog> {
  String get _currentUser => SnippetService.currentUser;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Snippet> _items = [];
  bool _loading = true;
  String? _error;
  Timer? _searchDebounce;

  SnippetScope _scope = SnippetScope.all;
  String _selectedLanguage = 'all';
  SnippetSort _sort = SnippetSort.recent;
  SnippetViewMode _viewMode = SnippetViewMode.grid;

  // Paginación server-side
  int _page = 1;
  final int _pageSize = 50;
  bool _hasMore = false;

  // Paneles laterales
  bool _sidebarOpen = false;
  static const double _sidebarWidth = 230.0;

  bool _inspectorOpen = true;
  static const double _inspectorWidth = 330.0;
  Snippet? _selectedSnippet;

  static const String _prefKeyViewMode = 'snippets_browser_view_mode';
  static const String _prefKeySort = 'snippets_browser_sort';
  static const String _prefKeyInspectorOpen = 'snippets_browser_inspector_open';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadSnippets();
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
          _viewMode = SnippetViewMode.values.firstWhere(
            (v) => v.name == savedView,
            orElse: () => SnippetViewMode.grid,
          );
        }
        if (savedSort != null) {
          _sort = SnippetSort.values.firstWhere(
            (s) => s.name == savedSort,
            orElse: () => SnippetSort.recent,
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

  Future<void> _loadSnippets({bool resetPage = false}) async {
    if (resetPage) _page = 1;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final queryText = _searchCtrl.text.trim();
      final langParam = _selectedLanguage == 'all' ? null : _selectedLanguage;
      final ownerParam = switch (_scope) {
        SnippetScope.mine => _currentUser,
        _ => null,
      };

      final pageResult = await SnippetService.instance.search(
        ownerUser: ownerParam,
        language: langParam,
        isActive: true,
        query: queryText.isEmpty ? null : queryText,
        top: _pageSize,
        pagina: _page,
      );

      if (!mounted) return;
      setState(() {
        _items = pageResult.items;
        _hasMore = pageResult.tieneSiguiente;
        _loading = false;

        if (_selectedSnippet != null) {
          final matched = _items.where((s) => s.id == _selectedSnippet!.id);
          _selectedSnippet = matched.isNotEmpty
              ? matched.first
              : _items.firstOrNull;
        } else {
          _selectedSnippet = _items.firstOrNull;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadSnippets(resetPage: true);
    });
  }

  List<Snippet> get _filteredAndSortedItems {
    var list = _items.where((s) {
      if (_scope == SnippetScope.team) {
        if (s.ownerUser.toUpperCase() == _currentUser.toUpperCase()) {
          return false;
        }
      }
      return true;
    }).toList();

    switch (_sort) {
      case SnippetSort.recent:
        list.sort((a, b) {
          final timeA = a.updatedAt ?? DateTime(1970);
          final timeB = b.updatedAt ?? DateTime(1970);
          return timeB.compareTo(timeA);
        });
      case SnippetSort.alphabetical:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case SnippetSort.prefix:
        list.sort(
          (a, b) => a.prefix.toLowerCase().compareTo(b.prefix.toLowerCase()),
        );
    }
    return list;
  }

  void _openEditor([Snippet? snippet]) {
    showSnippetEditorWindow(
      context,
      initialSnippet: snippet,
      onSaved: (saved) {
        _loadSnippets();
      },
      onDeleted: () {
        _loadSnippets();
      },
    );
  }

  void _copySnippetCode(Snippet snippet) {
    Clipboard.setData(ClipboardData(text: snippet.body));
    AppToast.success('Cuerpo del snippet copiado al portapapeles');
  }

  Future<void> _duplicateSnippet(Snippet snippet) async {
    final copy = snippet.copyWith(
      id: '',
      name: '${snippet.name} (copia)',
      prefix: '${snippet.prefix}_copia',
      ownerUser: _currentUser,
      modifiedBy: null,
      updatedAt: null,
    );
    _openEditor(copy);
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
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _openEditor(),
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
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divColor, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    children: [
                      _buildHeader(cs, divColor),
                      _buildToolbar(cs, divColor, displayItems.length),
                      if (_error != null) _buildErrorBanner(cs),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _loading
                                  ? const Center(
                                      child: SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : displayItems.isEmpty
                                  ? _buildEmptyState(cs)
                                  : _viewMode == SnippetViewMode.grid
                                  ? _buildGridView(displayItems, cs, divColor)
                                  : _buildListView(displayItems, cs, divColor),
                            ),
                            if (_inspectorOpen && _selectedSnippet != null)
                              Container(width: 0.5, color: divColor),
                            if (_inspectorOpen && _selectedSnippet != null)
                              SizedBox(
                                width: _inspectorWidth,
                                child: _buildInspector(
                                  _selectedSnippet!,
                                  cs,
                                  divColor,
                                  isDark,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _buildFooterPagination(cs, divColor),
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

  Widget _buildHeader(ColorScheme cs, Color divColor) {
    return ConstellationHeader(
      height: 50,
      padding: const EdgeInsets.only(left: 14, right: 10),
      lineColor: cs.primary.withValues(alpha: 0.3),
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
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(Icons.bookmarks_rounded, size: 16, color: cs.primary),
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
                      'Snippets de Usuario',
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
                        'Pág. $_page',
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
                  'Consulta, administración y reutilización de fragmentos de código',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Nuevo snippet', style: TextStyle(fontSize: 12)),
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
                      'Buscar por trigger, nombre, descripción o contenido… (Ctrl+F)',
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
                            _loadSnippets(resetPage: true);
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
                    borderSide: BorderSide(color: cs.primary, width: 1),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Ordenamiento
          MenuAnchor(
            menuChildren: [
              for (final s in SnippetSort.values)
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
          SegmentedButton<SnippetViewMode>(
            segments: const [
              ButtonSegment(
                value: SnippetViewMode.grid,
                icon: Icon(Icons.grid_view_rounded, size: 14),
                tooltip: 'Vista en cuadrícula',
              ),
              ButtonSegment(
                value: SnippetViewMode.list,
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
            Text(
              'FILTROS Y ÁMBITO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
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
              label: 'Todos los snippets',
              icon: Icons.all_inbox_rounded,
              selected: _scope == SnippetScope.all,
              onTap: () {
                setState(() => _scope = SnippetScope.all);
                _loadSnippets(resetPage: true);
              },
            ),
            _buildSidebarOption(
              label: 'Mis snippets',
              icon: Icons.person_rounded,
              selected: _scope == SnippetScope.mine,
              onTap: () {
                setState(() => _scope = SnippetScope.mine);
                _loadSnippets(resetPage: true);
              },
            ),
            _buildSidebarOption(
              label: 'Snippets del equipo',
              icon: Icons.group_outlined,
              selected: _scope == SnippetScope.team,
              onTap: () {
                setState(() => _scope = SnippetScope.team);
                _loadSnippets(resetPage: true);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSidebarCategory(
          title: 'LENGUAJE',
          children: [
            _buildSidebarOption(
              label: 'Todos los lenguajes',
              icon: Icons.layers_outlined,
              selected: _selectedLanguage == 'all',
              onTap: () {
                setState(() => _selectedLanguage = 'all');
                _loadSnippets(resetPage: true);
              },
            ),
            for (final entry in kSnippetLanguages.entries)
              _buildSidebarOption(
                label: entry.value.label,
                icon: entry.value.icon,
                color: entry.value.color,
                selected: _selectedLanguage == entry.key,
                onTap: () {
                  setState(() => _selectedLanguage = entry.key);
                  _loadSnippets(resetPage: true);
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

  Widget _buildGridView(List<Snippet> items, ColorScheme cs, Color divColor) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 170,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final snippet = items[i];
        final isSelected = _selectedSnippet?.id == snippet.id;
        final meta =
            kSnippetLanguages[snippet.language] ?? kSnippetLanguages['any']!;

        return _SnippetGridCard(
          snippet: snippet,
          meta: meta,
          isSelected: isSelected,
          onTap: () => setState(() => _selectedSnippet = snippet),
          onDoubleTap: () => _openEditor(snippet),
          onCopy: () => _copySnippetCode(snippet),
        );
      },
    );
  }

  Widget _buildListView(List<Snippet> items, ColorScheme cs, Color divColor) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        final snippet = items[i];
        final isSelected = _selectedSnippet?.id == snippet.id;
        final meta =
            kSnippetLanguages[snippet.language] ?? kSnippetLanguages['any']!;

        return _SnippetListRow(
          snippet: snippet,
          meta: meta,
          isSelected: isSelected,
          onTap: () => setState(() => _selectedSnippet = snippet),
          onDoubleTap: () => _openEditor(snippet),
          onCopy: () => _copySnippetCode(snippet),
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
              Icons.code_off_rounded,
              size: 38,
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No se encontraron snippets',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Intenta ajustar los filtros de búsqueda o crea uno nuevo.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text(
                'Crear snippet',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspector(
    Snippet snippet,
    ColorScheme cs,
    Color divColor,
    bool isDark,
  ) {
    final meta =
        kSnippetLanguages[snippet.language] ?? kSnippetLanguages['any']!;
    final lines = '\n'.allMatches(snippet.body).length + 1;

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
                Icon(meta.icon, size: 15, color: meta.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    snippet.name.isNotEmpty ? snippet.name : snippet.prefix,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _openEditor(snippet),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  tooltip: 'Abrir en editor Monaco',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  onPressed: () => _duplicateSnippet(snippet),
                  icon: const Icon(Icons.copy_all_rounded, size: 15),
                  tooltip: 'Duplicar snippet',
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
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        snippet.prefix,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: meta.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        meta.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: meta.color,
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
                if (snippet.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    snippet.description,
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
                            'Registrado por: ',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            snippet.ownerUser.isNotEmpty
                                ? snippet.ownerUser
                                : '—',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Consolas',
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                      if ((snippet.modifiedBy != null &&
                              snippet.modifiedBy!.isNotEmpty) ||
                          snippet.updatedAt != null) ...[
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
                              snippet.modifiedBy != null &&
                                      snippet.modifiedBy!.isNotEmpty
                                  ? snippet.modifiedBy!
                                  : snippet.ownerUser,
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
                  'CÓDIGO DEL FRAGMENTO',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _copySnippetCode(snippet),
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
                  snippet.body,
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

  Widget _buildFooterPagination(ColorScheme cs, Color divColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        border: Border(top: BorderSide(color: divColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            '${_items.length} snippets en página',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          IconButton(
            onPressed: (_page > 1 && !_loading)
                ? () {
                    setState(() => _page--);
                    _loadSnippets();
                  }
                : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            tooltip: 'Página anterior',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              'Página $_page',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          IconButton(
            onPressed: (_hasMore && !_loading)
                ? () {
                    setState(() => _page++);
                    _loadSnippets();
                  }
                : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            tooltip: 'Página siguiente',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
            onPressed: () => _loadSnippets(),
            child: const Text('Reintentar', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _SnippetGridCard extends StatefulWidget {
  final Snippet snippet;
  final LangMeta meta;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onCopy;

  const _SnippetGridCard({
    required this.snippet,
    required this.meta,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onCopy,
  });

  @override
  State<_SnippetGridCard> createState() => _SnippetGridCardState();
}

class _SnippetGridCardState extends State<_SnippetGridCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.snippet;

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
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      s.prefix,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.meta.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      widget.meta.icon,
                      size: 12,
                      color: widget.meta.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                s.name.isNotEmpty ? s.name : s.prefix,
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
                    s.body,
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
                  Text(
                    s.ownerUser.isNotEmpty ? s.ownerUser : '—',
                    style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: widget.onCopy,
                    child: Icon(
                      Icons.copy_rounded,
                      size: 11,
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

class _SnippetListRow extends StatefulWidget {
  final Snippet snippet;
  final LangMeta meta;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onCopy;

  const _SnippetListRow({
    required this.snippet,
    required this.meta,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onCopy,
  });

  @override
  State<_SnippetListRow> createState() => _SnippetListRowState();
}

class _SnippetListRowState extends State<_SnippetListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.snippet;

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
                width: 80,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  s.prefix,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name.isNotEmpty ? s.name : s.prefix,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: widget.isSelected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    if (s.description.isNotEmpty)
                      Text(
                        s.description,
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.meta.icon, size: 11, color: widget.meta.color),
                    const SizedBox(width: 4),
                    Text(
                      widget.meta.label,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: widget.meta.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: Text(
                  s.ownerUser.isNotEmpty ? s.ownerUser : '—',
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
