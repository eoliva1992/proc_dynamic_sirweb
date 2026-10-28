import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/deploy_ticket.dart';
import '../../services/deploy_ticket_service.dart';
import '../ambiente_selector.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart';
import 'create_hotfix_branch_dialog.dart';
import 'deploy_ticket_card_menu.dart';
import 'deploy_ticket_editor_dialog.dart';
import 'deploy_ticket_export_progress_dialog.dart';
import 'push_hotfix_dialog.dart';
import 'reverse_sql_config_dialog.dart';
import 'script_code_editor_dialog.dart';

enum DeployTicketViewMode { list, grid }

/// Abre la ventana flotante de consulta y mantenimiento de tickets de despliegue.
VoidCallback showDeployTicketsBrowser(BuildContext context) {
  return showFloatingWindow(
    context,
    (close) => DeployTicketsBrowserDialog(onClose: close),
  );
}

class DeployTicketsBrowserDialog extends StatefulWidget {
  final VoidCallback onClose;

  const DeployTicketsBrowserDialog({super.key, required this.onClose});

  @override
  State<DeployTicketsBrowserDialog> createState() =>
      _DeployTicketsBrowserDialogState();
}

class _DeployTicketsBrowserDialogState
    extends State<DeployTicketsBrowserDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _autorizaCtrl = TextEditingController();
  final TextEditingController _tipoSolicitudCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounceTimer;

  // Estado de ventana flotante
  bool _maximized = false;
  bool _minimized = false;
  int? _slot;
  Offset _position = Offset.zero;
  Offset _restorePos = Offset.zero;
  double? _winW;
  double? _winH;
  double _restoreW = 1180;
  double _restoreH = 760;
  Duration _anim = Duration.zero;

  // Filtros
  String? _selectedDb;
  String? _selectedDbd;

  static const List<String> _tipoSolicitudSugerencias = [
    'FreshServer',
    'Matriz',
    'Mesa de servicio',
    'Sysid',
    'Satelite',
  ];

  static const String _prefKeyViewMode = 'deploy_tickets_browser_view_mode';
  static const String _prefKeyInspectorOpen =
      'deploy_tickets_browser_inspector_open';

  // Modos de vista e inspector
  DeployTicketViewMode _viewMode = DeployTicketViewMode.list;
  bool _inspectorOpen = true;

  // Pestaña en el inspector (0: Resumen & Metadatos, 1: Artefactos, 2: index.txt)
  int _inspectorTab = 0;

  List<DeployTicket> _items = [];
  bool _loading = true;
  String? _error;

  int _page = 1;
  int _pageSize = 25;
  bool _hasMore = false;
  bool _hasPrev = false;

  DeployTicket? _selectedTicket;

  bool get _hasActiveFilters =>
      _searchCtrl.text.trim().isNotEmpty ||
      _autorizaCtrl.text.trim().isNotEmpty ||
      _tipoSolicitudCtrl.text.trim().isNotEmpty ||
      _selectedDb != null ||
      _selectedDbd != null;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _fetchTickets();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedView = prefs.getString(_prefKeyViewMode);
      final savedInspector = prefs.getBool(_prefKeyInspectorOpen);

      if (!mounted) return;
      setState(() {
        if (savedView != null) {
          _viewMode = DeployTicketViewMode.values.firstWhere(
            (v) => v.name == savedView,
            orElse: () => DeployTicketViewMode.list,
          );
        }
        if (savedInspector != null) {
          _inspectorOpen = savedInspector;
        }
      });
    } catch (_) {}
  }

  Future<void> _savePreference(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is String) await prefs.setString(key, value);
      if (value is bool) await prefs.setBool(key, value);
    } catch (_) {}
  }

  @override
  void dispose() {
    FloatingWindowSlots.release(_slot);
    _searchCtrl.dispose();
    _autorizaCtrl.dispose();
    _tipoSolicitudCtrl.dispose();
    _searchFocus.dispose();
    _debounceTimer?.cancel();
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
        _restoreW = _winW ?? 1180;
        _restoreH = _winH ?? 760;
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

  void _clearFilters() {
    setState(() {
      _searchCtrl.clear();
      _autorizaCtrl.clear();
      _tipoSolicitudCtrl.clear();
      _selectedDb = null;
      _selectedDbd = null;
    });
    _fetchTickets(resetPage: true);
  }

  Future<void> _fetchTickets({bool resetPage = false}) async {
    if (resetPage) _page = 1;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final queryText = _searchCtrl.text.trim();
      final autorizaText = _autorizaCtrl.text.trim();
      final tipoSolText = _tipoSolicitudCtrl.text.trim();

      final result = await DeployTicketService.instance.search(
        numeroSolicitud: queryText.isEmpty ? null : queryText,
        autoriza: autorizaText.isEmpty ? null : autorizaText,
        tipoSolicitud: tipoSolText.isEmpty ? null : tipoSolText,
        database: _selectedDb,
        databaseDestino: _selectedDbd,
        top: _pageSize,
        pagina: _page,
      );

      if (!mounted) return;
      setState(() {
        _items = result.items;
        _page = result.pagina;
        _hasMore = result.tieneSiguiente;
        _hasPrev = result.tienePrevio;
        _loading = false;

        if (_selectedTicket != null) {
          final match = _items.where((t) => t.id == _selectedTicket!.id);
          _selectedTicket = match.isNotEmpty ? match.first : _items.firstOrNull;
        } else {
          _selectedTicket = _items.firstOrNull;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _onFilterChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _fetchTickets(resetPage: true);
    });
  }

  void _openCreateDialog() {
    showDeployTicketEditorWindow(
      context,
      onSaved: (_) => _fetchTickets(resetPage: true),
    );
  }

  void _openEditDialog(DeployTicket ticket) {
    showDeployTicketEditorWindow(
      context,
      initialTicket: ticket,
      onSaved: (_) => _fetchTickets(),
      onDeleted: () => _fetchTickets(),
    );
  }

  Future<void> _confirmDelete(DeployTicket ticket) async {
    final confirmed = await showFloatingDialog<bool>(
      context,
      (ctx, close) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Confirmar Eliminación'),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar la ficha de pase '
          '${ticket.numeroSolicitud} (${ticket.tipoSolicitud})?\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => close(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DeployTicketService.instance.delete(ticket.id);
        AppToast.success(
          'Ticket ${ticket.numeroSolicitud} eliminado correctamente',
        );
        _fetchTickets();
      } catch (e) {
        AppToast.error('Error al eliminar ticket: $e');
      }
    }
  }

  bool _canPushTicket(DeployTicket ticket) {
    return (ticket.rutaRepositorio?.trim().isNotEmpty ?? false) &&
        (ticket.rutaDirectorioLocal?.trim().isNotEmpty ?? false);
  }

  Future<void> _exportDeployProduction(DeployTicket ticket) async {
    await DeployTicketExportProgressDialog.show(context, ticket: ticket);
  }

  Future<void> _createHotfixBranch(DeployTicket ticket) async {
    final updated = await CreateHotfixBranchDialog.show(
      context,
      ticket: ticket,
    );
    if (updated != null && mounted) {
      setState(() {
        final idx = _items.indexWhere((it) => it.id == updated.id);
        if (idx != -1) {
          _items[idx] = updated;
        }
        if (_selectedTicket?.id == updated.id) {
          _selectedTicket = updated;
        }
      });
      _fetchTickets();
    }
  }

  Future<void> _pushHotfix(DeployTicket ticket) async {
    final updated = await PushHotfixDialog.show(context, ticket: ticket);
    if (updated != null && mounted) {
      setState(() {
        final idx = _items.indexWhere((it) => it.id == updated.id);
        if (idx != -1) {
          _items[idx] = updated;
        }
        if (_selectedTicket?.id == updated.id) {
          _selectedTicket = updated;
        }
      });
      _fetchTickets();
    }
  }

  void _copyTicketIndexTxt(DeployTicket ticket) {
    final text = ticket.toIndexTxt();
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success('Formato index.txt copiado al portapapeles');
  }

  Future<void> _openTicketUrl(String? rawUrl) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      AppToast.warning('El ticket no tiene una URL configurada');
      return;
    }
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
      _winW ??= (screen.width * 0.92).clamp(860.0, 1340.0);
      _winH ??= (screen.height * 0.90).clamp(560.0, 880.0);
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

    final queryText = _searchCtrl.text.trim();
    final badgeText = queryText.isNotEmpty
        ? queryText
        : (_items.isNotEmpty ? '${_items.length} TICKETS' : 'CONSULTA');

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _openCreateDialog,
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
          setState(() => _inspectorOpen = !_inspectorOpen);
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          if (_minimized) _toggleMinimized();
          _searchFocus.requestFocus();
          _searchCtrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchCtrl.text.length,
          );
        },
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
                      _maximized ? 0 : (_minimized ? 8 : 14),
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
                          title: 'Tickets de Despliegue',
                          icon: Icons.rocket_launch_rounded,
                          accentColor: cs.primary,
                          badge: badgeText,
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
                                    maxStars: 90,
                                    intensity: 0.12,
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildTopBar(cs, divColor, isDark),
                                    _buildFilterBar(cs, divColor, isDark),
                                    Expanded(
                                      child: _buildBody(cs, divColor, isDark),
                                    ),
                                    _buildPaginationBar(cs, divColor, isDark),
                                  ],
                                ),
                              ],
                            ),
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

  Widget _buildTopBar(ColorScheme cs, Color divColor, bool isDark) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        if (!_maximized) {
          setState(() => _anim = Duration.zero);
        }
      },
      onPanUpdate: (details) {
        if (!_maximized) {
          setState(() {
            _position += details.delta;
          });
        }
      },
      onDoubleTap: _toggleMaximized,
      child: MouseRegion(
        cursor: _maximized ? SystemMouseCursors.basic : SystemMouseCursors.grab,
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
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.rocket_launch_rounded,
                  color: cs.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Mantenimiento de Tickets de Despliegue',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
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
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: cs.primary.withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            '${_items.length} mostrados',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Fichas de pase de cambios por Git SIRWEB y archivos index.txt',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  minimumSize: const Size(60, 32),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text(
                  'Nuevo Ticket',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: _openCreateDialog,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refrescar',
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: () => _fetchTickets(),
              ),
              const SizedBox(width: 4),
              WindowButton(
                icon: Icons.remove_rounded,
                tooltip: 'Minimizar',
                onTap: _toggleMinimized,
              ),
              const SizedBox(width: 2),
              WindowButton(
                icon: _maximized
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                tooltip: _maximized ? 'Restaurar (F11)' : 'Maximizar (F11)',
                onTap: _toggleMaximized,
              ),
              const SizedBox(width: 2),
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

  Widget _buildFilterBar(ColorScheme cs, Color divColor, bool isDark) {
    final inputBg = isDark ? const Color(0xFF141518) : Colors.white;
    final inputBorderColor = isDark
        ? const Color(0xFF383A42)
        : cs.outlineVariant.withValues(alpha: 0.7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191A1E) : const Color(0xFFF8F9FA),
        border: Border(bottom: BorderSide(color: divColor, width: 0.8)),
      ),
      child: Row(
        children: [
          // Campo de búsqueda principal
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: (_) => _onFilterChanged(),
                style: const TextStyle(fontSize: 12, height: 1.2),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputBg,
                  hintText: 'Buscar por NUSOL o palabra clave... (Ctrl+F)',
                  hintStyle: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: cs.primary,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 14),
                          splashRadius: 12,
                          padding: EdgeInsets.zero,
                          tooltip: 'Limpiar texto',
                          onPressed: () {
                            _searchCtrl.clear();
                            _fetchTickets(resetPage: true);
                          },
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: inputBorderColor, width: 0.8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: inputBorderColor, width: 0.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: cs.primary, width: 1.3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Campo de Autorizador
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _autorizaCtrl,
                onChanged: (_) => _onFilterChanged(),
                style: const TextStyle(fontSize: 12, height: 1.2),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputBg,
                  hintText: 'Autoriza (AUT)...',
                  hintStyle: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: Icon(
                    Icons.verified_user_outlined,
                    size: 15,
                    color: isDark
                        ? Colors.tealAccent.shade400
                        : Colors.teal.shade700,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  suffixIcon: _autorizaCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 14),
                          splashRadius: 12,
                          padding: EdgeInsets.zero,
                          tooltip: 'Limpiar autorizador',
                          onPressed: () {
                            _autorizaCtrl.clear();
                            _fetchTickets(resetPage: true);
                          },
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: inputBorderColor, width: 0.8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: inputBorderColor, width: 0.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: cs.primary, width: 1.3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Campo de Tipo de Solicitud (campo abierto con sugerencias)
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: RawAutocomplete<String>(
                textEditingController: _tipoSolicitudCtrl,
                focusNode: FocusNode(),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final text = textEditingValue.text.trim().toLowerCase();
                  if (text.isEmpty) {
                    return _tipoSolicitudSugerencias;
                  }
                  return _tipoSolicitudSugerencias.where(
                    (opt) => opt.toLowerCase().contains(text),
                  );
                },
                onSelected: (String selection) {
                  _tipoSolicitudCtrl.text = selection;
                  _onFilterChanged();
                },
                fieldViewBuilder:
                    (
                      BuildContext context,
                      TextEditingController controller,
                      FocusNode focusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: (_) => _onFilterChanged(),
                        onSubmitted: (_) => onFieldSubmitted(),
                        style: const TextStyle(fontSize: 12, height: 1.2),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: inputBg,
                          hintText: 'Tipo solicitud...',
                          hintStyle: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          prefixIcon: Icon(
                            Icons.category_outlined,
                            size: 15,
                            color: isDark
                                ? Colors.deepPurpleAccent.shade100
                                : Colors.deepPurple.shade700,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                  ),
                                  splashRadius: 12,
                                  padding: EdgeInsets.zero,
                                  tooltip: 'Limpiar tipo de solicitud',
                                  onPressed: () {
                                    controller.clear();
                                    _fetchTickets(resetPage: true);
                                  },
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: inputBorderColor,
                              width: 0.8,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: inputBorderColor,
                              width: 0.8,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: cs.primary,
                              width: 1.3,
                            ),
                          ),
                        ),
                      );
                    },
                optionsViewBuilder:
                    (
                      BuildContext context,
                      AutocompleteOnSelected<String> onSelected,
                      Iterable<String> options,
                    ) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 6,
                          color: isDark
                              ? const Color(0xFF222328)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: divColor, width: 0.8),
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 200,
                              maxWidth: 220,
                            ),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons
                                              .subdirectory_arrow_right_rounded,
                                          size: 13,
                                          color: isDark
                                              ? Colors.deepPurpleAccent.shade100
                                              : Colors.deepPurple.shade700,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            option,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF1F2328),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Dropdown DB Origen
          SizedBox(
            width: 130,
            child: _buildFilterDropdown(
              label: 'DB Origen',
              prefixIcon: Icons.storage_rounded,
              value: _selectedDb,
              items: [
                null,
                ...AmbienteSelector.ambientes.map((e) => e.toUpperCase()),
              ],
              cs: cs,
              divColor: inputBorderColor,
              inputBg: inputBg,
              isDark: isDark,
              isAmbiente: true,
              onChanged: (val) {
                setState(() => _selectedDb = val);
                _fetchTickets(resetPage: true);
              },
            ),
          ),
          const SizedBox(width: 8),

          // Dropdown DB Destino
          SizedBox(
            width: 130,
            child: _buildFilterDropdown(
              label: 'DB Destino',
              prefixIcon: Icons.send_rounded,
              value: _selectedDbd,
              items: [
                null,
                ...AmbienteSelector.ambientes.map((e) => e.toUpperCase()),
              ],
              cs: cs,
              divColor: inputBorderColor,
              inputBg: inputBg,
              isDark: isDark,
              isAmbiente: true,
              onChanged: (val) {
                setState(() => _selectedDbd = val);
                _fetchTickets(resetPage: true);
              },
            ),
          ),

          if (_hasActiveFilters) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Restablecer todos los filtros',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _clearFilters,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.amber.shade700.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.filter_alt_off_rounded,
                        size: 15,
                        color: isDark
                            ? Colors.amber.shade300
                            : Colors.amber.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Limpiar',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.amber.shade300
                              : Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          Container(height: 20, width: 1, color: divColor),
          const SizedBox(width: 10),
          SegmentedButton<DeployTicketViewMode>(
            segments: const [
              ButtonSegment(
                value: DeployTicketViewMode.list,
                icon: Icon(Icons.view_agenda_outlined, size: 14),
                tooltip: 'Vista Lista',
              ),
              ButtonSegment(
                value: DeployTicketViewMode.grid,
                icon: Icon(Icons.grid_view_rounded, size: 14),
                tooltip: 'Vista Tarjetas',
              ),
            ],
            selected: {_viewMode},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
            onSelectionChanged: (set) {
              if (set.isNotEmpty) {
                setState(() => _viewMode = set.first);
                _savePreference(_prefKeyViewMode, set.first.name);
              }
            },
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: _inspectorOpen
                ? 'Ocultar Inspector (Ctrl+I)'
                : 'Mostrar Inspector (Ctrl+I)',
            icon: Icon(
              _inspectorOpen
                  ? Icons.view_sidebar_rounded
                  : Icons.view_sidebar_outlined,
              size: 18,
              color: _inspectorOpen ? cs.primary : null,
            ),
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: _inspectorOpen
                  ? cs.primary.withValues(alpha: 0.12)
                  : null,
            ),
            onPressed: () {
              setState(() => _inspectorOpen = !_inspectorOpen);
              _savePreference(_prefKeyInspectorOpen, _inspectorOpen);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required IconData prefixIcon,
    required String? value,
    required List<String?> items,
    required ColorScheme cs,
    required Color divColor,
    required Color inputBg,
    required bool isDark,
    bool isAmbiente = false,
    required ValueChanged<String?> onChanged,
  }) {
    final hasValue = value != null;
    final activeColor = isAmbiente && hasValue
        ? AmbienteSelector.colorForAmbiente(value)
        : (hasValue ? cs.primary : (isDark ? Colors.white60 : Colors.black54));

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: inputBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasValue ? cs.primary.withValues(alpha: 0.6) : divColor,
          width: 0.8,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isDense: true,
          isExpanded: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
          hint: Row(
            children: [
              Icon(
                prefixIcon,
                size: 13,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          items: items.map((item) {
            if (item == null) {
              return DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'Todos ($label)',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }

            final badgeColor = isAmbiente
                ? AmbienteSelector.colorForAmbiente(item)
                : cs.primary;

            return DropdownMenuItem<String?>(
              value: item,
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1F2328),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          selectedItemBuilder: (context) {
            return items.map((item) {
              if (item == null) {
                return Row(
                  children: [
                    Icon(
                      prefixIcon,
                      size: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: activeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: activeColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            }).toList();
          },
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, Color divColor, bool isDark) {
    if (_loading && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Consultando fichas de pase...',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Colors.red.shade400,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                'Ocurrió un error al cargar los tickets',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade400,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reintentar'),
                onPressed: () => _fetchTickets(),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 44,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No se encontraron tickets de despliegue',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _hasActiveFilters
                  ? 'No hay registros que coincidan con los filtros aplicados.'
                  : 'Crea tu primera ficha de pase de cambios con el botón inferior.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            if (_hasActiveFilters)
              OutlinedButton.icon(
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                label: const Text('Limpiar Filtros'),
                onPressed: _clearFilters,
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Crear Ficha de Pase'),
                onPressed: _openCreateDialog,
              ),
          ],
        ),
      );
    }

    final contentWidget = _viewMode == DeployTicketViewMode.list
        ? _buildTicketsList(cs, divColor, isDark)
        : _buildGridView(cs, divColor, isDark);

    if (!_inspectorOpen) {
      return contentWidget;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 6, child: contentWidget),
        VerticalDivider(width: 1, thickness: 1, color: divColor),
        SizedBox(
          width: 380,
          child: _buildTicketDetailPanel(cs, divColor, isDark),
        ),
      ],
    );
  }

  Widget _buildTicketsList(ColorScheme cs, Color divColor, bool isDark) {
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, thickness: 0.8, color: divColor),
      itemBuilder: (context, index) {
        final ticket = _items[index];
        final isSelected = _selectedTicket?.id == ticket.id;

        return ListTile(
          selected: isSelected,
          selectedTileColor: cs.primary.withValues(alpha: 0.09),
          hoverColor: cs.primary.withValues(alpha: 0.04),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isSelected
                  ? cs.primary
                  : cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.assignment_turned_in_outlined,
              size: 20,
              color: isSelected ? Colors.white : cs.primary,
            ),
          ),
          title: Row(
            children: [
              Text(
                ticket.numeroSolicitud.isNotEmpty
                    ? ticket.numeroSolicitud
                    : '(Sin número)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ticket.tipoSolicitud,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
              ),
              const Spacer(),
              _buildEnvBadge(ticket.database ?? 'DESA', isDark),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 12,
                  color: Colors.grey,
                ),
              ),
              _buildEnvBadge(ticket.databaseDestino ?? 'PROD', isDark),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 13,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  'Autoriza: ${ticket.autoriza.isNotEmpty ? ticket.autoriza : '-'}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.layers_outlined,
                  size: 13,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_countArtifacts(ticket)} artefactos',
                  style: const TextStyle(fontSize: 11.5),
                ),
                if (ticket.fechaCreacion != null) ...[
                  const SizedBox(width: 14),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 12,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ticket.fechaCreacion!.toLocal().toString().split(' ').first,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ticket.url != null && ticket.url!.trim().isNotEmpty)
                IconButton(
                  tooltip: 'Abrir enlace del ticket (URL)',
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: Colors.cyan,
                  ),
                  onPressed: () => _openTicketUrl(ticket.url),
                ),
              IconButton(
                tooltip: 'Crear / Enlazar Hotfix en Git',
                icon: Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: Colors.amber.shade700,
                ),
                onPressed: () => _createHotfixBranch(ticket),
              ),
              if (_canPushTicket(ticket))
                IconButton(
                  tooltip: 'Generar Scripts y Realizar Push',
                  icon: Icon(
                    Icons.rocket_launch_rounded,
                    size: 16,
                    color: Colors.greenAccent.shade700,
                  ),
                  onPressed: () => _pushHotfix(ticket),
                )
              else
                IconButton(
                  tooltip:
                      'Push deshabilitado: configure rutas del repositorio primero',
                  icon: Icon(
                    Icons.rocket_launch_outlined,
                    size: 16,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                  onPressed: () => AppToast.info(
                    'Para hacer push, primero crea o enlaza el hotfix y configura la ruta local y remota.',
                  ),
                ),
              IconButton(
                tooltip: 'Exportar pase de producción',
                icon: const Icon(
                  Icons.file_download_outlined,
                  size: 16,
                  color: Colors.blueAccent,
                ),
                onPressed: () => _exportDeployProduction(ticket),
              ),
              IconButton(
                tooltip: 'Copiar index.txt',
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () => _copyTicketIndexTxt(ticket),
              ),
              IconButton(
                tooltip: 'Editar ticket',
                icon: const Icon(Icons.edit_outlined, size: 16),
                onPressed: () => _openEditDialog(ticket),
              ),
              IconButton(
                tooltip: 'Eliminar ticket',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: Colors.redAccent,
                ),
                onPressed: () => _confirmDelete(ticket),
              ),
            ],
          ),
          onTap: () {
            setState(() {
              _selectedTicket = ticket;
              _inspectorOpen = true;
            });
          },
        );
      },
    );
  }

  Widget _buildGridView(ColorScheme cs, Color divColor, bool isDark) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 172,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final ticket = _items[index];
        final isSelected = _selectedTicket?.id == ticket.id;

        return Card(
          elevation: isSelected ? 3 : 0.5,
          color: isSelected
              ? cs.primary.withValues(alpha: 0.08)
              : (isDark ? const Color(0xFF22242A) : Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isSelected ? cs.primary : divColor,
              width: isSelected ? 1.4 : 0.8,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                _selectedTicket = ticket;
                _inspectorOpen = true;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.assignment_outlined,
                          size: 16,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ticket.numeroSolicitud.isNotEmpty
                              ? ticket.numeroSolicitud
                              : '(Sin número)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ticket.tipoSolicitud,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildEnvBadge(ticket.database ?? 'DESA', isDark),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 11,
                          color: Colors.grey,
                        ),
                      ),
                      _buildEnvBadge(ticket.databaseDestino ?? 'PROD', isDark),
                      const Spacer(),
                      Text(
                        'v${ticket.version}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Autoriza: ${ticket.autoriza.isNotEmpty ? ticket.autoriza : "-"}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(
                        Icons.layers_outlined,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_countArtifacts(ticket)} artefactos',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      DeployTicketCardMenu(
                        ticket: ticket,
                        canPush: _canPushTicket(ticket),
                        onCreateHotfix: () => _createHotfixBranch(ticket),
                        onPushHotfix: () => _pushHotfix(ticket),
                        onExport: () => _exportDeployProduction(ticket),
                        onCopyIndex: () => _copyTicketIndexTxt(ticket),
                      ),
                      if (ticket.url != null && ticket.url!.trim().isNotEmpty)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Abrir enlace del ticket (URL)',
                          icon: const Icon(
                            Icons.open_in_new_rounded,
                            size: 15,
                            color: Colors.cyan,
                          ),
                          onPressed: () => _openTicketUrl(ticket.url),
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Editar ticket',
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        onPressed: () => _openEditDialog(ticket),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Eliminar ticket',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 15,
                          color: Colors.redAccent,
                        ),
                        onPressed: () => _confirmDelete(ticket),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int _countArtifacts(DeployTicket t) {
    return t.reglasNegocio.length +
        t.paquetes.length +
        t.funciones.length +
        t.sql.length +
        t.reverseSql.length +
        t.objetos.length +
        t.triggers.length +
        t.bloqueLogico.length;
  }

  Widget _buildEnvBadge(String env, bool isDark) {
    final color = AmbienteSelector.colorForAmbiente(env);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        env,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTicketDetailPanel(ColorScheme cs, Color divColor, bool isDark) {
    final t = _selectedTicket;
    if (t == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, size: 36, color: cs.outlineVariant),
            const SizedBox(height: 8),
            const Text(
              'Selecciona un ticket para ver sus detalles',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      color: isDark ? const Color(0xFF1B1D22) : Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: divColor, width: 0.8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.numeroSolicitud.isNotEmpty
                            ? t.numeroSolicitud
                            : '(Sin número)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${t.tipoSolicitud} · v${t.version}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Editar', style: TextStyle(fontSize: 11.5)),
                  onPressed: () => _openEditDialog(t),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Cerrar inspector',
                  icon: const Icon(Icons.close_rounded, size: 17),
                  onPressed: () => setState(() => _inspectorOpen = false),
                ),
              ],
            ),
          ),
          Container(
            height: 36,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: divColor, width: 0.8)),
            ),
            child: Row(
              children: [
                _buildInspectorTabButton(
                  0,
                  'Resumen',
                  Icons.info_outline_rounded,
                  cs,
                ),
                _buildInspectorTabButton(
                  1,
                  'Artefactos (${_countArtifacts(t)})',
                  Icons.layers_outlined,
                  cs,
                ),
                _buildInspectorTabButton(
                  2,
                  'index.txt',
                  Icons.description_outlined,
                  cs,
                ),
              ],
            ),
          ),
          Expanded(
            child: _inspectorTab == 0
                ? _buildInspectorOverviewTab(t, divColor, isDark)
                : _inspectorTab == 1
                ? _buildInspectorArtifactsTab(t, cs)
                : _buildInspectorIndexTxtTab(t, cs, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorTabButton(
    int index,
    String label,
    IconData icon,
    ColorScheme cs,
  ) {
    final active = _inspectorTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _inspectorTab = index),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? cs.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: active ? cs.primary : Colors.grey),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? cs.primary : Colors.grey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInspectorOverviewTab(
    DeployTicket t,
    Color divColor,
    bool isDark,
  ) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildDetailRow(
          'Autoriza (AUT):',
          t.autoriza.isNotEmpty ? t.autoriza : '-',
        ),
        _buildDetailRow(
          'Base de Datos:',
          '${t.database ?? "DESA"} ➔ ${t.databaseDestino ?? "PROD"}',
        ),
        if (t.url != null && t.url!.isNotEmpty)
          _buildDetailRow(
            'URL Ticket:',
            t.url!,
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Abrir enlace en navegador',
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    size: 15,
                    color: Colors.cyan,
                  ),
                  onPressed: () => _openTicketUrl(t.url),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copiar enlace',
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: t.url!));
                    AppToast.success('URL copiada al portapapeles');
                  },
                ),
              ],
            ),
          ),
        if (t.usuarioCrea.isNotEmpty)
          _buildDetailRow('Creado por:', t.usuarioCrea),
        if (t.usuarioActualiza != null)
          _buildDetailRow('Modificado por:', t.usuarioActualiza!),
        if (t.fechaCreacion != null)
          _buildDetailRow(
            'Fecha Creación:',
            t.fechaCreacion!.toLocal().toString().split('.').first,
          ),
        if (t.rutaRepositorio != null && t.rutaRepositorio!.isNotEmpty)
          _buildDetailRow('Repositorio Git:', t.rutaRepositorio!),
        if (t.rutaDirectorioLocal != null && t.rutaDirectorioLocal!.isNotEmpty)
          _buildDetailRow('Directorio Scripts:', t.rutaDirectorioLocal!),
        const SizedBox(height: 14),
        Divider(color: divColor, height: 1),
        const SizedBox(height: 12),
        const Text(
          'Resumen de Artefactos',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildCountBadge('RN', t.reglasNegocio.length, Colors.amber),
            _buildCountBadge('PCK', t.paquetes.length, Colors.blue),
            _buildCountBadge('FUN', t.funciones.length, Colors.purple),
            _buildCountBadge('SQL', t.sql.length, Colors.teal),
            _buildCountBadge('RSQL', t.reverseSql.length, Colors.green),
            _buildCountBadge('OBJ', t.objetos.length, Colors.indigo),
            _buildCountBadge('TRG', t.triggers.length, Colors.orange),
            _buildCountBadge('BLK', t.bloqueLogico.length, Colors.cyan),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.bolt_rounded, size: 15),
              label: const Text('Crear Hotfix', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.black,
              ),
              onPressed: () => _createHotfixBranch(t),
            ),
            if (_canPushTicket(t))
              FilledButton.icon(
                icon: const Icon(Icons.rocket_launch_rounded, size: 15),
                label: const Text(
                  'Push Hotfix',
                  style: TextStyle(fontSize: 12),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade700,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _pushHotfix(t),
              )
            else
              OutlinedButton.icon(
                icon: Icon(
                  Icons.rocket_launch_outlined,
                  size: 15,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                label: Text(
                  'Push (Configurar rutas)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                onPressed: () => _createHotfixBranch(t),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_download_outlined, size: 15),
              label: const Text(
                'Exportar Pase',
                style: TextStyle(fontSize: 12),
              ),
              onPressed: () => _exportDeployProduction(t),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.content_copy_rounded, size: 15),
              label: const Text(
                'Copiar index.txt',
                style: TextStyle(fontSize: 12),
              ),
              onPressed: () => _copyTicketIndexTxt(t),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInspectorArtifactsTab(DeployTicket t, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildArtifactListTile(
          'Reglas de Negocio (RN / PROC)',
          t.reglasNegocio,
          Icons.bolt_outlined,
          Colors.amber,
        ),
        _buildArtifactListTile(
          'Paquetes (PCK)',
          t.paquetes,
          Icons.folder_zip_outlined,
          Colors.blue,
        ),
        _buildArtifactListTile(
          'Funciones (FUN)',
          t.funciones,
          Icons.functions_rounded,
          Colors.purple,
        ),
        _buildArtifactListTile(
          'Scripts (SQL)',
          t.sqlNames,
          Icons.code_rounded,
          Colors.teal,
          onItemTap: (item) {
            final script = t.sql.firstWhere(
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
            );
          },
        ),
        _buildArtifactListTile(
          'Reverse SQL (RSQL)',
          t.reverseSqlNames,
          Icons.replay_circle_filled_rounded,
          Colors.green,
          onItemTap: (item) {
            final script = t.reverseSql.firstWhere(
              (s) => s.nombre == item,
              orElse: () => DeployTicketScript(nombre: item),
            );
            ReverseSqlConfigDialog.show(
              context,
              title: 'Detalle YAML RSQL: $item',
              initialYaml: script.contenido,
              scriptName: script.nombre,
            );
          },
        ),
        _buildArtifactListTile(
          'Objetos BD (OBJ)',
          t.objetos,
          Icons.view_in_ar_rounded,
          Colors.indigo,
        ),
        _buildArtifactListTile(
          'Triggers (TRG)',
          t.triggers,
          Icons.alarm_on_rounded,
          Colors.orange,
        ),
        _buildArtifactListTile(
          'Bloques Lógicos (BLK)',
          t.bloqueLogicoNames,
          Icons.widgets_outlined,
          Colors.cyan,
          onItemTap: (item) {
            final script = t.bloqueLogico.firstWhere(
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
            );
          },
        ),
      ],
    );
  }

  Widget _buildInspectorIndexTxtTab(
    DeployTicket t,
    ColorScheme cs,
    bool isDark,
  ) {
    final indexTxt = t.toIndexTxt();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Previsualización index.txt',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text(
                  'Copiar todo',
                  style: TextStyle(fontSize: 11),
                ),
                onPressed: () => _copyTicketIndexTxt(t),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF141518)
                    : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2C2D32)
                      : Colors.grey.shade300,
                  width: 0.8,
                ),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  indexTxt,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          ?action,
        ],
      ),
    );
  }

  Widget _buildArtifactListTile(
    String title,
    List<String> items,
    IconData icon,
    Color color, {
    ValueChanged<String>? onItemTap,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        leading: Icon(icon, size: 18, color: color),
        title: Text(
          '$title (${items.length})',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: items.map((item) {
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onItemTap != null ? () => onItemTap(item) : null,
                  child: Chip(
                    label: Text(
                      item,
                      style: TextStyle(
                        fontSize: 11,
                        decoration: onItemTap != null
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                    ),
                    backgroundColor: color.withValues(alpha: 0.12),
                    side: BorderSide(color: color.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar(ColorScheme cs, Color divColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222328) : const Color(0xFFF6F8FA),
        border: Border(top: BorderSide(color: divColor)),
      ),
      child: Row(
        children: [
          Text(
            _items.isEmpty
                ? '0 registros'
                : 'Página $_page (${_items.length} elementos mostrados)',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(width: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Filas: ',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              DropdownButton<int>(
                value: _pageSize,
                isDense: true,
                underline: const SizedBox.shrink(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                items: const [
                  DropdownMenuItem(value: 25, child: Text('25')),
                  DropdownMenuItem(value: 50, child: Text('50')),
                  DropdownMenuItem(value: 100, child: Text('100')),
                ],
                onChanged: (val) {
                  if (val != null && val != _pageSize) {
                    setState(() => _pageSize = val);
                    _fetchTickets(resetPage: true);
                  }
                },
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Página anterior',
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            onPressed: _hasPrev && !_loading
                ? () {
                    _page--;
                    _fetchTickets();
                  }
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$_page',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: 'Página siguiente',
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            onPressed: _hasMore && !_loading
                ? () {
                    _page++;
                    _fetchTickets();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
