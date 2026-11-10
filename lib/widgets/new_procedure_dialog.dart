import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import '../models/plantilla.dart';
import '../providers/procedimientos_provider.dart';
import '../services/editor_cursor_store.dart';
import '../services/plantilla_service.dart';
import 'ambiente_selector.dart';
import 'config_badge.dart';
import 'constellation_background.dart';
import 'floating_window.dart';
import 'monaco_snippets.dart' show insertMonacoSnippet;
import '_editor_themes.dart';

/// Pasos de la experiencia guiada (Wizard) para crear el procedimiento.
enum _WizardStep {
  /// Paso 1: Selección del Tipo de Configuración
  config,

  /// Paso 2: Selección de Inicio (En blanco vs Plantilla compatible)
  template,

  /// Paso 3: Editor de Regla de Negocio y Formulario Final
  editor,
}

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

  // ── Estado del Asistente Guiado (Wizard) ──────────────────────────────────
  _WizardStep _currentStep = _WizardStep.config;
  Plantilla? _selectedPlantilla;
  bool _startBlank = true;

  // ── Estado del Paso 1 (Filtro / Buscador de configuraciones) ──────────────
  final _configSearchCtrl = TextEditingController();
  String _configSearchQuery = '';

  // ── Estado del Paso 2 (Catálogo de plantillas) ────────────────────────────
  final _templateSearchCtrl = TextEditingController();
  String _templateSearchQuery = '';
  bool _templateIsListView = false;
  Future<List<Plantilla>>? _plantillasFuture;
  String? _plantillasFutureConfig;

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

  /// Sincroniza en tiempo real únicamente la línea donde se declara el nombre
  /// del procedimiento o la excepción, sin resetear la plantilla ni borrar el código.
  Future<void> _syncFunctionName() async {
    final ctrl = _editorCtrl;
    final currentText = ctrl != null ? await ctrl.document.getText() : _code;
    if (currentText.isEmpty) return;

    final rawName = _codigoCtrl.text.trim().toUpperCase();
    var cleanName = rawName;
    if (cleanName.endsWith('()')) {
      cleanName = cleanName.substring(0, cleanName.length - 2);
    }
    final targetName = cleanName.isEmpty ? 'NOMBRE_PROC' : cleanName;

    // 1. PL/SQL: línea de excepción :P_ERROR := '... EN ' || W_STAT
    //    o asignación de error con el nombre del procedimiento
    final plsqlErrorPattern = RegExp(
      r":P_ERROR\s*:=\s*'([^']*)(\s+EN\s+['\s\|]*W_STAT|\s*\*\*)",
      caseSensitive: false,
    );

    // 2. PL/SQL DDL: CREATE [OR REPLACE] PROCEDURE <name> ... END <name>;
    final createProcPattern = RegExp(
      r'^((\s*CREATE(\s+OR\s+REPLACE)?\s+PROCEDURE\s+)[A-Za-z0-9_\$#]+)',
      multiLine: true,
      caseSensitive: false,
    );
    final endProcPattern = RegExp(
      r'(\bEND\s+)[A-Za-z0-9_\$#]+(\s*;)',
      caseSensitive: false,
    );

    // 3. JavaScript: function <name>() ...
    final jsFuncPattern = RegExp(
      r'^((\s*function\s+)[A-Za-z0-9_\$]+)(\s*\([^)]*\))',
      multiLine: true,
    );
    final jsCatchPattern = RegExp(
      r"(console\.error\(\s*')[^']+(:')",
      caseSensitive: false,
    );
    final jsAlertPattern = RegExp(
      r"(alert\(\s*'Error\s+en\s+)[^':]+(:)",
      caseSensitive: false,
    );

    var updated = currentText;

    if (plsqlErrorPattern.hasMatch(updated)) {
      updated = updated.replaceAllMapped(plsqlErrorPattern, (m) {
        final suffix = m.group(2) ?? '';
        return ":P_ERROR := '$targetName$suffix";
      });
    }

    if (createProcPattern.hasMatch(updated)) {
      updated = updated.replaceAllMapped(createProcPattern, (m) {
        final prefix = m.group(2) ?? '';
        return '$prefix$targetName';
      });
      if (endProcPattern.hasMatch(updated)) {
        updated = updated.replaceAllMapped(endProcPattern, (m) {
          final prefix = m.group(1) ?? 'END ';
          final suffix = m.group(2) ?? ';';
          return '$prefix$targetName$suffix';
        });
      }
    }

    if (jsFuncPattern.hasMatch(updated)) {
      updated = updated.replaceAllMapped(jsFuncPattern, (m) {
        final prefix = m.group(2) ?? 'function ';
        final params = m.group(3) ?? '()';
        return '$prefix$targetName$params';
      });
      if (jsCatchPattern.hasMatch(updated)) {
        updated = updated.replaceAllMapped(jsCatchPattern, (m) {
          final prefix = m.group(1) ?? "console.error('";
          final suffix = m.group(2) ?? ":'";
          return '$prefix$targetName$suffix';
        });
      }
      if (jsAlertPattern.hasMatch(updated)) {
        updated = updated.replaceAllMapped(jsAlertPattern, (m) {
          final prefix = m.group(1) ?? "alert('Error en ";
          final suffix = m.group(2) ?? ":";
          return '$prefix$targetName$suffix';
        });
      }
    }

    if (updated != currentText) {
      _code = updated;
      if (ctrl != null) {
        await ctrl.document.setText(updated);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedAmbiente = widget.ambiente;
    _codigoCtrl.addListener(_syncFunctionName);
    editorThemeStore.addListener(_onEditorThemeChanged);
    editorCursorStore.addListener(_onEditorCursorChanged);
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
    _configSearchCtrl.dispose();
    _templateSearchCtrl.dispose();
    editorThemeStore.removeListener(_onEditorThemeChanged);
    editorCursorStore.removeListener(_onEditorCursorChanged);
    super.dispose();
  }

  void _onEditorThemeChanged() {
    _editorCtrl?.setTheme(editorThemeStore.monacoTheme);
  }

  void _onEditorCursorChanged() {
    _editorCtrl?.updateOptions(
      EditorOptions(cursorStyle: editorCursorStore.cursorStyle),
    );
  }

  void _onConfigChanged(String cfg) {
    final isJs = _isJsConfig(cfg);
    final template = _templateFor(cfg);
    final lang = isJs ? MonacoLanguage.javascript : MonacoLanguage.sql;
    setState(() {
      _selectedConfig = cfg;
      // Invalida el future de plantillas si cambió la configuración
      _plantillasFuture = null;
      _plantillasFutureConfig = null;
      // Si la plantilla actualmente seleccionada no es compatible con el nuevo tipo, resetearla
      if (_selectedPlantilla != null &&
          !_selectedPlantilla!.esCompatibleConConfig(isJs: isJs)) {
        _selectedPlantilla = null;
        _startBlank = true;
      }
      if (_editorCtrl == null) _code = template;
    });
    _editorCtrl?.document.setLanguage(lang);
    _editorCtrl?.document.setText(template);
  }

  /// Aplica la plantilla seleccionada o el boilerplate base al editor
  Future<void> _aplicarPlantillaOBase() async {
    final isJs = _isJsConfig(_selectedConfig);
    final lang = isJs ? MonacoLanguage.javascript : MonacoLanguage.sql;
    final procName = _codigoCtrl.text.trim().isEmpty
        ? 'P_NOMBRE_PROC'
        : _codigoCtrl.text.trim().toUpperCase();
    final user = _usuarioCtrl.text.trim().isEmpty
        ? 'USUARIO'
        : _usuarioCtrl.text.trim().toUpperCase();

    String targetCode;
    if (_startBlank || _selectedPlantilla == null) {
      targetCode = _templateFor(_selectedConfig);
      if (_editorCtrl != null) {
        await _editorCtrl!.document.setLanguage(lang);
        await _editorCtrl!.document.setText(targetCode);
      } else {
        setState(() => _code = targetCode);
      }
    } else {
      final snippetCode = _selectedPlantilla!.prepararParaInsercionSnippet(
        nombreObjeto: procName,
        usuario: user,
      );
      if (_editorCtrl != null) {
        await _editorCtrl!.document.setLanguage(lang);
        await _editorCtrl!.document.setText('');
        await insertMonacoSnippet(_editorCtrl!, snippetCode);
      } else {
        targetCode = _selectedPlantilla!.aplicarParametros(
          nombreObjeto: procName,
          usuario: user,
        );
        setState(() => _code = targetCode);
      }
    }
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
                  child: _minimized
                      ? MinimizedWindowCard(
                          title: 'Nuevo Procedimiento',
                          icon: Icons.add_circle_outline_rounded,
                          accentColor: const Color(0xFF0E8A4E),
                          badge: 'NUEVO',
                          onRestore: _toggleMinimized,
                          onClose: _close,
                        )
                      : OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: 0,
                          maxWidth: double.infinity,
                          minHeight: 0,
                          maxHeight: double.infinity,
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
                                      // Barra de navegación de pasos (Stepper)
                                      _buildWizardStepper(isDark, cs),
                                      Expanded(
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeInCubic,
                                          child: _buildCurrentStepView(
                                            isDark,
                                            cs,
                                          ),
                                        ),
                                      ),
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

  // ── Stepper Header ───────────────────────────────────────────────────────

  Widget _buildWizardStepper(bool isDark, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStepPill(
                    step: _WizardStep.config,
                    number: '1',
                    label: 'Configuración',
                    icon: Icons.tune_rounded,
                    isDark: isDark,
                    cs: cs,
                  ),
                  _buildStepDivider(
                    isDark,
                    cs,
                    active: _currentStep.index >= 1,
                  ),
                  _buildStepPill(
                    step: _WizardStep.template,
                    number: '2',
                    label: 'Plantilla / Base',
                    icon: Icons.auto_awesome_motion_rounded,
                    isDark: isDark,
                    cs: cs,
                  ),
                  _buildStepDivider(
                    isDark,
                    cs,
                    active: _currentStep.index >= 2,
                  ),
                  _buildStepPill(
                    step: _WizardStep.editor,
                    number: '3',
                    label: 'Editor y Creación',
                    icon: Icons.code_rounded,
                    isDark: isDark,
                    cs: cs,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Indicador de modo actual
          if (_currentStep == _WizardStep.editor)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConfigBadge(config: _selectedConfig, small: true),
                  const SizedBox(width: 6),
                  Text(
                    _startBlank
                        ? 'En blanco'
                        : (_selectedPlantilla?.nombre ?? 'Plantilla'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepDivider(
    bool isDark,
    ColorScheme cs, {
    required bool active,
  }) {
    return Container(
      width: 28,
      height: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: active
          ? (isDark ? cs.primary : const Color(0xFF0078D4))
          : cs.outlineVariant.withValues(alpha: 0.5),
    );
  }

  Widget _buildStepPill({
    required _WizardStep step,
    required String number,
    required String label,
    required IconData icon,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final isActive = _currentStep == step;
    final isDone = _currentStep.index > step.index;
    final primaryColor = isDark ? cs.primary : const Color(0xFF0078D4);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: isDone ? () => setState(() => _currentStep = step) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? primaryColor.withValues(alpha: 0.14)
              : (isDone
                    ? cs.onSurface.withValues(alpha: 0.05)
                    : Colors.transparent),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? primaryColor
                : (isDone
                      ? cs.outlineVariant
                      : cs.outlineVariant.withValues(alpha: 0.4)),
            width: isActive ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? primaryColor
                    : (isDone
                          ? const Color(0xFF107C10)
                          : cs.onSurfaceVariant.withValues(alpha: 0.2)),
              ),
              child: isDone
                  ? const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white,
                    )
                  : Text(
                      number,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : cs.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? primaryColor
                    : (isDone ? cs.onSurface : cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Switcher de Vistas del Wizard ─────────────────────────────────────────

  Widget _buildCurrentStepView(bool isDark, ColorScheme cs) {
    switch (_currentStep) {
      case _WizardStep.config:
        return _buildStepConfigView(isDark, cs);
      case _WizardStep.template:
        return _buildStepTemplateView(isDark, cs);
      case _WizardStep.editor:
        return _buildStepEditorView(isDark, cs);
    }
  }

  // ── PASO 1: Selección del Tipo de Configuración ────────────────────────────

  Widget _buildStepConfigView(bool isDark, ColorScheme cs) {
    final configs = procedimientosProvider.configuraciones;
    final allItems = configs.isEmpty
        ? _kFallbackConfigs
        : configs.map((c) => (c.cdModulo, c.deArgumento)).toList();

    final q = _configSearchQuery.trim().toLowerCase();
    final filteredItems = q.isEmpty
        ? allItems
        : allItems.where((it) {
            final code = it.$1.toLowerCase();
            final name = it.$2.toLowerCase();
            return code.contains(q) || name.contains(q);
          }).toList();

    return Column(
      key: const ValueKey('step_config'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner introductorio
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.tune_rounded, color: cs.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paso 1: Selecciona el Tipo de Configuración',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Determina el motor de ejecución, sintaxis (PL/SQL vs JavaScript) y contexto de la regla de negocio.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.8),
        // Barra de búsqueda de configuraciones
        _buildConfigSearchBar(
          isDark,
          cs,
          filteredItems.length,
          allItems.length,
        ),
        const Divider(height: 1, thickness: 0.8),
        // Grid de tarjetas de configuración o Estado Vacío
        Expanded(
          child: filteredItems.isEmpty
              ? _buildConfigEmptyState(cs, isDark)
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 280,
                          mainAxisExtent: 116,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final (code, name) = filteredItems[index];
                      final isSelected = _selectedConfig == code;
                      final isJs = _isJsConfig(code);
                      final badgeColor = ConfigBadge.colorForConfig(code);

                      return _ConfigCard(
                        code: code,
                        name: name,
                        isSelected: isSelected,
                        isJs: isJs,
                        badgeColor: badgeColor,
                        isDark: isDark,
                        cs: cs,
                        onTap: () => _onConfigChanged(code),
                        onDoubleTap: () {
                          _onConfigChanged(code);
                          setState(() => _currentStep = _WizardStep.template);
                        },
                      );
                    },
                  ),
                ),
        ),
        // Footer del paso 1
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              TextButton(
                onPressed: _close,
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: const Text('Cancelar'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _currentStep = _WizardStep.template);
                },
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text(
                  'Siguiente: Elegir Plantilla',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0078D4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Barra de búsqueda para el paso 1 (Configuraciones) ────────────────────

  Widget _buildConfigSearchBar(
    bool isDark,
    ColorScheme cs,
    int count,
    int total,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _configSearchCtrl,
                style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                decoration: InputDecoration(
                  hintText:
                      'Buscar configuración por código o nombre (ej. D, Dato, JavaScript)...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  suffixIcon: _configSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            _configSearchCtrl.clear();
                            setState(() => _configSearchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? cs.surface : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                      color: Color(0xFF0078D4),
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (val) {
                  setState(() => _configSearchQuery = val);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Contador de configuraciones
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.filter_alt_outlined,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  _configSearchQuery.trim().isEmpty
                      ? '$total tipos'
                      : '$count de $total',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigEmptyState(ColorScheme cs, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 36,
                color: cs.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No se encontraron configuraciones',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ninguna opción coincide con "$_configSearchQuery"',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                _configSearchCtrl.clear();
                setState(() => _configSearchQuery = '');
              },
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Restablecer búsqueda'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PASO 2: Selección de Inicio (En blanco vs Plantilla compatible) ────────

  Widget _buildStepTemplateView(bool isDark, ColorScheme cs) {
    final isJs = _isJsConfig(_selectedConfig);
    final langTitle = isJs ? 'JavaScript' : 'PL/SQL (Oracle)';

    if (_plantillasFuture == null ||
        _plantillasFutureConfig != _selectedConfig) {
      _plantillasFutureConfig = _selectedConfig;
      _plantillasFuture = PlantillaService.instance.loadParaConfiguracion(
        isJs: isJs,
      );
    }

    return Column(
      key: const ValueKey('step_template'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner informativo superior
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      (isJs ? const Color(0xFFF7DF1E) : const Color(0xFF0078D4))
                          .withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isJs ? Icons.javascript_rounded : Icons.terminal_rounded,
                  color: isJs
                      ? (isDark
                            ? const Color(0xFFF7DF1E)
                            : const Color(0xFFB78103))
                      : const Color(0xFF0078D4),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paso 2: Catálogo de Plantillas para $_selectedConfig ($langTitle)',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Explora las plantillas disponibles o inicia en blanco con vista previa de código en tiempo real.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.8),

        // Cuerpo: Layout Master-Detail (Catálogo a la izquierda, Preview a la derecha)
        Expanded(
          child: FutureBuilder<List<Plantilla>>(
            future: _plantillasFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final allPlantillas = snapshot.data ?? [];
              final q = _templateSearchQuery.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? allPlantillas
                  : allPlantillas.where((p) {
                      return p.nombre.toLowerCase().contains(q) ||
                          (p.descripcion ?? '').toLowerCase().contains(q);
                    }).toList();

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Panel Izquierdo: Catálogo y Buscador ────────────────
                  Expanded(
                    flex: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: cs.outlineVariant,
                            width: 0.8,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Barra de búsqueda y alternador de vista (Cards / Lista)
                          _buildTemplateSearchBar(isDark, cs, filtered.length),
                          const Divider(height: 1, thickness: 0.8),
                          // Listado / Grid del catálogo
                          Expanded(
                            child: _templateIsListView
                                ? _buildTemplateListView(
                                    filtered: filtered,
                                    isJs: isJs,
                                    isDark: isDark,
                                    cs: cs,
                                  )
                                : _buildTemplateGridView(
                                    filtered: filtered,
                                    isJs: isJs,
                                    isDark: isDark,
                                    cs: cs,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Panel Derecho: Vista Previa del Código en Tiempo Real ──
                  Expanded(
                    flex: 5,
                    child: _buildTemplatePreviewPanel(
                      isJs: isJs,
                      isDark: isDark,
                      cs: cs,
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // Footer del paso 2
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _currentStep = _WizardStep.config);
                },
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Atrás (Tipo)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Resumen de la selección activa en el footer
              Flexible(
                child: Text(
                  _startBlank
                      ? 'Opción activa: Crear en blanco (estructura base)'
                      : 'Plantilla seleccionada: ${_selectedPlantilla?.nombre ?? ""}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  setState(() => _currentStep = _WizardStep.editor);
                  await _aplicarPlantillaOBase();
                },
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text(
                  'Continuar al Editor',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0078D4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Barra de búsqueda y selector de vista para el catálogo ────────────────

  Widget _buildTemplateSearchBar(bool isDark, ColorScheme cs, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _templateSearchCtrl,
                style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: 'Buscar plantilla por nombre o descripción...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  suffixIcon: _templateSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            _templateSearchCtrl.clear();
                            setState(() => _templateSearchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? cs.surface : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                      color: Color(0xFF0078D4),
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (val) {
                  setState(() => _templateSearchQuery = val);
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Contador de plantillas
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count ${count == 1 ? "opción" : "opciones"}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botón alternador Cuadrícula / Lista
          Tooltip(
            message: _templateIsListView
                ? 'Cambiar a vista de Tarjetas'
                : 'Cambiar a vista de Lista detallada',
            child: InkWell(
              onTap: () {
                setState(() => _templateIsListView = !_templateIsListView);
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(6),
                  color: isDark ? cs.surface : Colors.white,
                ),
                child: Icon(
                  _templateIsListView
                      ? Icons.grid_view_rounded
                      : Icons.view_headline_rounded,
                  size: 18,
                  color: const Color(0xFF0078D4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Vista en Cuadrícula (Cards) ───────────────────────────────────────────

  Widget _buildTemplateGridView({
    required List<Plantilla> filtered,
    required bool isJs,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: GridView(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisExtent: 136,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        children: [
          // Tarjeta destacada 1: Comenzar en blanco
          _TemplateCard(
            title: 'Comenzar en blanco',
            description: isJs
                ? 'Estructura mínima con jQuery.ready() y función declarada.'
                : 'Bloque estándar PL/SQL con variable W_STAT y manejo de excepciones.',
            badgeText: isJs ? 'JS BASE' : 'PL/SQL BASE',
            badgeColor: isJs
                ? const Color(0xFFF7DF1E)
                : const Color(0xFF0078D4),
            icon: Icons.note_add_outlined,
            isSelected: _startBlank,
            isDark: isDark,
            cs: cs,
            onTap: () {
              setState(() {
                _startBlank = true;
                _selectedPlantilla = null;
              });
            },
            onDoubleTap: () async {
              setState(() {
                _startBlank = true;
                _selectedPlantilla = null;
                _currentStep = _WizardStep.editor;
              });
              await _aplicarPlantillaOBase();
            },
          ),
          // Plantillas compatibles filtradas
          ...filtered.map((p) {
            final isSelected = !_startBlank && _selectedPlantilla?.id == p.id;
            return _TemplateCard(
              title: p.nombre,
              description:
                  p.descripcion ??
                  'Plantilla compatible de procedimiento dinámico.',
              badgeText: p.monacoLanguage.toUpperCase(),
              badgeColor: p.monacoLanguage == 'javascript'
                  ? const Color(0xFFF7DF1E)
                  : const Color(0xFF0E8A4E),
              icon: Icons.auto_awesome_motion_rounded,
              isSelected: isSelected,
              isDark: isDark,
              cs: cs,
              onTap: () {
                setState(() {
                  _startBlank = false;
                  _selectedPlantilla = p;
                });
              },
              onDoubleTap: () async {
                setState(() {
                  _startBlank = false;
                  _selectedPlantilla = p;
                  _currentStep = _WizardStep.editor;
                });
                await _aplicarPlantillaOBase();
              },
            );
          }),
        ],
      ),
    );
  }

  // ── Vista en Lista Detallada (Estilo Explorador) ──────────────────────────

  Widget _buildTemplateListView({
    required List<Plantilla> filtered,
    required bool isJs,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      children: [
        // Fila 1: Comenzar en blanco
        _TemplateListItem(
          title: 'Comenzar en blanco',
          description: isJs
              ? 'Estructura mínima estándar con jQuery.ready()'
              : 'Bloque estándar PL/SQL con control de excepciones W_STAT',
          badgeText: isJs ? 'JS BASE' : 'PL/SQL BASE',
          badgeColor: isJs ? const Color(0xFFF7DF1E) : const Color(0xFF0078D4),
          icon: Icons.note_add_outlined,
          author: 'Sistema',
          isSelected: _startBlank,
          isDark: isDark,
          cs: cs,
          onTap: () {
            setState(() {
              _startBlank = true;
              _selectedPlantilla = null;
            });
          },
          onDoubleTap: () async {
            setState(() {
              _startBlank = true;
              _selectedPlantilla = null;
              _currentStep = _WizardStep.editor;
            });
            await _aplicarPlantillaOBase();
          },
        ),
        const SizedBox(height: 6),
        // Elementos de la lista
        ...filtered.map((p) {
          final isSelected = !_startBlank && _selectedPlantilla?.id == p.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _TemplateListItem(
              title: p.nombre,
              description: p.descripcion ?? 'Sin descripción adicional.',
              badgeText: p.monacoLanguage.toUpperCase(),
              badgeColor: p.monacoLanguage == 'javascript'
                  ? const Color(0xFFF7DF1E)
                  : const Color(0xFF0E8A4E),
              icon: Icons.auto_awesome_motion_rounded,
              author: p.ownerUser,
              version: p.version,
              isSelected: isSelected,
              isDark: isDark,
              cs: cs,
              onTap: () {
                setState(() {
                  _startBlank = false;
                  _selectedPlantilla = p;
                });
              },
              onDoubleTap: () async {
                setState(() {
                  _startBlank = false;
                  _selectedPlantilla = p;
                  _currentStep = _WizardStep.editor;
                });
                await _aplicarPlantillaOBase();
              },
            ),
          );
        }),
      ],
    );
  }

  // ── Panel Derecho: Vista Previa del Código en Tiempo Real ─────────────────

  Widget _buildTemplatePreviewPanel({
    required bool isJs,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final codePreview = _startBlank || _selectedPlantilla == null
        ? _templateFor(_selectedConfig)
        : _selectedPlantilla!.contenido;

    final title = _startBlank || _selectedPlantilla == null
        ? 'Estructura Base en Blanco'
        : _selectedPlantilla!.nombre;

    final description = _startBlank || _selectedPlantilla == null
        ? (isJs
              ? 'Plantilla mínima boilerplate con inicialización jQuery y función declarada.'
              : 'Bloque anónimo PL/SQL estándar con declaración de W_STAT y canal de error :P_ERROR.')
        : (_selectedPlantilla!.descripcion?.isNotEmpty == true
              ? _selectedPlantilla!.descripcion!
              : 'Plantilla de negocio preconfigurada.');

    final langBadge = isJs ? 'JAVASCRIPT' : 'PL/SQL';
    final langColor = isJs ? const Color(0xFFF7DF1E) : const Color(0xFF0078D4);

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9FAFB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera del Preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? cs.surfaceContainerLow
                  : cs.surfaceContainerLowest,
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant, width: 0.8),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.code_rounded,
                            size: 16,
                            color: const Color(0xFF0078D4),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'VISTA PREVIA DEL CÓDIGO',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: const Color(0xFF0078D4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: langColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              langBadge,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: langColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Botón de copiar vista previa
                Tooltip(
                  message: 'Copiar código al portapapeles',
                  child: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(8),
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: codePreview));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Código copiado al portapapeles'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Descripción de la plantilla
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark
                ? cs.surfaceContainerLowest.withValues(alpha: 0.5)
                : const Color(0xFFF3F4F6),
            child: Text(
              description,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1, thickness: 0.8),

          // Visualizador de Código
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                codePreview,
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  height: 1.45,
                  color: isDark
                      ? const Color(0xFFD4D4D4)
                      : const Color(0xFF1E1E1E),
                ),
              ),
            ),
          ),

          // Footer de la vista previa con acción directa
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? cs.surfaceContainerLow
                  : cs.surfaceContainerLowest,
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 0.8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  'Doble clic en la opción o pulsa "Continuar al Editor"',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── PASO 3: Editor de Regla de Negocio y Formulario Final ───────────────────

  Widget _buildStepEditorView(bool isDark, ColorScheme cs) {
    return Column(
      key: const ValueKey('step_editor'),
      children: [
        _buildForm(isDark, cs),
        Expanded(child: _buildCodeSection(isDark, cs)),
        _buildFooter(isDark, cs),
      ],
    );
  }

  // ── Form section ─────────────────────────────────────────────────────────

  Widget _buildForm(bool isDark, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Form(
        key: _formKey,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _buildCodigoField(cs)),
            const SizedBox(width: 14),
            Expanded(flex: 3, child: _buildConfigPillSelector(isDark, cs)),
            const SizedBox(width: 14),
            Expanded(flex: 2, child: _buildUsuarioField(cs)),
            const SizedBox(width: 14),
            _buildAmbienteField(isDark, cs),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigPillSelector(bool isDark, ColorScheme cs) {
    final configs = procedimientosProvider.configuraciones;
    final items = configs.isEmpty
        ? _kFallbackConfigs
        : configs.map((c) => (c.cdModulo, c.deArgumento)).toList();

    final selectedItem =
        items.where((item) => item.$1 == _selectedConfig).firstOrNull ??
        items.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: _label('Tipo de configuración', required: true)),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => setState(() => _currentStep = _WizardStep.config),
              borderRadius: BorderRadius.circular(4),
              child: Text(
                'Cambiar',
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? cs.primary : const Color(0xFF0078D4),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        MenuAnchor(
          alignmentOffset: const Offset(0, 4),
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(
              isDark ? cs.surfaceContainerHigh : cs.surface,
            ),
            elevation: const WidgetStatePropertyAll(12),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
          menuChildren: items.map((item) {
            final (code, label) = item;
            final active = _selectedConfig == code;
            final color = ConfigBadge.colorForConfig(code);
            return MenuItemButton(
              onPressed: () => _onConfigChanged(code),
              leadingIcon: ConfigBadge(config: code, small: true),
              trailingIcon: active
                  ? Icon(Icons.check_rounded, size: 16, color: color)
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 160),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? color : cs.onSurface,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
          builder: (context, controller, child) {
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cs.onSurface.withValues(alpha: 0.04),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8.5,
                    horizontal: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: cs.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: controller.isOpen ? cs.primary : cs.outlineVariant,
                      width: controller.isOpen ? 1.5 : 1.0,
                    ),
                  ),
                  suffixIcon: Icon(
                    controller.isOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 20,
                  ),
                ),
                child: Row(
                  children: [
                    ConfigBadge(config: selectedItem.$1, small: true),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedItem.$2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
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

  // ── Code section ─────────────────────────────────────────────────────────

  Widget _buildCodeSection(bool isDark, ColorScheme cs) {
    final isJs = _isJsConfig(_selectedConfig);
    final langLabel = isJs ? 'JavaScript' : 'SQL / PL/SQL';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Professional IDE Section Header Toolbar
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainer,
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.7),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            children: [
              // Indicador de sintaxis y estado
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isJs
                      ? (isDark
                            ? const Color(0xFFF7DF1E).withValues(alpha: 0.15)
                            : const Color(0xFFFFF8E1))
                      : (isDark
                            ? const Color(0xFF0078D4).withValues(alpha: 0.15)
                            : const Color(0xFFE3F2FD)),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: isJs
                        ? (isDark
                              ? const Color(0xFFF7DF1E).withValues(alpha: 0.4)
                              : const Color(0xFFFFB300))
                        : (isDark
                              ? const Color(0xFF0078D4).withValues(alpha: 0.4)
                              : const Color(0xFF90CAF9)),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isJs
                            ? (isDark
                                  ? const Color(0xFFF7DF1E)
                                  : const Color(0xFFF57F17))
                            : const Color(0xFF0078D4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      langLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: isJs
                            ? (isDark
                                  ? const Color(0xFFF7DF1E)
                                  : const Color(0xFFB78103))
                            : (isDark
                                  ? const Color(0xFF64B5F6)
                                  : const Color(0xFF0053A6)),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Chip informativo de plantilla activa
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _startBlank
                          ? Icons.note_outlined
                          : Icons.bookmark_added_rounded,
                      size: 13,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _startBlank
                          ? 'En blanco'
                          : (_selectedPlantilla?.nombre ?? 'Plantilla activa'),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Botón profesional para cambiar de plantilla
              _buildPlantillaSelectorBtn(cs, isDark),
              const SizedBox(width: 8),
              // Botón de restablecer
              Tooltip(
                message:
                    'Restablecer código al contenido base o plantilla seleccionada',
                child: TextButton.icon(
                  onPressed: _aplicarPlantillaOBase,
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text(
                    'Restablecer',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Monaco editor
        Expanded(
          child: _editorReady
              ? MonacoEditor(
                  initialText: _code,
                  options: EditorOptions(
                    language: isJs
                        ? MonacoLanguage.javascript
                        : MonacoLanguage.sql,
                    theme: editorThemeStore.monacoTheme,
                    fontSize: 13,
                    cursorStyle: editorCursorStore.cursorStyle,
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
                    // Inicializar con la plantilla o boilerplate seleccionado en el wizard
                    await _aplicarPlantillaOBase();
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

  Widget _buildPlantillaSelectorBtn(ColorScheme cs, bool isDark) {
    final isJs = _isJsConfig(_selectedConfig);
    return FutureBuilder<List<Plantilla>>(
      future: PlantillaService.instance.loadParaConfiguracion(isJs: isJs),
      builder: (context, snapshot) {
        final plantillas = snapshot.data ?? [];

        return MenuAnchor(
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(
              isDark ? cs.surfaceContainerHigh : cs.surface,
            ),
            elevation: const WidgetStatePropertyAll(16),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 6),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
          menuChildren: [
            // Opción en blanco
            MenuItemButton(
              onPressed: () async {
                setState(() {
                  _startBlank = true;
                  _selectedPlantilla = null;
                });
                await _aplicarPlantillaOBase();
              },
              leadingIcon: Icon(
                Icons.note_add_outlined,
                size: 16,
                color: _startBlank
                    ? (isDark ? cs.primary : const Color(0xFF0078D4))
                    : cs.onSurfaceVariant,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 220),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Comenzar en blanco (Base)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _startBlank
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: _startBlank
                              ? (isDark ? cs.primary : const Color(0xFF0078D4))
                              : cs.onSurface,
                        ),
                      ),
                    ),
                    if (_startBlank)
                      Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: isDark ? cs.primary : const Color(0xFF0078D4),
                      ),
                  ],
                ),
              ),
            ),
            if (plantillas.isNotEmpty) const Divider(height: 8),
            // Plantillas compatibles
            ...plantillas.map((p) {
              final active = !_startBlank && _selectedPlantilla?.id == p.id;
              return MenuItemButton(
                onPressed: () async {
                  setState(() {
                    _startBlank = false;
                    _selectedPlantilla = p;
                  });
                  await _aplicarPlantillaOBase();
                },
                leadingIcon: Icon(
                  Icons.auto_awesome_motion_rounded,
                  size: 16,
                  color: active
                      ? (isDark ? cs.primary : const Color(0xFF0078D4))
                      : cs.onSurfaceVariant,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 220),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              p.nombre,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: active
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: active
                                    ? (isDark
                                          ? cs.primary
                                          : const Color(0xFF0078D4))
                                    : cs.onSurface,
                              ),
                            ),
                            if (p.descripcion != null &&
                                p.descripcion!.isNotEmpty)
                              Text(
                                p.descripcion!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (active)
                        Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: isDark ? cs.primary : const Color(0xFF0078D4),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
          builder: (context, controller, child) {
            return FilledButton.tonalIcon(
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              icon: const Icon(Icons.style_rounded, size: 14),
              label: Text(
                _startBlank
                    ? 'Plantilla: En blanco'
                    : 'Plantilla: ${_selectedPlantilla?.nombre ?? 'Elegir'}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary.withValues(alpha: 0.12),
                foregroundColor: isDark ? cs.primary : const Color(0xFF0053A6),
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                    color: cs.primary.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
              ),
            );
          },
        );
      },
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
  ('D', 'Dato'),
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

/// Tarjeta visual seleccionable para el Paso 1 (Tipo de Configuración)
class _ConfigCard extends StatefulWidget {
  final String code;
  final String name;
  final bool isSelected;
  final bool isJs;
  final Color badgeColor;
  final bool isDark;
  final ColorScheme cs;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _ConfigCard({
    required this.code,
    required this.name,
    required this.isSelected,
    required this.isJs,
    required this.badgeColor,
    required this.isDark,
    required this.cs,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  State<_ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends State<_ConfigCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isDark
        ? widget.cs.primary
        : const Color(0xFF0078D4);
    final borderColor = widget.isSelected
        ? activeColor
        : (_hovered
              ? activeColor.withValues(alpha: 0.5)
              : widget.cs.outlineVariant.withValues(alpha: 0.6));

    final bgColor = widget.isSelected
        ? activeColor.withValues(alpha: widget.isDark ? 0.16 : 0.08)
        : (_hovered
              ? widget.cs.onSurface.withValues(alpha: 0.04)
              : widget.cs.surface);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: widget.isSelected ? 1.8 : 1.0,
            ),
            boxShadow: [
              if (widget.isSelected || _hovered)
                BoxShadow(
                  color: activeColor.withValues(
                    alpha: widget.isSelected ? 0.16 : 0.08,
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ConfigBadge(config: widget.code, small: true),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: widget.isSelected
                            ? (widget.isDark
                                  ? widget.cs.primary
                                  : const Color(0xFF0053A6))
                            : widget.cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      color: activeColor,
                      size: 18,
                    ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isJs
                          ? const Color(0xFFF7DF1E).withValues(alpha: 0.18)
                          : const Color(0xFF0078D4).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.isJs ? 'MOTOR JS' : 'PL/SQL',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: widget.isJs
                            ? (widget.isDark
                                  ? const Color(0xFFF7DF1E)
                                  : const Color(0xFFB78103))
                            : (widget.isDark
                                  ? const Color(0xFF64B5F6)
                                  : const Color(0xFF0053A6)),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Doble clic para avanzar',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: widget.cs.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta visual seleccionable para el Paso 2 (Modo de Inicio / Plantillas)
class _TemplateCard extends StatefulWidget {
  final String title;
  final String description;
  final String badgeText;
  final Color badgeColor;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final ColorScheme cs;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _TemplateCard({
    required this.title,
    required this.description,
    required this.badgeText,
    required this.badgeColor,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.cs,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isDark
        ? widget.cs.primary
        : const Color(0xFF0078D4);
    final borderColor = widget.isSelected
        ? activeColor
        : (_hovered
              ? activeColor.withValues(alpha: 0.5)
              : widget.cs.outlineVariant.withValues(alpha: 0.6));

    final bgColor = widget.isSelected
        ? activeColor.withValues(alpha: widget.isDark ? 0.16 : 0.08)
        : (_hovered
              ? widget.cs.onSurface.withValues(alpha: 0.04)
              : widget.cs.surface);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: widget.isSelected ? 1.8 : 1.0,
            ),
            boxShadow: [
              if (widget.isSelected || _hovered)
                BoxShadow(
                  color: activeColor.withValues(
                    alpha: widget.isSelected ? 0.16 : 0.08,
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: widget.badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: widget.badgeColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: widget.isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: widget.isSelected
                                ? (widget.isDark
                                      ? widget.cs.primary
                                      : const Color(0xFF0053A6))
                                : widget.cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: widget.badgeColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.badgeText,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: widget.badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      color: activeColor,
                      size: 18,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                widget.description,
                style: TextStyle(
                  fontSize: 11,
                  color: widget.cs.onSurfaceVariant,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Elemento en lista detallada tipo explorador para el Paso 2
class _TemplateListItem extends StatefulWidget {
  final String title;
  final String description;
  final String badgeText;
  final Color badgeColor;
  final IconData icon;
  final String? author;
  final int? version;
  final bool isSelected;
  final bool isDark;
  final ColorScheme cs;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _TemplateListItem({
    required this.title,
    required this.description,
    required this.badgeText,
    required this.badgeColor,
    required this.icon,
    this.author,
    this.version,
    required this.isSelected,
    required this.isDark,
    required this.cs,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  State<_TemplateListItem> createState() => _TemplateListItemState();
}

class _TemplateListItemState extends State<_TemplateListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isDark
        ? widget.cs.primary
        : const Color(0xFF0078D4);
    final borderColor = widget.isSelected
        ? activeColor
        : (_hovered
              ? activeColor.withValues(alpha: 0.4)
              : widget.cs.outlineVariant.withValues(alpha: 0.6));

    final bgColor = widget.isSelected
        ? activeColor.withValues(alpha: widget.isDark ? 0.16 : 0.08)
        : (_hovered
              ? widget.cs.onSurface.withValues(alpha: 0.04)
              : (widget.isDark ? widget.cs.surface : Colors.white));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: widget.isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: widget.badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(widget.icon, size: 16, color: widget.badgeColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: widget.isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: widget.isSelected
                                  ? (widget.isDark
                                        ? widget.cs.primary
                                        : const Color(0xFF0053A6))
                                  : widget.cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.version != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            'v${widget.version}',
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.cs.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (widget.author != null && widget.author!.isNotEmpty) ...[
                Text(
                  widget.author!,
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.badgeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.badgeText,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: widget.badgeColor,
                  ),
                ),
              ),
              if (widget.isSelected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, color: activeColor, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
