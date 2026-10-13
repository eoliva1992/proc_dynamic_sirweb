import 'package:flutter/material.dart';

import '../../models/note.dart';
import '../../services/note_service.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart' show showFloatingDialog;

/// Shows the sharing dialog for [note] and returns once it's closed.
///
/// Lists current shares (if the caller can share, i.e. is the owner) and
/// lets the owner add/modify/revoke per-user permissions (ReadOnly/Edit).
Future<void> showShareNoteDialog(
  BuildContext context, {
  required Note note,
  required String currentUser,
}) {
  return showFloatingDialog<void>(
    context,
    (dialogContext, close) =>
        ShareNoteDialog(note: note, currentUser: currentUser, close: close),
  );
}

class ShareNoteDialog extends StatefulWidget {
  final Note note;
  final String currentUser;
  final void Function([void]) close;

  const ShareNoteDialog({
    super.key,
    required this.note,
    required this.currentUser,
    required this.close,
  });

  @override
  State<ShareNoteDialog> createState() => _ShareNoteDialogState();
}

class _NewGrantRow {
  final TextEditingController userController = TextEditingController();
  NotePermission permission = NotePermission.readOnly;

  void dispose() => userController.dispose();
}

class _ShareNoteDialogState extends State<ShareNoteDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _updatingUser;
  String? _revokingUser;
  String? _error;
  List<NoteShare> _shares = const [];
  final List<_NewGrantRow> _newGrants = [_NewGrantRow()];

  @override
  void initState() {
    super.initState();
    NoteService.registerCloser(widget.close);
    _loadShares();
  }

  @override
  void dispose() {
    NoteService.unregisterCloser(widget.close);
    for (final row in _newGrants) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadShares({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final shares = await NoteService.instance.listShares(
        widget.note.id,
        ownerUser: widget.currentUser,
      );
      if (!mounted) return;
      setState(() {
        _shares = shares;
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

  Future<void> _updatePermission(
    NoteShare share,
    NotePermission newPerm,
  ) async {
    if (share.permission == newPerm) return;
    setState(() {
      _updatingUser = share.sharedWithUser;
      // Actualización inmediata por coincidencia de usuario (independiente de referencia de objeto)
      _shares = _shares.map((s) {
        if (s.sharedWithUser.trim().toLowerCase() ==
            share.sharedWithUser.trim().toLowerCase()) {
          return NoteShare(
            noteId: s.noteId,
            sharedWithUser: s.sharedWithUser,
            permission: newPerm,
            sharedBy: s.sharedBy,
            sharedAt: s.sharedAt,
          );
        }
        return s;
      }).toList();
    });
    try {
      await NoteService.instance.share(
        widget.note.id,
        ownerUser: widget.currentUser,
        grants: {share.sharedWithUser: newPerm},
      );
      AppToast.success(
        'Permiso de ${share.sharedWithUser} actualizado a ${newPerm == NotePermission.edit ? "Edición" : "Solo lectura"}',
      );
      await _loadShares(silent: true);
    } catch (e) {
      AppToast.error('No se pudo actualizar el permiso: $e');
      await _loadShares(silent: true);
    } finally {
      if (mounted) setState(() => _updatingUser = null);
    }
  }

  Future<void> _revoke(NoteShare share) async {
    setState(() => _revokingUser = share.sharedWithUser);
    try {
      await NoteService.instance.revokeShare(
        widget.note.id,
        ownerUser: widget.currentUser,
        targetUser: share.sharedWithUser,
      );
      AppToast.success('Acceso revocado para ${share.sharedWithUser}');
      await _loadShares(silent: true);
    } catch (e) {
      AppToast.error('No se pudo revocar: $e');
    } finally {
      if (mounted) setState(() => _revokingUser = null);
    }
  }

  Future<void> _applyNewGrants() async {
    final grants = <String, NotePermission>{};
    for (final row in _newGrants) {
      final user = row.userController.text.trim();
      if (user.isEmpty) continue;
      grants[user] = row.permission;
    }
    if (grants.isEmpty) {
      AppToast.warning('Ingresá al menos un usuario para compartir');
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await NoteService.instance.share(
        widget.note.id,
        ownerUser: widget.currentUser,
        grants: grants,
      );
      if (!mounted) return;
      if (result.aplicados.isNotEmpty) {
        AppToast.success(
          'Compartido con: '
          '${result.aplicados.map((a) => a.user).join(', ')}',
        );
      }
      if (result.omitidos.isNotEmpty) {
        AppToast.warning('Omitidos: ${result.omitidos.join(', ')}');
      }
      setState(() {
        for (final row in _newGrants) {
          row.dispose();
        }
        _newGrants
          ..clear()
          ..add(_NewGrantRow());
      });
      await _loadShares();
    } catch (e) {
      AppToast.error('No se pudo compartir: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 540,
          constraints: const BoxConstraints(maxHeight: 640),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E22) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
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
              // Header elegante
              ConstellationHeader(
                height: 56,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF26262B)
                      : const Color(0xFFF6F8FA),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                ),
                onDark: isDark,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 18,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Compartir nota',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1F2328),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              widget.note.title.trim().isEmpty
                                  ? 'Nota sin título'
                                  : widget.note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Cerrar (Esc)',
                        onPressed: () => widget.close(),
                      ),
                    ],
                  ),
                ),
              ),

              // Contenido scrolleable
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Encabezado de sección: Accesos actuales
                      Row(
                        children: [
                          Icon(
                            Icons.group_outlined,
                            size: 16,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Accesos actuales',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.90)
                                  : Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          if (!_loading && _shares.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_shares.length} ${_shares.length == 1 ? "usuario" : "usuarios"}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildSharesList(cs, isDark),

                      const SizedBox(height: 20),
                      Divider(
                        height: 1,
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                      const SizedBox(height: 18),

                      // Encabezado de sección: Invitar usuarios
                      Row(
                        children: [
                          Icon(
                            Icons.person_add_outlined,
                            size: 16,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Invitar usuarios',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.90)
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      ..._newGrants.asMap().entries.map((entry) {
                        return _buildNewGrantRow(
                          entry.key,
                          entry.value,
                          cs,
                          isDark,
                        );
                      }),

                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _newGrants.add(_NewGrantRow())),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Agregar otro usuario'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Barra de acciones inferior
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF222226)
                      : const Color(0xFFF8F9FA),
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => widget.close(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                      child: const Text('Cerrar'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _saving ? null : _applyNewGrants,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 15),
                      label: Text(
                        _saving ? 'Compartiendo...' : 'Compartir accesos',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
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

  Widget _buildSharesList(ColorScheme cs, bool isDark) {
    if (_loading) {
      return Container(
        height: 90,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'Cargando accesos compartidos...',
              style: TextStyle(fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.red,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              tooltip: 'Reintentar',
              onPressed: _loadShares,
            ),
          ],
        ),
      );
    }

    if (_shares.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black12,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 20,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Esta nota es privada. Todavía no la has compartido con nadie.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181B) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _shares.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
        itemBuilder: (context, index) {
          final share = _shares[index];
          final isUpdating = _updatingUser == share.sharedWithUser;
          final isRevoking = _revokingUser == share.sharedWithUser;
          final initial = share.sharedWithUser.trim().isNotEmpty
              ? share.sharedWithUser.trim()[0].toUpperCase()
              : '?';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Avatar con inicial
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primary.withValues(alpha: 0.16),
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Nombre de usuario y badge de permiso actual
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              share.sharedWithUser,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Tag / Badge con color distintivo de permiso
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: share.permission == NotePermission.edit
                                  ? (isDark
                                        ? Colors.amber.shade900.withValues(
                                            alpha: 0.35,
                                          )
                                        : Colors.amber.shade50)
                                  : (isDark
                                        ? Colors.blue.shade900.withValues(
                                            alpha: 0.35,
                                          )
                                        : Colors.blue.shade50),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: share.permission == NotePermission.edit
                                    ? (isDark
                                          ? Colors.amber.shade600.withValues(
                                              alpha: 0.5,
                                            )
                                          : Colors.amber.shade300)
                                    : (isDark
                                          ? Colors.blue.shade600.withValues(
                                              alpha: 0.5,
                                            )
                                          : Colors.blue.shade300),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  share.permission == NotePermission.edit
                                      ? Icons.edit_note_rounded
                                      : Icons.visibility_outlined,
                                  size: 11,
                                  color: share.permission == NotePermission.edit
                                      ? (isDark
                                            ? Colors.amber.shade300
                                            : Colors.amber.shade900)
                                      : (isDark
                                            ? Colors.blue.shade300
                                            : Colors.blue.shade900),
                                ),
                                const SizedBox(width: 3.5),
                                Text(
                                  share.permission == NotePermission.edit
                                      ? 'Edición'
                                      : 'Lectura',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        share.permission == NotePermission.edit
                                        ? (isDark
                                              ? Colors.amber.shade300
                                              : Colors.amber.shade900)
                                        : (isDark
                                              ? Colors.blue.shade300
                                              : Colors.blue.shade900),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (share.sharedAt != null)
                        Text(
                          'Compartida el ${_formatShareDate(share.sharedAt!)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Selector de permiso interactivo (Modificar acceso)
                if (isUpdating)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  _buildPermissionSelector(
                    value: share.permission,
                    isDark: isDark,
                    enabled: !isUpdating && !isRevoking,
                    onChanged: (newVal) => _updatePermission(share, newVal),
                  ),
                const SizedBox(width: 8),
                // Botón revocar
                if (isRevoking)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.redAccent,
                    ),
                  )
                else
                  Tooltip(
                    message: 'Revocar acceso de ${share.sharedWithUser}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _revoke(share),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.person_remove_outlined,
                          size: 17,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewGrantRow(
    int index,
    _NewGrantRow row,
    ColorScheme cs,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // Campo usuario
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: row.userController,
                decoration: InputDecoration(
                  hintText: 'Usuario de red (ej. JUANP)',
                  hintStyle: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: const Icon(
                    Icons.alternate_email_rounded,
                    size: 16,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF26262B)
                      : const Color(0xFFF1F3F5),
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
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Selector permiso
          _buildPermissionSelector(
            value: row.permission,
            isDark: isDark,
            enabled: !_saving,
            onChanged: (val) {
              setState(() => row.permission = val);
            },
          ),
          if (_newGrants.length > 1) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
              tooltip: 'Quitar fila',
              color: isDark ? Colors.white54 : Colors.black45,
              onPressed: () {
                setState(() {
                  row.dispose();
                  _newGrants.removeAt(index);
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionSelector({
    required NotePermission value,
    required ValueChanged<NotePermission> onChanged,
    required bool isDark,
    bool enabled = true,
  }) {
    final isReadOnly = value == NotePermission.readOnly;
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141417) : const Color(0xFFE9ECEF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegmentOption(
            selected: isReadOnly,
            label: 'Lectura',
            icon: Icons.visibility_outlined,
            isDark: isDark,
            enabled: enabled,
            onTap: () {
              if (enabled && !isReadOnly) onChanged(NotePermission.readOnly);
            },
          ),
          _buildSegmentOption(
            selected: !isReadOnly,
            label: 'Edición',
            icon: Icons.edit_outlined,
            isDark: isDark,
            enabled: enabled,
            onTap: () {
              if (enabled && isReadOnly) onChanged(NotePermission.edit);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentOption({
    required bool selected,
    required String label,
    required IconData icon,
    required bool isDark,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final activeBg = isDark ? const Color(0xFF2C2C32) : Colors.white;
    final activeColor = isDark ? Colors.white : const Color(0xFF1F2328);
    final inactiveColor = isDark ? Colors.white54 : Colors.black54;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? activeColor : inactiveColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatShareDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}
