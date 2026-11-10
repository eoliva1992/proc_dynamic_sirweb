import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;
import '../models/plantilla.dart';
import '../providers/procedimientos_provider.dart';
import '../services/plantilla_service.dart';
import 'ambiente_selector.dart';
import 'constellation_background.dart';
import 'floating_window.dart';

/// Tipo de objeto seleccionable en el paso 1 del asistente.
enum NewObjectType {
  function(
    id: 'function',
    category: Plantilla.catFunction,
    label: 'Nueva Función',
    subtitle: 'Función determinista o escalar con valor de retorno',
    icon: Icons.functions_rounded,
    badgeColor: Color(0xFF5C2D91),
  ),
  procedure(
    id: 'procedure',
    category: Plantilla.catProcedure,
    label: 'Nuevo Procedimiento',
    subtitle: 'Procedimiento almacenado estándar PL/SQL de base de datos',
    icon: Icons.terminal_rounded,
    badgeColor: Color(0xFF107C41),
  ),
  dynamicProcedure(
    id: 'dynamic_procedure',
    category: Plantilla.catProcDinamico,
    label: 'Nuevo Procedimiento Dinámico',
    subtitle: 'Regla de negocio, validación o cálculo del motor SirWeb',
    icon: Icons.flash_on_rounded,
    badgeColor: Color(0xFF0078D4),
    isSpecialFlow: true,
  ),
  package(
    id: 'package',
    category: Plantilla.catPackage,
    label: 'Nuevo Package',
    subtitle: 'Especificación y cuerpo de paquete PL/SQL modular',
    icon: Icons.folder_zip_rounded,
    badgeColor: Color(0xFF8E44AD),
  ),
  trigger(
    id: 'trigger',
    category: Plantilla.catTrigger,
    label: 'Nuevo Trigger',
    subtitle: 'Disparador automático asociado a eventos de tabla (DML)',
    icon: Icons.bolt_rounded,
    badgeColor: Color(0xFFFF8C00),
  ),
  type(
    id: 'type',
    category: Plantilla.catType,
    label: 'Nuevo Type',
    subtitle: 'Tipo de dato objeto Oracle compuesto o estructurado',
    icon: Icons.category_rounded,
    badgeColor: Color(0xFF0288D1),
  ),
  blankSql(
    id: 'blank_sql',
    category: 'SQL_BLANK',
    label: 'Documento en blanco (SQL)',
    subtitle: 'Hoja limpia para consultas libres o scripts Ad-hoc',
    icon: Icons.dataset_outlined,
    badgeColor: Color(0xFF607D8B),
    isBlankDirect: true,
  );

  final String id;
  final String category;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color badgeColor;
  final bool isSpecialFlow;
  final bool isBlankDirect;

  const NewObjectType({
    required this.id,
    required this.category,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.badgeColor,
    this.isSpecialFlow = false,
    this.isBlankDirect = false,
  });
}

/// Resultado de la selección en el diálogo de nuevo objeto.
sealed class NewObjectResult {
  const NewObjectResult();
}

/// Abre directamente el diálogo de procedimiento dinámico SirWeb.
class NewDynamicProcedureAction extends NewObjectResult {
  final String ambiente;
  const NewDynamicProcedureAction({required this.ambiente});
}

/// Abre una hoja limpia en el editor de SQL.
class OpenBlankSqlSheetAction extends NewObjectResult {
  final String ambiente;
  const OpenBlankSqlSheetAction({required this.ambiente});
}

/// Abre el editor de SQL sembrado con la plantilla y el código generado.
class OpenInSqlEditorAction extends NewObjectResult {
  final String code;
  final String title;
  final String ambiente;
  final Plantilla? plantilla;
  final String? snippetCode;

  const OpenInSqlEditorAction({
    required this.code,
    required this.title,
    required this.ambiente,
    this.plantilla,
    this.snippetCode,
  });
}

/// Pasos del asistente guiado.
enum _WizardStep { objectType, template }

/// Abre el asistente de creación de nuevos objetos Oracle/SQL en una ventana flotante.
Future<NewObjectResult?> showNewObjectDialog(
  BuildContext context, {
  required String ambiente,
  NewObjectType? initialType,
}) {
  if (initialType?.isSpecialFlow == true) {
    return Future.value(NewDynamicProcedureAction(ambiente: ambiente));
  }
  final done = Completer<NewObjectResult?>();
  showFloatingWindow(
    context,
    (close) => NewObjectDialog(
      ambiente: ambiente,
      initialType: initialType,
      onClose: (result) {
        close();
        if (!done.isCompleted) done.complete(result);
      },
    ),
  );
  return done.future;
}

/// Diálogo modal flotante de selección de tipo de objeto y plantilla.
class NewObjectDialog extends StatefulWidget {
  final String ambiente;
  final NewObjectType? initialType;
  final void Function(NewObjectResult? result) onClose;

  const NewObjectDialog({
    super.key,
    required this.ambiente,
    required this.onClose,
    this.initialType,
  });

  @override
  State<NewObjectDialog> createState() => _NewObjectDialogState();
}

class _NewObjectDialogState extends State<NewObjectDialog> {
  late String _selectedAmbiente;
  _WizardStep _currentStep = _WizardStep.objectType;
  late NewObjectType _selectedType;

  // Catálogo de plantillas
  final _templateSearchCtrl = TextEditingController();
  String _templateSearchQuery = '';
  Plantilla? _selectedPlantilla;
  bool _startBlank = false;
  Future<List<Plantilla>>? _plantillasFuture;
  String? _plantillasFutureCategory;

  // Geometría flotante
  static const double _kHeaderH = 66;
  Offset _position = Offset.zero;
  double? _winW;
  double? _winH;
  bool _maximized = false;
  bool _minimized = false;
  int? _slot;
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;
  Duration _anim = Duration.zero;

  @override
  void initState() {
    super.initState();
    _selectedAmbiente = widget.ambiente;
    _selectedType = widget.initialType ?? NewObjectType.function;
    if (widget.initialType != null &&
        !widget.initialType!.isSpecialFlow &&
        !widget.initialType!.isBlankDirect) {
      _currentStep = _WizardStep.template;
    }
  }

  @override
  void dispose() {
    _templateSearchCtrl.dispose();
    super.dispose();
  }

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

  void _close([NewObjectResult? result]) {
    FloatingWindowSlots.release(_slot);
    _slot = null;
    widget.onClose(result);
  }

  void _onTypeSelected(NewObjectType type) {
    if (type.isSpecialFlow) {
      _close(NewDynamicProcedureAction(ambiente: _selectedAmbiente));
      return;
    }
    if (type.isBlankDirect) {
      _close(OpenBlankSqlSheetAction(ambiente: _selectedAmbiente));
      return;
    }
    setState(() {
      _selectedType = type;
      _selectedPlantilla = null;
      _startBlank = false;
      _plantillasFuture = null;
      _plantillasFutureCategory = null;
      _currentStep = _WizardStep.template;
    });
  }

  String _generateFallbackBlankFor(NewObjectType type) {
    switch (type) {
      case NewObjectType.function:
        return 'CREATE OR REPLACE FUNCTION f_nombre (\n'
            '    p_id IN NUMBER\n'
            ') RETURN VARCHAR2 IS\n'
            'BEGIN\n'
            '    RETURN NULL;\n'
            'END f_nombre;\n/';
      case NewObjectType.procedure:
        return 'CREATE OR REPLACE PROCEDURE pr_nombre (\n'
            '    p_id IN NUMBER\n'
            ') IS\n'
            'BEGIN\n'
            '    NULL;\n'
            'END pr_nombre;\n/';
      case NewObjectType.package:
        return 'CREATE OR REPLACE PACKAGE pkg_nombre AS\n'
            '    PROCEDURE ejecutar;\n'
            'END pkg_nombre;\n/\n\n'
            'CREATE OR REPLACE PACKAGE BODY pkg_nombre AS\n'
            '    PROCEDURE ejecutar IS\n'
            '    BEGIN\n'
            '        NULL;\n'
            '    END ejecutar;\n'
            'END pkg_nombre;\n/';
      case NewObjectType.trigger:
        return 'CREATE OR REPLACE TRIGGER trg_nombre\n'
            'BEFORE INSERT OR UPDATE ON tabla_nombre\n'
            'FOR EACH ROW\n'
            'BEGIN\n'
            '    NULL;\n'
            'END trg_nombre;\n/';
      case NewObjectType.type:
        return 'CREATE OR REPLACE TYPE t_objeto AS OBJECT (\n'
            '    id          NUMBER,\n'
            '    descripcion VARCHAR2(100)\n'
            ');\n/';
      case NewObjectType.dynamicProcedure:
      case NewObjectType.blankSql:
        return '-- Hoja SQL limpia\n';
    }
  }

  void _confirmSelection() {
    final user = procedimientosProvider.cdUsuario.trim().isNotEmpty
        ? procedimientosProvider.cdUsuario
        : null;

    final code = _startBlank || _selectedPlantilla == null
        ? _generateFallbackBlankFor(_selectedType)
        : _selectedPlantilla!.aplicarParametros(usuario: user);

    final snippetCode = (!_startBlank && _selectedPlantilla != null)
        ? _selectedPlantilla!.prepararParaInsercionSnippet(usuario: user)
        : null;

    final title = _startBlank || _selectedPlantilla == null
        ? _selectedType.label
        : _selectedPlantilla!.nombre;

    _close(
      OpenInSqlEditorAction(
        code: code,
        title: title,
        ambiente: _selectedAmbiente,
        plantilla: _startBlank ? null : _selectedPlantilla,
        snippetCode: snippetCode,
      ),
    );
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
      _winW ??= (screen.width * 0.88).clamp(560.0, 920.0);
      _winH ??= (screen.height * 0.82).clamp(420.0, 720.0);
    }
    if (_winW! > screen.width) _winW = screen.width;
    if (_winH! > screen.height) _winH = screen.height;

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
                          title: 'Nuevo Objeto / Documento',
                          icon: Icons.create_new_folder_outlined,
                          accentColor: const Color(0xFF0078D4),
                          badge: 'CREAR',
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
                                      const SizedBox(height: _kHeaderH),
                                      _buildWizardStepper(isDark, cs),
                                      Expanded(
                                        child:
                                            _currentStep ==
                                                _WizardStep.objectType
                                            ? _buildStepObjectTypeView(
                                                isDark,
                                                cs,
                                              )
                                            : _buildStepTemplateView(
                                                isDark,
                                                cs,
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
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

            // Resize handle inferior derecho
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

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark, ColorScheme cs) {
    final headerBg = isDark
        ? cs.surfaceContainerHighest
        : const Color(0xFF0053A6);
    final onHeader = isDark ? cs.onSurface : Colors.white;

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
                    Icons.library_add_rounded,
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
                      'Nuevo Objeto / Documento',
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
                          'Crear Nuevo Objeto o Documento',
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
                          'Elige un tipo de objeto, selecciona una plantilla y abre en el editor SQL',
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
                // Badge de ambiente
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
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],
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

  // ── Stepper ───────────────────────────────────────────────────────────────

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
          _buildStepPill(
            step: _WizardStep.objectType,
            number: '1',
            label: 'Tipo de Objeto',
            icon: Icons.category_rounded,
            isDark: isDark,
            cs: cs,
          ),
          Container(
            width: 20,
            height: 1.5,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: _currentStep == _WizardStep.template
                ? (isDark ? cs.primary : const Color(0xFF0078D4))
                : cs.outlineVariant.withValues(alpha: 0.5),
          ),
          _buildStepPill(
            step: _WizardStep.template,
            number: '2',
            label: 'Plantilla y Código',
            icon: Icons.auto_awesome_motion_rounded,
            isDark: isDark,
            cs: cs,
          ),
          const SizedBox(width: 8),
          const Spacer(),
          if (_currentStep == _WizardStep.template)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _selectedType.badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedType.badgeColor.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _selectedType.icon,
                      size: 13,
                      color: _selectedType.badgeColor,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _selectedType.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _selectedType.badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
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

  // ── PASO 1: Selección de Tipo de Objeto ────────────────────────────────────

  Widget _buildStepObjectTypeView(bool isDark, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner informativo
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
                child: Icon(
                  Icons.category_rounded,
                  color: cs.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paso 1: ¿Qué tipo de objeto deseas crear?',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Selecciona una estructura Oracle (Función, Procedimiento, Package, Trigger, Type) o un documento en blanco.',
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
        // Grid de opciones
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                mainAxisExtent: 120,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: NewObjectType.values.length,
              itemBuilder: (context, index) {
                final type = NewObjectType.values[index];
                final isSelected = _selectedType == type;

                return _ObjectTypeCard(
                  type: type,
                  isSelected: isSelected,
                  isDark: isDark,
                  cs: cs,
                  onTap: () {
                    setState(() => _selectedType = type);
                  },
                  onDoubleTap: () {
                    _onTypeSelected(type);
                  },
                );
              },
            ),
          ),
        ),
        // Footer del Paso 1
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
                onPressed: () => _onTypeSelected(_selectedType),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text(
                  _selectedType.isSpecialFlow
                      ? 'Abrir Procedimiento Dinámico'
                      : (_selectedType.isBlankDirect
                            ? 'Abrir Editor SQL'
                            : 'Siguiente: Elegir Plantilla'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
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

  // ── PASO 2: Selección de Plantilla con Vista Previa ───────────────────────

  Widget _buildStepTemplateView(bool isDark, ColorScheme cs) {
    if (_plantillasFuture == null ||
        _plantillasFutureCategory != _selectedType.category) {
      _plantillasFutureCategory = _selectedType.category;
      _plantillasFuture = PlantillaService.instance.loadParaCategoria(
        _selectedType.category,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner superior
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _selectedType.badgeColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _selectedType.icon,
                  color: _selectedType.badgeColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paso 2: Plantillas para ${_selectedType.label}',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Selecciona una estructura predefinida o inicia con una base estándar.',
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
        // Layout Master-Detail (Catálogo / Vista previa)
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

              // Si no hay plantilla seleccionada y no se eligió blanco, seleccionar la primera
              if (_selectedPlantilla == null &&
                  !_startBlank &&
                  filtered.isNotEmpty) {
                _selectedPlantilla = filtered.first;
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Catálogo
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
                          _buildTemplateSearchBar(isDark, cs, filtered.length),
                          const Divider(height: 1, thickness: 0.8),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.all(12),
                              children: [
                                // Opción 1: Base estándar
                                _TemplateSelectableCard(
                                  title:
                                      'Estructura base (${_selectedType.label})',
                                  description:
                                      'Declaración DDL estándar limpia sin tokens.',
                                  badgeText: 'BASE',
                                  badgeColor: const Color(0xFF0078D4),
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
                                  onDoubleTap: _confirmSelection,
                                ),
                                const SizedBox(height: 8),
                                ...filtered.map((p) {
                                  final isSelected =
                                      !_startBlank &&
                                      _selectedPlantilla?.id == p.id;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _TemplateSelectableCard(
                                      title: p.nombre,
                                      description:
                                          p.descripcion ??
                                          'Plantilla predefinida para ${_selectedType.label}',
                                      badgeText: p.categoria,
                                      badgeColor: _selectedType.badgeColor,
                                      icon: _selectedType.icon,
                                      isSelected: isSelected,
                                      isDark: isDark,
                                      cs: cs,
                                      onTap: () {
                                        setState(() {
                                          _startBlank = false;
                                          _selectedPlantilla = p;
                                        });
                                      },
                                      onDoubleTap: _confirmSelection,
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Vista previa
                  Expanded(
                    flex: 5,
                    child: _buildTemplatePreviewPanel(isDark, cs),
                  ),
                ],
              );
            },
          ),
        ),
        // Footer del Paso 2
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
                  setState(() => _currentStep = _WizardStep.objectType);
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
              const Spacer(),
              FilledButton.icon(
                onPressed: _confirmSelection,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text(
                  'Abrir en Editor SQL',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF107C41),
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
        ),
      ],
    );
  }

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
                  hintText: 'Buscar plantilla...',
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
          const SizedBox(width: 8),
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
        ],
      ),
    );
  }

  Widget _buildTemplatePreviewPanel(bool isDark, ColorScheme cs) {
    final codePreview = _startBlank || _selectedPlantilla == null
        ? _generateFallbackBlankFor(_selectedType)
        : _selectedPlantilla!.aplicarParametros();

    final title = _startBlank || _selectedPlantilla == null
        ? 'Estructura Base: ${_selectedType.label}'
        : _selectedPlantilla!.nombre;

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9FAFB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                          const Text(
                            'VISTA PREVIA DEL CÓDIGO',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: Color(0xFF0078D4),
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
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  tooltip: 'Copiar código',
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
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.8),
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
        ],
      ),
    );
  }
}

/// Tarjeta para el Paso 1: Tipo de Objeto
class _ObjectTypeCard extends StatefulWidget {
  final NewObjectType type;
  final bool isSelected;
  final bool isDark;
  final ColorScheme cs;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _ObjectTypeCard({
    required this.type,
    required this.isSelected,
    required this.isDark,
    required this.cs,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  State<_ObjectTypeCard> createState() => _ObjectTypeCardState();
}

class _ObjectTypeCardState extends State<_ObjectTypeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.type.badgeColor;
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
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(widget.type.icon, size: 16, color: activeColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.type.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: widget.isSelected
                            ? activeColor
                            : widget.cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.type.isSpecialFlow)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'WIZARD',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: activeColor,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  widget.type.subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta seleccionable de plantilla en el Paso 2
class _TemplateSelectableCard extends StatefulWidget {
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

  const _TemplateSelectableCard({
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
  State<_TemplateSelectableCard> createState() =>
      _TemplateSelectableCardState();
}

class _TemplateSelectableCardState extends State<_TemplateSelectableCard> {
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
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: widget.isSelected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(widget.icon, size: 16, color: widget.badgeColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: widget.isSelected
                                  ? activeColor
                                  : widget.cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: widget.badgeColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.badgeText,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: widget.badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.cs.onSurfaceVariant,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

/// Botón de control de ventana sobre la cabecera.
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
    final bg = _hovered
        ? (widget.danger
              ? const Color(0xFFC42B1C)
              : widget.color.withValues(alpha: 0.18))
        : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 42,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: _hovered && widget.danger ? Colors.white : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
