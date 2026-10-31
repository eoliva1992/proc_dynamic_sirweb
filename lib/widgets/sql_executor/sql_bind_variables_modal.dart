import 'package:flutter/material.dart';
import '../constellation_background.dart';

/// Modal estilo PL/SQL Developer para ingresar valores de bind variables (`:variable`, `:gen.variable`).
///
/// Recuerda los últimos valores utilizados durante la sesión para agilizar re-ejecuciones.
class SqlBindVariablesModal extends StatefulWidget {
  final List<String> variables;
  final String statementPreview;
  final String ambiente;

  const SqlBindVariablesModal({
    super.key,
    required this.variables,
    required this.statementPreview,
    required this.ambiente,
  });

  /// Cache en memoria de los últimos valores y tipos asignados a cada variable.
  static final Map<String, ({String value, String type})> _sessionValues = {};

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<String> variables,
    required String statementPreview,
    required String ambiente,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SqlBindVariablesModal(
        variables: variables,
        statementPreview: statementPreview,
        ambiente: ambiente,
      ),
    );
  }

  @override
  State<SqlBindVariablesModal> createState() => _SqlBindVariablesModalState();
}

class _SqlBindVariablesModalState extends State<SqlBindVariablesModal> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _types = {};
  final _formKey = GlobalKey<FormState>();

  static const List<String> _tiposOracle = [
    'VARCHAR2',
    'NUMBER',
    'DATE',
    'TIMESTAMP',
  ];

  @override
  void initState() {
    super.initState();
    for (final v in widget.variables) {
      final cached = SqlBindVariablesModal._sessionValues[v.toUpperCase()];
      _controllers[v] = TextEditingController(text: cached?.value ?? '');
      _types[v] = cached?.type ?? 'VARCHAR2';
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onConfirm() {
    final result = <String, dynamic>{};
    for (final v in widget.variables) {
      final text = _controllers[v]?.text.trim() ?? '';
      final type = _types[v] ?? 'VARCHAR2';

      // Guardar en sesión
      SqlBindVariablesModal._sessionValues[v.toUpperCase()] = (
        value: text,
        type: type,
      );

      if (text.isEmpty) {
        result[v] = null;
        continue;
      }

      if (type == 'NUMBER') {
        final numVal = num.tryParse(text);
        result[v] = numVal ?? text;
      } else {
        result[v] = text;
      }
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? cs.surfaceContainerHigh : cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.6),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
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
              // ── Cabecera ───────────────────────────────────────────
              ConstellationHeader(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
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
                        isDark ? Colors.black : const Color(0xFF003D73),
                        0.38,
                      )!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
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
                        Icons.tune_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Variables de Entrada',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Asigna valores para las bind variables detectadas en la sentencia (${widget.ambiente})',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: Colors.white70,
                      tooltip: 'Cancelar ejecución',
                      splashRadius: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => Navigator.of(context).pop(null),
                    ),
                  ],
                ),
              ),

              // ── Preview de sentencia ───────────────────────────────
              if (widget.statementPreview.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.25)
                        : cs.surfaceContainerLowest,
                    border: Border(
                      bottom: BorderSide(
                        color: cs.outlineVariant.withValues(
                          alpha: isDark ? 0.3 : 0.5,
                        ),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.code_rounded,
                        size: 15,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.statementPreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Lista de variables ─────────────────────────────────
              Flexible(
                child: Form(
                  key: _formKey,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                    shrinkWrap: true,
                    itemCount: widget.variables.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final varName = widget.variables[index];
                      final ctrl = _controllers[varName]!;
                      final currentType = _types[varName] ?? 'VARCHAR2';

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? cs.surfaceContainerLowest.withValues(alpha: 0.5)
                              : cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(
                              alpha: isDark ? 0.25 : 0.6,
                            ),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Nombre de la variable
                            SizedBox(
                              width: 140,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      ':$varName',
                                      style: TextStyle(
                                        fontFamily: 'Consolas',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Selector de Tipo
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? cs.surfaceContainerHighest.withValues(
                                        alpha: 0.45,
                                      )
                                    : cs.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                  width: 0.8,
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: currentType,
                                  isDense: true,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                  items: [
                                    for (final t in _tiposOracle)
                                      DropdownMenuItem(
                                        value: t,
                                        child: Text(t),
                                      ),
                                  ],
                                  onChanged: (newVal) {
                                    if (newVal != null) {
                                      setState(() => _types[varName] = newVal);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Input de Valor
                            Expanded(
                              child: TextField(
                                controller: ctrl,
                                autofocus: index == 0,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface,
                                  fontFamily: 'Consolas',
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Valor (NULL si vacío)',
                                  hintStyle: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? cs.surfaceContainerHighest.withValues(
                                          alpha: 0.35,
                                        )
                                      : cs.surface,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: cs.outlineVariant,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: cs.outlineVariant.withValues(
                                        alpha: isDark ? 0.35 : 0.6,
                                      ),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: cs.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) {
                                  if (index == widget.variables.length - 1) {
                                    _onConfirm();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── Pie de página con botones ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        foregroundColor: cs.onSurfaceVariant,
                        side: BorderSide(
                          color: cs.outlineVariant.withValues(
                            alpha: isDark ? 0.5 : 0.8,
                          ),
                          width: 1.0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _onConfirm,
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: const Text(
                        'Ejecutar',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
}
