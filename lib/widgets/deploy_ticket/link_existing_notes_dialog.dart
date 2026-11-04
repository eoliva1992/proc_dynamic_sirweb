import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/note.dart';
import '../../services/deploy_ticket_service.dart';
import '../../services/note_service.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart' show showFloatingDialog;
import '../notes/note_colors.dart';

/// Ámbito de filtrado de notas para la vinculación
enum LinkNoteScope { all, mine, shared }

/// Muestra el diálogo modal profesional para vincular notas existentes a un ticket.
///
/// Retorna la lista de identificadores de notas que fueron vinculadas exitosamente.
Future<List<String>?> showLinkExistingNotesDialog(
  BuildContext context, {
  required String ticketId,
  String? ticketDisplayNumber,
  required List<String> alreadyLinkedNoteIds,
  required String activeUser,
}) {
  return showFloatingDialog<List<String>>(
    context,
    (dialogContext, close) => LinkExistingNotesDialog(
      ticketId: ticketId,
      ticketDisplayNumber: ticketDisplayNumber,
      alreadyLinkedNoteIds: alreadyLinkedNoteIds,
      activeUser: activeUser,
      close: close,
    ),
  );
}

class LinkExistingNotesDialog extends StatefulWidget {
  final String ticketId;
  final String? ticketDisplayNumber;
  final List<String> alreadyLinkedNoteIds;
  final String activeUser;
  final void Function([List<String>?]) close;

  const LinkExistingNotesDialog({
    super.key,
    required this.ticketId,
    this.ticketDisplayNumber,
    required this.alreadyLinkedNoteIds,
    required this.activeUser,
    required this.close,
  });

  @override
  State<LinkExistingNotesDialog> createState() =>
      _LinkExistingNotesDialogState();
}

class _LinkExistingNotesDialogState extends State<LinkExistingNotesDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<NoteListItem> _allLoadedItems = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;
  String? _linkingSingleId;

  // Filtros
  LinkNoteScope _scope = LinkNoteScope.all;
  String? _selectedTag;
  String _searchFilter = '';

  // Selección múltiple
  final Set<String> _selectedNoteIds = {};

  // Acumulador de notas exitosamente vinculadas
  final List<String> _newlyLinkedIds = [];

  String get _currentUser => widget.activeUser.trim().isNotEmpty
      ? widget.activeUser.trim()
      : NoteService.currentUser;

  @override
  void initState() {
    super.initState();
    _fetchAvailableNotes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchAvailableNotes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await NoteService.instance.search(
        requestingUser: _currentUser,
        top: 200,
      );

      if (!mounted) return;

      // Filtrar las notas que ya están vinculadas a este ticket
      final alreadyLinked = widget.alreadyLinkedNoteIds.toSet();
      final available = res.items
          .where((item) => !alreadyLinked.contains(item.note.id))
          .toList();

      setState(() {
        _allLoadedItems = available;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Tags disponibles calculados de las notas no vinculadas
  Map<String, int> get _tagCounts {
    final map = <String, int>{};
    for (final item in _allLoadedItems) {
      for (final rawTag in item.note.tags) {
        final t = rawTag.trim();
        if (t.isNotEmpty) {
          map[t] = (map[t] ?? 0) + 1;
        }
      }
    }
    return map;
  }

  int get _countAll => _allLoadedItems.length;

  int get _countMine => _allLoadedItems
      .where(
        (i) =>
            i.accessLevel == NoteAccessLevel.owner ||
            (i.note.ownerUser.isNotEmpty &&
                i.note.ownerUser.toUpperCase() == _currentUser.toUpperCase()),
      )
      .length;

  int get _countShared => _allLoadedItems
      .where(
        (i) =>
            i.accessLevel != NoteAccessLevel.owner &&
            (i.note.ownerUser.isEmpty ||
                i.note.ownerUser.toUpperCase() != _currentUser.toUpperCase()),
      )
      .length;

  List<NoteListItem> get _filteredNotes {
    return _allLoadedItems.where((item) {
      final isMine =
          item.accessLevel == NoteAccessLevel.owner ||
          (item.note.ownerUser.isNotEmpty &&
              item.note.ownerUser.toUpperCase() == _currentUser.toUpperCase());

      // Filtro de ámbito
      if (_scope == LinkNoteScope.mine && !isMine) return false;
      if (_scope == LinkNoteScope.shared && isMine) return false;

      // Filtro de tag
      if (_selectedTag != null) {
        final hasTag = item.note.tags.any(
          (t) => t.trim().toLowerCase() == _selectedTag!.trim().toLowerCase(),
        );
        if (!hasTag) return false;
      }

      // Filtro de búsqueda textual
      if (_searchFilter.isNotEmpty) {
        final q = _searchFilter.toLowerCase();
        final matchTitle = item.note.title.toLowerCase().contains(q);
        final matchContent = item.note.content.toLowerCase().contains(q);
        final matchTags = item.note.tags.any(
          (t) => t.toLowerCase().contains(q),
        );
        if (!matchTitle && !matchContent && !matchTags) return false;
      }

      return true;
    }).toList();
  }

  // --- Acciones de vinculación ---

  Future<void> _linkSingleNote(NoteListItem item) async {
    if (_submitting || _linkingSingleId != null) return;

    final note = item.note;
    final hasOtherTicket =
        note.ticketDespliegueId != null &&
        note.ticketDespliegueId!.isNotEmpty &&
        note.ticketDespliegueId != widget.ticketId;

    if (hasOtherTicket) {
      final confirm = await _showReassignmentWarning(
        context,
        singleTitle: note.title.isEmpty ? 'Sin título' : note.title,
        fromTicketId: note.ticketDespliegueId!,
      );
      if (confirm != true) return;
    }

    setState(() => _linkingSingleId = note.id);

    try {
      await DeployTicketService.instance.asociarNota(
        widget.ticketId,
        note.id,
        usuarioActualiza: _currentUser,
      );

      _newlyLinkedIds.add(note.id);
      AppToast.success(
        'Nota "${note.title.isEmpty ? "Sin título" : note.title}" vinculada exitosamente',
      );
      widget.close(_newlyLinkedIds);
    } catch (e) {
      AppToast.error('Error al vincular nota: $e');
      if (mounted) setState(() => _linkingSingleId = null);
    }
  }

  Future<void> _linkSelectedNotes() async {
    if (_selectedNoteIds.isEmpty || _submitting) return;

    final selectedItems = _allLoadedItems
        .where((i) => _selectedNoteIds.contains(i.note.id))
        .toList();

    // Comprobar si alguna nota ya pertenece a otro ticket
    final notesWithOtherTicket = selectedItems
        .where(
          (i) =>
              i.note.ticketDespliegueId != null &&
              i.note.ticketDespliegueId!.isNotEmpty &&
              i.note.ticketDespliegueId != widget.ticketId,
        )
        .toList();

    if (notesWithOtherTicket.isNotEmpty) {
      final confirm = await _showReassignmentWarning(
        context,
        multipleCount: notesWithOtherTicket.length,
      );
      if (confirm != true) return;
    }

    setState(() => _submitting = true);

    int successCount = 0;
    int errorCount = 0;

    for (final item in selectedItems) {
      try {
        await DeployTicketService.instance.asociarNota(
          widget.ticketId,
          item.note.id,
          usuarioActualiza: _currentUser,
        );
        _newlyLinkedIds.add(item.note.id);
        successCount++;
      } catch (e) {
        errorCount++;
      }
    }

    if (mounted) {
      setState(() => _submitting = false);
    }

    if (successCount > 0) {
      AppToast.success(
        '$successCount nota${successCount > 1 ? "s" : ""} vinculada${successCount > 1 ? "s" : ""} exitosamente',
      );
    }
    if (errorCount > 0) {
      AppToast.warning('No se pudieron vincular $errorCount notas');
    }

    widget.close(_newlyLinkedIds);
  }

  Future<bool?> _showReassignmentWarning(
    BuildContext context, {
    String? singleTitle,
    String? fromTicketId,
    int? multipleCount,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final message = singleTitle != null
        ? 'La nota "$singleTitle" actualmente está vinculada al Ticket #$fromTicketId.\n\nAl vincularla a este ticket, será reasignada automáticamente.'
        : '$multipleCount de las notas seleccionadas ya están asociadas a otros tickets.\n\nAl continuar, se reasignarán automáticamente a esta solicitud de pase.';

    return showFloatingDialog<bool>(
      context,
      (ctx, close) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF26262B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.swap_horiz_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 10),
            Text(
              'Reasignación de Notas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
            height: 1.4,
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
            ),
            onPressed: () => close(true),
            child: const Text('Reasignar y Vincular'),
          ),
        ],
      ),
    );
  }

  void _toggleSelectAll(List<NoteListItem> visibleNotes) {
    setState(() {
      final visibleIds = visibleNotes.map((n) => n.note.id).toSet();
      final allSelected =
          visibleIds.isNotEmpty &&
          visibleIds.every((id) => _selectedNoteIds.contains(id));

      if (allSelected) {
        _selectedNoteIds.removeAll(visibleIds);
      } else {
        _selectedNoteIds.addAll(visibleIds);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final filtered = _filteredNotes;
    final visibleIds = filtered.map((n) => n.note.id).toSet();
    final isAllVisibleSelected =
        visibleIds.isNotEmpty &&
        visibleIds.every((id) => _selectedNoteIds.contains(id));

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 620,
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E22) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.18),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header con constelación y estilo del sistema
              _buildHeader(cs, isDark),

              // Sección de Búsqueda y Filtros
              _buildFiltersSection(cs, isDark),

              // Barra de selección rápida / resumen
              _buildSelectionBar(cs, isDark, filtered, isAllVisibleSelected),

              // Lista de Notas o Estados Vacíos/Carga
              Flexible(child: _buildBody(cs, isDark, filtered)),

              // Footer con acciones Cancelar / Vincular seleccionadas
              _buildFooter(cs, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    final subtitleTicket =
        widget.ticketDisplayNumber != null &&
            widget.ticketDisplayNumber!.trim().isNotEmpty
        ? 'Ticket Solicitud #${widget.ticketDisplayNumber}'
        : 'Ticket ID: ${widget.ticketId}';

    return ConstellationHeader(
      height: 64,
      onDark: true,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary,
            Color.lerp(
              cs.primary,
              isDark ? const Color(0xFF0F172A) : const Color(0xFF003D73),
              0.45,
            )!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.link_rounded,
                size: 22,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Vincular Nota de Trabajo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_allLoadedItems.length} disp.',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleTicket,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              color: Colors.white70,
              tooltip: 'Cerrar (Esc)',
              splashRadius: 18,
              onPressed: () => widget.close(_newlyLinkedIds),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersSection(ColorScheme cs, bool isDark) {
    final tags = _tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222227) : const Color(0xFFF9FAFB),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra de búsqueda con bordes de 10px y botón clear
          TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: 'Buscar notas por título, contenido o etiqueta...',
              hintStyle: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: cs.primary,
              ),
              suffixIcon: _searchFilter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchFilter = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark
                  ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
                  : Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 1.0,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.primary, width: 1.6),
              ),
            ),
            onChanged: (val) => setState(() => _searchFilter = val.trim()),
          ),
          const SizedBox(height: 10),

          // Selector de ámbito (Todas, Mis Notas, Compartidas)
          Row(
            children: [
              _buildScopeTab(
                label: 'Todas',
                count: _countAll,
                scope: LinkNoteScope.all,
                cs: cs,
                isDark: isDark,
              ),
              const SizedBox(width: 6),
              _buildScopeTab(
                label: 'Mis Notas',
                count: _countMine,
                scope: LinkNoteScope.mine,
                cs: cs,
                isDark: isDark,
              ),
              const SizedBox(width: 6),
              _buildScopeTab(
                label: 'Compartidas',
                count: _countShared,
                scope: LinkNoteScope.shared,
                cs: cs,
                isDark: isDark,
              ),
              const Spacer(),
              if (_selectedTag != null) ...[
                ActionChip(
                  avatar: const Icon(Icons.close_rounded, size: 13),
                  label: Text(
                    'Tag: $_selectedTag',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: cs.primary.withValues(alpha: 0.15),
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.35)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _selectedTag = null),
                ),
              ],
            ],
          ),

          // Carrusel de tags si existen
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 24,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tags.length,
                separatorBuilder: (_, _) => const SizedBox(width: 5),
                itemBuilder: (ctx, index) {
                  final entry = tags[index];
                  final isSelected = _selectedTag == entry.key;
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      setState(() {
                        _selectedTag = isSelected ? null : entry.key;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cs.primary
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.05)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? cs.primary
                              : (isDark ? Colors.white10 : Colors.black12),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tag_rounded,
                            size: 11,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white60 : Colors.black54),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${entry.value})',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: isSelected
                                  ? Colors.white70
                                  : (isDark ? Colors.white38 : Colors.black38),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScopeTab({
    required String label,
    required int count,
    required LinkNoteScope scope,
    required ColorScheme cs,
    required bool isDark,
  }) {
    final active = _scope == scope;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _scope = scope),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: isDark ? 0.25 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? cs.primary.withValues(alpha: 0.6)
                : (isDark ? Colors.white10 : Colors.black12),
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: active
                    ? cs.primary
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: active
                    ? cs.primary
                    : (isDark ? Colors.white12 : Colors.black12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: active
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar(
    ColorScheme cs,
    bool isDark,
    List<NoteListItem> filtered,
    bool isAllVisibleSelected,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B1F) : const Color(0xFFF3F4F6),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: filtered.isEmpty ? null : () => _toggleSelectAll(filtered),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: isAllVisibleSelected,
                      onChanged: filtered.isEmpty
                          ? null
                          : (_) => _toggleSelectAll(filtered),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Seleccionar visibles (${filtered.length})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (_selectedNoteIds.isNotEmpty)
            Text(
              '${_selectedNoteIds.length} seleccionada${_selectedNoteIds.length > 1 ? "s" : ""}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, bool isDark, List<NoteListItem> filtered) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              SizedBox(height: 12),
              Text(
                'Cargando notas disponibles...',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
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
                color: Colors.red,
                size: 36,
              ),
              const SizedBox(height: 10),
              Text(
                'No se pudieron cargar las notas',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _error!,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Reintentar'),
                onPressed: _fetchAvailableNotes,
              ),
            ],
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                size: 44,
                color: Colors.grey.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 12),
              Text(
                'No hay notas disponibles para vincular.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _searchFilter.isNotEmpty ||
                        _selectedTag != null ||
                        _scope != LinkNoteScope.all
                    ? 'Intenta relajar los filtros de búsqueda o categoría.'
                    : 'Todas tus notas ya están vinculadas a este pase o no tienes creadas.',
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scrollbar(
      thumbVisibility: true,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (ctx, index) {
          final item = filtered[index];
          return _buildNoteCard(item, cs, isDark);
        },
      ),
    );
  }

  Widget _buildNoteCard(NoteListItem item, ColorScheme cs, bool isDark) {
    final note = item.note;
    final isSelected = _selectedNoteIds.contains(note.id);
    final isSingleLinking = _linkingSingleId == note.id;

    // Color temático Fluent de la nota
    final colorEntry = noteColorEntryFor(
      note.isPersisted ? note.id : note.title,
    );
    final accentColor = colorEntry.header(isDark);

    final hasOtherTicket =
        note.ticketDespliegueId != null &&
        note.ticketDespliegueId!.isNotEmpty &&
        note.ticketDespliegueId != widget.ticketId;

    final snippet = note.content.replaceAll('\n', ' ').trim();

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedNoteIds.remove(note.id);
          } else {
            _selectedNoteIds.add(note.id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: isDark ? 0.16 : 0.08)
              : (isDark ? const Color(0xFF24242A) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? cs.primary
                : (isDark
                      ? Colors.white.withValues(alpha: 0.09)
                      : Colors.black.withValues(alpha: 0.08)),
            width: isSelected ? 1.5 : 0.9,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox de selección múltiple
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedNoteIds.add(note.id);
                      } else {
                        _selectedNoteIds.remove(note.id);
                      }
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Acento vertical de color tipo Sticky Note
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),

            // Contenido central: Título, fragmento, tags, alertas
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.title.trim().isEmpty ? 'Sin título' : note.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (note.ownerUser.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            note.ownerUser.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    snippet.isEmpty ? 'Sin contenido' : snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),

                  // Tags e indicador de reasignación
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (hasOtherTicket)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 11,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Reasignará de Pase #${note.ticketDespliegueId}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (final tag in note.tags.take(3))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4.5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Botón de acción rápida individual (1 clic)
            Tooltip(
              message: 'Vincular esta nota directamente',
              child: isSingleLinking
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.add_link_rounded, size: 20),
                      color: cs.primary,
                      splashRadius: 18,
                      onPressed: () => _linkSingleNote(item),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(ColorScheme cs, bool isDark) {
    final selectedCount = _selectedNoteIds.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222227) : const Color(0xFFF9FAFB),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: () => widget.close(_newlyLinkedIds),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              foregroundColor: isDark ? Colors.white70 : Colors.black87,
              side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Cerrar', style: TextStyle(fontSize: 12.5)),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: (selectedCount == 0 || _submitting)
                ? null
                : _linkSelectedNotes,
            icon: _submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(
              selectedCount > 0
                  ? 'Vincular $selectedCount nota${selectedCount > 1 ? "s" : ""}'
                  : 'Vincular seleccionadas',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
