import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/deploy_ticket.dart';
import '../../providers/procedimientos_provider.dart';
import '../../services/deploy_ticket_service.dart';
import '../ambiente_selector.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart';
import 'artifact_list_editor.dart';
import 'deploy_ticket_export_progress_dialog.dart';
import 'reverse_sql_config_dialog.dart';
import 'script_code_editor_dialog.dart';

/// Abre la ventana modal flotante profesional para crear o editar un ticket de pase / despliegue.
/// Soporta minimizado a la barra flotante (dock), maximizado y redimensionamiento.
VoidCallback showDeployTicketEditorWindow(
  BuildContext context, {
  DeployTicket? initialTicket,
  void Function(DeployTicket saved)? onSaved,
  VoidCallback? onDeleted,
}) {
  return showFloatingWindow(
    context,
    (close) => DeployTicketEditorDialog(
      initialTicket: initialTicket,
      onClose: close,
      onSaved: onSaved,
      onDeleted: onDeleted,
    ),
  );
}

class DeployTicketEditorDialog extends StatefulWidget {
  final DeployTicket? initialTicket;
  final VoidCallback onClose;
  final void Function(DeployTicket saved)? onSaved;
  final VoidCallback? onDeleted;

  const DeployTicketEditorDialog({
    super.key,
    this.initialTicket,
    required this.onClose,
    this.onSaved,
    this.onDeleted,
  });

  @override
  State<DeployTicketEditorDialog> createState() =>
      _DeployTicketEditorDialogState();
}

class _DeployTicketEditorDialogState extends State<DeployTicketEditorDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  static const String _prefKeyLastAutoriza = 'deploy_ticket_last_autoriza';
  static const String _prefKeyLastTipoSol = 'deploy_ticket_last_tipo_solicitud';

  late TabController _tabController;

  // Estado de ventana flotante
  bool _minimized = false;
  bool _maximized = false;
  int? _slot;
  Offset _position = Offset.zero;
  double? _winW;
  double? _winH;
  double _restoreW = 920;
  double _restoreH = 740;
  Offset _restorePos = Offset.zero;
  Duration _anim = Duration.zero;

  // Controladores principales
  late TextEditingController _numeroSolCtrl;
  late TextEditingController _tipoSolCtrl;
  late TextEditingController _autorizaCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _versionCtrl;

  // Listas de artefactos
  List<String> _reglasNegocio = [];
  List<String> _paquetes = [];
  List<String> _funciones = [];
  List<DeployTicketScript> _sql = [];
  List<DeployTicketScript> _reverseSql = [];
  List<String> _objetos = [];
  List<String> _triggers = [];
  List<DeployTicketScript> _bloqueLogico = [];

  String? _selectedDb;
  String? _selectedDbd;
  bool _saving = false;

  bool get _isEditing =>
      widget.initialTicket != null && widget.initialTicket!.isPersisted;

  int get _totalArtifacts =>
      _reglasNegocio.length +
      _paquetes.length +
      _funciones.length +
      _sql.length +
      _reverseSql.length +
      _objetos.length +
      _triggers.length +
      _bloqueLogico.length;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    final t = widget.initialTicket;

    _numeroSolCtrl = TextEditingController(text: t?.numeroSolicitud ?? '');
    _tipoSolCtrl = TextEditingController(
      text: t?.tipoSolicitud ?? 'Freshserver',
    );
    _autorizaCtrl = TextEditingController(text: t?.autoriza ?? '');
    _urlCtrl = TextEditingController(text: t?.url ?? '');
    _versionCtrl = TextEditingController(text: (t?.version ?? 1).toString());

    _reglasNegocio = List<String>.from(t?.reglasNegocio ?? []);
    _paquetes = List<String>.from(t?.paquetes ?? []);
    _funciones = List<String>.from(t?.funciones ?? []);
    _sql = List<DeployTicketScript>.from(t?.sql ?? []);
    _reverseSql = List<DeployTicketScript>.from(t?.reverseSql ?? []);
    _objetos = List<String>.from(t?.objetos ?? []);
    _triggers = List<String>.from(t?.triggers ?? []);
    _bloqueLogico = List<DeployTicketScript>.from(t?.bloqueLogico ?? []);

    _selectedDb = t?.database ?? 'DESA';
    _selectedDbd = t?.databaseDestino ?? 'PROD';

    if (t == null) {
      _loadLastPreferences();
    }
  }

  Future<void> _loadLastPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastAutoriza = prefs.getString(_prefKeyLastAutoriza);
      final lastTipoSol = prefs.getString(_prefKeyLastTipoSol);
      if (mounted) {
        setState(() {
          if (lastAutoriza != null &&
              lastAutoriza.isNotEmpty &&
              _autorizaCtrl.text.isEmpty) {
            _autorizaCtrl.text = lastAutoriza;
          }
          if (lastTipoSol != null && lastTipoSol.isNotEmpty) {
            _tipoSolCtrl.text = lastTipoSol;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveLastPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoriza = _autorizaCtrl.text.trim();
      final tipoSol = _tipoSolCtrl.text.trim();
      if (autoriza.isNotEmpty) {
        await prefs.setString(_prefKeyLastAutoriza, autoriza);
      }
      if (tipoSol.isNotEmpty) {
        await prefs.setString(_prefKeyLastTipoSol, tipoSol);
      }
    } catch (_) {}
  }

  Future<void> _testOpenUrl(String rawUrl) async {
    if (rawUrl.trim().isEmpty) return;
    var urlStr = rawUrl.trim();
    if (urlStr.startsWith('//')) {
      urlStr = 'https:$urlStr';
    } else if (!urlStr.startsWith('http://') &&
        !urlStr.startsWith('https://')) {
      urlStr = 'https://$urlStr';
    }

    final uri = Uri.tryParse(urlStr);
    if (uri == null || !uri.hasScheme) {
      AppToast.error('La URL no tiene un formato válido: $rawUrl');
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        AppToast.error('No se pudo abrir el enlace en el navegador');
      }
    } catch (e) {
      AppToast.error('Error al abrir URL: $e');
    }
  }

  @override
  void dispose() {
    FloatingWindowSlots.release(_slot);
    _tabController.dispose();
    _numeroSolCtrl.dispose();
    _tipoSolCtrl.dispose();
    _autorizaCtrl.dispose();
    _urlCtrl.dispose();
    _versionCtrl.dispose();
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
        _restoreW = _winW ?? 920;
        _restoreH = _winH ?? 740;
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

  void _close() {
    FloatingWindowSlots.release(_slot);
    _slot = null;
    widget.onClose();
  }

  String _resolveActiveUser() {
    final providerUser = procedimientosProvider.cdUsuario.trim();
    if (providerUser.isNotEmpty) return providerUser.toUpperCase();
    return DeployTicketService.currentUser;
  }

  DeployTicket _buildTicketFromInputs() {
    final version = int.tryParse(_versionCtrl.text.trim()) ?? 1;
    final activeUser = _resolveActiveUser();

    return DeployTicket(
      id: widget.initialTicket?.id ?? '',
      version: version,
      autoriza: _autorizaCtrl.text.trim(),
      url: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
      tipoSolicitud: _tipoSolCtrl.text.trim(),
      numeroSolicitud: _numeroSolCtrl.text.trim(),
      reglasNegocio: _reglasNegocio,
      paquetes: _paquetes,
      funciones: _funciones,
      sql: _sql,
      reverseSql: _reverseSql,
      objetos: _objetos,
      triggers: _triggers,
      bloqueLogico: _bloqueLogico,
      database: _selectedDb?.trim().isEmpty ?? true
          ? null
          : _selectedDb!.trim(),
      databaseDestino: _selectedDbd?.trim().isEmpty ?? true
          ? null
          : _selectedDbd!.trim(),
      usuarioCrea: widget.initialTicket?.usuarioCrea.isNotEmpty == true
          ? widget.initialTicket!.usuarioCrea
          : activeUser,
      usuarioActualiza: _isEditing ? activeUser : null,
      fechaCreacion: widget.initialTicket?.fechaCreacion,
      fechaModificacion: widget.initialTicket?.fechaModificacion,
    );
  }

  Future<void> _saveTicket() async {
    if (!_formKey.currentState!.validate()) {
      _tabController.animateTo(0);
      AppToast.error(
        'Por favor completa los campos requeridos en la pestaña General.',
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final ticket = _buildTicketFromInputs();
      final saved = await DeployTicketService.instance.save(ticket);
      await _saveLastPreferences();
      AppToast.success(
        _isEditing
            ? 'Ticket ${saved.numeroSolicitud} actualizado con éxito'
            : 'Ticket ${saved.numeroSolicitud} registrado con éxito',
      );
      widget.onSaved?.call(saved);
      _close();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error('Error al guardar ticket: $e');
    }
  }

  Future<void> _importIndexTxt() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Seleccionar archivo index.txt',
        type: FileType.custom,
        allowedExtensions: ['txt', 'conf', 'cfg'],
      );

      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      final content = await file.readAsString();

      _applyParsedIndexTxt(content);
      AppToast.success('Archivo index.txt importado con éxito');
    } catch (e) {
      AppToast.error('No se pudo importar el archivo: $e');
    }
  }

  void _applyParsedIndexTxt(String content) {
    final activeUser = _resolveActiveUser();
    final parsed = DeployTicket.parseIndexTxt(content, currentUser: activeUser);

    setState(() {
      _versionCtrl.text = parsed.version.toString();
      if (parsed.autoriza.isNotEmpty) _autorizaCtrl.text = parsed.autoriza;
      if (parsed.url != null && parsed.url!.isNotEmpty) {
        _urlCtrl.text = parsed.url!;
      }
      if (parsed.tipoSolicitud.isNotEmpty) {
        _tipoSolCtrl.text = parsed.tipoSolicitud;
      }
      if (parsed.numeroSolicitud.isNotEmpty) {
        _numeroSolCtrl.text = parsed.numeroSolicitud;
      }

      if (parsed.database != null && parsed.database!.isNotEmpty) {
        _selectedDb = parsed.database;
      }
      if (parsed.databaseDestino != null &&
          parsed.databaseDestino!.isNotEmpty) {
        _selectedDbd = parsed.databaseDestino;
      }

      _reglasNegocio = List<String>.from(parsed.reglasNegocio);
      _paquetes = List<String>.from(parsed.paquetes);
      _funciones = List<String>.from(parsed.funciones);
      _sql = List<DeployTicketScript>.from(parsed.sql);
      _reverseSql = List<DeployTicketScript>.from(parsed.reverseSql);
      _objetos = List<String>.from(parsed.objetos);
      _triggers = List<String>.from(parsed.triggers);
      _bloqueLogico = List<DeployTicketScript>.from(parsed.bloqueLogico);
    });
  }

  void _copyIndexTxt() {
    final ticket = _buildTicketFromInputs();
    final text = ticket.toIndexTxt();
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success('Formato index.txt copiado al portapapeles');
  }

  Future<void> _exportDeployProduction() async {
    final ticket = _buildTicketFromInputs();
    await DeployTicketExportProgressDialog.show(context, ticket: ticket);
  }

  Future<void> _exportIndexTxt() async {
    try {
      final ticket = _buildTicketFromInputs();
      final text = ticket.toIndexTxt();

      final filename = ticket.numeroSolicitud.isNotEmpty
          ? 'index_${ticket.numeroSolicitud}.txt'
          : 'index.txt';

      final outputFile = await FilePicker.saveFile(
        dialogTitle: 'Guardar archivo index.txt',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(text);
        AppToast.success('Archivo index.txt guardado en $outputFile');
      }
    } catch (e) {
      AppToast.error('Error al exportar archivo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final divColor = isDark
        ? const Color(0xFF333338)
        : cs.outlineVariant.withValues(alpha: 0.5);

    final screen = MediaQuery.sizeOf(context);

    if (_maximized) {
      _winW = screen.width;
      _winH = screen.height;
    } else {
      _winW ??= (screen.width * 0.88).clamp(700.0, 980.0);
      _winH ??= (screen.height * 0.88).clamp(520.0, 840.0);
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

    final ticketBadge = _numeroSolCtrl.text.trim().isNotEmpty
        ? _numeroSolCtrl.text.trim()
        : 'TICKET';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
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
                    color: bg,
                    borderRadius: BorderRadius.circular(
                      _maximized ? 0 : (_minimized ? 8 : 12),
                    ),
                    border: Border.all(color: divColor, width: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.65 : 0.22,
                        ),
                        blurRadius: _minimized ? 16 : 36,
                        offset: Offset(0, _minimized ? 4 : 14),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _minimized
                      ? MinimizedWindowCard(
                          title: _numeroSolCtrl.text.trim().isNotEmpty
                              ? 'Ticket ${_numeroSolCtrl.text.trim()}'
                              : 'Ficha de Pase Git',
                          icon: Icons.rocket_launch_rounded,
                          accentColor: cs.primary,
                          badge: ticketBadge,
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
                                const Positioned.fill(
                                  child: ConstellationBackground(
                                    density: 0.35,
                                    maxStars: 80,
                                    intensity: 0.12,
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildHeader(cs, divColor, isDark),
                                    _buildTabBar(cs, divColor, isDark),
                                    Expanded(
                                      child: Form(
                                        key: _formKey,
                                        child: TabBarView(
                                          controller: _tabController,
                                          children: [
                                            _buildGeneralTab(cs, isDark),
                                            _buildCodeTab(cs, isDark),
                                            _buildScriptsTab(cs, isDark),
                                            _buildSchemaTab(cs, isDark),
                                            _buildPreviewTab(
                                              cs,
                                              divColor,
                                              isDark,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    _buildFooter(cs, divColor, isDark),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),

            // Resize handle derecho
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 5,
                top: top + 54,
                width: 10,
                height: (h - 64).clamp(0.0, double.infinity),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(
                        700.0,
                        screen.width - 20,
                      );
                    }),
                  ),
                ),
              ),

            // Resize handle inferior
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
                        520.0,
                        screen.height - 20,
                      );
                    }),
                  ),
                ),
              ),

            // Resize handle esquina inferior derecha
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
                        700.0,
                        screen.width - 20,
                      );
                      _winH = (_winH! + d.delta.dy).clamp(
                        520.0,
                        screen.height - 20,
                      );
                    }),
                    child: CustomPaint(
                      painter: WindowGripPainter(
                        isDark ? Colors.white30 : Colors.black26,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, Color divColor, bool isDark) {
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
          height: 54,
          onDark: isDark,
          lineColor: cs.primary.withValues(alpha: 0.3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF26262B) : const Color(0xFFF6F8FA),
            border: Border(bottom: BorderSide(color: divColor, width: 0.8)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              titleArea(
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isEditing
                        ? Icons.edit_note_rounded
                        : Icons.rocket_launch_rounded,
                    color: cs.primary,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: titleArea(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _isEditing
                                  ? 'Editar Ficha de Pase Git'
                                  : 'Nuevo Ticket de Despliegue Git',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1F2328),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: cs.primary.withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              _numeroSolCtrl.text.isNotEmpty
                                  ? _numeroSolCtrl.text
                                  : 'Borrador',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Configuración de objetos de pase en base de datos e integración index.txt',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  minimumSize: const Size(60, 30),
                  backgroundColor: cs.primary.withValues(alpha: 0.15),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 14),
                label: const Text(
                  'Exportar Pase',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                onPressed: _exportDeployProduction,
              ),
              const SizedBox(width: 6),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  minimumSize: const Size(60, 30),
                ),
                icon: const Icon(Icons.file_upload_outlined, size: 15),
                label: const Text(
                  'Importar index.txt',
                  style: TextStyle(fontSize: 11.5),
                ),
                onPressed: _importIndexTxt,
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Copiar contenido index.txt',
                icon: const Icon(Icons.copy_rounded, size: 17),
                onPressed: _copyIndexTxt,
              ),
              IconButton(
                tooltip: 'Guardar como archivo index.txt',
                icon: const Icon(Icons.download_rounded, size: 18),
                onPressed: _exportIndexTxt,
              ),
              const SizedBox(width: 4),
              WindowButton(
                icon: Icons.remove_rounded,
                tooltip: 'Minimizar',
                onTap: _toggleMinimized,
              ),
              WindowButton(
                icon: _maximized
                    ? Icons.close_fullscreen_rounded
                    : Icons.crop_square_rounded,
                tooltip: _maximized
                    ? 'Restaurar tamaño (F11)'
                    : 'Maximizar (F11)',
                onTap: _toggleMaximized,
              ),
              WindowButton(
                icon: Icons.close_rounded,
                tooltip: 'Cerrar (Esc)',
                isClose: true,
                onTap: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs, Color divColor, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191A1E) : Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: divColor, width: 0.8)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorWeight: 3,
        indicatorColor: cs.primary,
        labelColor: cs.primary,
        unselectedLabelColor: isDark
            ? Colors.grey.shade400
            : Colors.grey.shade600,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12.5,
        ),
        tabs: [
          const Tab(
            icon: Icon(Icons.assignment_outlined, size: 16),
            text: 'General & Solicitud',
          ),
          Tab(
            icon: const Icon(Icons.code_rounded, size: 16),
            text:
                'Código / PL·SQL (${_reglasNegocio.length + _paquetes.length + _funciones.length})',
          ),
          Tab(
            icon: const Icon(Icons.storage_rounded, size: 16),
            text:
                'Scripts & Datos (${_sql.length + _reverseSql.length + _bloqueLogico.length})',
          ),
          Tab(
            icon: const Icon(Icons.view_in_ar_rounded, size: 16),
            text: 'Esquema & Objetos (${_objetos.length + _triggers.length})',
          ),
          const Tab(
            icon: Icon(Icons.description_outlined, size: 16),
            text: 'Vista Previa index.txt',
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralTab(ColorScheme cs, bool isDark) {
    final inputBg = isDark ? const Color(0xFF26262D) : const Color(0xFFFAFAFC);
    final borderColor = isDark ? const Color(0xFF383844) : Colors.grey.shade300;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      children: [
        _buildSectionTitle(
          'Identificación de la Solicitud',
          Icons.badge_outlined,
          cs,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _numeroSolCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Número de Solicitud (NUSOL) *',
                  hintText: 'Ej. INC-56430, REQ-1234',
                  prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                  filled: true,
                  fillColor: inputBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _tipoSolCtrl,
                decoration: InputDecoration(
                  labelText: 'Tipo de Solicitud (TPSOL) *',
                  hintText: 'Ej. Freshserver, Matriz',
                  prefixIcon: const Icon(Icons.category_outlined, size: 18),
                  filled: true,
                  fillColor: inputBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _autorizaCtrl,
                decoration: InputDecoration(
                  labelText: 'Autoriza (AUT) *',
                  hintText: 'Ej. ARTORRES',
                  prefixIcon: const Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                  ),
                  filled: true,
                  fillColor: inputBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _buildSectionTitle(
          'Ruta de Despliegue y Enlace',
          Icons.alt_route_rounded,
          cs,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: TextFormField(
                controller: _urlCtrl,
                decoration: InputDecoration(
                  labelText: 'Enlace / URL del Ticket (URL)',
                  hintText: '//dev.azure.com/...',
                  prefixIcon: const Icon(Icons.link_rounded, size: 18),
                  filled: true,
                  fillColor: inputBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  suffixIcon: _urlCtrl.text.isNotEmpty
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Abrir enlace en el navegador',
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                                color: Colors.cyan,
                              ),
                              onPressed: () => _testOpenUrl(_urlCtrl.text),
                            ),
                            IconButton(
                              tooltip: 'Copiar enlace',
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: _urlCtrl.text),
                                );
                                AppToast.success('URL copiada al portapapeles');
                              },
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 1,
              child: TextFormField(
                controller: _versionCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Versión (V)',
                  prefixIcon: const Icon(Icons.numbers_rounded, size: 18),
                  filled: true,
                  fillColor: inputBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: _buildEnvDropdown(
                label: 'DB Fuente (DB)',
                value: _selectedDb,
                onChanged: (v) => setState(() => _selectedDb = v),
                inputBg: inputBg,
                borderColor: borderColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: _buildEnvDropdown(
                label: 'DB Destino (DBD)',
                value: _selectedDbd,
                onChanged: (v) => setState(() => _selectedDbd = v),
                inputBg: inputBg,
                borderColor: borderColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Para agregar artefactos (reglas, procedimientos, paquetes, scripts), '
                  'utiliza las pestañas superiores. Puedes escribir un nombre y presionar Enter, '
                  'o pegar múltiples valores separados por coma directamente.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCodeTab(ColorScheme cs, bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      children: [
        ArtifactListEditor(
          title: 'Reglas de Negocio / Procedimientos (RN / PROC)',
          hintText: 'Ej. RN_CALCULO_PRIMA, PR_ACTUALIZA_COTIZACION',
          icon: Icons.bolt_outlined,
          color: Colors.amber.shade700,
          items: _reglasNegocio,
          onChanged: (val) => setState(() => _reglasNegocio = val),
          emptyMessage: 'No hay reglas ni procedimientos asignados.',
        ),
        const SizedBox(height: 14),
        ArtifactListEditor(
          title: 'Paquetes PL/SQL (PCK)',
          hintText: 'Ej. PKG_COTIZADOR_AUTO, PKG_COMISIONES',
          icon: Icons.folder_zip_outlined,
          color: Colors.blue.shade600,
          items: _paquetes,
          onChanged: (val) => setState(() => _paquetes = val),
          emptyMessage: 'No hay paquetes asignados.',
        ),
        const SizedBox(height: 14),
        ArtifactListEditor(
          title: 'Funciones PL/SQL (FUN)',
          hintText: 'Ej. FN_CALCULA_EDAD, FN_GET_TASA',
          icon: Icons.functions_rounded,
          color: Colors.purple.shade600,
          items: _funciones,
          onChanged: (val) => setState(() => _funciones = val),
          emptyMessage: 'No hay funciones asignadas.',
        ),
      ],
    );
  }

  Widget _buildScriptsTab(ColorScheme cs, bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      children: [
        ArtifactListEditor(
          title: 'Scripts Personalizados (SQL)',
          hintText: 'Ej. script22102026, alter_table_poliza',
          icon: Icons.code_rounded,
          color: Colors.teal.shade600,
          items: _sql.map((e) => e.nombre).toList(),
          onChanged: (newNames) {
            setState(() {
              // Mantener contenido de los existentes y agregar nuevos con contenido vacío
              final map = {for (var s in _sql) s.nombre: s};
              _sql = newNames.map((name) {
                return map[name] ?? DeployTicketScript(nombre: name);
              }).toList();
            });
          },
          emptyMessage: 'No hay scripts SQL asignados.',
          trailingHeaderAction: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(60, 26),
            ),
            icon: const Icon(Icons.code_rounded, size: 14),
            label: const Text(
              'Editor Monaco SQL',
              style: TextStyle(fontSize: 11),
            ),
            onPressed: () {
              ScriptCodeEditorDialog.show(
                context,
                title: 'Editor de Script SQL',
                language: 'plsql',
                themeColor: Colors.teal.shade600,
                icon: Icons.code_rounded,
                onSave: (code, filePath, scriptName) {
                  final fileName = scriptName.isNotEmpty
                      ? scriptName
                      : (filePath != null
                            ? filePath.split(Platform.pathSeparator).last
                            : 'custom_script.sql');
                  setState(() {
                    final idx = _sql.indexWhere((s) => s.nombre == fileName);
                    if (idx >= 0) {
                      _sql[idx] = _sql[idx].copyWith(contenido: code);
                    } else {
                      _sql.add(
                        DeployTicketScript(nombre: fileName, contenido: code),
                      );
                    }
                  });
                },
              );
            },
          ),
          onItemTap: (item) {
            final script = _sql.firstWhere(
              (s) => s.nombre == item,
              orElse: () => DeployTicketScript(nombre: item),
            );
            ScriptCodeEditorDialog.show(
              context,
              title: 'Script SQL: $item',
              initialCode: script.contenido,
              scriptName: script.nombre,
              language: 'plsql',
              themeColor: Colors.teal.shade600,
              icon: Icons.code_rounded,
              onSave: (code, filePath, scriptName) {
                final targetName = scriptName.isNotEmpty ? scriptName : item;
                setState(() {
                  final idx = _sql.indexWhere((s) => s.nombre == targetName);
                  if (idx >= 0) {
                    _sql[idx] = _sql[idx].copyWith(contenido: code);
                  } else {
                    _sql.add(
                      DeployTicketScript(nombre: targetName, contenido: code),
                    );
                  }
                });
              },
            );
          },
        ),
        const SizedBox(height: 14),
        ArtifactListEditor(
          title: 'Ingeniería Inversa YAML (RSQL)',
          hintText: 'Ej. reverse_inserts.yaml, migra_conceptos.yaml',
          icon: Icons.replay_circle_filled_rounded,
          color: Colors.green.shade600,
          items: _reverseSql.map((e) => e.nombre).toList(),
          onChanged: (newNames) {
            setState(() {
              final map = {for (var s in _reverseSql) s.nombre: s};
              _reverseSql = newNames.map((name) {
                return map[name] ?? DeployTicketScript(nombre: name);
              }).toList();
            });
          },
          emptyMessage: 'No hay configuraciones YAML asignadas.',
          trailingHeaderAction: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(60, 26),
            ),
            icon: const Icon(Icons.tune_rounded, size: 14),
            label: const Text(
              'Configurar / Abrir YAML',
              style: TextStyle(fontSize: 11),
            ),
            onPressed: () {
              ReverseSqlConfigDialog.show(
                context,
                title: 'Editor de Extracción RSQL (YAML)',
                onSave: (yaml, filePath, scriptName) {
                  final fileName = scriptName.isNotEmpty
                      ? scriptName
                      : (filePath != null
                            ? filePath.split(Platform.pathSeparator).last
                            : 'reverse_config.yaml');
                  setState(() {
                    final idx = _reverseSql.indexWhere(
                      (s) => s.nombre == fileName,
                    );
                    if (idx >= 0) {
                      _reverseSql[idx] = _reverseSql[idx].copyWith(
                        contenido: yaml,
                      );
                    } else {
                      _reverseSql.add(
                        DeployTicketScript(nombre: fileName, contenido: yaml),
                      );
                    }
                  });
                },
              );
            },
          ),
          onItemTap: (item) {
            final script = _reverseSql.firstWhere(
              (s) => s.nombre == item,
              orElse: () => DeployTicketScript(nombre: item),
            );
            ReverseSqlConfigDialog.show(
              context,
              title: 'Archivo RSQL: $item',
              initialYaml: script.contenido,
              scriptName: script.nombre,
              onSave: (yaml, filePath, scriptName) {
                final targetName = scriptName.isNotEmpty ? scriptName : item;
                setState(() {
                  final idx = _reverseSql.indexWhere(
                    (s) => s.nombre == targetName,
                  );
                  if (idx >= 0) {
                    _reverseSql[idx] = _reverseSql[idx].copyWith(
                      contenido: yaml,
                    );
                  } else {
                    _reverseSql.add(
                      DeployTicketScript(nombre: targetName, contenido: yaml),
                    );
                  }
                });
              },
            );
          },
        ),
        const SizedBox(height: 14),
        ArtifactListEditor(
          title: 'Bloques Lógicos (BLK)',
          hintText: 'Ej. BLK_REGLAS_EXTRA, BLK_VALIDACION_EMISION',
          icon: Icons.widgets_outlined,
          color: Colors.cyan.shade700,
          items: _bloqueLogico.map((e) => e.nombre).toList(),
          onChanged: (newNames) {
            setState(() {
              final map = {for (var s in _bloqueLogico) s.nombre: s};
              _bloqueLogico = newNames.map((name) {
                return map[name] ?? DeployTicketScript(nombre: name);
              }).toList();
            });
          },
          emptyMessage: 'No hay bloques lógicos asignados.',
          trailingHeaderAction: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(60, 26),
            ),
            icon: const Icon(Icons.widgets_outlined, size: 14),
            label: const Text(
              'Editor Monaco BLK',
              style: TextStyle(fontSize: 11),
            ),
            onPressed: () {
              ScriptCodeEditorDialog.show(
                context,
                title: 'Editor de Bloque Lógico (BLK)',
                language: 'plsql',
                themeColor: Colors.cyan.shade700,
                icon: Icons.widgets_outlined,
                onSave: (code, filePath, scriptName) {
                  final fileName = scriptName.isNotEmpty
                      ? scriptName
                      : (filePath != null
                            ? filePath.split(Platform.pathSeparator).last
                            : 'bloque_logico.sql');
                  setState(() {
                    final idx = _bloqueLogico.indexWhere(
                      (s) => s.nombre == fileName,
                    );
                    if (idx >= 0) {
                      _bloqueLogico[idx] = _bloqueLogico[idx].copyWith(
                        contenido: code,
                      );
                    } else {
                      _bloqueLogico.add(
                        DeployTicketScript(nombre: fileName, contenido: code),
                      );
                    }
                  });
                },
              );
            },
          ),
          onItemTap: (item) {
            final script = _bloqueLogico.firstWhere(
              (s) => s.nombre == item,
              orElse: () => DeployTicketScript(nombre: item),
            );
            ScriptCodeEditorDialog.show(
              context,
              title: 'Bloque Lógico: $item',
              initialCode: script.contenido,
              scriptName: script.nombre,
              language: 'plsql',
              themeColor: Colors.cyan.shade700,
              icon: Icons.widgets_outlined,
              onSave: (code, filePath, scriptName) {
                final targetName = scriptName.isNotEmpty ? scriptName : item;
                setState(() {
                  final idx = _bloqueLogico.indexWhere(
                    (s) => s.nombre == targetName,
                  );
                  if (idx >= 0) {
                    _bloqueLogico[idx] = _bloqueLogico[idx].copyWith(
                      contenido: code,
                    );
                  } else {
                    _bloqueLogico.add(
                      DeployTicketScript(nombre: targetName, contenido: code),
                    );
                  }
                });
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSchemaTab(ColorScheme cs, bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      children: [
        ArtifactListEditor(
          title: 'Objetos / Tipos de Base de Datos (OBJ)',
          hintText: 'Ej. TY_OBJETO_ASEGURADO, TBL_COTIZACIONES',
          icon: Icons.view_in_ar_rounded,
          color: Colors.indigo.shade600,
          items: _objetos,
          onChanged: (val) => setState(() => _objetos = val),
          emptyMessage: 'No hay objetos ni tipos asignados.',
        ),
        const SizedBox(height: 14),
        ArtifactListEditor(
          title: 'Disparadores / Triggers (TRG)',
          hintText: 'Ej. TRG_AUDIT_POLIZA, TRG_BIU_REGLA',
          icon: Icons.alarm_on_rounded,
          color: Colors.orange.shade700,
          items: _triggers,
          onChanged: (val) => setState(() => _triggers = val),
          emptyMessage: 'No hay disparadores asignados.',
        ),
      ],
    );
  }

  Widget _buildPreviewTab(ColorScheme cs, Color divColor, bool isDark) {
    final ticket = _buildTicketFromInputs();
    final indexTxt = ticket.toIndexTxt();

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141518) : Colors.grey.shade900,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: divColor, width: 0.8),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B1D22) : Colors.black26,
                border: Border(bottom: BorderSide(color: divColor, width: 0.8)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.terminal_rounded,
                    size: 16,
                    color: Colors.greenAccent,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'index.txt generado',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copiar al portapapeles',
                    icon: const Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: indexTxt));
                      AppToast.success('index.txt copiado al portapapeles');
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: SelectableText(
                  indexTxt,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFFDCDCAA),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
        ),
      ],
    );
  }

  Widget _buildEnvDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    Color? inputBg,
    Color? borderColor,
  }) {
    final curVal = value?.toUpperCase() ?? 'DESA';
    final curColor = AmbienteSelector.colorForAmbiente(curVal);

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: AmbienteSelector.ambientes.map((env) {
        final envUpper = env.toUpperCase();
        final color = AmbienteSelector.colorForAmbiente(envUpper);
        final isSelected = envUpper == curVal;
        return MenuItemButton(
          onPressed: () => onChanged(envUpper),
          leadingIcon: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          trailingIcon: isSelected ? const Icon(Icons.check, size: 16) : null,
          child: Text(
            envUpper,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      builder: (context, controller, child) {
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.storage_rounded, size: 18),
              suffixIcon: Icon(
                controller.isOpen
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                size: 22,
              ),
              filled: inputBg != null,
              fillColor: inputBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: borderColor ?? Colors.grey.shade400,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: borderColor ?? Colors.grey.shade400,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: curColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  curVal,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter(ColorScheme cs, Color divColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222328) : const Color(0xFFF6F8FA),
        border: Border(top: BorderSide(color: divColor, width: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'Total Artefactos: $_totalArtifacts',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Usuario: ${_resolveActiveUser()}',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _saving ? null : widget.onClose,
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_isEditing ? 'Guardar Cambios' : 'Registrar Ficha'),
            onPressed: _saving ? null : _saveTicket,
          ),
        ],
      ),
    );
  }
}
