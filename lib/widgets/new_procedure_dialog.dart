import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import '../providers/procedimientos_provider.dart';
import 'ambiente_selector.dart';
import 'config_badge.dart';
import 'constellation_background.dart';
import 'floating_window.dart';
import '_editor_themes.dart';

/// Resultado de la creación de un procedimiento dinámico.
typedef NuevoProcedimiento = ({
  String cdProcedimiento,
  String inConfiguracion,
  String ambiente,
});

/// Abre el alta de procedimiento dinámico como **ventana flotante**.
///
/// Igual que el resto de los modales de la app: se mueve arrastrando la barra
/// de título, se puede minimizar a la barra inferior, maximizar (F11) y aparece
/// y se cierra con animación. Completa con `null` si el usuario cancela.
Future<NuevoProcedimiento?> showNewProcedureDialog(
  BuildContext context, {
  required String ambiente,
}) {
  final done = Completer<NuevoProcedimiento?>();
  showFloatingWindow(
    context,
    (close) => NewProcedureDialog(
      ambiente: ambiente,
      onClose: (result) {
        close();
        if (!done.isCompleted) done.complete(result);
      },
    ),
  );
  return done.future;
}

class NewProcedureDialog extends StatefulWidget {
  final String ambiente;

  /// Cierra la ventana devolviendo el procedimiento creado (o `null`).
  final void Function(NuevoProcedimiento? result) onClose;

  const NewProcedureDialog({
    super.key,
    required this.ambiente,
    required this.onClose,
  });

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

  // ── Geometría de la ventana flotante ───────────────────────────────────────
  /// Alto de la barra de título en modo normal (reserva el hueco del header).
  static const double _kHeaderH = 66;

  /// Desplazamiento respecto del centro de la pantalla (arrastre).
  Offset _position = Offset.zero;
  double? _winW;
  double? _winH;
  bool _maximized = false;
  bool _minimized = false;
  int? _slot;

  /// Geometría previa, para restaurar al des-maximizar.
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;

  /// 180 ms al maximizar/minimizar; cero mientras se arrastra o redimensiona.
  Duration _anim = Duration.zero;

  void _toggleMaximized() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_maximized) {
        _winW = _restoreW;
        _winH = _restoreH;
        _position = _restorePos;
        _maximized = false;
      } else {
        _restoreW = _winW;
        _restoreH = _winH;
        _restorePos = _position;
        _position = Offset.zero;
        _maximized = true;
      }
    });
  }

  /// Minimiza la ventana a la barra inferior (o la restaura).
  void _toggleMinimized() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_minimized) {
        FloatingWindowSlots.release(_slot);
        _slot = null;
        _minimized = false;
      } else {
        _slot = FloatingWindowSlots.take();
        _minimized = true;
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _close([NuevoProcedimiento? result]) {
    FloatingWindowSlots.release(_slot);
    _slot = null;
    widget.onClose(result);
  }

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
      _close((
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
    final screen = MediaQuery.sizeOf(context);
    final gripColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.18,
    );

    if (_maximized) {
      _winW = (screen.width - 48).clamp(360.0, screen.width);
      _winH = (screen.height - 48).clamp(320.0, screen.height);
    } else {
      _winW ??= (screen.width * 0.9).clamp(560.0, 940.0);
      _winH ??= (screen.height * 0.88).clamp(420.0, 780.0);
    }
    if (_winW! > screen.width) _winW = screen.width;
    if (_winH! > screen.height) _winH = screen.height;

    // Geometría efectiva: minimizada ocupa solo la barra de título.
    final double w, h, left, top;
    if (_minimized) {
      w = FloatingWindowSlots.barW;
      h = FloatingWindowSlots.barH;
      final (l, t) = FloatingWindowSlots.offsetFor(_slot ?? 0, screen);
      left = l;
      top = t;
    } else {
      w = _winW!;
      h = _winH!;
      left = ((screen.width - w) / 2 + _position.dx).clamp(
        0.0,
        (screen.width - w).clamp(0.0, double.infinity),
      );
      top = ((screen.height - h) / 2 + _position.dy).clamp(
        0.0,
        (screen.height - h).clamp(0.0, double.infinity),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
        const SingleActivator(LogicalKeyboardKey.escape): () => _close(),
      },
      child: Focus(
        autofocus: !_minimized,
        canRequestFocus: !_minimized,
        descendantsAreFocusable: !_minimized,
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
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(
                      _maximized ? 6 : (_minimized ? 8 : 10),
                    ),
                    border: Border.all(color: cs.outlineVariant, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.5 : 0.22,
                        ),
                        blurRadius: _minimized ? 16 : 32,
                        offset: Offset(0, _minimized ? 4 : 12),
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
                    // El contenido se mantiene SIEMPRE montado con el tamaño
                    // de la ventana restaurada: al minimizar sólo se recorta.
                    // Si se quitara del árbol, el editor Monaco se destruiría
                    // y al restaurar se recargaría perdiendo lo escrito.
                    child: SizedBox(
                      width: _winW,
                      height: _winH,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Column(
                              children: [
                                // Hueco reservado para la barra de título.
                                const SizedBox(height: _kHeaderH),
                                _buildForm(isDark, cs),
                                Expanded(child: _buildCodeSection(isDark, cs)),
                                _buildFooter(isDark, cs),
                              ],
                            ),
                          ),
                          // La barra de título usa el ancho *visible* para que
                          // al minimizar siga viéndose completa.
                          Positioned(
                            left: 0,
                            top: 0,
                            width: w,
                            child: _buildHeader(isDark, cs),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Resize: borde derecho ─────────────────────────────────────
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 5,
                top: top + 64,
                width: 10,
                height: (h - 74).clamp(0.0, double.infinity),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(
                        560.0,
                        screen.width - 40,
                      );
                    }),
                  ),
                ),
              ),

            // ── Resize: borde inferior ────────────────────────────────────
            if (!_maximized && !_minimized)
              Positioned(
                left: left + 16,
                top: top + h - 5,
                width: (w - 32).clamp(0.0, double.infinity),
                height: 10,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winH = (_winH! + d.delta.dy).clamp(
                        420.0,
                        screen.height - 40,
                      );
                    }),
                  ),
                ),
              ),

            // ── Resize: esquina inferior derecha (grip) ───────────────────
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 18,
                top: top + h - 18,
                width: 22,
                height: 22,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(
                        560.0,
                        screen.width - 40,
                      );
                      _winH = (_winH! + d.delta.dy).clamp(
                        420.0,
                        screen.height - 40,
                      );
                    }),
                    child: CustomPaint(painter: WindowGripPainter(gripColor)),
                  ),
                ),
              ),
          ],
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

    // El doble clic (maximizar) se aplica sólo al área del título: si
    // envolviera también a los botones, el `onTap` de cada uno quedaría a la
    // espera del timeout del doble clic (~300 ms) antes de dispararse.
    Widget titleArea(Widget child) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _minimized ? _toggleMinimized : _toggleMaximized,
      child: child,
    );

    return MouseRegion(
      cursor: (_maximized || _minimized)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Arrastrar la barra de título mueve la ventana.
        onPanUpdate: (_maximized || _minimized)
            ? null
            : (d) => setState(() {
                _anim = Duration.zero;
                _position += d.delta;
              }),
        child: ConstellationHeader(
          height: _minimized ? FloatingWindowSlots.barH : _kHeaderH,
          padding: _minimized
              ? const EdgeInsets.fromLTRB(12, 0, 6, 0)
              : const EdgeInsets.fromLTRB(20, 0, 14, 0),
          decoration: BoxDecoration(color: headerBg),
          onDark: true,
          child: Row(
            children: [
              titleArea(
                Container(
                  padding: EdgeInsets.all(_minimized ? 5 : 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.post_add_rounded,
                    color: onHeader,
                    size: _minimized ? 14 : 20,
                  ),
                ),
              ),
              SizedBox(width: _minimized ? 8 : 14),
              if (_minimized)
                Expanded(
                  child: titleArea(
                    Text(
                      'Nuevo Procedimiento',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onHeader,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: titleArea(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Nuevo Procedimiento Dinámico',
                          overflow: TextOverflow.ellipsis,
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
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onHeader.withValues(alpha: 0.65),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Ambiente badge — prominently shows target DB
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
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
                            ? AmbienteSelector.colorForAmbiente(
                                _selectedAmbiente,
                              )
                            : Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _selectedAmbiente,
                        style: TextStyle(
                          color: isDark
                              ? AmbienteSelector.colorForAmbiente(
                                  _selectedAmbiente,
                                )
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
              ],
              // ── Controles de ventana ────────────────────────────────────
              _WinBtn(
                icon: _minimized
                    ? Icons.expand_less_rounded
                    : Icons.remove_rounded,
                tooltip: _minimized ? 'Restaurar' : 'Minimizar',
                color: onHeader,
                onTap: _toggleMinimized,
              ),
              _WinBtn(
                icon: _maximized
                    ? Icons.close_fullscreen_rounded
                    : Icons.open_in_full_rounded,
                tooltip: _maximized
                    ? 'Restaurar tamaño (F11)'
                    : 'Maximizar (F11)',
                size: 15,
                color: onHeader,
                onTap: () {
                  if (_minimized) {
                    _toggleMinimized();
                  } else {
                    _toggleMaximized();
                  }
                },
              ),
              _WinBtn(
                icon: Icons.close_rounded,
                tooltip: 'Cerrar (Esc)',
                color: onHeader,
                danger: true,
                onTap: _close,
              ),
            ],
          ),
        ),
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
                onPressed: _close,
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

/// Botón de control de ventana sobre la cabecera de color del modal.
///
/// No se usa [WindowButton] porque aquí el fondo es oscuro/azul y los iconos
/// deben heredar el color del header.
class _WinBtn extends StatefulWidget {
  const _WinBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
    this.size = 17,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  final double size;
  final bool danger;

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.danger
                        ? const Color(0xFFE81123)
                        : widget.color.withValues(alpha: 0.18))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: _hovered && widget.danger
                  ? Colors.white
                  : widget.color.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}
