import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import '../services/favorites_service.dart';
import 'config_badge.dart';

class ProcedureCard extends StatefulWidget {
  final Procedimiento procedimiento;
  final VoidCallback onTap;
  final VoidCallback? onOpenInNewTab;
  final VoidCallback? onViewSource;
  final String searchQuery;

  const ProcedureCard({
    super.key,
    required this.procedimiento,
    required this.onTap,
    this.onOpenInNewTab,
    this.onViewSource,
    this.searchQuery = '',
  });

  @override
  State<ProcedureCard> createState() => _ProcedureCardState();
}

class _ProcedureCardState extends State<ProcedureCard> {
  bool _hovered = false;
  bool _focused = false;
  Timer? _hoverTimer;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  // Cached per-procedure values — recomputed only when widget.procedimiento changes
  late String _dateText;
  late String? _snippet;

  static final _skipRe = RegExp(
    r'^(CREATE\s+(OR\s+REPLACE\s+)?(PROCEDURE|FUNCTION|PACKAGE|TRIGGER|VIEW|TYPE|BODY)|--|/\*|\*)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _dateText = _relativeDate(widget.procedimiento.feModificacion);
    _snippet = _meaningfulSnippet();
  }

  @override
  void didUpdateWidget(ProcedureCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.procedimiento, widget.procedimiento)) {
      _dateText = _relativeDate(widget.procedimiento.feModificacion);
      _snippet = _meaningfulSnippet();
    }
  }

  String _relativeDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'hoy';
    if (diff.inDays == 1) return 'ayer';
    if (diff.inDays < 7) return 'hace ${diff.inDays} días';
    if (diff.inDays < 30) return 'hace ${(diff.inDays / 7).floor()} sem.';
    if (diff.inDays < 365) return 'hace ${(diff.inDays / 30).floor()} meses';
    return 'hace ${(diff.inDays / 365).floor()} años';
  }

  // Returns the first meaningful code line (skips headers, comments, blanks)
  String? _meaningfulSnippet() {
    for (final line in widget.procedimiento.deTexto.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || _skipRe.hasMatch(trimmed)) continue;
      return trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed;
    }
    return null;
  }

  void _showCodePreview() {
    _overlayEntry?.remove();
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final pos = box.localToGlobal(Offset.zero);
    final cardSize = box.size;
    _overlayEntry = OverlayEntry(
      builder: (ctx) => _CodePreviewOverlay(
        cardPosition: pos,
        cardSize: cardSize,
        proc: widget.procedimiento,
        screenSize: MediaQuery.of(ctx).size,
        onMouseEnter: _cancelHide,
        onMouseExit: _scheduleHide,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _scheduleHide() {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 150), _hideCodePreview);
  }

  void _cancelHide() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
  }

  void _hideCodePreview() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildHighlightedName(ColorScheme cs) {
    final name = widget.procedimiento.cdProcedimiento;
    final query = widget.searchQuery.trim();
    final style = TextStyle(
      color: cs.onSurface,
      fontWeight: FontWeight.w600,
      fontSize: 13,
      fontFamily: 'Consolas',
    );
    if (query.isEmpty) return Text(name, style: style);
    final lower = name.toLowerCase();
    final start = lower.indexOf(query.toLowerCase());
    if (start == -1) return Text(name, style: style);
    final end = start + query.length;
    return RichText(
      text: TextSpan(
        style: style,
        children: [
          if (start > 0) TextSpan(text: name.substring(0, start)),
          TextSpan(
            text: name.substring(start, end),
            style: TextStyle(
              color: Colors.amber.shade300,
              fontWeight: FontWeight.w700,
              backgroundColor: Colors.amber.withValues(alpha: 0.15),
              fontFamily: 'Consolas',
              fontSize: 13,
            ),
          ),
          if (end < name.length) TextSpan(text: name.substring(end)),
        ],
      ),
    );
  }

  void _showContextMenu(TapUpDetails details) {
    final pos = details.globalPosition;
    showMenu<_CardAction>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        const PopupMenuItem(
          value: _CardAction.viewSource,
          child: Row(
            children: [
              Icon(Icons.code_rounded, size: 14),
              SizedBox(width: 8),
              Text('Ver fuente', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: _CardAction.openInNewTab,
          enabled: widget.onOpenInNewTab != null,
          child: const Row(
            children: [
              Icon(Icons.open_in_new, size: 14),
              SizedBox(width: 8),
              Text('Abrir en nueva pestaña', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: _CardAction.copyName,
          child: const Row(
            children: [
              Icon(Icons.content_copy, size: 14),
              SizedBox(width: 8),
              Text('Copiar nombre', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: _CardAction.copyAsCall,
          child: const Row(
            children: [
              Icon(Icons.code, size: 14),
              SizedBox(width: 8),
              Text('Copiar como llamada', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((action) {
      if (action == _CardAction.viewSource) widget.onViewSource?.call();
      if (action == _CardAction.openInNewTab) widget.onOpenInNewTab?.call();
      if (action == _CardAction.copyName) {
        Clipboard.setData(
          ClipboardData(text: widget.procedimiento.cdProcedimiento),
        );
      }
      if (action == _CardAction.copyAsCall) {
        final name = widget.procedimiento.cdProcedimiento;
        final isJs = widget.procedimiento.inConfiguracion == 'J';
        final call = isJs ? '$name();' : 'BEGIN\n  $name;\nEND;';
        Clipboard.setData(ClipboardData(text: call));
      }
    });
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final proc = widget.procedimiento;
    final configDesc = procedimientosProvider.descriptionForConfig(
      proc.inConfiguracion,
    );

    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            FocusScope.of(context).nextFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            FocusScope.of(context).previousFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _focused
                ? cs.surfaceContainerHighest
                : _hovered
                ? cs.surfaceContainerHigh
                : cs.surface,
            borderRadius: BorderRadius.circular(6),
            border: _focused
                ? Border.all(color: cs.primary, width: 1.5)
                : Border(
                    left: BorderSide(
                      color: ConfigBadge.colorForConfig(proc.inConfiguracion),
                      width: 3,
                    ),
                  ),
            boxShadow: _hovered && !_focused
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: MouseRegion(
            onEnter: (_) {
              setState(() => _hovered = true);
              _cancelHide();
              _hoverTimer = Timer(
                const Duration(milliseconds: 700),
                _showCodePreview,
              );
            },
            onExit: (_) {
              setState(() => _hovered = false);
              _scheduleHide();
            },
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onSecondaryTapUp: _showContextMenu,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHighlightedName(cs),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (_dateText.isNotEmpty) ...[
                                  Icon(
                                    Icons.access_time,
                                    size: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _dateText,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (proc.cdUsuario != null) ...[
                                  Icon(
                                    Icons.person_outline,
                                    size: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    proc.cdUsuario!,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  configDesc,
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                            if (_snippet != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  _snippet!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Consolas',
                                    fontSize: 10.5,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConfigBadge(config: proc.inConfiguracion, small: true),
                      const SizedBox(width: 8),
                      _VersionBadge(version: proc.version),
                      const SizedBox(width: 8),
                      _EstadoBadge(activo: proc.activo),
                      const SizedBox(width: 4),
                      if (widget.onViewSource != null)
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: _hovered ? 1.0 : 0.25,
                          child: Tooltip(
                            message: 'Ver fuente Oracle',
                            child: InkWell(
                              onTap: widget.onViewSource,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.code_rounded,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (widget.onOpenInNewTab != null)
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: _hovered ? 1.0 : 0.25,
                          child: Tooltip(
                            message: 'Abrir en nueva pestaña',
                            child: InkWell(
                              onTap: widget.onOpenInNewTab,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.open_in_new_rounded,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      _FavStar(procId: proc.cdProcedimiento),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        color: cs.onSurfaceVariant,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FavStar extends StatelessWidget {
  final String procId;
  const _FavStar({required this.procId});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: FavoritesService.listenable,
      builder: (_, favs, _) {
        final isFav = favs.contains(procId);
        return GestureDetector(
          onTap: () => FavoritesService.toggle(procId),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              isFav ? Icons.star_rounded : Icons.star_border_rounded,
              size: 16,
              color: isFav
                  ? Colors.amber.shade600
                  : Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
          ),
        );
      },
    );
  }
}

enum _CardAction { viewSource, openInNewTab, copyName, copyAsCall }

class _VersionBadge extends StatelessWidget {
  final int version;
  const _VersionBadge({required this.version});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF569CD6).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFF569CD6).withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Text(
        'v$version',
        style: TextStyle(
          color: cs.brightness == Brightness.dark
              ? const Color(0xFF569CD6)
              : const Color(0xFF1565C0),
          fontSize: 10,
          fontFamily: 'Consolas',
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _EstadoBadge extends StatelessWidget {
  final bool activo;
  const _EstadoBadge({required this.activo});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: activo ? 'Activo' : 'Inactivo',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: activo ? Colors.green.shade500 : Colors.red.shade400,
          boxShadow: [
            BoxShadow(
              color: (activo ? Colors.green : Colors.red).withValues(
                alpha: 0.4,
              ),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

class _CodePreviewOverlay extends StatelessWidget {
  final Offset cardPosition;
  final Size cardSize;
  final Procedimiento proc;
  final Size screenSize;
  final VoidCallback onMouseEnter;
  final VoidCallback onMouseExit;

  const _CodePreviewOverlay({
    required this.cardPosition,
    required this.cardSize,
    required this.proc,
    required this.screenSize,
    required this.onMouseEnter,
    required this.onMouseExit,
  });

  static const double _popupW = 460;
  static const double _popupH = 320;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    final headerBg = isDark ? const Color(0xFF252526) : const Color(0xFFE8E8E8);
    final textColor = isDark
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF1E1E1E);

    // Prefer above card; fall back to below if not enough vertical space.
    double top = cardPosition.dy - _popupH - 4;
    if (top < 8) top = cardPosition.dy + cardSize.height + 4;

    double left = cardPosition.dx + 12;
    if (left + _popupW > screenSize.width - 8) {
      left = screenSize.width - _popupW - 8;
    }

    return Positioned(
      top: top,
      left: left,
      width: _popupW,
      height: _popupH,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        builder: (_, opacity, child) => Opacity(opacity: opacity, child: child),
        child: MouseRegion(
          onEnter: (_) => onMouseEnter(),
          onExit: (_) => onMouseExit(),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: headerBg,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(7),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.code_rounded,
                          size: 13,
                          color: Color(0xFF569CD6),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          proc.cdProcedimiento,
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF569CD6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          proc.deTexto,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11.5,
                            color: textColor,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
