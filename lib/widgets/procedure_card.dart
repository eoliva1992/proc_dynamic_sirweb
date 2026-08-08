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

  const ProcedureCard({
    super.key,
    required this.procedimiento,
    required this.onTap,
    this.onOpenInNewTab,
  });

  @override
  State<ProcedureCard> createState() => _ProcedureCardState();
}

class _ProcedureCardState extends State<ProcedureCard> {
  bool _hovered = false;

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

  void _showContextMenu(TapUpDetails details) {
    final pos = details.globalPosition;
    showMenu<_CardAction>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final proc = widget.procedimiento;
    final configDesc = procedimientosProvider.descriptionForConfig(
      proc.inConfiguracion,
    );
    final dateText = _relativeDate(proc.feModificacion);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _hovered ? cs.surfaceContainerHigh : cs.surface,
        borderRadius: BorderRadius.circular(6),
        boxShadow: _hovered
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
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
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
                        Text(
                          proc.cdProcedimiento,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            fontFamily: 'Consolas',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (dateText.isNotEmpty) ...[
                              Icon(
                                Icons.access_time,
                                size: 11,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                dateText,
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

enum _CardAction { openInNewTab, copyName, copyAsCall }

class _VersionBadge extends StatelessWidget {
  final int version;
  const _VersionBadge({required this.version});

  @override
  Widget build(BuildContext context) {
    return Text(
      'v$version',
      style: const TextStyle(
        color: Color(0xFF569CD6),
        fontSize: 11,
        fontFamily: 'Consolas',
      ),
    );
  }
}

class _EstadoBadge extends StatelessWidget {
  final bool activo;
  const _EstadoBadge({required this.activo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: activo
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: activo ? Colors.green.shade700 : Colors.red.shade700,
          width: 0.5,
        ),
      ),
      child: Text(
        activo ? 'Activo' : 'Inactivo',
        style: TextStyle(
          color: activo ? Colors.green.shade400 : Colors.red.shade400,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
