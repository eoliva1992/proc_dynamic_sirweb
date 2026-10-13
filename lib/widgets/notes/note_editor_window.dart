import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

import '../../models/note.dart';
import '../../services/note_service.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart';
import 'note_block_editor.dart';
import 'note_colors.dart';
import 'share_note_dialog.dart';

/// Opens a single note in its own draggable, minimizable floating window,
/// styled like a classic sticky note (small, colored, no chrome), separate
/// from the read-only notes browser used to find/search notes.
///
/// Several of these windows can be open at the same time.
void showNoteEditorWindow(
  BuildContext context, {
  required NoteListItem item,
  void Function({bool silent})? onSaved,
  VoidCallback? onDeleted,
}) {
  showFloatingWindow(
    context,
    (close) => _NoteEditorWindow(
      initial: item,
      onClose: close,
      onSaved: onSaved,
      onDeleted: onDeleted,
    ),
  );
}

/// Helper para abrir una nota en blanco en una ventana flotante adhesiva
/// desde cualquier parte de la aplicación o atajo de teclado.
void showNewNoteWindow(
  BuildContext context, {
  String? tag,
  void Function({bool silent})? onSaved,
  VoidCallback? onDeleted,
}) {
  final blank = Note(
    id: '',
    title: 'Nueva nota',
    content: '',
    ownerUser: NoteService.currentUser,
    tags: tag != null && tag.isNotEmpty ? [tag] : const [],
  );
  showNoteEditorWindow(
    context,
    item: NoteListItem(note: blank, accessLevel: NoteAccessLevel.owner),
    onSaved: onSaved,
    onDeleted: onDeleted,
  );
}

class _NoteEditorWindow extends StatefulWidget {
  final NoteListItem initial;
  final VoidCallback onClose;
  final void Function({bool silent})? onSaved;
  final VoidCallback? onDeleted;

  const _NoteEditorWindow({
    required this.initial,
    required this.onClose,
    this.onSaved,
    this.onDeleted,
  });

  @override
  State<_NoteEditorWindow> createState() => _NoteEditorWindowState();
}

class _NoteEditorWindowState extends State<_NoteEditorWindow> {
  static const double _kHeaderH = 36;
  static const double _kMinW = 280;
  static const double _kMinH = 260;
  String get _currentUser => NoteService.currentUser;

  late NoteListItem _item;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _tagInputController = TextEditingController();
  final FocusNode _tagInputFocusNode = FocusNode();
  final _editorKey = GlobalKey<NoteBlockEditorState>();
  String _pendingMarkdown = '';
  late List<String> _tags;

  bool _saving = false;
  bool _deleting = false;
  bool _hasUnsavedChanges = false;
  DateTime? _lastSavedAt;
  Timer? _autoSaveTimer;
  late int _colorIndex;
  final MenuController _colorMenuController = MenuController();
  int? _sharesCount;
  bool _loadingShares = false;

  // ── Geometría de la ventana flotante (mover + redimensionar + minimizar/maximizar) ──
  Offset _position = Offset.zero;
  double _winW = 340;
  double _winH = 400;
  bool _minimized = false;
  bool _maximized = false;
  Offset _prevPosition = Offset.zero;
  double _prevW = 340;
  double _prevH = 400;
  int? _slot;
  Duration _anim = Duration.zero;

  @override
  void initState() {
    super.initState();
    NoteService.registerCloser(widget.onClose);
    _item = widget.initial;
    _titleController.text = _item.note.title;
    _tags = List<String>.from(_item.note.tags);
    _pendingMarkdown = _item.note.content;
    _colorIndex = noteColorIndexFor(
      _item.note.isPersisted ? _item.note.id : _item.note.title,
    );
    _loadSharesCount();

    if (!_item.note.isPersisted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _editorKey.currentState?.focus();
      });
    }
  }

  Future<void> _loadSharesCount() async {
    if (!_item.note.isPersisted || !_item.accessLevel.canShare) return;
    setState(() => _loadingShares = true);
    try {
      final shares = await NoteService.instance.listShares(
        _item.note.id,
        ownerUser: _currentUser,
      );
      if (mounted) {
        setState(() {
          _sharesCount = shares.length;
          _loadingShares = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingShares = false);
      }
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    NoteService.unregisterCloser(widget.onClose);
    FloatingWindowSlots.release(_slot);
    _titleController.dispose();
    _tagInputController.dispose();
    _tagInputFocusNode.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (!_item.accessLevel.canEdit) return;
    if (!_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = true);
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _hasUnsavedChanges && !_saving) {
        _save(silent: true);
      }
    });
  }

  void _addTag(String tag) {
    final cleaned = tag.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return;
    if (!_tags.contains(cleaned)) {
      setState(() {
        _tags.add(cleaned);
      });
      _onDataChanged();
    }
    _tagInputController.clear();
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    _onDataChanged();
  }

  void _toggleMinimized() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_minimized) {
        FloatingWindowSlots.release(_slot);
        _slot = null;
        _minimized = false;
      } else {
        if (_maximized) _maximized = false;
        _slot = FloatingWindowSlots.take();
        _minimized = true;
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _toggleMaximized() {
    if (_minimized) return;
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_maximized) {
        _position = _prevPosition;
        _winW = _prevW;
        _winH = _prevH;
        _maximized = false;
      } else {
        _prevPosition = _position;
        _prevW = _winW;
        _prevH = _winH;
        _position = Offset.zero;
        _maximized = true;
      }
    });
  }

  void _newNoteQuick() {
    final blank = Note(
      id: '',
      title: 'Nueva nota',
      content: '',
      ownerUser: _currentUser,
    );
    showNoteEditorWindow(
      context,
      item: NoteListItem(note: blank, accessLevel: NoteAccessLevel.owner),
      onSaved: widget.onSaved,
      onDeleted: widget.onDeleted,
    );
  }

  Future<void> _save({bool silent = false}) async {
    String title = _titleController.text.trim();
    final markdown = _editorKey.currentState?.toMarkdown() ?? _pendingMarkdown;

    // Si el título está vacío, intenta inferir una primera línea inteligente del contenido
    if (title.isEmpty) {
      final lines = markdown
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^[#*\-\s\d\.]+'), '').trim())
          .where((l) => l.isNotEmpty);
      if (lines.isNotEmpty) {
        title = lines.first;
        if (title.length > 40) title = '${title.substring(0, 37)}...';
        _titleController.text = title;
      }
    }

    if (title.isEmpty) {
      if (!silent) {
        AppToast.warning('Ingresá un título o contenido para la nota');
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final toSave = _item.note.copyWith(
        title: title,
        content: markdown,
        tags: _tags,
      );
      final saved = await NoteService.instance.save(
        toSave,
        requestingUser: _currentUser,
      );
      if (!mounted) return;
      setState(() {
        _item = NoteListItem(note: saved, accessLevel: _item.accessLevel);
        _hasUnsavedChanges = false;
        _lastSavedAt = DateTime.now();
      });
      if (!silent) {
        AppToast.success('Nota guardada');
      }
      widget.onSaved?.call(silent: silent);
    } catch (e) {
      if (!silent) {
        AppToast.error('No se pudo guardar: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!_item.note.isPersisted) return;
    final confirmed = await showFloatingDialog<bool>(
      context,
      (ctx, close) => AlertDialog(
        title: const Text('Eliminar nota'),
        content: Text(
          '¿Eliminar "${_item.note.title}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => close(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await NoteService.instance.delete(
        _item.note.id,
        requestingUser: _currentUser,
      );
      AppToast.success('Nota eliminada');
      widget.onDeleted?.call();
      widget.onClose();
    } catch (e) {
      if (mounted) setState(() => _deleting = false);
      AppToast.error('No se pudo eliminar: $e');
    }
  }

  Future<void> _share() async {
    if (!_item.note.isPersisted) return;
    await showShareNoteDialog(
      context,
      note: _item.note,
      currentUser: _currentUser,
    );
    _loadSharesCount();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entry = kNoteColors[_colorIndex];
    final bg = entry.bg(isDark);
    final headerColor = entry.header(isDark);
    final onBg = entry.fg(isDark);
    final screen = MediaQuery.sizeOf(context);
    final access = _item.accessLevel;
    final canEdit = access.canEdit;

    final double w, h, left, top;
    if (_minimized) {
      w = FloatingWindowSlots.barW;
      h = FloatingWindowSlots.barH;
      final (l, t) = FloatingWindowSlots.offsetFor(_slot ?? 0, screen);
      left = l;
      top = t;
    } else if (_maximized) {
      w = (screen.width - 32).clamp(_kMinW, screen.width);
      h = (screen.height - 48).clamp(_kMinH, screen.height);
      left = 16;
      top = 24;
    } else {
      w = _winW.clamp(_kMinW, screen.width);
      h = _winH.clamp(_kMinH, screen.height);
      left = ((screen.width - w) / 2 + _position.dx).clamp(
        0.0,
        (screen.width - w).clamp(0.0, double.infinity),
      );
      top = ((screen.height - h) / 2 + _position.dy).clamp(
        0.0,
        (screen.height - h).clamp(0.0, double.infinity),
      );
    }

    final gripColor = isDark
        ? Colors.white.withValues(alpha: 0.35)
        : Colors.black.withValues(alpha: 0.35);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (canEdit && !_saving) unawaited(_save());
        },
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(
        autofocus: !_minimized,
        canRequestFocus: !_minimized,
        descendantsAreFocusable: !_minimized,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: _anim,
              curve: Curves.easeOutCubic,
              left: left,
              top: top,
              width: w,
              height: h,
              child: Material(
                color: Colors.transparent,
                child: AnimatedContainer(
                  duration: _anim,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(_minimized ? 10 : 12),
                    border: Border.all(color: entry.border(isDark), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.50 : 0.14,
                        ),
                        blurRadius: _minimized ? 14 : 28,
                        offset: Offset(0, _minimized ? 4 : 10),
                      ),
                      if (!_minimized)
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.22 : 0.05,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: Column(
                        children: [
                          _buildHeader(headerColor, onBg, w),
                          if (!_minimized)
                            Expanded(
                              child: _buildBody(canEdit, access, bg, onBg),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Resize handles (Right, Bottom, Bottom-Right corner grip)
            if (!_maximized && !_minimized) ...[
              // Borde derecho
              Positioned(
                left: left + w - 6,
                top: top + _kHeaderH,
                width: 10,
                height: (h - _kHeaderH - 12).clamp(0.0, double.infinity),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW + d.delta.dx).clamp(
                        _kMinW,
                        screen.width - 40,
                      );
                    }),
                  ),
                ),
              ),
              // Borde inferior
              Positioned(
                left: left + 12,
                top: top + h - 6,
                width: (w - 24).clamp(0.0, double.infinity),
                height: 10,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winH = (_winH + d.delta.dy).clamp(
                        _kMinH,
                        screen.height - 40,
                      );
                    }),
                  ),
                ),
              ),
              // Esquina inferior derecha con grip
              Positioned(
                left: left + w - 18,
                top: top + h - 18,
                width: 18,
                height: 18,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW + d.delta.dx).clamp(
                        _kMinW,
                        screen.width - 40,
                      );
                      _winH = (_winH + d.delta.dy).clamp(
                        _kMinH,
                        screen.height - 40,
                      );
                    }),
                    child: CustomPaint(painter: WindowGripPainter(gripColor)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color headerColor, Color onBg, double w) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final starColor = onBg.withValues(alpha: isDark ? 0.45 : 0.28);
    final lineColor = onBg.withValues(alpha: isDark ? 0.25 : 0.16);

    return MouseRegion(
      cursor: (_minimized || _maximized)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _minimized ? _toggleMinimized : _toggleMaximized,
        onPanUpdate: (_minimized || _maximized)
            ? null
            : (d) => setState(() {
                _anim = Duration.zero;
                _position += d.delta;
              }),
        child: ConstellationHeader(
          height: _minimized ? FloatingWindowSlots.barH : _kHeaderH,
          decoration: BoxDecoration(color: headerColor),
          onDark: isDark,
          starColor: starColor,
          lineColor: lineColor,
          density: 1.8,
          scale: 0.65,
          speed: 0.35,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                if (!_minimized) ...[
                  _HeaderIconButton(
                    icon: Icons.add_rounded,
                    color: onBg,
                    tooltip: 'Nueva nota (+)',
                    onTap: _newNoteQuick,
                  ),
                  const SizedBox(width: 2),
                ],
                Expanded(
                  child: Text(
                    _titleController.text.trim().isEmpty
                        ? 'Nota adhesiva'
                        : _titleController.text.trim(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: onBg.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                MenuAnchor(
                  controller: _colorMenuController,
                  alignmentOffset: const Offset(-110, 4),
                  menuChildren: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Color de nota',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 220,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (var i = 0; i < kNoteColors.length; i++)
                                  Tooltip(
                                    message: kNoteColors[i].name,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        _colorMenuController.close();
                                        setState(() => _colorIndex = i);
                                        _onDataChanged();
                                      },
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: kNoteColors[i].lightBg,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: i == _colorIndex
                                                ? Colors.black87
                                                : Colors.black.withValues(
                                                    alpha: 0.15,
                                                  ),
                                            width: i == _colorIndex ? 2.5 : 1,
                                          ),
                                        ),
                                        child: i == _colorIndex
                                            ? const Icon(
                                                Icons.check,
                                                size: 16,
                                                color: Colors.black87,
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  builder: (context, controller, child) => _HeaderIconButton(
                    icon: Icons.palette_outlined,
                    color: onBg,
                    tooltip: 'Color de la nota',
                    onTap: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                  ),
                ),
                _HeaderIconButton(
                  icon: _minimized
                      ? Icons.expand_less_rounded
                      : Icons.remove_rounded,
                  color: onBg,
                  tooltip: _minimized ? 'Restaurar' : 'Minimizar',
                  onTap: _toggleMinimized,
                ),
                if (!_minimized)
                  _HeaderIconButton(
                    icon: _maximized
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: onBg,
                    tooltip: _maximized ? 'Restaurar tamaño' : 'Maximizar',
                    onTap: _toggleMaximized,
                  ),
                _HeaderIconButton(
                  icon: Icons.close_rounded,
                  color: onBg,
                  tooltip: 'Cerrar (Esc)',
                  onTap: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    bool canEdit,
    NoteAccessLevel access,
    Color bg,
    Color onBg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: TextField(
            controller: _titleController,
            enabled: canEdit,
            onChanged: (_) {
              setState(() {});
              _onDataChanged();
            },
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: onBg,
            ),
            cursorColor: onBg,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Título de la nota...',
              hintStyle: TextStyle(
                color: onBg.withValues(alpha: 0.38),
                fontWeight: FontWeight.w500,
                fontSize: 16.5,
                letterSpacing: -0.3,
              ),
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        // Fila de etiquetas (Chips estilo píldora Notion)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tag in _tags)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: onBg.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: onBg.withValues(alpha: 0.14),
                          width: 0.6,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: onBg.withValues(alpha: 0.88),
                            ),
                          ),
                          if (canEdit) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _removeTag(tag),
                              child: Padding(
                                padding: const EdgeInsets.all(1.0),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 11.5,
                                  color: onBg.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (canEdit)
                  Container(
                    height: 23,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: onBg.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: onBg.withValues(alpha: 0.10),
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 12,
                          color: onBg.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 2),
                        SizedBox(
                          width: 62,
                          child: TextField(
                            controller: _tagInputController,
                            focusNode: _tagInputFocusNode,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: onBg.withValues(alpha: 0.85),
                            ),
                            decoration: InputDecoration(
                              hintText: 'etiqueta',
                              hintStyle: TextStyle(
                                fontSize: 10.5,
                                color: onBg.withValues(alpha: 0.40),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: _addTag,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: NoteBlockEditor(
            key: _editorKey,
            initialMarkdown: _pendingMarkdown,
            editable: canEdit,
            autoFocus: !_item.note.isPersisted,
            onEscape: widget.onClose,
            toolbarColor: bg,
            onChanged: (markdown) {
              _pendingMarkdown = markdown;
              _onDataChanged();
            },
          ),
        ),
        // Barra inferior: Estado de sincronización + Acciones contextuales
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: onBg.withValues(alpha: 0.07), width: 0.8),
            ),
          ),
          child: Row(
            children: [
              // Indicador de autoguardado animado / estado
              Expanded(
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _saving
                            ? Colors.amberAccent.shade400
                            : _hasUnsavedChanges
                            ? Colors.orangeAccent
                            : const Color(0xFF10B981),
                        boxShadow: [
                          if (_saving || _hasUnsavedChanges)
                            BoxShadow(
                              color:
                                  (_saving
                                          ? Colors.amberAccent
                                          : Colors.orangeAccent)
                                      .withValues(alpha: 0.45),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                          color: onBg.withValues(alpha: _saving ? 0.9 : 0.65),
                        ),
                        child: Text(
                          _saving
                              ? 'Guardando cambios...'
                              : _hasUnsavedChanges
                              ? 'Cambios pendientes'
                              : _lastSavedAt != null
                              ? 'Guardado a las ${_lastSavedAt!.hour.toString().padLeft(2, '0')}:${_lastSavedAt!.minute.toString().padLeft(2, '0')}'
                              : (_item.note.isPersisted
                                    ? 'Sincronizado'
                                    : 'Borrador local'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (access.canDelete && _item.note.isPersisted)
                _HeaderIconButton(
                  icon: Icons.delete_outline_rounded,
                  color: Colors.redAccent.withValues(alpha: 0.8),
                  tooltip: 'Eliminar nota',
                  onTap: _deleting ? null : _delete,
                ),
              if (access.canShare && _item.note.isPersisted) ...[
                InkWell(
                  onTap: _share,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (_sharesCount ?? 0) > 0
                          ? onBg.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: onBg.withValues(alpha: 0.15),
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (_sharesCount ?? 0) > 0
                              ? Icons.people_alt_rounded
                              : Icons.lock_outline_rounded,
                          size: 13,
                          color: onBg.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        if (_loadingShares)
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation<Color>(onBg),
                            ),
                          )
                        else
                          Text(
                            (_sharesCount ?? 0) > 0
                                ? '$_sharesCount ${(_sharesCount ?? 0) == 1 ? 'persona' : 'personas'}'
                                : 'Privada',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: onBg.withValues(alpha: 0.8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _HeaderIconButton(
                  icon: Icons.share_outlined,
                  color: onBg,
                  tooltip: 'Compartir nota',
                  onTap: _share,
                ),
              ],
              if (canEdit)
                _HeaderIconButton(
                  icon: _saving ? null : Icons.cloud_done_outlined,
                  color: onBg,
                  tooltip: 'Guardar ahora (Ctrl+S)',
                  onTap: _saving ? null : () => _save(silent: false),
                  busy: _saving,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact icon-only button used in the sticky note's header/footer rows.
class _HeaderIconButton extends StatelessWidget {
  final IconData? icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  const _HeaderIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(icon, size: 16, color: color.withValues(alpha: 0.88)),
        ),
      ),
    );
  }
}
