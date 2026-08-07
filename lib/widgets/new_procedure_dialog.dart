import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import '../providers/procedimientos_provider.dart';
import 'ambiente_selector.dart';
import 'config_badge.dart';
import '_editor_themes.dart';

class NewProcedureDialog extends StatefulWidget {
  final String ambiente;
  const NewProcedureDialog({super.key, required this.ambiente});

  @override
  State<NewProcedureDialog> createState() => _NewProcedureDialogState();
}

class _NewProcedureDialogState extends State<NewProcedureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();
  final _usuarioCtrl = TextEditingController();
  String _selectedConfig = 'D';
  late String _selectedAmbiente;
  String _code = _kDefaultCode;
  bool _editorReady = false;
  MonacoController? _editorCtrl;

  static const _kDefaultCode =
      'BEGIN\n'
      '  DECLARE\n'
      "    W_STAT VARCHAR2(5) := '0';\n"
      '  BEGIN\n'
      '    -- Tu código aquí\n'
      '    NULL;\n'
      '  EXCEPTION\n'
      '    WHEN OTHERS THEN\n'
      "      :P_ERROR := 'NOMBRE_PROC EN ' || W_STAT || ' ** ' || SQLERRM;\n"
      '  END;\n'
      'END;';

  // Generates the PL/SQL template inserting the current procedure code in the exception handler
  String _plsqlTemplateFor() {
    final name = _codigoCtrl.text.trim().isEmpty
        ? 'NOMBRE_PROC'
        : _codigoCtrl.text.trim().toUpperCase();
    return 'BEGIN\n'
        '  DECLARE\n'
        "    W_STAT VARCHAR2(5) := '0';\n"
        '  BEGIN\n'
        '    -- Tu código aquí\n'
        '    NULL;\n'
        '  EXCEPTION\n'
        '    WHEN OTHERS THEN\n'
        "      :P_ERROR := '$name EN ' || W_STAT || ' ** ' || SQLERRM;\n"
        '  END;\n'
        'END;';
  }

  // Generates the JS template with procedure name as both the ready() call and the declaration
  String _jsTemplateFor() {
    var name = _codigoCtrl.text.trim().toUpperCase();
    // Strip trailing () if the user typed them in the code field
    if (name.endsWith('()')) name = name.substring(0, name.length - 2);
    if (name.isEmpty) name = 'NOMBRE_PROC';
    return 'jQuery(document).ready(function () {\n\n});\nfunction $name() {\n  try {\n\n  } catch (e) {\n    console.error(\'$name:\', e);\n    alert(\'Error en $name: \' + e.message);\n  }\n}';
  }

  // Checks provider configs (or fallback) to determine if a config type uses JavaScript
  bool _isJsConfig(String cfg) {
    final providerConfigs = procedimientosProvider.configuraciones;
    if (providerConfigs.isNotEmpty) {
      final match = providerConfigs.where((c) => c.cdModulo == cfg).firstOrNull;
      if (match != null) {
        return match.deArgumento.toLowerCase().contains('javascript');
      }
    }
    return _kFallbackConfigs
            .where((item) => item.$1 == cfg)
            .firstOrNull
            ?.$2
            .toLowerCase()
            .contains('javascript') ??
        false;
  }

  String _templateFor(String cfg) =>
      _isJsConfig(cfg) ? _jsTemplateFor() : _plsqlTemplateFor();

  // Updates the full template in the editor as the user types the procedure code
  void _syncFunctionName() {
    final ctrl = _editorCtrl;
    if (ctrl == null) return;
    unawaited(ctrl.document.setText(_templateFor(_selectedConfig)));
  }

  @override
  void initState() {
    super.initState();
    _selectedAmbiente = widget.ambiente;
    _codigoCtrl.addListener(_syncFunctionName);
    editorThemeStore.addListener(_onEditorThemeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final u = procedimientosProvider.cdUsuario;
      if (u.isNotEmpty) _usuarioCtrl.text = u;
    });
    // Two frames ensure WebView2/DWM is ready before the editor mounts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _editorReady = true);
      });
    });
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _usuarioCtrl.dispose();
    editorThemeStore.removeListener(_onEditorThemeChanged);
    super.dispose();
  }

  void _onEditorThemeChanged() {
    _editorCtrl?.setTheme(editorThemeStore.monacoTheme);
  }

  void _onConfigChanged(String cfg) {
    final template = _templateFor(cfg);
    final lang = _isJsConfig(cfg)
        ? MonacoLanguage.javascript
        : MonacoLanguage.sql;
    setState(() {
      _selectedConfig = cfg;
      if (_editorCtrl == null) _code = template;
    });
    _editorCtrl?.document.setLanguage(lang);
    _editorCtrl?.document.setText(template);
  }

  Future<void> _crear() async {
    if (!_formKey.currentState!.validate()) return;
    final code = _editorCtrl != null
        ? await _editorCtrl!.document.getText()
        : _code;
    final provider = procedimientosProvider;
    final cdProc = _codigoCtrl.text.trim().toUpperCase();
    provider.setAmbiente(_selectedAmbiente);
    final ok = await provider.crear(
      cdProcedimiento: cdProc,
      deTexto: code,
      inConfiguracion: _selectedConfig,
      cdUsuario: _usuarioCtrl.text.trim(),
    );
    if (ok && mounted) {
      provider.setCdUsuario(_usuarioCtrl.text.trim());
      Navigator.of(context).pop((
        cdProcedimiento: cdProc,
        inConfiguracion: _selectedConfig,
        ambiente: _selectedAmbiente,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 940,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(isDark, cs),
              _buildForm(isDark, cs),
              Expanded(child: _buildCodeSection(isDark, cs)),
              _buildFooter(isDark, cs),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark, ColorScheme cs) {
    final headerBg = isDark
        ? cs.surfaceContainerHighest
        : const Color(0xFF0053A6);
    final onHeader = isDark ? cs.onSurface : Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 14, 15),
      color: headerBg,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.post_add_rounded, color: onHeader, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Nuevo Procedimiento Dinámico',
                style: TextStyle(
                  color: onHeader,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Completa los datos e ingresa el código inicial',
                style: TextStyle(
                  color: onHeader.withValues(alpha: 0.65),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Ambiente badge — prominently shows target DB
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark
                  ? AmbienteSelector.colorForAmbiente(
                      _selectedAmbiente,
                    ).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDark
                    ? AmbienteSelector.colorForAmbiente(
                        _selectedAmbiente,
                      ).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storage_rounded,
                  size: 13,
                  color: isDark
                      ? AmbienteSelector.colorForAmbiente(_selectedAmbiente)
                      : Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  _selectedAmbiente,
                  style: TextStyle(
                    color: isDark
                        ? AmbienteSelector.colorForAmbiente(_selectedAmbiente)
                        : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: onHeader.withValues(alpha: 0.7),
            ),
            style: IconButton.styleFrom(
              minimumSize: const Size(36, 36),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  // ── Form section ─────────────────────────────────────────────────────────

  Widget _buildForm(bool isDark, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildCodigoField(cs)),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: _buildConfigSelector(isDark, cs)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildUsuarioField(cs)),
                const SizedBox(width: 16),
                _buildAmbienteField(isDark, cs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodigoField(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Código del procedimiento', required: true),
        const SizedBox(height: 6),
        TextFormField(
          controller: _codigoCtrl,
          style: TextStyle(
            color: cs.onSurface,
            fontFamily: 'Consolas',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
          decoration: _deco(cs, Icons.code_rounded, hint: 'P.EJ_MI_PROC'),
          textCapitalization: TextCapitalization.characters,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Requerido';
            if (v.trim().length > 30) return 'Máximo 30 caracteres';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildUsuarioField(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Usuario', required: true),
        const SizedBox(height: 6),
        TextFormField(
          controller: _usuarioCtrl,
          style: TextStyle(color: cs.onSurface, fontSize: 13),
          decoration: _deco(cs, Icons.person_outline_rounded, hint: 'USUARIO'),
          textCapitalization: TextCapitalization.characters,
          validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
        ),
      ],
    );
  }

  Widget _buildAmbienteField(bool isDark, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Base de datos'),
        const SizedBox(height: 6),
        SizedBox(
          height: 42,
          child: AmbienteSelector(
            value: _selectedAmbiente,
            onChanged: (v) => setState(() => _selectedAmbiente = v),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigSelector(bool isDark, ColorScheme cs) {
    final configs = procedimientosProvider.configuraciones;
    final items = configs.isEmpty
        ? _kFallbackConfigs
        : configs.map((c) => (c.cdModulo, c.deArgumento)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Tipo de configuración', required: true),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _selectedConfig,
          isExpanded: true,
          dropdownColor: isDark ? cs.surfaceContainerHigh : cs.surface,
          icon: Icon(
            Icons.expand_more_rounded,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.onSurface.withValues(alpha: 0.04),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: cs.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
          ),
          selectedItemBuilder: (_) => items.map((item) {
            final (code, label) = item;
            return Row(
              children: [
                ConfigBadge(config: code, small: true),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }).toList(),
          items: items.map((item) {
            final (code, label) = item;
            final active = _selectedConfig == code;
            final color = ConfigBadge.colorForConfig(code);
            return DropdownMenuItem(
              value: code,
              child: Row(
                children: [
                  ConfigBadge(config: code, small: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: active ? color : cs.onSurface,
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (active) Icon(Icons.check_rounded, size: 14, color: color),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) => v != null ? _onConfigChanged(v) : null,
        ),
      ],
    );
  }

  // ── Code section ─────────────────────────────────────────────────────────

  Widget _buildCodeSection(bool isDark, ColorScheme cs) {
    final langLabel = _isJsConfig(_selectedConfig)
        ? 'JavaScript'
        : 'SQL / PL/SQL';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header bar
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainer,
          child: Row(
            children: [
              Icon(Icons.code_rounded, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Código inicial',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  langLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  final template = _templateFor(_selectedConfig);
                  _editorCtrl?.document.setText(template);
                  if (_editorCtrl == null) setState(() => _code = template);
                },
                icon: const Icon(Icons.refresh_rounded, size: 13),
                label: const Text('Restaurar', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        // Monaco editor
        Expanded(
          child: _editorReady
              ? MonacoEditor(
                  initialText: _kDefaultCode,
                  options: EditorOptions(
                    language: _isJsConfig(_selectedConfig)
                        ? MonacoLanguage.javascript
                        : MonacoLanguage.sql,
                    theme: editorThemeStore.monacoTheme,
                    fontSize: 13,
                    lineNumbers: MonacoLineNumbers.on,
                    minimap: const MonacoMinimapOptions(enabled: false),
                    wordWrap: MonacoWordWrap.off,
                    tabSize: 2,
                    bracketPairColorization: true,
                  ),
                  onReady: (ctrl) async {
                    _editorCtrl = ctrl;
                    await EditorThemeStore.defineAllThemes(ctrl);
                    await ctrl.setTheme(editorThemeStore.monacoTheme);
                    // Apply correct template/language if JS config was set before editor was ready
                    if (_isJsConfig(_selectedConfig)) {
                      await ctrl.document.setText(_jsTemplateFor());
                      await ctrl.document.setLanguage(
                        MonacoLanguage.javascript,
                      );
                    }
                  },
                  onContentChanged: (text) => _code = text,
                  onError: (err, _) => debugPrint('Dialog editor error: $err'),
                )
              : Container(
                  color: isDark
                      ? const Color(0xFF1A1A2E)
                      : const Color(0xFFFAFAFA),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────────

  Widget _buildFooter(bool isDark, ColorScheme cs) {
    return Observer(
      builder: (context) {
        final provider = procedimientosProvider;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: BoxDecoration(
            color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              if (provider.error != null)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 15,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.error!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: provider.cargando ? null : _crear,
                icon: provider.cargando
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_rounded, size: 16),
                label: Text(
                  provider.cargando ? 'Creando...' : 'Crear Procedimiento',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF107C10),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _label(String text, {bool required = false}) {
    final cs = Theme.of(context).colorScheme;
    return RichText(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
        children: required
            ? const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ]
            : null,
      ),
    );
  }

  InputDecoration _deco(ColorScheme cs, IconData icon, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
        fontSize: 12,
      ),
      prefixIcon: Icon(icon, size: 16, color: cs.onSurfaceVariant),
      filled: true,
      fillColor: cs.onSurface.withValues(alpha: 0.04),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }
}

const _kFallbackConfigs = <(String, String)>[
  ('D', 'Delphi'),
  ('J', 'JavaScript'),
  ('A', 'Acción'),
  ('G', 'Global'),
  ('S', 'Siniestro'),
  ('C', 'Cotización'),
  ('F', 'Financiero'),
  ('T', 'Técnico'),
  ('V', 'Vigencia'),
  ('O', 'Otro'),
  ('I', 'Integración'),
];
