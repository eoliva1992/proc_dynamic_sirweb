import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/ambiente_selector.dart';
import 'app_toast.dart';
import 'object_source_page.dart';

// Tracks live child source-viewer processes so they can be killed on main-window close.
final _childProcesses = <Process>{};

/// Kills every child source-viewer window spawned by this session.
void closeAllSourceWindows() {
  for (final p in _childProcesses) {
    try {
      p.kill();
    } catch (_) {}
  }
  _childProcesses.clear();
}

/// Abre el código fuente en una ventana OS separada (Windows desktop).
/// En web/otros platforms, abre un overlay interno.
void openSourceWindow(
  BuildContext context, {
  required String name,
  required String objectType,
  required String ambiente,
}) {
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    _openNewProcess(
      context,
      name: name,
      objectType: objectType,
      ambiente: ambiente,
    );
  } else {
    _openOverlay(
      context,
      name: name,
      objectType: objectType,
      ambiente: ambiente,
    );
  }
}

void _openNewProcess(
  BuildContext context, {
  required String name,
  required String objectType,
  required String ambiente,
}) {
  try {
    // normal mode keeps streams piped (not shared) so the child's VM service URI
    // never appears on the parent's stdout — that was causing Flutter tooling to
    // lose connection on hot restart. Drain streams to prevent pipe-buffer deadlock.
    Process.start(Platform.resolvedExecutable, [
      '--source=$name::$objectType::$ambiente',
    ]).then((process) {
      process.stdout.listen(null);
      process.stderr.listen(null);
      _childProcesses.add(process);
      process.exitCode.then((_) => _childProcesses.remove(process));
    });
  } catch (e) {
    AppToast.error('No se pudo abrir la ventana: $e');
    _openOverlay(
      context,
      name: name,
      objectType: objectType,
      ambiente: ambiente,
    );
  }
}

void _openOverlay(
  BuildContext context, {
  required String name,
  required String objectType,
  required String ambiente,
}) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _SourceFloatWindow(
      name: name,
      objectType: objectType,
      ambiente: ambiente,
      onClose: () => entry.remove(),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
}

// ── Ventana flotante ──────────────────────────────────────────────────────────

class _SourceFloatWindow extends StatefulWidget {
  final String name;
  final String objectType;
  final String ambiente;
  final VoidCallback onClose;

  const _SourceFloatWindow({
    required this.name,
    required this.objectType,
    required this.ambiente,
    required this.onClose,
  });

  @override
  State<_SourceFloatWindow> createState() => _SourceFloatWindowState();
}

class _SourceFloatWindowState extends State<_SourceFloatWindow>
    with SingleTickerProviderStateMixin {
  Offset _pos = const Offset(80, 60);
  Size _size = const Size(820, 580);
  bool _minimized = false;
  bool _resizing = false;
  Offset _resizeStart = Offset.zero;
  Size _resizeStartSize = Size.zero;

  static const _minW = 480.0;
  static const _minH = 300.0;
  static const _titleH = 38.0;
  static const _resizeHandleSize = 12.0;

  late final AnimationController _minimizeAnim;
  late final Animation<double> _heightAnim;

  @override
  void initState() {
    super.initState();
    _minimizeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1.0,
    );
    _heightAnim = CurvedAnimation(parent: _minimizeAnim, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _minimizeAnim.dispose();
    super.dispose();
  }

  void _toggleMinimize() {
    setState(() => _minimized = !_minimized);
    if (_minimized) {
      _minimizeAnim.reverse();
    } else {
      _minimizeAnim.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = kTypeColors[widget.objectType] ?? Colors.blueGrey;
    final ambColor = AmbienteSelector.colorForAmbiente(widget.ambiente);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── Ventana principal ──────────────────────────────────────────────
          Positioned(
            left: _pos.dx,
            top: _pos.dy,
            child: SizeTransition(
              sizeFactor: _heightAnim,
              axis: Axis.vertical,
              axisAlignment: -1,
              child: Container(
                width: _size.width,
                height: _minimized ? _titleH : _size.height,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.5 : 0.22,
                      ),
                      blurRadius: 28,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFDDE2EA),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    children: [
                      _buildTitleBar(isDark, color, ambColor),
                      if (!_minimized)
                        Expanded(
                          child: DefaultTabController(
                            length:
                                widget.objectType == 'PACKAGE' ||
                                    widget.objectType == 'TYPE'
                                ? 2
                                : 1,
                            child: ObjectSourcePage(
                              key: ValueKey(
                                '${widget.name}::${widget.objectType}::${widget.ambiente}',
                              ),
                              name: widget.name,
                              objectType: widget.objectType,
                              ambiente: widget.ambiente,
                              embedded: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ── Resize handle (esquina inferior derecha) ──────────────────────
          if (!_minimized)
            Positioned(
              left: _pos.dx + _size.width - _resizeHandleSize,
              top: _pos.dy + _size.height - _resizeHandleSize,
              child: GestureDetector(
                onPanStart: (d) {
                  _resizing = true;
                  _resizeStart = d.globalPosition;
                  _resizeStartSize = _size;
                },
                onPanUpdate: (d) {
                  if (!_resizing) return;
                  final delta = d.globalPosition - _resizeStart;
                  final newW = (_resizeStartSize.width + delta.dx).clamp(
                    _minW,
                    1400.0,
                  );
                  final newH = (_resizeStartSize.height + delta.dy).clamp(
                    _minH,
                    900.0,
                  );
                  setState(() => _size = Size(newW, newH));
                },
                onPanEnd: (_) => _resizing = false,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: Container(
                    width: _resizeHandleSize,
                    height: _resizeHandleSize,
                    decoration: BoxDecoration(color: Colors.transparent),
                    child: Icon(
                      Icons.open_in_full,
                      size: 10,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTitleBar(bool isDark, Color color, Color ambColor) {
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF0F2F5);
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA);

    return GestureDetector(
      onPanUpdate: (d) {
        final screen = MediaQuery.of(context).size;
        setState(() {
          _pos = Offset(
            (_pos.dx + d.delta.dx).clamp(0, screen.width - _size.width),
            (_pos.dy + d.delta.dy).clamp(0, screen.height - _titleH),
          );
        });
      },
      child: Container(
        height: _titleH,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: Row(
          children: [
            // Tipo icon
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                kTypeIcons[widget.objectType] ?? Icons.storage_outlined,
                size: 14,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            // Nombre
            Expanded(
              child: Text(
                widget.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Consolas',
                  color: isDark ? const Color(0xFFD4D4D4) : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Ambiente badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ambColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: ambColor.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Text(
                widget.ambiente,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: ambColor,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Minimizar
            _WinButton(
              icon: Icons.remove,
              tooltip: _minimized ? 'Restaurar' : 'Minimizar',
              onTap: _toggleMinimize,
              isDark: isDark,
            ),
            const SizedBox(width: 2),
            // Cerrar
            _WinButton(
              icon: Icons.close,
              tooltip: 'Cerrar',
              onTap: widget.onClose,
              isDark: isDark,
              isClose: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDark;
  final bool isClose;

  const _WinButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.isDark,
    this.isClose = false,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isClose
        ? Colors.red.shade600
        : (widget.isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0));
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _hovered ? hoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _hovered && widget.isClose
                  ? Colors.white
                  : (widget.isDark ? Colors.white60 : Colors.black54),
            ),
          ),
        ),
      ),
    );
  }
}
