import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/procedimientos_provider.dart';
import 'constellation_background.dart';

/// Abre el diálogo de identificación de usuario para Sirweb.
///
/// Permite capturar y normalizar `cdUsuario` para la atribución de
/// operaciones, guardado y compilación en Oracle.
Future<void> showUsuarioDialog(
  BuildContext context, {
  VoidCallback? onSaved,
  String? initialValue,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'usuario',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 240),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return ScaleTransition(
        scale: curved,
        child: FadeTransition(opacity: anim, child: child),
      );
    },
    pageBuilder: (ctx, _, _) {
      return UsuarioDialog(onSaved: onSaved, initialValue: initialValue);
    },
  );
}

/// Diálogo modal con diseño Constellation y paleta adaptativa de tema
/// para la configuración del código de usuario (`cdUsuario`).
class UsuarioDialog extends StatefulWidget {
  final VoidCallback? onSaved;
  final String? initialValue;

  const UsuarioDialog({super.key, this.onSaved, this.initialValue});

  @override
  State<UsuarioDialog> createState() => _UsuarioDialogState();
}

class _UsuarioDialogState extends State<UsuarioDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue ?? procedimientosProvider.cdUsuario,
    );
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _save(String rawValue) {
    final trimmed = rawValue.trim();
    procedimientosProvider.setCdUsuario(trimmed);
    Navigator.of(context).pop();
    if (trimmed.isNotEmpty) {
      widget.onSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isEmptyInitial =
        (widget.initialValue ?? procedimientosProvider.cdUsuario)
            .trim()
            .isEmpty;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? cs.surfaceContainerHigh : cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.outlineVariant.withValues(
                    alpha: isDark ? 0.35 : 0.6,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Cabecera con constelación y gradiente de tema ──
                      ConstellationHeader(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 10, 10, 16),
                        onDark: true,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              cs.primary,
                              Color.lerp(
                                    cs.primary,
                                    isDark
                                        ? Colors.black
                                        : const Color(0xFF003D73),
                                    0.38,
                                  ) ??
                                  cs.primary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                color: Colors.white70,
                                tooltip: 'Cerrar',
                                splashRadius: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                            Center(
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    width: 1.8,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.badge_rounded,
                                  size: 26,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Identificación de Usuario',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Código para registrar autoría y cambios en Sirweb',
                              textAlign: TextAlign.center,
                              softWrap: true,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Cuerpo del formulario ───────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isEmptyInitial) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (isDark
                                              ? Colors.amber.shade900
                                              : Colors.amber.shade50)
                                          .withValues(
                                            alpha: isDark ? 0.35 : 0.8,
                                          ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        (isDark
                                                ? Colors.amber.shade700
                                                : Colors.amber.shade300)
                                            .withValues(alpha: 0.6),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 15,
                                      color: isDark
                                          ? Colors.amber.shade200
                                          : Colors.amber.shade900,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Requerido para guardar, compilar o activar procedimientos.',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.amber.shade100
                                              : Colors.amber.shade900,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'CÓDIGO DE USUARIO',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'MAYÚSCULAS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _controller,
                              autofocus: true,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [
                                TextInputFormatter.withFunction(
                                  (old, val) => val.copyWith(
                                    text: val.text.toUpperCase(),
                                    selection: val.selection,
                                  ),
                                ),
                              ],
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Ej: EOLIVA',
                                hintStyle: TextStyle(
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.45,
                                  ),
                                  fontWeight: FontWeight.normal,
                                  letterSpacing: 0.5,
                                ),
                                prefixIcon: Icon(
                                  Icons.badge_outlined,
                                  size: 18,
                                  color: cs.primary,
                                ),
                                suffixIcon: _controller.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.clear_rounded,
                                          size: 16,
                                        ),
                                        tooltip: 'Borrar texto',
                                        onPressed: () {
                                          _controller.clear();
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: isDark
                                    ? cs.surfaceContainerHighest.withValues(
                                        alpha: 0.45,
                                      )
                                    : cs.surfaceContainerLowest,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: cs.outlineVariant,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: cs.outlineVariant.withValues(
                                      alpha: isDark ? 0.45 : 0.7,
                                    ),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: cs.primary,
                                    width: 1.8,
                                  ),
                                ),
                              ),
                              onSubmitted: _save,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Se registrará en el historial de versiones del procedimiento.',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Botones de acción ───────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  foregroundColor: cs.onSurfaceVariant,
                                  side: BorderSide(
                                    color: cs.outlineVariant.withValues(
                                      alpha: isDark ? 0.5 : 0.8,
                                    ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  'Cancelar',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _save(_controller.text),
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: const Text(
                                  'Guardar',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: cs.primary,
                                  foregroundColor: cs.onPrimary,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
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
            ),
          ),
        ),
      ),
    );
  }
}
