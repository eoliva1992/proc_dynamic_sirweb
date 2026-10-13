import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import '../../models/note_markdown_codec.dart';

const _kTodoListItemId = 'editor.todo_list';

/// Alterna una selección de uno o múltiples bloques a lista numerada con orden secuencial (1, 2, 3...).
/// Si todos los bloques en la selección ya son listas numeradas, se revierten a párrafos estándar.
void toggleNumberedListForSelection(
  EditorState editorState, [
  Selection? targetSelection,
]) {
  var selection = targetSelection ?? editorState.selection;
  if (selection == null) {
    final first = editorState.document.first;
    if (first == null) return;
    selection = Selection.collapsed(Position(path: first.path, offset: 0));
  }
  selection = selection.normalized;

  final nodes = editorState.getNodesInSelection(selection);
  if (nodes.isEmpty) return;

  final allNumbered = nodes.every((n) => n.type == NumberedListBlockKeys.type);
  final transaction = editorState.transaction;

  if (allNumbered) {
    // Revertir a párrafos
    for (final node in nodes) {
      final delta = node.delta ?? Delta();
      final newNode = paragraphNode(
        delta: delta,
        attributes: {blockComponentDelta: delta.toJson()},
      );
      transaction
        ..insertNode(node.path, newNode)
        ..deleteNode(node);
    }
  } else {
    // Convertir a lista numerada con orden secuencial estricto 1, 2, 3...
    int seq = 1;
    for (final node in nodes) {
      final delta = node.delta ?? Delta();
      final newNode = Node(
        type: NumberedListBlockKeys.type,
        attributes: {
          blockComponentDelta: delta.toJson(),
          NumberedListBlockKeys.number: seq,
        },
      );
      transaction
        ..insertNode(node.path, newNode)
        ..deleteNode(node);
      seq++;
    }
  }

  transaction.afterSelection = selection;
  editorState.apply(transaction);
}

/// Alterna una selección de bloques a lista con viñetas.
void toggleBulletedListForSelection(
  EditorState editorState, [
  Selection? targetSelection,
]) {
  var selection = targetSelection ?? editorState.selection;
  if (selection == null) {
    final first = editorState.document.first;
    if (first == null) return;
    selection = Selection.collapsed(Position(path: first.path, offset: 0));
  }
  selection = selection.normalized;

  final nodes = editorState.getNodesInSelection(selection);
  if (nodes.isEmpty) return;

  final allBulleted = nodes.every((n) => n.type == BulletedListBlockKeys.type);
  final transaction = editorState.transaction;

  for (final node in nodes) {
    final delta = node.delta ?? Delta();
    final newNode = allBulleted
        ? paragraphNode(
            delta: delta,
            attributes: {blockComponentDelta: delta.toJson()},
          )
        : bulletedListNode(
            delta: delta,
            attributes: {blockComponentDelta: delta.toJson()},
          );
    transaction
      ..insertNode(node.path, newNode)
      ..deleteNode(node);
  }

  transaction.afterSelection = selection;
  editorState.apply(transaction);
}

/// Alterna una selección de bloques a checklist de tareas.
void toggleTodoListForSelection(
  EditorState editorState, [
  Selection? targetSelection,
]) {
  var selection = targetSelection ?? editorState.selection;
  if (selection == null) {
    final first = editorState.document.first;
    if (first == null) return;
    selection = Selection.collapsed(Position(path: first.path, offset: 0));
  }
  selection = selection.normalized;

  final nodes = editorState.getNodesInSelection(selection);
  if (nodes.isEmpty) return;

  final allTodo = nodes.every((n) => n.type == TodoListBlockKeys.type);
  final transaction = editorState.transaction;

  for (final node in nodes) {
    final delta = node.delta ?? Delta();
    final newNode = allTodo
        ? paragraphNode(
            delta: delta,
            attributes: {blockComponentDelta: delta.toJson()},
          )
        : Node(
            type: TodoListBlockKeys.type,
            attributes: {
              blockComponentDelta: delta.toJson(),
              TodoListBlockKeys.checked: false,
            },
          );
    transaction
      ..insertNode(node.path, newNode)
      ..deleteNode(node);
  }

  transaction.afterSelection = selection;
  editorState.apply(transaction);
}

/// Toolbar item to convert current block to/from a checklist item (with interactive checkbox).
final ToolbarItem todoListItem = ToolbarItem(
  id: _kTodoListItemId,
  group: 3,
  isActive: onlyShowInTextType,
  builder: (context, editorState, highlightColor, iconColor, tooltipBuilder) {
    final selection = editorState.selection!;
    final node = editorState.getNodeAtPath(selection.start.path)!;
    final isHighlight = node.type == TodoListBlockKeys.type;
    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: IconButton(
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        padding: EdgeInsets.zero,
        iconSize: 18,
        tooltip: 'Lista de tareas (checklist)',
        icon: Icon(
          isHighlight
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          size: 18,
          color: isHighlight ? highlightColor : iconColor,
        ),
        onPressed: () => toggleTodoListForSelection(editorState, selection),
      ),
    );

    if (tooltipBuilder != null) {
      return tooltipBuilder(
        context,
        _kTodoListItemId,
        'Lista de tareas (checklist)',
        child,
      );
    }

    return child;
  },
);

/// Toolbar item mejorado para lista numerada con ordenación secuencial
final ToolbarItem proNumberedListItem = ToolbarItem(
  id: 'editor.pro_numbered_list',
  group: 3,
  isActive: onlyShowInTextType,
  builder: (context, editorState, highlightColor, iconColor, tooltipBuilder) {
    final selection = editorState.selection!;
    final node = editorState.getNodeAtPath(selection.start.path)!;
    final isHighlight = node.type == NumberedListBlockKeys.type;
    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: IconButton(
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        padding: EdgeInsets.zero,
        iconSize: 18,
        tooltip: 'Lista numerada (1, 2, 3...)',
        icon: Icon(
          Icons.format_list_numbered_rounded,
          size: 18,
          color: isHighlight ? highlightColor : iconColor,
        ),
        onPressed: () => toggleNumberedListForSelection(editorState, selection),
      ),
    );

    if (tooltipBuilder != null) {
      return tooltipBuilder(
        context,
        'editor.pro_numbered_list',
        'Lista numerada',
        child,
      );
    }

    return child;
  },
);

/// Visual block editor for a [Note]'s content.
///
/// Features:
/// - Continuous regular line heights and block spacings (eliminates irregular gaps)
/// - Pro sequential numbered lists formatting across multiple lines
/// - Floating bubble toolbar on selection with sleek Fluent design
/// - Compact quick-formatting bar for frictionless workflow
class NoteBlockEditor extends StatefulWidget {
  final String initialMarkdown;
  final bool editable;

  /// Debounced callback invoked with the serialized markdown whenever the
  /// document changes.
  final ValueChanged<String>? onChanged;

  /// Tint used for the background and accents.
  final Color? toolbarColor;

  /// Si es true, enfoca automáticamente el editor en el contenido al inicializarse.
  final bool autoFocus;

  /// Callback opcional invocado al presionar la tecla Escape.
  final VoidCallback? onEscape;

  const NoteBlockEditor({
    super.key,
    required this.initialMarkdown,
    this.editable = true,
    this.autoFocus = false,
    this.onEscape,
    this.onChanged,
    this.toolbarColor,
  });

  @override
  State<NoteBlockEditor> createState() => NoteBlockEditorState();
}

class NoteBlockEditorState extends State<NoteBlockEditor> {
  late EditorState _editorState;
  late EditorScrollController _scrollController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _editorState = EditorState(
      document: noteMarkdownToDocument(widget.initialMarkdown),
    );
    _editorState.editable = widget.editable;
    _scrollController = EditorScrollController(editorState: _editorState);
    _editorState.transactionStream.listen((_) => _scheduleEmit());
  }

  @override
  void didUpdateWidget(covariant NoteBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editable != widget.editable) {
      _editorState.editable = widget.editable;
    }
  }

  void _scheduleEmit() {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      onChanged(toMarkdown());
    });
  }

  /// Serializes the current document to markdown.
  String toMarkdown() => noteDocumentToMarkdown(_editorState.document);

  /// Replaces the current document with [markdown] (used when switching the
  /// selected note without rebuilding this widget).
  void loadMarkdown(String markdown) {
    setState(() {
      _editorState = EditorState(document: noteMarkdownToDocument(markdown));
      _editorState.editable = widget.editable;
      _scrollController.dispose();
      _scrollController = EditorScrollController(editorState: _editorState);
      _editorState.transactionStream.listen((_) => _scheduleEmit());
    });
  }

  /// Enfoca el editor y coloca el cursor al inicio del contenido o al final si [atEnd] es true.
  void focus({bool atEnd = false}) {
    if (!widget.editable) return;
    final targetNode = atEnd
        ? _editorState.document.last
        : _editorState.document.first;
    if (targetNode != null) {
      final offset = atEnd ? (targetNode.delta?.length ?? 0) : 0;
      _editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: targetNode.path, offset: offset)),
        reason: SelectionUpdateReason.uiEvent,
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _editorState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : Colors.black87;
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final cursorColor = isDark ? Colors.white70 : Colors.black87;
    final selectionColor = isDark
        ? Colors.white.withValues(alpha: 0.20)
        : Colors.black.withValues(alpha: 0.12);

    // Tipografía uniforme con altura regular estricta (1.4) para evitar saltos irregulares
    final baseTextStyle = TextStyle(
      fontSize: 14,
      height: 1.4,
      color: textColor,
      letterSpacing: -0.1,
    );

    final editorStyle = EditorStyle.desktop(
      // Padding vertical en 0 para evitar que PageBlockComponent inyecte 10px arriba y abajo
      // de CADA párrafo al presionar Enter, comportándose como una nota continua fluida.
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      cursorColor: cursorColor,
      selectionColor: selectionColor,
      textStyleConfiguration: TextStyleConfiguration(
        text: baseTextStyle,
        lineHeight: 1.4,
      ),
    );

    // Espaciado vertical continuo y compacto entre bloques (1.0px) para un flujo de texto natural
    EdgeInsets compactBlockPadding(Node _) =>
        const EdgeInsets.symmetric(vertical: 1.0);

    final customBuilders = Map<String, BlockComponentBuilder>.from(
      standardBlockComponentBuilderMap,
    );

    // Párrafos uniformes con placeholder SOLO en el primer párrafo cuando la nota está vacía.
    // Al dar Enter no debe reaparecer el placeholder en la nueva línea ni saltar como nueva nota.
    customBuilders[ParagraphBlockKeys.type] = ParagraphBlockComponentBuilder(
      configuration: standardBlockComponentConfiguration.copyWith(
        padding: compactBlockPadding,
        placeholderText: (_) => 'Escribe una nota aquí...',
        placeholderTextStyle: (_, {textSpan}) => TextStyle(
          fontSize: 14,
          height: 1.4,
          fontStyle: FontStyle.italic,
          color: hintColor,
        ),
      ),
      showPlaceholder: (editorState, node) {
        // Solo mostrar si es el primer nodo de un documento con un solo nodo vacío
        final isFirstNode = node.path.equals([0]);
        if (!isFirstNode) return false;
        final hasOnlyOneNode = editorState.document.root.children.length <= 1;
        final text = node.delta?.toPlainText().trim() ?? '';
        return hasOnlyOneNode && text.isEmpty;
      },
    );

    // Lista numerada uniforme
    customBuilders[NumberedListBlockKeys.type] =
        NumberedListBlockComponentBuilder(
          configuration: standardBlockComponentConfiguration.copyWith(
            padding: compactBlockPadding,
            placeholderText: (_) => '1. Elemento numerado...',
            placeholderTextStyle: (_, {textSpan}) => TextStyle(
              fontSize: 14,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: hintColor,
            ),
          ),
        );

    // Lista con viñetas uniforme
    customBuilders[BulletedListBlockKeys.type] =
        BulletedListBlockComponentBuilder(
          configuration: standardBlockComponentConfiguration.copyWith(
            padding: compactBlockPadding,
            placeholderText: (_) => 'Elemento con viñeta...',
            placeholderTextStyle: (_, {textSpan}) => TextStyle(
              fontSize: 14,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: hintColor,
            ),
          ),
        );

    // Checklist uniforme
    customBuilders[TodoListBlockKeys.type] = TodoListBlockComponentBuilder(
      configuration: standardBlockComponentConfiguration.copyWith(
        padding: compactBlockPadding,
        placeholderText: (_) => 'Elemento por hacer...',
        placeholderTextStyle: (_, {textSpan}) => TextStyle(
          fontSize: 14,
          height: 1.4,
          fontStyle: FontStyle.italic,
          color: hintColor,
        ),
      ),
    );

    // Encabezados con padding armónico
    customBuilders[HeadingBlockKeys.type] = HeadingBlockComponentBuilder(
      configuration: standardBlockComponentConfiguration.copyWith(
        padding: (node) {
          final level = node.attributes[HeadingBlockKeys.level] ?? 1;
          return EdgeInsets.only(top: level == 1 ? 8.0 : 5.0, bottom: 3.0);
        },
      ),
    );

    // Cita en bloque uniforme
    customBuilders[QuoteBlockKeys.type] = QuoteBlockComponentBuilder(
      configuration: standardBlockComponentConfiguration.copyWith(
        padding: compactBlockPadding,
      ),
    );

    // Ítems de la Floating Toolbar flotante (Medium / Notion style)
    final floatingItems = [
      paragraphItem,
      ...headingItems,
      ...markdownFormatItems,
      quoteItem,
      bulletedListItem,
      proNumberedListItem,
      todoListItem,
      linkItem,
      buildTextColorItem(),
      buildHighlightColorItem(),
    ];

    final floatingToolbarBg = isDark
        ? const Color(0xFF1E2024).withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.96);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editable) _buildToolbar(isDark),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_editorState.selection == null) {
                final firstNode = _editorState.document.first;
                if (firstNode != null) {
                  _editorState.updateSelectionWithReason(
                    Selection.collapsed(
                      Position(path: firstNode.path, offset: 0),
                    ),
                  );
                }
              }
            },
            child: FloatingToolbar(
              items: floatingItems,
              editorState: _editorState,
              editorScrollController: _scrollController,
              textDirection: TextDirection.ltr,
              floatingToolbarHeight: 40,
              style: FloatingToolbarStyle(
                backgroundColor: floatingToolbarBg,
                toolbarActiveColor: Theme.of(context).colorScheme.primary,
                toolbarIconColor: isDark ? Colors.white70 : Colors.black87,
                toolbarElevation: 10,
                toolbarShadowColor: Colors.black.withValues(alpha: 0.28),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: floatingToolbarBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.black.withValues(alpha: 0.10),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: AppFlowyEditor(
                  editorState: _editorState,
                  editorScrollController: _scrollController,
                  editorStyle: editorStyle,
                  blockComponentBuilders: customBuilders,
                  commandShortcutEvents: [
                    ...standardCommandShortcutEvents.where(
                      (cmd) => cmd.command != 'escape',
                    ),
                    CommandShortcutEvent(
                      key: 'exit the editing mode and onEscape',
                      command: 'escape',
                      getDescription: () =>
                          'Exit editing mode and trigger onEscape',
                      handler: (editorState) {
                        editorState.selection = null;
                        editorState.service.keyboardService?.closeKeyboard();
                        widget.onEscape?.call();
                        return KeyEventResult.handled;
                      },
                    ),
                  ],
                  editable: widget.editable,
                  autoFocus: widget.autoFocus,
                  shrinkWrap: false,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(bool isDark) {
    // Rebuild on every selection change so highlight state (e.g. "bold" is
    // active at the cursor) stays in sync, same as the built-in toolbar.
    return ListenableBuilder(
      listenable: _editorState.selectionNotifier,
      builder: (context, _) {
        final highlightColor = Theme.of(context).colorScheme.primary;
        final iconColor = isDark
            ? Colors.white.withValues(alpha: 0.85)
            : Colors.black87;
        final dividerColor = isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.10);
        final barColor =
            widget.toolbarColor ??
            (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF2F2F2));

        return Container(
          decoration: BoxDecoration(
            color: barColor,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Grupo 1: Tipografía y encabezados (T ▾)
                _buildTypographyDropdown(iconColor, highlightColor),
                _buildToolbarDivider(dividerColor),

                // Grupo 2: Formatos inline esenciales (B, I, U, S, Code)
                _buildInlineFormatGroup(iconColor, highlightColor),
                _buildToolbarDivider(dividerColor),

                // Grupo 3: Listas (Viñetas, Números secuenciales, Tareas ▾)
                _buildListsDropdown(iconColor, highlightColor),
                _buildToolbarDivider(dividerColor),

                // Grupo 4: Alineaciones (Izquierda, Centro, Derecha ▾)
                _buildAlignmentDropdown(iconColor),
                _buildToolbarDivider(dividerColor),

                // Grupo 5: Inserciones (Tabla 2x2, 3x3, Enlace ▾)
                _buildInsertDropdown(iconColor),
                _buildToolbarDivider(dividerColor),

                // Grupo 6: Colores (Texto y Resaltado)
                _buildColorsGroup(iconColor, highlightColor),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbarDivider(Color color) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: color,
    );
  }

  Selection _ensureSelection() {
    var sel = _editorState.selection;
    if (sel == null) {
      final firstNode = _editorState.document.first;
      if (firstNode != null) {
        sel = Selection.collapsed(Position(path: firstNode.path, offset: 0));
        _editorState.updateSelectionWithReason(sel);
      }
    }
    return sel!;
  }

  // ── Grupo 1: Tipografía ──────────────────────────────────────────────────
  Widget _buildTypographyDropdown(Color iconColor, Color highlightColor) {
    final sel = _editorState.selection;
    String currentLabel = 'T';
    String tooltip = 'Tipografía (Normal)';

    if (sel != null) {
      final node = _editorState.getNodeAtPath(sel.start.path);
      if (node?.type == HeadingBlockKeys.type) {
        final level = node?.attributes[HeadingBlockKeys.level] ?? 1;
        currentLabel = 'H$level';
        tooltip = 'Encabezado $level';
      } else if (node?.type == QuoteBlockKeys.type) {
        currentLabel = '“ ”';
        tooltip = 'Cita en bloque';
      }
    }

    return MenuAnchor(
      builder: (context, controller, child) {
        return Tooltip(
          message: tooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: controller.isOpen
                    ? highlightColor.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: currentLabel != 'T' ? highlightColor : iconColor,
                    ),
                  ),
                  const SizedBox(width: 1),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 15,
                    color: iconColor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.text_fields_rounded, size: 16),
          child: const Text('Texto normal (Párrafo)'),
          onPressed: () {
            final selection = _ensureSelection();
            _editorState.formatNode(
              selection,
              (node) => node.copyWith(type: ParagraphBlockKeys.type),
            );
          },
        ),
        for (int lvl = 1; lvl <= 3; lvl++)
          MenuItemButton(
            leadingIcon: SizedBox(
              width: 18,
              child: Text(
                'H$lvl',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ),
            child: Text('Título $lvl (H$lvl)'),
            onPressed: () {
              final selection = _ensureSelection();
              _editorState.formatNode(
                selection,
                (node) => node.copyWith(
                  type: HeadingBlockKeys.type,
                  attributes: {...node.attributes, HeadingBlockKeys.level: lvl},
                ),
              );
            },
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.format_quote_rounded, size: 16),
          child: const Text('Cita en bloque (Quote)'),
          onPressed: () {
            final selection = _ensureSelection();
            _editorState.formatNode(
              selection,
              (node) => node.copyWith(type: QuoteBlockKeys.type),
            );
          },
        ),
      ],
    );
  }

  // ── Grupo 2: Formatos Inline (B, I, U, S, Code) ──────────────────────────
  Widget _buildInlineFormatGroup(Color iconColor, Color highlightColor) {
    final sel = _editorState.selection;
    final nodes = sel != null
        ? _editorState.getNodesInSelection(sel)
        : <Node>[];

    bool isAttrActive(String attr) {
      if (sel == null) return false;
      if (sel.isCollapsed) return _editorState.toggledStyle[attr] == true;
      return nodes.isNotEmpty &&
          nodes.allSatisfyInSelection(
            sel,
            (delta) =>
                delta.isNotEmpty &&
                delta.everyAttributes((a) => a[attr] == true),
          );
    }

    final formats = [
      (
        AppFlowyRichTextKeys.bold,
        Icons.format_bold_rounded,
        'Negrita (Ctrl+B)',
      ),
      (
        AppFlowyRichTextKeys.italic,
        Icons.format_italic_rounded,
        'Cursiva (Ctrl+I)',
      ),
      (
        AppFlowyRichTextKeys.underline,
        Icons.format_underlined_rounded,
        'Subrayado (Ctrl+U)',
      ),
      (
        AppFlowyRichTextKeys.strikethrough,
        Icons.format_strikethrough_rounded,
        'Tachado',
      ),
      (AppFlowyRichTextKeys.code, Icons.code_rounded, 'Código inline'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: formats.map((item) {
        final (key, iconData, tip) = item;
        final active = isAttrActive(key);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Tooltip(
            message: tip,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                _ensureSelection();
                _editorState.toggleAttribute(key);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? highlightColor.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: active
                      ? Border.all(
                          color: highlightColor.withValues(alpha: 0.35),
                          width: 0.8,
                        )
                      : null,
                ),
                child: Icon(
                  iconData,
                  size: 15,
                  color: active ? highlightColor : iconColor,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Grupo 3: Listas ──────────────────────────────────────────────────────
  Widget _buildListsDropdown(Color iconColor, Color highlightColor) {
    final sel = _editorState.selection;
    IconData currentIcon = Icons.format_list_bulleted_rounded;
    if (sel != null) {
      final node = _editorState.getNodeAtPath(sel.start.path);
      if (node?.type == NumberedListBlockKeys.type) {
        currentIcon = Icons.format_list_numbered_rounded;
      } else if (node?.type == TodoListBlockKeys.type) {
        currentIcon = Icons.check_box_outlined;
      }
    }

    return MenuAnchor(
      builder: (context, controller, child) {
        return Tooltip(
          message: 'Listas y tareas',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: controller.isOpen
                    ? highlightColor.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(currentIcon, size: 15, color: iconColor),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 15,
                    color: iconColor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.format_list_bulleted_rounded, size: 16),
          child: const Text('Lista con viñetas'),
          onPressed: () {
            final sel = _ensureSelection();
            toggleBulletedListForSelection(_editorState, sel);
          },
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.format_list_numbered_rounded, size: 16),
          child: const Text('Lista numerada (1, 2, 3...)'),
          onPressed: () {
            final sel = _ensureSelection();
            toggleNumberedListForSelection(_editorState, sel);
          },
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.check_box_outlined, size: 16),
          child: const Text('Lista de tareas (Checklist)'),
          onPressed: () {
            final sel = _ensureSelection();
            toggleTodoListForSelection(_editorState, sel);
          },
        ),
      ],
    );
  }

  // ── Grupo 4: Alineaciones ────────────────────────────────────────────────
  Widget _buildAlignmentDropdown(Color iconColor) {
    return MenuAnchor(
      builder: (context, controller, child) {
        return Tooltip(
          message: 'Alineación de texto',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: controller.isOpen
                    ? iconColor.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.format_align_left_rounded,
                    size: 15,
                    color: iconColor,
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 15,
                    color: iconColor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.format_align_left_rounded, size: 16),
          child: const Text('Alinear a la izquierda'),
          onPressed: () => _setAlignment('left'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.format_align_center_rounded, size: 16),
          child: const Text('Centrar texto'),
          onPressed: () => _setAlignment('center'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.format_align_right_rounded, size: 16),
          child: const Text('Alinear a la derecha'),
          onPressed: () => _setAlignment('right'),
        ),
      ],
    );
  }

  void _setAlignment(String align) {
    final sel = _ensureSelection();
    _editorState.updateNode(
      sel,
      (node) => node.copyWith(
        attributes: {...node.attributes, blockComponentAlign: align},
      ),
    );
  }

  // ── Grupo 5: Inserciones (Tablas, Enlace) ─────────────────────────────────
  Widget _buildInsertDropdown(Color iconColor) {
    final sel = _editorState.selection;
    bool isInTable = false;
    if (sel != null) {
      final node = _editorState.getNodeAtPath(sel.start.path);
      isInTable =
          node?.findParent((e) => e.type == TableBlockKeys.type) != null;
    }

    return MenuAnchor(
      builder: (context, controller, child) {
        return Tooltip(
          message: 'Insertar tabla o enlace',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: controller.isOpen
                    ? iconColor.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_box_rounded, size: 15, color: iconColor),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 15,
                    color: iconColor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.table_chart_outlined, size: 16),
          child: const Text('Insertar Tabla (2x2)'),
          onPressed: () => _insertTable(2, 2),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.grid_on_rounded, size: 16),
          child: const Text('Insertar Tabla (3x3)'),
          onPressed: () => _insertTable(3, 3),
        ),
        if (isInTable)
          MenuItemButton(
            leadingIcon: const Icon(
              Icons.table_rows_rounded,
              color: Colors.redAccent,
              size: 16,
            ),
            onPressed: _deleteCurrentTable,
            child: const Text(
              'Eliminar tabla completa',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.link_rounded, size: 16),
          child: const Text('Insertar / editar enlace (Ctrl+K)'),
          onPressed: () {
            final sel = _ensureSelection();
            final nodes = _editorState.getNodesInSelection(sel);
            final isHref = nodes.allSatisfyInSelection(sel, (delta) {
              return delta.everyAttributes(
                (attributes) => attributes[AppFlowyRichTextKeys.href] != null,
              );
            });
            showLinkMenu(context, _editorState, sel, isHref);
          },
        ),
      ],
    );
  }

  void _deleteCurrentTable() {
    final sel = _editorState.selection;
    if (sel == null) return;
    final node = _editorState.getNodeAtPath(sel.start.path);
    final tableNode = node?.findParent((e) => e.type == TableBlockKeys.type);
    if (tableNode == null) return;

    final transaction = _editorState.transaction;
    // Si la tabla es el único bloque en el documento, insertar un párrafo vacío antes de borrarla
    if (_editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
      transaction.afterSelection = Selection.collapsed(
        Position(path: tableNode.path, offset: 0),
      );
    } else {
      final prev = tableNode.previous;
      if (prev != null) {
        transaction.afterSelection = Selection.collapsed(
          Position(path: prev.path, offset: prev.delta?.length ?? 0),
        );
      }
    }

    transaction.deleteNode(tableNode);
    _editorState.apply(transaction);
  }

  void _insertTable(int rows, int cols) {
    final sel = _ensureSelection();
    final tableNode = TableNode.fromList(
      List.generate(cols, (_) => List.generate(rows, (_) => '')),
    );
    final transaction = _editorState.transaction;
    final currentNode = _editorState.getNodeAtPath(sel.end.path);

    if (currentNode != null && (currentNode.delta?.isEmpty ?? false)) {
      transaction
        ..insertNode(sel.end.path, tableNode.node)
        ..deleteNode(currentNode);
      transaction.afterSelection = Selection.collapsed(
        Position(path: sel.end.path + [0, 0], offset: 0),
      );
    } else {
      transaction.insertNode(sel.end.path.next, tableNode.node);
      transaction.afterSelection = Selection.collapsed(
        Position(path: sel.end.path.next + [0, 0], offset: 0),
      );
    }
    _editorState.apply(transaction);
  }

  // ── Grupo 6: Colores ─────────────────────────────────────────────────────
  static final List<ColorOption> _textColorOptions = [
    ColorOption(colorHex: Colors.black.toHex(), name: 'Negro'),
    ColorOption(colorHex: Colors.grey.toHex(), name: 'Gris'),
    ColorOption(colorHex: Colors.brown.toHex(), name: 'Marrón'),
    ColorOption(colorHex: Colors.orange.toHex(), name: 'Naranja'),
    ColorOption(colorHex: Colors.yellow.toHex(), name: 'Amarillo'),
    ColorOption(colorHex: Colors.green.toHex(), name: 'Verde'),
    ColorOption(colorHex: Colors.blue.toHex(), name: 'Azul'),
    ColorOption(colorHex: Colors.purple.toHex(), name: 'Púrpura'),
    ColorOption(colorHex: Colors.pink.toHex(), name: 'Rosa'),
    ColorOption(colorHex: Colors.red.toHex(), name: 'Rojo'),
  ];

  static final List<ColorOption> _highlightColorOptions = [
    ColorOption(
      colorHex: Colors.grey.withValues(alpha: 0.3).toHex(),
      name: 'Gris',
    ),
    ColorOption(
      colorHex: Colors.brown.withValues(alpha: 0.3).toHex(),
      name: 'Marrón',
    ),
    ColorOption(
      colorHex: Colors.orange.withValues(alpha: 0.3).toHex(),
      name: 'Naranja',
    ),
    ColorOption(
      colorHex: Colors.yellow.withValues(alpha: 0.3).toHex(),
      name: 'Amarillo',
    ),
    ColorOption(
      colorHex: Colors.green.withValues(alpha: 0.3).toHex(),
      name: 'Verde',
    ),
    ColorOption(
      colorHex: Colors.blue.withValues(alpha: 0.3).toHex(),
      name: 'Azul',
    ),
    ColorOption(
      colorHex: Colors.purple.withValues(alpha: 0.3).toHex(),
      name: 'Púrpura',
    ),
    ColorOption(
      colorHex: Colors.pink.withValues(alpha: 0.3).toHex(),
      name: 'Rosa',
    ),
    ColorOption(
      colorHex: Colors.red.withValues(alpha: 0.3).toHex(),
      name: 'Rojo',
    ),
  ];

  Widget _buildColorsGroup(Color iconColor, Color highlightColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildColorPickerDropdown(
          icon: Icons.format_color_text_rounded,
          tooltip: 'Color de texto',
          isTextColor: true,
          iconColor: iconColor,
          highlightColor: highlightColor,
        ),
        _buildColorPickerDropdown(
          icon: Icons.format_color_fill_rounded,
          tooltip: 'Resaltado de fondo',
          isTextColor: false,
          iconColor: iconColor,
          highlightColor: highlightColor,
        ),
      ],
    );
  }

  Widget _buildColorPickerDropdown({
    required IconData icon,
    required String tooltip,
    required bool isTextColor,
    required Color iconColor,
    required Color highlightColor,
  }) {
    final sel = _editorState.selection;
    bool isActive = false;
    if (sel != null) {
      final nodes = _editorState.getNodesInSelection(sel);
      isActive = nodes.allSatisfyInSelection(sel, (delta) {
        if (delta.everyAttributes((attr) => attr.isEmpty)) return false;
        return delta.everyAttributes((attr) {
          final color = isTextColor
              ? attr[AppFlowyRichTextKeys.textColor]
              : attr[AppFlowyRichTextKeys.backgroundColor];
          return color != null;
        });
      });
    }

    final options = isTextColor ? _textColorOptions : _highlightColorOptions;

    return MenuAnchor(
      builder: (context, controller, child) {
        return Tooltip(
          message: tooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: controller.isOpen || isActive
                    ? highlightColor.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: isActive ? highlightColor : iconColor,
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 15,
                    color: iconColor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.format_color_reset_rounded, size: 16),
          child: Text(
            isTextColor
                ? 'Color predeterminado'
                : 'Sin resaltado (transparente)',
          ),
          onPressed: () {
            final selection = _ensureSelection();
            if (isTextColor) {
              formatFontColor(
                _editorState,
                selection,
                null,
                withUpdateSelection: true,
              );
            } else {
              formatHighlightColor(
                _editorState,
                selection,
                null,
                withUpdateSelection: true,
              );
            }
          },
        ),
        for (final opt in options)
          MenuItemButton(
            leadingIcon: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: opt.colorHex.tryToColor(),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26, width: 0.5),
              ),
            ),
            child: Text(opt.name),
            onPressed: () {
              final selection = _ensureSelection();
              if (isTextColor) {
                formatFontColor(
                  _editorState,
                  selection,
                  opt.colorHex,
                  withUpdateSelection: true,
                );
              } else {
                formatHighlightColor(
                  _editorState,
                  selection,
                  opt.colorHex,
                  withUpdateSelection: true,
                );
              }
            },
          ),
      ],
    );
  }
}
