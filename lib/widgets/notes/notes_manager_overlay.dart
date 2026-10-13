import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/code_highlight.dart';
import '../../models/note.dart';
import '../../models/snippet.dart';
import '../../services/backup_service.dart';
import '../../services/note_service.dart';
import '../../services/snippet_service.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart' show showFloatingDialog;
import 'note_colors.dart';
import 'note_editor_window.dart';
import 'share_note_dialog.dart';

/// Abre la estación de trabajo y consulta de notas: interfaz profesional
/// con sidebar de categorías, filtrado dinámico por tags, vista dual (cuadrícula/lista),
/// inspector lateral con previsualización en tiempo real y acciones rápidas.
Future<void> showNotesManager(BuildContext context) {
  return showFloatingDialog<void>(
    context,
    (dialogContext, close) => NotesBrowserDialog(close: close),
  );
}

/// Ámbito de filtrado lateral
enum NotesFilterScope { all, mine, shared }

/// Criterio de ordenamiento
enum NotesSortOption {
  recent('Más recientes', Icons.update_rounded),
  created('Fecha de creación', Icons.schedule_rounded),
  alphabetical('Título (A - Z)', Icons.sort_by_alpha_rounded);

  final String label;
  final IconData icon;
  const NotesSortOption(this.label, this.icon);
}

/// Modo de visualización de notas
enum NotesViewMode {
  grid('Cuadrícula', Icons.grid_view_rounded),
  list('Lista detallada', Icons.view_agenda_outlined);

  final String label;
  final IconData icon;
  const NotesViewMode(this.label, this.icon);
}

class NotesBrowserDialog extends StatefulWidget {
  final void Function([void]) close;

  const NotesBrowserDialog({super.key, required this.close});

  @override
  State<NotesBrowserDialog> createState() => NotesBrowserDialogState();
}

class NotesBrowserDialogState extends State<NotesBrowserDialog> {
  String get _currentUser => NoteService.currentUser;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<NoteListItem> _items = [];
  bool _loading = true;
  String? _error;
  Timer? _searchDebounce;

  NotesFilterScope _scope = NotesFilterScope.all;
  String? _selectedTag;
  String? _selectedColorName;
  NotesSortOption _sortOption = NotesSortOption.recent;
  NotesViewMode _viewMode = NotesViewMode.grid;

  static const String _prefKeyViewMode = 'notes_browser_view_mode';
  static const String _prefKeySortOption = 'notes_browser_sort_option';
  static const String _prefKeyInspectorOpen = 'notes_browser_inspector_open';

  /// Control de apertura del sidebar como Drawer flotante sobrepuesto
  bool _sidebarOpen = false;

  /// Ancho del drawer del sidebar
  static const double _sidebarWidth = 240.0;

  /// Ancho del drawer de vista previa / inspector lateral
  static const double _inspectorWidth = 340.0;

  /// Nota seleccionada para el panel inspector lateral
  NoteListItem? _selectedItem;
  bool _inspectorOpen = true;

  /// Conteo de personas con las que está compartida cada nota
  final Map<String, int> _noteShareCounts = {};

  @override
  void initState() {
    super.initState();
    NoteService.registerCloser(widget.close);
    _loadPreferences();
    _loadNotes();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedView = prefs.getString(_prefKeyViewMode);
      final savedSort = prefs.getString(_prefKeySortOption);
      final savedInspector = prefs.getBool(_prefKeyInspectorOpen);

      if (!mounted) return;
      setState(() {
        if (savedView != null) {
          _viewMode = NotesViewMode.values.firstWhere(
            (v) => v.name == savedView,
            orElse: () => NotesViewMode.grid,
          );
        }
        if (savedSort != null) {
          _sortOption = NotesSortOption.values.firstWhere(
            (s) => s.name == savedSort,
            orElse: () => NotesSortOption.recent,
          );
        }
        if (savedInspector != null) {
          _inspectorOpen = savedInspector;
        }
      });
    } catch (_) {}
  }

  Future<void> _setViewMode(NotesViewMode mode) async {
    setState(() => _viewMode = mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyViewMode, mode.name);
    } catch (_) {}
  }

  Future<void> _setSortOption(NotesSortOption sort) async {
    setState(() => _sortOption = sort);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeySortOption, sort.name);
    } catch (_) {}
  }

  Future<void> _toggleInspector() async {
    final next = !_inspectorOpen;
    setState(() => _inspectorOpen = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyInspectorOpen, next);
    } catch (_) {}
  }

  @override
  void dispose() {
    NoteService.unregisterCloser(widget.close);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadNotes({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await NoteService.instance.search(
        requestingUser: _currentUser,
        query: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
        // Si la nota seleccionada sigue existiendo, sincronizarla con la versión fresca
        if (_selectedItem != null) {
          final updated = _items.where(
            (i) => i.note.id == _selectedItem!.note.id,
          );
          _selectedItem = updated.isNotEmpty ? updated.first : null;
        }
      });
      _loadAllShareCounts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _loadNotes);
  }

  void _clearSearch() {
    _searchController.clear();
    _loadNotes();
  }

  Future<void> _loadAllShareCounts() async {
    for (final item in _items) {
      if (item.accessLevel == NoteAccessLevel.owner && item.note.isPersisted) {
        try {
          final shares = await NoteService.instance.listShares(
            item.note.id,
            ownerUser: _currentUser,
          );
          if (mounted) {
            setState(() {
              _noteShareCounts[item.note.id] = shares.length;
            });
          }
        } catch (_) {}
      }
    }
  }

  // ----------------------------------------------------------- Cálculos / Métricas

  Map<String, int> get _tagCounts {
    final map = <String, int>{};
    for (final item in _items) {
      for (final rawTag in item.note.tags) {
        final t = rawTag.trim();
        if (t.isNotEmpty) {
          map[t] = (map[t] ?? 0) + 1;
        }
      }
    }
    return map;
  }

  int get _countAll => _items.length;
  int get _countMine => _items
      .where(
        (i) =>
            i.accessLevel == NoteAccessLevel.owner ||
            (i.note.ownerUser.isNotEmpty &&
                i.note.ownerUser.toUpperCase() == _currentUser.toUpperCase()),
      )
      .length;
  int get _countShared => _items
      .where(
        (i) =>
            i.accessLevel != NoteAccessLevel.owner &&
            (i.note.ownerUser.isEmpty ||
                i.note.ownerUser.toUpperCase() != _currentUser.toUpperCase()),
      )
      .length;

  List<NoteListItem> get _filteredItems {
    var result = _items.where((item) {
      final isMine =
          item.accessLevel == NoteAccessLevel.owner ||
          (item.note.ownerUser.isNotEmpty &&
              item.note.ownerUser.toUpperCase() == _currentUser.toUpperCase());

      // Filtro de ámbito
      if (_scope == NotesFilterScope.mine && !isMine) return false;
      if (_scope == NotesFilterScope.shared && isMine) return false;

      // Filtro de tag
      if (_selectedTag != null) {
        final hasTag = item.note.tags.any(
          (t) => t.trim().toLowerCase() == _selectedTag!.trim().toLowerCase(),
        );
        if (!hasTag) return false;
      }

      // Filtro de color
      if (_selectedColorName != null) {
        final seed = item.note.isPersisted ? item.note.id : item.note.title;
        final color = noteColorEntryFor(seed);
        if (color.name.toLowerCase() != _selectedColorName!.toLowerCase()) {
          return false;
        }
      }

      return true;
    }).toList();

    // Ordenamiento
    switch (_sortOption) {
      case NotesSortOption.recent:
        result.sort((a, b) {
          final dateA = a.note.updatedAt ?? a.note.createdAt ?? DateTime(1970);
          final dateB = b.note.updatedAt ?? b.note.createdAt ?? DateTime(1970);
          return dateB.compareTo(dateA);
        });
        break;
      case NotesSortOption.created:
        result.sort((a, b) {
          final dateA = a.note.createdAt ?? DateTime(1970);
          final dateB = b.note.createdAt ?? DateTime(1970);
          return dateB.compareTo(dateA);
        });
        break;
      case NotesSortOption.alphabetical:
        result.sort((a, b) {
          return a.note.title.toLowerCase().compareTo(
            b.note.title.toLowerCase(),
          );
        });
        break;
    }

    return result;
  }

  // ----------------------------------------------------------- Acciones de Usuario

  void _openNote(NoteListItem item) {
    showNoteEditorWindow(
      context,
      item: item,
      onSaved: ({bool silent = false}) => _loadNotes(silent: silent),
      onDeleted: () {
        if (_selectedItem?.note.id == item.note.id) {
          setState(() => _selectedItem = null);
        }
        _loadNotes();
      },
    );
  }

  void _newNote() {
    final blank = Note(
      id: '',
      title: 'Nueva nota',
      content: '',
      ownerUser: _currentUser,
      tags: _selectedTag != null ? [_selectedTag!] : const [],
    );
    showNoteEditorWindow(
      context,
      item: NoteListItem(note: blank, accessLevel: NoteAccessLevel.owner),
      onSaved: ({bool silent = false}) => _loadNotes(silent: silent),
    );
  }

  Future<void> _share(NoteListItem item) async {
    await showShareNoteDialog(
      context,
      note: item.note,
      currentUser: _currentUser,
    );
    _loadNotes(silent: true);
    _loadAllShareCounts();
  }

  Future<void> _copyMarkdown(NoteListItem item) async {
    final text = '# ${item.note.title}\n\n${item.note.content}';
    await Clipboard.setData(ClipboardData(text: text));
    AppToast.success('Markdown copiado al portapapeles');
  }

  Future<void> _duplicateNote(NoteListItem item) async {
    final duplicate = Note(
      id: '',
      title: '${item.note.title} (Copia)',
      content: item.note.content,
      tags: List<String>.from(item.note.tags),
      ownerUser: _currentUser,
    );
    showNoteEditorWindow(
      context,
      item: NoteListItem(note: duplicate, accessLevel: NoteAccessLevel.owner),
      onSaved: ({bool silent = false}) => _loadNotes(silent: silent),
    );
    AppToast.info('Nota duplicada lista para guardar');
  }

  Future<void> _deleteNote(NoteListItem item) async {
    final confirmed = await showFloatingDialog<bool>(
      context,
      (ctx, close) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        title: const ConstellationDialogTitle(
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
              SizedBox(width: 8),
              Text('¿Eliminar nota?'),
            ],
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Se eliminará "${item.note.title}". Esta acción no se puede deshacer.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => close(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await NoteService.instance.delete(
        item.note.id,
        requestingUser: _currentUser,
      );
      if (_selectedItem?.note.id == item.note.id) {
        setState(() => _selectedItem = null);
      }
      AppToast.success('Nota eliminada');
      _loadNotes();
    } catch (e) {
      AppToast.error('Error al eliminar: $e');
    }
  }

  Future<void> _showNoteContextMenu(
    BuildContext context,
    Offset globalPosition,
    NoteListItem item,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.open_in_new_rounded, size: 16),
              SizedBox(width: 8),
              Text('Abrir nota'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.content_copy_rounded, size: 16),
              SizedBox(width: 8),
              Text('Duplicar nota'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 16),
              SizedBox(width: 8),
              Text('Copiar Markdown'),
            ],
          ),
        ),
        if (item.accessLevel.canShare)
          const PopupMenuItem<String>(
            value: 'share',
            child: Row(
              children: [
                Icon(Icons.share_outlined, size: 16),
                SizedBox(width: 8),
                Text('Compartir'),
              ],
            ),
          ),
        if (item.accessLevel.canDelete) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: Colors.red.shade400,
                ),
                const SizedBox(width: 8),
                Text(
                  'Eliminar nota',
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (selected == null) return;
    switch (selected) {
      case 'open':
        _openNote(item);
        break;
      case 'duplicate':
        _duplicateNote(item);
        break;
      case 'copy':
        _copyMarkdown(item);
        break;
      case 'share':
        _share(item);
        break;
      case 'delete':
        _deleteNote(item);
        break;
    }
  }

  // ----------------------------------------------------------- Exportación e Integración

  Future<void> _exportNotes() async {
    final itemsToExport = _filteredItems;
    if (itemsToExport.isEmpty) {
      AppToast.warning('No hay notas para exportar con los filtros actuales');
      return;
    }

    final data = itemsToExport
        .map(
          (i) => {
            'id': i.note.id,
            'title': i.note.title,
            'content': i.note.content,
            'tags': i.note.tags,
            'ownerUser': i.note.ownerUser,
            'createdAt': i.note.createdAt?.toIso8601String(),
            'updatedAt': i.note.updatedAt?.toIso8601String(),
            'accessLevel': i.accessLevel.name,
          },
        )
        .toList();

    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

    // Permitir al usuario elegir la ubicación y el archivo en disco
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final defaultFileName =
        'notas_export_${itemsToExport.length}_$timestamp.json';

    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Exportar ${itemsToExport.length} notas a archivo JSON',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (savePath == null) {
      // Usuario canceló el guardado en disco; copiamos al portapapeles como respaldo
      await Clipboard.setData(ClipboardData(text: jsonStr));
      AppToast.info(
        'Exportación cancelada para disco. JSON de ${itemsToExport.length} notas copiado al portapapeles.',
      );
      return;
    }

    try {
      final file = File(savePath);
      await file.writeAsString(jsonStr, flush: true);

      // Copiar también al portapapeles por comodidad
      await Clipboard.setData(ClipboardData(text: jsonStr));

      final fileName = Uri.file(savePath).pathSegments.last;
      AppToast.successWithAction(
        'Exportadas ${itemsToExport.length} notas en: $fileName',
        detail: savePath,
        actionLabel: 'Abrir ubicación',
        onAction: () => unawaited(BackupService.revealInExplorer(savePath)),
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      AppToast.error('Error al guardar archivo de exportación: $e');
    }
  }

  Future<void> _importSnippetAsNote() async {
    setState(() => _loading = true);
    List<Snippet> snippets = [];
    try {
      snippets = await SnippetService.instance.loadAll(ownerUser: _currentUser);
    } catch (e) {
      AppToast.error('No se pudieron cargar snippets: $e');
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = false);

    if (!mounted) return;
    if (snippets.isEmpty) {
      AppToast.info('No hay snippets disponibles para importar');
      return;
    }

    final selectedSnippet = await showFloatingDialog<Snippet>(
      context,
      (ctx, close) => _ImportSnippetDialog(snippets: snippets, close: close),
    );

    if (selectedSnippet == null) return;

    final markdownContent =
        '```${selectedSnippet.language}\n${selectedSnippet.body}\n```\n\n${selectedSnippet.description}';
    final newNote = Note(
      id: '',
      title: selectedSnippet.name,
      content: markdownContent,
      tags: ['snippet', selectedSnippet.language],
      ownerUser: _currentUser,
    );

    showNoteEditorWindow(
      context,
      item: NoteListItem(note: newNote, accessLevel: NoteAccessLevel.owner),
      onSaved: ({bool silent = false}) => _loadNotes(silent: silent),
    );
  }

  // ----------------------------------------------------------- Atajos de Teclado y Navegación

  void _selectNextNote() {
    final list = _filteredItems;
    if (list.isEmpty) return;
    if (_selectedItem == null) {
      setState(() {
        _selectedItem = list.first;
        _inspectorOpen = true;
      });
      return;
    }
    final currentIndex = list.indexWhere(
      (i) => i.note.id == _selectedItem!.note.id,
    );
    if (currentIndex >= 0 && currentIndex < list.length - 1) {
      setState(() {
        _selectedItem = list[currentIndex + 1];
        _inspectorOpen = true;
      });
    }
  }

  void _selectPreviousNote() {
    final list = _filteredItems;
    if (list.isEmpty) return;
    if (_selectedItem == null) {
      setState(() {
        _selectedItem = list.last;
        _inspectorOpen = true;
      });
      return;
    }
    final currentIndex = list.indexWhere(
      (i) => i.note.id == _selectedItem!.note.id,
    );
    if (currentIndex > 0) {
      setState(() {
        _selectedItem = list[currentIndex - 1];
        _inspectorOpen = true;
      });
    }
  }

  // ----------------------------------------------------------- Render Principal

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;

    // Adaptación a pantallas: dimensiones cómodas para el Hub de productividad
    final dialogWidth = (screenSize.width * 0.88).clamp(860.0, 1140.0);
    final dialogHeight = (screenSize.height * 0.84).clamp(580.0, 740.0);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newNote,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
          setState(() => _sidebarOpen = !_sidebarOpen);
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocusNode.requestFocus();
          _searchController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchController.text.length,
          );
        },
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
          if (_selectedItem != null && !_searchFocusNode.hasFocus) {
            _copyMarkdown(_selectedItem!);
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_selectedItem != null && !_searchFocusNode.hasFocus) {
            _openNote(_selectedItem!);
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (!_searchFocusNode.hasFocus) _selectNextNote();
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (!_searchFocusNode.hasFocus) _selectPreviousNote();
        },
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (_selectedItem != null &&
              !_searchFocusNode.hasFocus &&
              _selectedItem!.accessLevel.canDelete) {
            _deleteNote(_selectedItem!);
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_sidebarOpen) {
            setState(() => _sidebarOpen = false);
          } else if (_inspectorOpen && _selectedItem != null) {
            setState(() => _inspectorOpen = false);
          } else if (_searchController.text.isNotEmpty) {
            _clearSearch();
          } else {
            widget.close();
          }
        },
      },
      child: FocusScope(
        autofocus: true,
        child: Dialog(
          backgroundColor: isDark ? const Color(0xFF1B1B1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark ? Colors.white12 : Colors.black12,
              width: 0.5,
            ),
          ),
          elevation: 20,
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Column(
              children: [
                _buildMainHeader(cs, isDark),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      // CAPA BASE: Contenido principal (Toolbar + Cuadrícula/Lista)
                      // Esta capa toma siempre el 100% del ancho del modal y NUNCA se mueve ni salta.
                      Positioned.fill(
                        child: Column(
                          children: [
                            _buildTopToolbar(cs, isDark),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: isDark ? Colors.white10 : Colors.black12,
                            ),
                            Expanded(child: _buildContentArea(isDark)),
                          ],
                        ),
                      ),

                      // CAPA OVERLAY: Telón translúcido (Backdrop barrier)
                      // Si el sidebar izquierdo o el inspector derecho están abiertos,
                      // oscurece el fondo y al hacer clic fuera los cierra con animación fluida.
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring:
                              !_sidebarOpen &&
                              !(_inspectorOpen && _selectedItem != null),
                          child: AnimatedOpacity(
                            opacity:
                                (_sidebarOpen ||
                                    (_inspectorOpen && _selectedItem != null))
                                ? 1.0
                                : 0.0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() {
                                  _sidebarOpen = false;
                                  _inspectorOpen = false;
                                });
                              },
                              child: Container(
                                color: isDark
                                    ? Colors.black.withValues(alpha: 0.55)
                                    : Colors.black.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // CAPA DRAWER IZQUIERDO: Sidebar de navegación y filtros
                      // Se desliza suavemente sobre el contenido desde la izquierda.
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        top: 0,
                        bottom: 0,
                        left: _sidebarOpen ? 0 : -_sidebarWidth,
                        width: _sidebarWidth,
                        child: Material(
                          elevation: 16,
                          shadowColor: Colors.black.withValues(alpha: 0.5),
                          color: isDark
                              ? const Color(0xFF1E1E22)
                              : const Color(0xFFF9FAFC),
                          shape: Border(
                            right: BorderSide(
                              color: isDark ? Colors.white12 : Colors.black12,
                              width: 1,
                            ),
                          ),
                          child: _buildSidebar(cs, isDark),
                        ),
                      ),

                      // CAPA DRAWER DERECHO: Inspector y preview de nota seleccionada
                      // Se desliza suavemente sobre el contenido desde la derecha sin desplazar nada.
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        top: 0,
                        bottom: 0,
                        right: (_inspectorOpen && _selectedItem != null)
                            ? 0
                            : -_inspectorWidth,
                        width: _inspectorWidth,
                        child: Material(
                          elevation: 16,
                          shadowColor: Colors.black.withValues(alpha: 0.5),
                          color: isDark
                              ? const Color(0xFF1E1E22)
                              : const Color(0xFFFBFCFD),
                          shape: Border(
                            left: BorderSide(
                              color: isDark ? Colors.white12 : Colors.black12,
                              width: 1,
                            ),
                          ),
                          child: _selectedItem != null
                              ? _buildInspectorPanel(cs, isDark)
                              : const SizedBox.shrink(),
                        ),
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
  }

  // ----------------------------------------------------------- Header Principal

  Widget _buildMainHeader(ColorScheme cs, bool isDark) {
    return ConstellationHeader(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222226) : const Color(0xFFF8F9FA),
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
        ),
      ),
      onDark: isDark,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Botón toggle del Sidebar Drawer
            Tooltip(
              message: _sidebarOpen
                  ? 'Cerrar navegación (Ctrl+B)'
                  : 'Abrir navegación y filtros (Ctrl+B)',
              child: Material(
                color: _sidebarOpen
                    ? cs.primary.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _sidebarOpen = !_sidebarOpen),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(
                      _sidebarOpen
                          ? Icons.menu_open_rounded
                          : Icons.menu_rounded,
                      size: 20,
                      color: _sidebarOpen
                          ? cs.primary
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.sticky_note_2_rounded,
                size: 20,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Text(
                      'Notas Adhesivas',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: -0.2,
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'PRO HUB',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Gestión colaborativa, filtrado ágil y edición dinámica',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Botón de alternar inspector si hay nota seleccionada
            if (_selectedItem != null)
              IconButton(
                icon: Icon(
                  _inspectorOpen
                      ? Icons.vertical_split_rounded
                      : Icons.vertical_split_outlined,
                  size: 20,
                  color: _inspectorOpen ? cs.primary : null,
                ),
                tooltip: _inspectorOpen
                    ? 'Ocultar panel de vista previa'
                    : 'Mostrar panel de vista previa',
                onPressed: _toggleInspector,
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'Actualizar lista',
              onPressed: _loadNotes,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Cerrar (Esc)',
              onPressed: () => widget.close(),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- Sidebar Lateral

  Widget _buildSidebar(ColorScheme cs, bool isDark) {
    final tags = _tagCounts;

    return Container(
      width: _sidebarWidth,
      color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF9FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera del sidebar con botón para cerrar el drawer
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 4),
            child: Row(
              children: [
                Icon(
                  Icons.explore_outlined,
                  size: 16,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
                const SizedBox(width: 8),
                Text(
                  'NAVEGACIÓN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Ocultar panel (Esc)',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _sidebarOpen = false),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: 20,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: FilledButton.icon(
              onPressed: () {
                _newNote();
                setState(() => _sidebarOpen = false);
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text(
                'Nueva nota',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Secciones de ámbito
          _buildSidebarScopeItem(
            label: 'Todas las notas',
            icon: Icons.notes_rounded,
            count: _countAll,
            scope: NotesFilterScope.all,
            cs: cs,
            isDark: isDark,
          ),
          _buildSidebarScopeItem(
            label: 'Mis notas',
            icon: Icons.person_outline_rounded,
            count: _countMine,
            scope: NotesFilterScope.mine,
            cs: cs,
            isDark: isDark,
          ),
          _buildSidebarScopeItem(
            label: 'Compartidas',
            icon: Icons.people_outline_rounded,
            count: _countShared,
            scope: NotesFilterScope.shared,
            cs: cs,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: isDark ? Colors.white10 : Colors.black12,
          ),
          const SizedBox(height: 10),
          // Sección de Filtro por Color
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  'COLORES',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
                const Spacer(),
                if (_selectedColorName != null)
                  InkWell(
                    onTap: () => setState(() => _selectedColorName = null),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        'Todos',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: kNoteColors.map((nc) {
                final isSelected =
                    _selectedColorName?.toLowerCase() == nc.name.toLowerCase();
                return Tooltip(
                  message: nc.name,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _selectedColorName = isSelected ? null : nc.name;
                      });
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: nc.bg(isDark),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? cs.primary
                              : (isDark ? Colors.white30 : Colors.black26),
                          width: isSelected ? 2.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: cs.primary.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? Center(
                              child: Icon(
                                Icons.check,
                                size: 12,
                                color: nc.fg(isDark),
                              ),
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: isDark ? Colors.white10 : Colors.black12,
          ),
          const SizedBox(height: 10),
          // Sección de Etiquetas
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  'ETIQUETAS',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
                const Spacer(),
                if (_selectedTag != null)
                  InkWell(
                    onTap: () => setState(() => _selectedTag = null),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        'Limpiar',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: tags.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No hay etiquetas definidas aún (#tag).',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white30 : Colors.black38,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    children: tags.entries.map((entry) {
                      final isSelected = _selectedTag == entry.key;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Material(
                          color: isSelected
                              ? cs.primary.withValues(alpha: isDark ? 0.2 : 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () {
                              setState(() {
                                _selectedTag = isSelected ? null : entry.key;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.tag_rounded,
                                    size: 14,
                                    color: isSelected
                                        ? cs.primary
                                        : (isDark
                                              ? Colors.white54
                                              : Colors.black45),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? cs.primary
                                            : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? cs.primary.withValues(alpha: 0.2)
                                          : (isDark
                                                ? Colors.white10
                                                : Colors.black.withValues(
                                                    alpha: 0.05,
                                                  )),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${entry.value}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? cs.primary
                                            : (isDark
                                                  ? Colors.white54
                                                  : Colors.black54),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          // Pie del sidebar con usuario actual
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black12
                  : Colors.black.withValues(alpha: 0.02),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: cs.primary.withValues(alpha: 0.15),
                  child: Text(
                    _currentUser.isNotEmpty ? _currentUser[0] : 'U',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentUser,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarScopeItem({
    required String label,
    required IconData icon,
    required int count,
    required NotesFilterScope scope,
    required ColorScheme cs,
    required bool isDark,
  }) {
    final isSelected = _scope == scope;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: isSelected
            ? cs.primary.withValues(alpha: isDark ? 0.22 : 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () {
            setState(() {
              _scope = scope;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? cs.primary
                      : (isDark ? Colors.white60 : Colors.black54),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? cs.primary
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.87)
                                : Colors.black87),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primary.withValues(alpha: 0.2)
                        : (isDark
                              ? Colors.white10
                              : Colors.black.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? cs.primary
                          : (isDark ? Colors.white54 : Colors.black54),
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

  // ----------------------------------------------------------- Barra de Herramientas

  Widget _buildTopToolbar(ColorScheme cs, bool isDark) {
    final filteredCount = _filteredItems.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: isDark ? const Color(0xFF1B1B1E) : Colors.white,
      child: Row(
        children: [
          // Botón rápido para abrir navegación lateral con badge si hay filtros activos
          Tooltip(
            message: _sidebarOpen
                ? 'Ocultar panel lateral (Ctrl+B)'
                : 'Filtros y etiquetas (Ctrl+B)',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _sidebarOpen = !_sidebarOpen),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color:
                      (_selectedTag != null ||
                          _selectedColorName != null ||
                          _scope != NotesFilterScope.all)
                      ? cs.primary.withValues(alpha: 0.12)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.04)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        (_selectedTag != null ||
                            _selectedColorName != null ||
                            _scope != NotesFilterScope.all)
                        ? cs.primary.withValues(alpha: 0.35)
                        : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_list_rounded,
                      size: 16,
                      color:
                          (_selectedTag != null ||
                              _selectedColorName != null ||
                              _scope != NotesFilterScope.all)
                          ? cs.primary
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _selectedTag != null
                          ? '#$_selectedTag'
                          : (_scope == NotesFilterScope.mine
                                ? 'Mis notas'
                                : (_scope == NotesFilterScope.shared
                                      ? 'Compartidas'
                                      : 'Filtros')),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            (_selectedTag != null ||
                                _selectedColorName != null ||
                                _scope != NotesFilterScope.all)
                            ? cs.primary
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    if (_selectedColorName != null) ...[
                      const SizedBox(width: 4),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: noteColorEntryFor(
                            _selectedColorName!,
                          ).bg(isDark),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Botón directo para crear una nueva nota desde la barra de consulta
          Tooltip(
            message: 'Crear nueva nota adhesiva (Ctrl+N)',
            child: FilledButton.icon(
              onPressed: _newNote,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Nueva nota',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Input de búsqueda
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.1),
                  width: 0.8,
                ),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          tooltip: 'Limpiar búsqueda',
                          onPressed: _clearSearch,
                        )
                      : null,
                  hintText: 'Buscar por título, contenido o etiquetas...',
                  hintStyle: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Conteo sutil
          Text(
            '$filteredCount notas',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          const SizedBox(width: 12),
          // Menú de Ordenamiento (MenuAnchor ancla el popup al widget en el árbol local sin irse a Navigator.push)
          MenuAnchor(
            alignmentOffset: const Offset(0, 4),
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(
                isDark ? const Color(0xFF26262B) : Colors.white,
              ),
              elevation: const WidgetStatePropertyAll(12),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 4),
              ),
            ),
            menuChildren: NotesSortOption.values.map((opt) {
              final isSelected = opt == _sortOption;
              return MenuItemButton(
                onPressed: () => _setSortOption(opt),
                leadingIcon: Icon(
                  opt.icon,
                  size: 16,
                  color: isSelected
                      ? cs.primary
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
                trailingIcon: isSelected
                    ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
                    : null,
                child: Text(
                  opt.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? cs.primary : null,
                  ),
                ),
              );
            }).toList(),
            builder: (context, controller, child) {
              return Tooltip(
                message: 'Ordenar por',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _sortOption.icon,
                          size: 15,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _sortOption.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // Botón Importar Snippet a Nota
          Tooltip(
            message: 'Importar Snippet como Nota',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _importSnippetAsNote,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Icon(
                  Icons.post_add_rounded,
                  size: 16,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Botón Exportar Notas Filtradas
          Tooltip(
            message: 'Exportar notas visibles (JSON)',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _exportNotes,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Icon(
                  Icons.file_download_outlined,
                  size: 16,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Selector de Vista (Grid / List)
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildViewModeButton(
                  mode: NotesViewMode.grid,
                  icon: Icons.grid_view_rounded,
                  tooltip: 'Vista tarjetas',
                  cs: cs,
                  isDark: isDark,
                ),
                _buildViewModeButton(
                  mode: NotesViewMode.list,
                  icon: Icons.view_agenda_outlined,
                  tooltip: 'Vista lista',
                  cs: cs,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeButton({
    required NotesViewMode mode,
    required IconData icon,
    required String tooltip,
    required ColorScheme cs,
    required bool isDark,
  }) {
    final isSelected = _viewMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _setViewMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? Colors.white12 : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected
                ? cs.primary
                : (isDark ? Colors.white54 : Colors.black54),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- Área de Contenido

  Widget _buildContentArea(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: Colors.red,
              ),
              const SizedBox(height: 12),
              Text(
                'Ocurrió un error al cargar las notas:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: _loadNotes,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final items = _filteredItems;

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.04),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _selectedTag != null || _searchController.text.isNotEmpty
                      ? Icons.search_off_rounded
                      : Icons.note_alt_outlined,
                  size: 40,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _selectedTag != null || _searchController.text.isNotEmpty
                    ? 'No hay notas con los filtros actuales'
                    : 'No hay notas todavía',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _selectedTag != null
                    ? 'Filtro por tag "#$_selectedTag" activo.'
                    : 'Crea tu primera nota para empezar a organizar tu trabajo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedTag != null || _searchController.text.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() {
                      _selectedTag = null;
                      _searchController.clear();
                    });
                    _loadNotes();
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: const Text('Limpiar filtros'),
                )
              else
                FilledButton.icon(
                  onPressed: _newNote,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Crear primera nota'),
                ),
            ],
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(
        key: ValueKey<NotesViewMode>(_viewMode),
        child: _viewMode == NotesViewMode.list
            ? _buildListView(items, isDark)
            : _buildGridView(items, isDark),
      ),
    );
  }

  // ----------------------------------------------------------- Vista Cuadrícula

  Widget _buildGridView(List<NoteListItem> items, bool isDark) {
    final showSections = _scope == NotesFilterScope.all;
    final myItems = showSections
        ? items
              .where(
                (i) =>
                    i.accessLevel == NoteAccessLevel.owner ||
                    (i.note.ownerUser.isNotEmpty &&
                        i.note.ownerUser.toUpperCase() ==
                            _currentUser.toUpperCase()),
              )
              .toList()
        : <NoteListItem>[];
    final sharedItems = showSections
        ? items
              .where(
                (i) =>
                    i.accessLevel != NoteAccessLevel.owner &&
                    (i.note.ownerUser.isEmpty ||
                        i.note.ownerUser.toUpperCase() !=
                            _currentUser.toUpperCase()),
              )
              .toList()
        : <NoteListItem>[];

    if (showSections && myItems.isNotEmpty && sharedItems.isNotEmpty) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildSectionHeader(
              title: 'Mis Notas',
              count: myItems.length,
              icon: Icons.person_outline_rounded,
              isDark: isDark,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 200,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildGridCard(myItems[index], isDark),
                childCount: myItems.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _buildSectionHeader(
                title: 'Compartidas Conmigo',
                count: sharedItems.length,
                icon: Icons.people_outline_rounded,
                isDark: isDark,
                withDivider: true,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 200,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildGridCard(sharedItems[index], isDark),
                childCount: sharedItems.length,
              ),
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(18),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 200,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildGridCard(items[index], isDark),
    );
  }

  Widget _buildGridCard(NoteListItem item, bool isDark) {
    final isSelected = _selectedItem?.note.id == item.note.id;
    final seed = item.note.isPersisted ? item.note.id : item.note.title;
    final entry = noteColorEntryFor(seed);
    final bg = entry.bg(isDark);
    final headerBg = entry.header(isDark);
    final fg = entry.fg(isDark);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      elevation: isSelected ? 4 : (isDark ? 2 : 1),
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _selectedItem = item;
            _inspectorOpen = true;
          });
        },
        onDoubleTap: () => _openNote(item),
        onSecondaryTapUp: (details) =>
            _showNoteContextMenu(context, details.globalPosition, item),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : entry.border(isDark),
              width: isSelected ? 2 : 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header de la tarjeta con acento de color
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                decoration: BoxDecoration(
                  color: headerBg,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(9),
                    topRight: Radius.circular(9),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.note.title.trim().isEmpty
                            ? 'Sin título'
                            : item.note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: fg,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    _buildAccessBadge(item.accessLevel, fg),
                  ],
                ),
              ),
              // Extracto del contenido
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                  child: Text(
                    _plainSnippet(item.note.content),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: fg.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ),
              // Pie con etiquetas y fecha
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: item.note.tags.isNotEmpty
                          ? Text(
                              item.note.tags.map((t) => '#$t').join(' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: fg.withValues(alpha: 0.65),
                              ),
                            )
                          : Text(
                              _formatDate(
                                item.note.updatedAt ?? item.note.createdAt,
                              ),
                              style: TextStyle(
                                fontSize: 9.5,
                                color: fg.withValues(alpha: 0.5),
                              ),
                            ),
                    ),
                    if (item.accessLevel == NoteAccessLevel.owner &&
                        _noteShareCounts.containsKey(item.note.id)) ...[
                      Tooltip(
                        message: _noteShareCounts[item.note.id] == 0
                            ? 'Nota privada'
                            : 'Compartida con ${_noteShareCounts[item.note.id]} personas',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => _share(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.group_outlined,
                                  size: 12,
                                  color: fg.withValues(alpha: 0.7),
                                ),
                                if ((_noteShareCounts[item.note.id] ?? 0) >
                                    0) ...[
                                  const SizedBox(width: 2),
                                  Text(
                                    '${_noteShareCounts[item.note.id]}',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: fg.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    // Botón de abrir en ventana rápida
                    Tooltip(
                      message: 'Abrir ventana flotante',
                      child: InkWell(
                        onTap: () => _openNote(item),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.open_in_new_rounded,
                            size: 14,
                            color: fg.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                    if (item.accessLevel.canDelete) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Eliminar nota',
                        child: InkWell(
                          onTap: () => _deleteNote(item),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 14,
                              color: Colors.red.shade400.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required int count,
    required IconData icon,
    required bool isDark,
    bool withDivider = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (withDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Divider(
              height: 1,
              color: isDark ? Colors.white12 : Colors.black12,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
          child: Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.90)
                      : Colors.black87,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------- Vista Lista Detallada

  Widget _buildListView(List<NoteListItem> items, bool isDark) {
    final showSections = _scope == NotesFilterScope.all;
    final myItems = showSections
        ? items
              .where(
                (i) =>
                    i.accessLevel == NoteAccessLevel.owner ||
                    (i.note.ownerUser.isNotEmpty &&
                        i.note.ownerUser.toUpperCase() ==
                            _currentUser.toUpperCase()),
              )
              .toList()
        : <NoteListItem>[];
    final sharedItems = showSections
        ? items
              .where(
                (i) =>
                    i.accessLevel != NoteAccessLevel.owner &&
                    (i.note.ownerUser.isEmpty ||
                        i.note.ownerUser.toUpperCase() !=
                            _currentUser.toUpperCase()),
              )
              .toList()
        : <NoteListItem>[];

    if (showSections && myItems.isNotEmpty && sharedItems.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildSectionHeader(
            title: 'Mis Notas',
            count: myItems.length,
            icon: Icons.person_outline_rounded,
            isDark: isDark,
          ),
          const SizedBox(height: 4),
          for (final item in myItems) ...[
            _buildListTile(item, isDark),
            Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
          ],
          const SizedBox(height: 12),
          _buildSectionHeader(
            title: 'Compartidas Conmigo',
            count: sharedItems.length,
            icon: Icons.people_outline_rounded,
            isDark: isDark,
            withDivider: true,
          ),
          const SizedBox(height: 4),
          for (final item in sharedItems) ...[
            _buildListTile(item, isDark),
            Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
          ],
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
      itemBuilder: (context, index) => _buildListTile(items[index], isDark),
    );
  }

  Widget _buildListTile(NoteListItem item, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedItem?.note.id == item.note.id;
    final seed = item.note.isPersisted ? item.note.id : item.note.title;
    final entry = noteColorEntryFor(seed);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primary.withValues(alpha: isDark ? 0.16 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isSelected ? cs.primary : Colors.transparent,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _selectedItem = item;
              _inspectorOpen = true;
            });
          },
          onDoubleTap: () => _openNote(item),
          onSecondaryTapUp: (details) =>
              _showNoteContextMenu(context, details.globalPosition, item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Pastilla de color
                Container(
                  width: 10,
                  height: 38,
                  decoration: BoxDecoration(
                    color: entry.bg(isDark),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: entry.border(isDark), width: 0.8),
                  ),
                ),
                const SizedBox(width: 12),
                // Título y preview
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.note.title.trim().isEmpty
                            ? 'Sin título'
                            : item.note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? cs.primary : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _plainSnippet(item.note.content),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Tags en chips
                Expanded(
                  flex: 2,
                  child: item.note.tags.isNotEmpty
                      ? Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: item.note.tags.take(3).map((t) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#$t',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                            );
                          }).toList(),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 10),
                // Permiso / Autor y Compartidos
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.accessLevel == NoteAccessLevel.owner
                            ? 'Mía'
                            : (item.accessLevel == NoteAccessLevel.edit
                                  ? 'Edición'
                                  : 'Lectura'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                    if (item.accessLevel == NoteAccessLevel.owner &&
                        _noteShareCounts.containsKey(item.note.id)) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _share(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.group_outlined,
                                size: 13,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _noteShareCounts[item.note.id] == 0
                                    ? 'Privada'
                                    : '${_noteShareCounts[item.note.id]} pers.',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 12),
                // Fecha
                Text(
                  _formatDate(item.note.updatedAt ?? item.note.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(width: 8),
                // Botón flotante
                IconButton(
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  tooltip: 'Abrir ventana flotante',
                  onPressed: () => _openNote(item),
                ),
                if (item.accessLevel.canDelete)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: Colors.red.shade400,
                    ),
                    tooltip: 'Eliminar nota',
                    onPressed: () => _deleteNote(item),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- Inspector Lateral

  Widget _buildInspectorPanel(ColorScheme cs, bool isDark) {
    final item = _selectedItem!;
    final seed = item.note.isPersisted ? item.note.id : item.note.title;
    final entry = noteColorEntryFor(seed);

    return Container(
      width: _inspectorWidth,
      color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFFBFCFD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header del inspector con color de la nota
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: entry.header(isDark),
              border: Border(bottom: BorderSide(color: entry.border(isDark))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.note.title.trim().isEmpty
                            ? 'Sin título'
                            : item.note.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: entry.fg(isDark),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _buildAccessBadge(item.accessLevel, entry.fg(isDark)),
                          const SizedBox(width: 6),
                          Text(
                            item.note.ownerUser.isNotEmpty
                                ? 'Por: ${item.note.ownerUser}'
                                : 'Autor desconocido',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: entry.fg(isDark).withValues(alpha: 0.7),
                            ),
                          ),
                          if (item.accessLevel == NoteAccessLevel.owner) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => _share(item),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.group_outlined,
                                      size: 13,
                                      color: entry
                                          .fg(isDark)
                                          .withValues(alpha: 0.75),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      _noteShareCounts.containsKey(item.note.id)
                                          ? (_noteShareCounts[item.note.id] == 0
                                                ? 'Privada'
                                                : '${_noteShareCounts[item.note.id]} pers.')
                                          : '...',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: entry
                                            .fg(isDark)
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Cerrar panel',
                  onPressed: () => setState(() => _inspectorOpen = false),
                ),
              ],
            ),
          ),
          // Fechas y metadatos
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                const SizedBox(width: 6),
                Text(
                  'Modificada: ${_formatDate(item.note.updatedAt ?? item.note.createdAt)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          // Tags
          if (item.note.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: item.note.tags.map((t) {
                  final isTagFiltered = _selectedTag == t;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _selectedTag = isTagFiltered ? null : t;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: isTagFiltered
                            ? cs.primary.withValues(alpha: 0.2)
                            : (isDark
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.05)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isTagFiltered
                              ? cs.primary
                              : (isDark ? Colors.white12 : Colors.black12),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '#$t',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isTagFiltered
                              ? cs.primary
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          Divider(height: 16, color: isDark ? Colors.white10 : Colors.black12),
          // Preview enriquecido del contenido (con resaltado de código y bloques)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildRichMarkdownPreview(item.note.content, isDark),
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
          // Barra de acciones rápidas al pie del inspector
          Container(
            padding: const EdgeInsets.all(10),
            color: isDark ? const Color(0xFF1B1B1E) : const Color(0xFFF1F3F5),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openNote(item),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text(
                          'Abrir editor',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildQuickActionBtn(
                      icon: Icons.copy_rounded,
                      tooltip: 'Copiar Markdown',
                      onPressed: () => _copyMarkdown(item),
                      isDark: isDark,
                    ),
                    _buildQuickActionBtn(
                      icon: Icons.content_copy_rounded,
                      tooltip: 'Duplicar nota',
                      onPressed: () => _duplicateNote(item),
                      isDark: isDark,
                    ),
                    if (item.accessLevel.canShare)
                      _buildQuickActionBtn(
                        icon: Icons.share_outlined,
                        tooltip: 'Compartir nota',
                        onPressed: () => _share(item),
                        isDark: isDark,
                      ),
                    if (item.accessLevel.canDelete)
                      _buildQuickActionBtn(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Eliminar nota',
                        color: Colors.red.shade400,
                        onPressed: () => _deleteNote(item),
                        isDark: isDark,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required bool isDark,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 17,
              color: color ?? (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- Helpers

  Widget _buildAccessBadge(NoteAccessLevel level, Color fg) {
    if (level == NoteAccessLevel.owner) {
      return Icon(
        Icons.verified_user_rounded,
        size: 13,
        color: fg.withValues(alpha: 0.6),
      );
    }
    if (level == NoteAccessLevel.edit) {
      return Icon(
        Icons.edit_note_rounded,
        size: 15,
        color: fg.withValues(alpha: 0.7),
      );
    }
    return Icon(
      Icons.visibility_outlined,
      size: 13,
      color: fg.withValues(alpha: 0.6),
    );
  }

  String _plainSnippet(String markdown) {
    return markdown
        .replaceAll(RegExp(r'[#*`_>-]'), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Hace un momento';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes}m';
    if (diff.inDays < 1) return 'Hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays}d';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  // ----------------------------------------------------------- Markdown Enriquecido

  Widget _buildRichMarkdownPreview(String rawContent, bool isDark) {
    if (rawContent.trim().isEmpty) {
      return Text(
        '(Nota vacía)',
        style: TextStyle(
          fontSize: 12.5,
          fontStyle: FontStyle.italic,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      );
    }

    final lines = rawContent.split('\n');
    final widgets = <Widget>[];
    bool inCodeBlock = false;
    String codeBlockLang = '';
    final codeBuffer = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Bloque de código ```
      if (line.trim().startsWith('```')) {
        if (!inCodeBlock) {
          inCodeBlock = true;
          codeBlockLang = line.trim().substring(3).trim();
          codeBuffer.clear();
        } else {
          // Terminar bloque de código
          inCodeBlock = false;
          final codeText = codeBuffer.toString().trimRight();
          final spans = highlightCode(
            codeText,
            codeBlockLang.isNotEmpty ? codeBlockLang : 'sql',
            isDark: isDark,
          );
          widgets.add(
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF141416)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 0.8,
                ),
              ),
              child: SelectableText.rich(
                TextSpan(children: spans),
                style: const TextStyle(
                  fontFamily: 'Cascadia Code, Consolas, monospace',
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
          );
        }
        continue;
      }

      if (inCodeBlock) {
        codeBuffer.writeln(line);
        continue;
      }

      final trimmed = line.trim();

      // Checklists: - [ ] o - [x]
      if (trimmed.startsWith('- [ ]') || trimmed.startsWith('- [x]')) {
        final isChecked = trimmed.startsWith('- [x]');
        final text = trimmed.substring(5).trim();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isChecked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 16,
                  color: isChecked
                      ? Theme.of(context).colorScheme.primary
                      : (isDark ? Colors.white54 : Colors.black45),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      decoration: isChecked ? TextDecoration.lineThrough : null,
                      color: isChecked
                          ? (isDark ? Colors.white38 : Colors.black38)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.87)
                                : Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Títulos Markdown
      if (trimmed.startsWith('# ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              trimmed.substring(2).trim(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        );
        continue;
      }

      if (trimmed.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 3),
            child: Text(
              trimmed.substring(3).trim(),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        );
        continue;
      }

      // Citas / Blockquotes
      if (trimmed.startsWith('> ')) {
        widgets.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
              ),
            ),
            child: Text(
              trimmed.substring(2).trim(),
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
        );
        continue;
      }

      // Párrafo normal o línea en blanco
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: SelectableText(
              line,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        );
      }
    }

    // Si quedó un bloque de código abierto sin cerrar
    if (inCodeBlock && codeBuffer.isNotEmpty) {
      final codeText = codeBuffer.toString().trimRight();
      final spans = highlightCode(
        codeText,
        codeBlockLang.isNotEmpty ? codeBlockLang : 'sql',
        isDark: isDark,
      );
      widgets.add(
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141416) : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
              width: 0.8,
            ),
          ),
          child: SelectableText.rich(
            TextSpan(children: spans),
            style: const TextStyle(
              fontFamily: 'Cascadia Code, Consolas, monospace',
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }
}

/// Diálogo modal estilizado para seleccionar e importar un Snippet a una Nota adhesiva.
///
/// Utiliza la estética corporativa de la aplicación:
/// - Cabecera con constelación interactiva [ConstellationDialogTitle].
/// - Buscador instantáneo con atajo y botón de limpieza.
/// - Badges de lenguaje (SQL, JS, Cualquier) acordes al tema.
/// - Previsualización limpia del cuerpo o descripción del snippet.
class _ImportSnippetDialog extends StatefulWidget {
  final List<Snippet> snippets;
  final void Function([Snippet? result]) close;

  const _ImportSnippetDialog({required this.snippets, required this.close});

  @override
  State<_ImportSnippetDialog> createState() => _ImportSnippetDialogState();
}

class _ImportSnippetDialogState extends State<_ImportSnippetDialog> {
  final TextEditingController _filterController = TextEditingController();
  final FocusNode _filterFocusNode = FocusNode();
  String _filterText = '';

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      setState(() {
        _filterText = _filterController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    _filterFocusNode.dispose();
    super.dispose();
  }

  List<Snippet> get _filteredSnippets {
    if (_filterText.isEmpty) return widget.snippets;
    return widget.snippets.where((s) {
      final name = s.name.toLowerCase();
      final prefix = s.prefix.toLowerCase();
      final desc = s.description.toLowerCase();
      final body = s.body.toLowerCase();
      final lang = s.language.toLowerCase();
      return name.contains(_filterText) ||
          prefix.contains(_filterText) ||
          desc.contains(_filterText) ||
          body.contains(_filterText) ||
          lang.contains(_filterText);
    }).toList();
  }

  Color _badgeColorFor(String lang, ColorScheme cs) {
    switch (lang.toLowerCase()) {
      case 'sql':
        return const Color(0xFF0078D4);
      case 'javascript':
      case 'js':
        return const Color(0xFFD9A407);
      default:
        return cs.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredSnippets;

    return Center(
      child: Material(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        elevation: 24,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 520,
          constraints: const BoxConstraints(maxHeight: 520),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabecera con constelación y estilo de la aplicación
              ConstellationDialogTitle(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.code_rounded,
                        size: 18,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Importar Snippet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Selecciona un fragmento para convertirlo en Nota Adhesiva',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.normal,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Cerrar (Esc)',
                      onPressed: () => widget.close(null),
                    ),
                  ],
                ),
              ),

              // Buscador de snippets
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _filterController,
                  focusNode: _filterFocusNode,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, prefijo o sintaxis...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36),
                    suffixIcon: _filterText.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () => _filterController.clear(),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF6F8FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: cs.primary, width: 1.5),
                    ),
                  ),
                ),
              ),

              // Lista de snippets filtrados
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 36,
                                color: isDark ? Colors.white24 : Colors.black26,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No se encontraron snippets',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, idx) {
                          final snippet = filtered[idx];
                          final badgeColor = _badgeColorFor(
                            snippet.language,
                            cs,
                          );

                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => widget.close(snippet),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.03)
                                    : const Color(0xFFF9FAFB),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.07)
                                      : Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      snippet.language.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: badgeColor,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                snippet.name,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (snippet.prefix.isNotEmpty)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? Colors.white12
                                                      : Colors.black.withValues(
                                                          alpha: 0.06,
                                                        ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  snippet.prefix,
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontFamily: 'Consolas',
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          snippet.description.isNotEmpty
                                              ? snippet.description
                                              : snippet.body.replaceAll(
                                                  '\n',
                                                  ' ',
                                                ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: isDark
                                                ? Colors.white54
                                                : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 12,
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.black26,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Barra inferior de acciones
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black12,
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${filtered.length} snippet${filtered.length == 1 ? '' : 's'} disponible${filtered.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                      onPressed: () => widget.close(null),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
