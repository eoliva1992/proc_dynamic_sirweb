import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/oracle_credential.dart';
import '../providers/procedimientos_provider.dart';
import '../services/oracle_credenciales_service.dart';
import '../services/server_config_service.dart';
import 'ambiente_selector.dart';
import 'app_toast.dart';
import 'constellation_background.dart';
import 'floating_window.dart'
    show
        FloatingWindowSlots,
        MinimizedWindowCard,
        WindowButton,
        showFloatingDialog,
        showFloatingWindow;

/// Diálogo / ventana flotante profesional para configurar la dirección del servidor SirWeb
/// y gestionar en caliente las credenciales de los ambientes Oracle con auditoría.
class ServerConfigDialog extends StatefulWidget {
  final VoidCallback? onServerConfigChanged;
  final VoidCallback? onClose;

  const ServerConfigDialog({
    super.key,
    this.onServerConfigChanged,
    this.onClose,
  });

  /// Abre la ventana flotante sobre el overlay superior garantizando que nunca quede
  /// tapada por otras ventanas activas, con soporte para minimizar y maximizar.
  static VoidCallback show(
    BuildContext context, {
    VoidCallback? onServerConfigChanged,
  }) {
    return showFloatingWindow(
      context,
      (close) => ServerConfigDialog(
        onServerConfigChanged: onServerConfigChanged,
        onClose: close,
      ),
    );
  }

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Ventana Flotante: Dimensiones y Estado ─────────────────────────────────
  Offset _position = Offset.zero;
  Offset _restorePos = Offset.zero;
  double? _winW;
  double? _winH;
  double _restoreW = 960;
  double _restoreH = 800;
  bool _minimized = false;
  bool _maximized = false;
  int? _slot;
  Duration _anim = Duration.zero;

  // ── Tab 1: Servidor ────────────────────────────────────────────────────────
  late TextEditingController _urlController;
  final _serverFormKey = GlobalKey<FormState>();
  bool _isSavingServer = false;
  bool _isTestingPing = false;
  int? _pingLatencyMs;
  bool? _pingSuccess;
  String? _pingMessage;

  // ── Tab 2: Ambientes Oracle ────────────────────────────────────────────────
  bool _isLoadingCredentials = true;
  String? _credentialsError;
  List<OracleCredentialStatus> _credentials = [];
  String _selectedAmbiente = 'Desa';

  late TextEditingController _userIdController;
  late TextEditingController _passwordController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  bool _obscurePassword = true;
  bool _isApplyingOverride = false;
  bool _isRestoringConfig = false;

  // ── Tab 3: Historial & Carga Progresiva ─────────────────────────────────────
  late final ScrollController _historyScrollCtrl;
  late final TextEditingController _historySearchCtrl;
  bool _isLoadingHistory = false;
  bool _isLoadingMoreHistory = false;
  String? _historyError;
  List<OracleCredencialHistorialEntry> _historyItems = [];
  String _historyFilterAmbiente = 'Todos';
  String _historySearchQuery = '';
  int _historyPage = 1;
  final int _historyPageSize = 20;
  int _historyTotal = 0;
  bool _hasMoreHistory = false;
  final Set<String> _revealedPasswordIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    _urlController = TextEditingController();
    _userIdController = TextEditingController();
    _passwordController = TextEditingController();
    _hostController = TextEditingController();
    _portController = TextEditingController();

    _historyScrollCtrl = ScrollController();
    _historyScrollCtrl.addListener(_onHistorialScroll);
    _historySearchCtrl = TextEditingController();

    _loadCurrentServerUrl();
    _cargarCredencialesOracle();
  }

  void _onTabChanged() {
    if (_tabController.index == 2 &&
        _historyItems.isEmpty &&
        !_isLoadingHistory) {
      _cargarHistorial(reset: true);
    }
  }

  void _onHistorialScroll() {
    if (_isLoadingMoreHistory || _isLoadingHistory || !_hasMoreHistory) return;
    if (!_historyScrollCtrl.hasClients) return;

    final maxScroll = _historyScrollCtrl.position.maxScrollExtent;
    final currentScroll = _historyScrollCtrl.position.pixels;
    // Dispara al estar cerca del final del scroll (dentro de 60px o si ya llegó al fondo)
    if (currentScroll >= maxScroll - 60) {
      _cargarMasHistorial();
    }
  }

  @override
  void dispose() {
    FloatingWindowSlots.release(_slot);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _urlController.dispose();
    _userIdController.dispose();
    _passwordController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _historyScrollCtrl.removeListener(_onHistorialScroll);
    _historyScrollCtrl.dispose();
    _historySearchCtrl.dispose();
    super.dispose();
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

  void _toggleMaximized() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_maximized) {
        _winW = _restoreW;
        _winH = _restoreH;
        _position = _restorePos;
        _maximized = false;
      } else {
        _restoreW = _winW ?? 960;
        _restoreH = _winH ?? 800;
        _restorePos = _position;
        _position = Offset.zero;
        _maximized = true;
      }
    });
  }

  void _closeDialog() {
    FloatingWindowSlots.release(_slot);
    _slot = null;
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  // ── Servidor Methods ───────────────────────────────────────────────────────

  Future<void> _loadCurrentServerUrl() async {
    final currentUrl = await ServerConfigService().getBaseUrl();
    if (mounted) {
      _urlController.text = currentUrl;
    }
  }

  Future<void> _probarConexionServidor() async {
    final url = _urlController.text.trim();
    if (url.isEmpty ||
        (!url.startsWith('http://') && !url.startsWith('https://'))) {
      setState(() {
        _pingSuccess = false;
        _pingLatencyMs = null;
        _pingMessage = 'Ingresa una URL válida (http:// o https://)';
      });
      return;
    }

    setState(() {
      _isTestingPing = true;
      _pingSuccess = null;
      _pingMessage = null;
    });

    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(url);
      final client = http.Client();
      try {
        final res = await client.get(uri).timeout(const Duration(seconds: 5));
        sw.stop();
        if (mounted) {
          setState(() {
            _isTestingPing = false;
            _pingSuccess = res.statusCode < 500;
            _pingLatencyMs = sw.elapsedMilliseconds;
            _pingMessage =
                'Respuesta del servidor: HTTP ${res.statusCode} (${sw.elapsedMilliseconds} ms)';
          });
        }
      } finally {
        client.close();
      }
    } catch (e) {
      sw.stop();
      if (mounted) {
        setState(() {
          _isTestingPing = false;
          _pingSuccess = false;
          _pingLatencyMs = sw.elapsedMilliseconds;
          _pingMessage =
              'Sin conexión: ${e.toString().replaceFirst('Exception: ', '')}';
        });
      }
    }
  }

  Future<void> _guardarServidor() async {
    if (!_serverFormKey.currentState!.validate()) return;

    setState(() => _isSavingServer = true);
    try {
      final newUrl = _urlController.text.trim();
      await ServerConfigService().setBaseUrl(newUrl);

      if (mounted) {
        AppToast.success('Dirección base del servidor guardada');
        widget.onServerConfigChanged?.call();
        _cargarCredencialesOracle();
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('Error al guardar: $e');
      }
    } finally {
      if (mounted) setState(() => _isSavingServer = false);
    }
  }

  Future<void> _resetServidorDefault() async {
    final confirmed = await showFloatingDialog<bool>(
      context,
      (ctx, close) => AlertDialog(
        title: const Text('Restablecer servidor'),
        content: Text(
          '¿Deseas restablecer la dirección del servidor al valor predeterminado?\n\n'
          'Valor: ${ServerConfigService.getDefault()}',
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => close(true),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ServerConfigService().resetToDefault();
      if (mounted) {
        _urlController.text = ServerConfigService.getDefault();
        AppToast.info('Servidor restablecido a valor por defecto');
        widget.onServerConfigChanged?.call();
        _probarConexionServidor();
      }
    }
  }

  // ── Oracle Credenciales Methods ───────────────────────────────────────────

  Future<void> _cargarCredencialesOracle() async {
    setState(() {
      _isLoadingCredentials = true;
      _credentialsError = null;
    });

    try {
      final list = await OracleCredencialesService.instance.consultarEstado();
      if (mounted) {
        setState(() {
          _credentials = list;
          _isLoadingCredentials = false;
          _sincronizarCamposAmbienteActual();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCredentials = false;
          _credentialsError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _sincronizarCamposAmbienteActual() {
    final cur = _credentials.firstWhere(
      (c) => c.ambiente.toLowerCase() == _selectedAmbiente.toLowerCase(),
      orElse: () => OracleCredentialStatus(
        ambiente: _selectedAmbiente,
        userId: '',
        password: '',
        host: '',
        port: '',
        origen: 'Config',
      ),
    );
    _userIdController.text = cur.userId;
    _passwordController.text = cur.password;
    _hostController.text = cur.host ?? '';
    _portController.text = cur.port ?? '';
  }

  OracleCredentialStatus? get _currentStatus {
    try {
      return _credentials.firstWhere(
        (c) => c.ambiente.toLowerCase() == _selectedAmbiente.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _aplicarOverrideCredenciales() async {
    final user = _userIdController.text.trim();
    final pass = _passwordController.text;

    if (user.isEmpty) {
      AppToast.warning('El usuario de conexión Oracle es requerido');
      return;
    }
    if (pass.isEmpty) {
      AppToast.warning('La contraseña de conexión Oracle es requerida');
      return;
    }

    final cdUsuario = procedimientosProvider.cdUsuario.trim().toUpperCase();
    if (cdUsuario.isEmpty) {
      AppToast.warning(
        'Identifica tu usuario en el sistema antes de aplicar cambios',
      );
      return;
    }

    final isProd = _selectedAmbiente.toLowerCase() == 'prod';
    if (isProd) {
      final confirmed = await showFloatingDialog<bool>(
        context,
        (ctx, close) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade700,
                size: 28,
              ),
              const SizedBox(width: 8),
              const Text('Ambiente de Producción'),
            ],
          ),
          content: const Text(
            '¡ATENCIÓN! Estás a punto de alterar las credenciales activas del ambiente PROD.\n'
            'Cualquier consulta o transacción usará este usuario.',
          ),
          actions: [
            TextButton(
              onPressed: () => close(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => close(true),
              child: const Text('Confirmar Cambio en PROD'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isApplyingOverride = true);
    try {
      await OracleCredencialesService.instance.actualizarCredenciales(
        ambiente: _selectedAmbiente,
        userId: user,
        password: pass,
        cdUsuario: cdUsuario,
        host: _hostController.text.trim(),
        port: _portController.text.trim(),
      );

      AppToast.success(
        'Credenciales en caliente actualizadas para $_selectedAmbiente',
      );
      await _cargarCredencialesOracle();
      if (_tabController.index == 2 || _historyItems.isNotEmpty) {
        _cargarHistorial();
      }
    } catch (e) {
      AppToast.error('Error al aplicar credenciales: $e');
    } finally {
      if (mounted) setState(() => _isApplyingOverride = false);
    }
  }

  Future<void> _restablecerCredencialesConfig() async {
    final cdUsuario = procedimientosProvider.cdUsuario.trim().toUpperCase();
    if (cdUsuario.isEmpty) {
      AppToast.warning(
        'Identifica tu usuario en el sistema antes de restablecer',
      );
      return;
    }

    final confirmed = await showFloatingDialog<bool>(
      context,
      (ctx, close) => AlertDialog(
        title: Text('Restablecer credenciales ($_selectedAmbiente)'),
        content: Text(
          'Se descartará el override en memoria de $_selectedAmbiente y se volverán a utilizar '
          'las credenciales configuradas en el servidor (appsettings).',
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => close(true),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRestoringConfig = true);
    try {
      await OracleCredencialesService.instance.restablecerCredenciales(
        ambiente: _selectedAmbiente,
        cdUsuario: cdUsuario,
      );

      AppToast.info(
        'Credenciales de $_selectedAmbiente restablecidas a la configuración',
      );
      await _cargarCredencialesOracle();
      if (_tabController.index == 2 || _historyItems.isNotEmpty) {
        _cargarHistorial(reset: true);
      }
    } catch (e) {
      AppToast.error('Error al restablecer: $e');
    } finally {
      if (mounted) setState(() => _isRestoringConfig = false);
    }
  }

  // ── Historial Methods & Infinite Scroll ────────────────────────────────────

  Future<void> _cargarHistorial({bool reset = true}) async {
    if (reset) {
      _historyPage = 1;
    }

    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
      if (reset) {
        _historyItems = [];
        _historyTotal = 0;
        _hasMoreHistory = false;
      }
    });

    try {
      final filtro = _historyFilterAmbiente == 'Todos'
          ? null
          : _historyFilterAmbiente;
      final paged = await OracleCredencialesService.instance.consultarHistorial(
        ambiente: filtro,
        top: _historyPageSize,
        pagina: _historyPage,
      );
      if (mounted) {
        setState(() {
          _historyItems = paged.items;
          _historyTotal = paged.total;
          _hasMoreHistory = _historyItems.length < _historyTotal;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
          _historyError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _cargarMasHistorial() async {
    if (_isLoadingMoreHistory || _isLoadingHistory || !_hasMoreHistory) return;

    setState(() {
      _isLoadingMoreHistory = true;
    });

    try {
      final nextPage = _historyPage + 1;
      final filtro = _historyFilterAmbiente == 'Todos'
          ? null
          : _historyFilterAmbiente;
      final paged = await OracleCredencialesService.instance.consultarHistorial(
        ambiente: filtro,
        top: _historyPageSize,
        pagina: nextPage,
      );
      if (mounted) {
        setState(() {
          _historyPage = nextPage;
          _historyItems.addAll(paged.items);
          _historyTotal = paged.total;
          _hasMoreHistory = _historyItems.length < _historyTotal;
          _isLoadingMoreHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMoreHistory = false;
        });
        AppToast.error('Error al cargar más historial: $e');
      }
    }
  }

  String _formatRelativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 45) return 'Hace un momento';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays}d';
    final local = dt.toLocal();
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$d/$m/$y';
  }

  String _formatAbsoluteDate(DateTime dt) {
    final l = dt.toLocal();
    final y = l.year;
    final m = l.month.toString().padLeft(2, '0');
    final d = l.day.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    final ss = l.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  Future<void> _copiarAlPortapapeles(
    OracleCredencialHistorialEntry item,
  ) async {
    final buf = StringBuffer();
    buf.writeln('=== AUDITORÍA CREDENCIALES ORACLE ===');
    buf.writeln('ID: ${item.id}');
    buf.writeln('Ambiente: ${item.ambiente}');
    buf.writeln('Acción: ${item.accion}');
    buf.writeln('Usuario: ${item.cdUsuario}');
    buf.writeln('Fecha (Local): ${_formatAbsoluteDate(item.fechaCambioUtc)}');
    buf.writeln('Cambio Usuario: ${item.userIdAntes} → ${item.userIdDespues}');
    if (item.hostAntes != null || item.hostDespues != null) {
      buf.writeln(
        'Cambio Host: ${item.hostAntes ?? '(no fijado)'} → ${item.hostDespues ?? '(no fijado)'}',
      );
    }
    if (item.puertoAntes != null || item.puertoDespues != null) {
      buf.writeln(
        'Cambio Puerto: ${item.puertoAntes ?? '(no fijado)'} → ${item.puertoDespues ?? '(no fijado)'}',
      );
    }
    if (item.passwordAntes.isNotEmpty || item.passwordDespues.isNotEmpty) {
      buf.writeln('Contraseña Anterior: ${item.passwordAntes}');
      buf.writeln('Contraseña Nueva: ${item.passwordDespues}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    AppToast.success('Registro de auditoría copiado al portapapeles');
  }

  // ── UI Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bg = isDark ? const Color(0xFF1E1F25) : Colors.white;
    final borderColor = isDark ? const Color(0xFF33353F) : Colors.grey.shade300;
    final screen = MediaQuery.sizeOf(context);

    if (_maximized) {
      _winW = (screen.width - 24).clamp(480.0, screen.width);
      _winH = (screen.height - 24).clamp(420.0, screen.height);
    } else {
      _winW ??= math.min(960.0, screen.width * 0.94);
      _winH ??= math.min(820.0, screen.height * 0.92);
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
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_maximized) {
            _toggleMaximized();
          } else {
            _closeDialog();
          }
        },
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
                      _maximized ? 0 : (_minimized ? 8 : 16),
                    ),
                    border: Border.all(
                      color: isDark
                          ? borderColor
                          : cs.outlineVariant.withValues(alpha: 0.7),
                      width: 1.0,
                    ),
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
                          title: 'Servidor SirWeb & Oracle',
                          icon: Icons.dns_rounded,
                          accentColor: cs.primary,
                          badge: _selectedAmbiente.toUpperCase(),
                          badgeColor: _selectedAmbiente.toLowerCase() == 'prod'
                              ? Colors.red.shade700
                              : cs.primary,
                          onRestore: _toggleMinimized,
                          onClose: _closeDialog,
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Encabezado Constellation
                                _buildHeader(cs, isDark),

                                // Barra de Pestañas
                                Container(
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF252731)
                                        : const Color(0xFFF3F5F8),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: isDark
                                            ? borderColor
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                  ),
                                  child: TabBar(
                                    controller: _tabController,
                                    isScrollable: false,
                                    labelColor: cs.primary,
                                    unselectedLabelColor: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                    indicatorColor: cs.primary,
                                    indicatorWeight: 3,
                                    labelStyle: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                    tabs: const [
                                      Tab(
                                        icon: Icon(Icons.dns_rounded, size: 18),
                                        text: 'Servidor SirWeb',
                                      ),
                                      Tab(
                                        icon: Icon(Icons.key_rounded, size: 18),
                                        text: 'Ambientes Oracle & Credenciales',
                                      ),
                                      Tab(
                                        icon: Icon(Icons.history_rounded, size: 18),
                                        text: 'Historial de Auditoría',
                                      ),
                                    ],
                                  ),
                                ),

                                // Contenido con TabBarView
                                Expanded(
                                  child: TabBarView(
                                    controller: _tabController,
                                    children: [
                                      _buildServidorTab(cs, isDark),
                                      _buildOracleCredencialesTab(cs, isDark),
                                      _buildHistorialTab(cs, isDark),
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
                        600.0,
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
                        480.0,
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
                        600.0,
                        screen.width - 20,
                      );
                      _winH = (_winH! + d.delta.dy).clamp(
                        480.0,
                        screen.height - 20,
                      );
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _minimized ? _toggleMinimized : _toggleMaximized,
      child: MouseRegion(
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
            height: 64,
            onDark: true,
            lineColor: Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(_maximized ? 0 : 16),
              topRight: Radius.circular(_maximized ? 0 : 16),
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary,
                  Color.lerp(
                        cs.primary,
                        isDark ? Colors.black : const Color(0xFF003D73),
                        0.45,
                      ) ??
                      cs.primary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(_maximized ? 0 : 16),
                topRight: Radius.circular(_maximized ? 0 : 16),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
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
                      width: 1.6,
                    ),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Configuración del Servidor y Credenciales Oracle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Conexión base, rotación en caliente por ambiente y auditoría',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                WindowButton(
                  icon: Icons.remove_rounded,
                  tooltip: 'Minimizar',
                  onTap: _toggleMinimized,
                ),
                const SizedBox(width: 2),
                WindowButton(
                  icon: _maximized
                      ? Icons.close_fullscreen_rounded
                      : Icons.crop_square_rounded,
                  tooltip: _maximized
                      ? 'Restaurar tamaño (F11)'
                      : 'Maximizar (F11)',
                  onTap: _toggleMaximized,
                ),
                const SizedBox(width: 2),
                WindowButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Cerrar (Esc)',
                  isClose: true,
                  onTap: _closeDialog,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Tab 1 Widget ───────────────────────────────────────────────────────────

  Widget _buildServidorTab(ColorScheme cs, bool isDark) {
    final cardBg = isDark ? const Color(0xFF252731) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF33353F) : Colors.grey.shade300;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _serverFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link_rounded, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Dirección Base del Servidor (REST / MCP)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: 'ej: http://localhost:5179',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1B1C22)
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      prefixIcon: const Icon(Icons.language_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Probar ping a la URL',
                        icon: _isTestingPing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.network_check_rounded),
                        onPressed: _isTestingPing
                            ? null
                            : _probarConexionServidor,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'La URL no puede estar vacía';
                      }
                      final trimmed = value.trim();
                      if (!trimmed.startsWith('http://') &&
                          !trimmed.startsWith('https://')) {
                        return 'La URL debe comenzar con http:// o https://';
                      }
                      try {
                        Uri.parse(trimmed);
                      } catch (_) {
                        return 'Formato de URL no válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Valor predeterminado: ${ServerConfigService.getDefault()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.restore_rounded, size: 16),
                        label: const Text('Restablecer predeterminado'),
                        onPressed: _resetServidorDefault,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Resultado de ping
            if (_pingMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: (_pingSuccess ?? false)
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (_pingSuccess ?? false) ? Colors.green : Colors.red,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      (_pingSuccess ?? false)
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      color: (_pingSuccess ?? false)
                          ? Colors.green
                          : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pingMessage!,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: (_pingSuccess ?? false)
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                    if (_pingLatencyMs != null)
                      Text(
                        '${_pingLatencyMs}ms',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: (_pingSuccess ?? false)
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Al guardar la dirección base, todas las operaciones de la app '
                      '(MCP, ejecución de procedimientos dinámicos, navegador de esquemas y llamadas REST) '
                      'se redirigirán inmediatamente al nuevo destino sin necesidad de reiniciar la app.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white70 : Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isSavingServer ? null : _guardarServidor,
                icon: _isSavingServer
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text('Guardar Configuración'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 2 Widget ───────────────────────────────────────────────────────────

  Widget _buildOracleCredencialesTab(ColorScheme cs, bool isDark) {
    if (_isLoadingCredentials) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Consultando credenciales vigentes en el servidor...',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      );
    }

    if (_credentialsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.redAccent,
                  size: 40,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'No se pudo obtener el estado de credenciales',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                _credentialsError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade400, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cargarCredencialesOracle,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar conexión'),
              ),
            ],
          ),
        ),
      );
    }

    final cardBg = isDark ? const Color(0xFF252731) : Colors.white;
    final borderColor = isDark ? const Color(0xFF33353F) : Colors.grey.shade300;
    final curStatus = _currentStatus;
    final isOverride = curStatus?.isOverride ?? false;
    final ambColor = AmbienteSelector.colorForAmbiente(_selectedAmbiente);
    final isProd = _selectedAmbiente.toUpperCase() == 'PROD';

    // Detección de cambios ("dirty state")
    final currentInputUser = _userIdController.text.trim();
    final currentInputPass = _passwordController.text;
    final currentInputHost = _hostController.text.trim();
    final currentInputPort = _portController.text.trim();
    final originalUser = (curStatus?.userId ?? '').trim();
    final originalPass = curStatus?.password ?? '';
    final originalHost = (curStatus?.host ?? '').trim();
    final originalPort = (curStatus?.port ?? '').trim();
    final hasPendingChanges =
        (currentInputUser != originalUser) ||
        (currentInputPass != originalPass) ||
        (currentInputHost != originalHost) ||
        (currentInputPort != originalPort);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Selector de Ambientes en Tarjetas Compactas ────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Seleccionar Ambiente:',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: 'Refrescar credenciales desde el servidor',
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                onPressed: _cargarCredencialesOracle,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Grid horizontal de tarjetas de ambiente
          LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AmbienteSelector.ambientes.map((amb) {
                  final isSel =
                      amb.toLowerCase() == _selectedAmbiente.toLowerCase();
                  final itemColor = AmbienteSelector.colorForAmbiente(amb);
                  final statusObj = _credentials.firstWhere(
                    (c) => c.ambiente.toLowerCase() == amb.toLowerCase(),
                    orElse: () => OracleCredentialStatus(
                      ambiente: amb,
                      userId: '',
                      password: '',
                      host: '',
                      port: '',
                      origen: 'Config',
                    ),
                  );
                  final itemOverride = statusObj.isOverride;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedAmbiente = amb;
                        _sincronizarCamposAmbienteActual();
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSel
                            ? itemColor.withValues(alpha: isDark ? 0.22 : 0.12)
                            : (isDark
                                  ? const Color(0xFF22242D)
                                  : const Color(0xFFF8FAFC)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSel
                              ? itemColor
                              : (isDark
                                    ? const Color(0xFF33353F)
                                    : Colors.grey.shade300),
                          width: isSel ? 1.8 : 1.0,
                        ),
                        boxShadow: isSel
                            ? [
                                BoxShadow(
                                  color: itemColor.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            AmbienteSelector.iconForAmbiente(amb),
                            size: 17,
                            color: itemColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            amb,
                            style: TextStyle(
                              fontWeight: isSel
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 13,
                              color: isSel
                                  ? (isDark ? Colors.white : itemColor)
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Mini-badge de estado
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: itemOverride
                                  ? Colors.amber.withValues(alpha: 0.2)
                                  : Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: itemOverride
                                        ? Colors.amber.shade700
                                        : Colors.blue.shade600,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  itemOverride ? 'Override' : 'Config',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: itemOverride
                                        ? Colors.amber.shade800
                                        : Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 18),

          // ── Tarjeta de Estado y Edición del Ambiente Seleccionado ──────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera del Ambiente
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: ambColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ambColor.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Icon(
                            AmbienteSelector.iconForAmbiente(_selectedAmbiente),
                            color: ambColor,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Credenciales para $_selectedAmbiente',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: ambColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Define el usuario, contraseña, servidor host y puerto de conexión',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Badge de origen detallado
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isOverride
                            ? Colors.amber.withValues(alpha: 0.16)
                            : Colors.blue.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isOverride
                              ? Colors.amber.shade700
                              : Colors.blue.shade600,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOverride
                                ? Icons.bolt_rounded
                                : Icons.verified_user_outlined,
                            size: 14,
                            color: isOverride
                                ? Colors.amber.shade800
                                : Colors.blue.shade700,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isOverride
                                ? 'Override Activo en Memoria'
                                : 'Configuración Original (appsettings)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isOverride
                                  ? Colors.amber.shade800
                                  : Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Alerta si es PROD
                if (isProd) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.red.shade400,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '¡Atención! Estás modificando el ambiente de PRODUCCIÓN. '
                            'Cualquier cambio de credenciales afectará en caliente todas las consultas, transacciones y '
                            'auditorías sobre la base de datos productiva.',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Formulario de credenciales estilizado
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Campo Usuario
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.badge_rounded,
                                size: 14,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Usuario Oracle (UserId):',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _userIdController,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'ej: SIRWEB',
                              isDense: true,
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF1E1F25)
                                  : const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: ambColor,
                                  width: 1.6,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.person_rounded,
                                size: 17,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Campo Contraseña
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.key_rounded,
                                size: 14,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Contraseña (Password):',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Ingresa la contraseña de Oracle',
                              isDense: true,
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF1E1F25)
                                  : const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: ambColor,
                                  width: 1.6,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.lock_rounded,
                                size: 17,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Mostrar contraseña'
                                    : 'Ocultar contraseña',
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  size: 17,
                                ),
                                onPressed: () {
                                  setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  );
                                },
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Campos Host y Puerto de Conexión
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Campo Host
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.dns_rounded,
                                size: 14,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Host / Servidor DB:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _hostController,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'ej: 10.10.1.20 o db-oracle.local',
                              isDense: true,
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF1E1F25)
                                  : const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: ambColor,
                                  width: 1.6,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.computer_rounded,
                                size: 17,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Campo Puerto
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.numbers_rounded,
                                size: 14,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Puerto:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _portController,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'ej: 1521',
                              isDense: true,
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF1E1F25)
                                  : const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: ambColor,
                                  width: 1.6,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.settings_ethernet_rounded,
                                size: 17,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Detección de cambios sin aplicar
                if (hasPendingChanges) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade600),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          size: 17,
                          color: Colors.amber.shade800,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Has modificado las credenciales. Pulsa "Aplicar en Caliente" para activar los cambios.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Advertencia explicativa
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1F25)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El cambio de credenciales vive exclusivamente en la memoria del servidor backend. '
                          'Al reiniciar el proceso del servidor volverá a las credenciales fijadas en appsettings.json. '
                          'Todo cambio queda registrado en la auditoría con tu usuario actual.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Barra de Acciones y Firma de Auditoría
                Row(
                  children: [
                    // Firma de usuario
                    Icon(
                      Icons.account_circle_outlined,
                      size: 16,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Firma auditoría: ${procedimientosProvider.cdUsuario.isEmpty ? '(Anónimo)' : procedimientosProvider.cdUsuario}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white60 : Colors.grey.shade700,
                      ),
                    ),
                    const Spacer(),

                    // Botón Restablecer
                    if (isOverride) ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade800,
                          side: BorderSide(color: Colors.orange.shade600),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isRestoringConfig
                            ? null
                            : _restablecerCredencialesConfig,
                        icon: _isRestoringConfig
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.undo_rounded, size: 18),
                        label: const Text('Restablecer a Config Original'),
                      ),
                      const SizedBox(width: 12),
                    ],

                    // Botón Aplicar en Caliente
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: ambColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isApplyingOverride
                          ? null
                          : _aplicarOverrideCredenciales,
                      icon: _isApplyingOverride
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.bolt_rounded, size: 18),
                      label: const Text('Aplicar en Caliente (Override)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 3 Widget ───────────────────────────────────────────────────────────

  Widget _buildHistorialTab(ColorScheme cs, bool isDark) {
    final borderColor = isDark ? const Color(0xFF33353F) : Colors.grey.shade300;

    // Filtrar elementos en memoria por query de búsqueda
    final query = _historySearchQuery.trim().toLowerCase();
    final itemsFiltrados = query.isEmpty
        ? _historyItems
        : _historyItems.where((item) {
            return item.cdUsuario.toLowerCase().contains(query) ||
                item.ambiente.toLowerCase().contains(query) ||
                item.accion.toLowerCase().contains(query) ||
                item.id.toLowerCase().contains(query) ||
                item.userIdAntes.toLowerCase().contains(query) ||
                item.userIdDespues.toLowerCase().contains(query);
          }).toList();

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra superior: Búsqueda, Filtro por ambiente, Contador y Refresco
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF252731) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Campo de búsqueda
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 220,
                    maxWidth: 300,
                  ),
                  child: TextField(
                    controller: _historySearchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Buscar por usuario, ambiente o ID...',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: _historySearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              tooltip: 'Limpiar búsqueda',
                              onPressed: () {
                                _historySearchCtrl.clear();
                                setState(() => _historySearchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E1F25)
                          : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: cs.primary, width: 1.5),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() => _historySearchQuery = val);
                    },
                  ),
                ),

                // Filtro por ambiente & Contador
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ambiente:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1F25) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _historyFilterAmbiente,
                          isDense: true,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          items: ['Todos', ...AmbienteSelector.ambientes].map((
                            a,
                          ) {
                            final ambColor = a == 'Todos'
                                ? cs.primary
                                : AmbienteSelector.colorForAmbiente(a);
                            return DropdownMenuItem(
                              value: a,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: ambColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(a),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _historyFilterAmbiente = val);
                              _cargarHistorial(reset: true);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Badge de conteo de eventos
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '${itemsFiltrados.length} / $_historyTotal eventos',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Botón refrescar
                    IconButton.filledTonal(
                      tooltip: 'Refrescar auditoría',
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: _isLoadingHistory
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      onPressed: _isLoadingHistory
                          ? null
                          : () => _cargarHistorial(reset: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Contenedor principal de la lista con Scroll Infinito (Carga Progresiva)
          Expanded(
            child: _isLoadingHistory && _historyItems.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _historyError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 40,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _historyError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: () => _cargarHistorial(reset: true),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
                : itemsFiltrados.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_toggle_off_rounded,
                          size: 52,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _historySearchQuery.isNotEmpty
                              ? 'No se encontraron eventos coincidentes con "$_historySearchQuery"'
                              : 'No hay registros de auditoría de credenciales',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.white60
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _historyScrollCtrl,
                    padding: const EdgeInsets.only(right: 6, bottom: 12),
                    itemCount:
                        itemsFiltrados.length +
                        (_hasMoreHistory || _isLoadingMoreHistory ? 1 : 1),
                    itemBuilder: (context, index) {
                      // Pie de lista: Spinner de carga progresiva o fin del historial
                      if (index == itemsFiltrados.length) {
                        if (_isLoadingMoreHistory) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Cargando más eventos...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        if (!_hasMoreHistory && itemsFiltrados.isNotEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: Text(
                                '— Fin del historial de auditoría (${itemsFiltrados.length} registros cargados) —',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontStyle: FontStyle.italic,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ),
                          );
                        }

                        return const SizedBox.shrink();
                      }

                      final item = itemsFiltrados[index];
                      final isLast =
                          index == itemsFiltrados.length - 1 &&
                          !_hasMoreHistory;
                      return _buildTimelineCard(
                        item: item,
                        isDark: isDark,
                        cs: cs,
                        borderColor: borderColor,
                        isLast: isLast,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard({
    required OracleCredencialHistorialEntry item,
    required bool isDark,
    required ColorScheme cs,
    required Color borderColor,
    required bool isLast,
  }) {
    final ambColor = AmbienteSelector.colorForAmbiente(item.ambiente);
    final isActualizar = item.accion.toLowerCase() == 'actualizar';
    final isRestablecer = item.accion.toLowerCase() == 'restablecer';
    final isRevealed = _revealedPasswordIds.contains(item.id);

    final actionColor = isActualizar
        ? Colors.amber.shade700
        : (isRestablecer ? Colors.blue.shade600 : Colors.purple.shade600);
    final actionIcon = isActualizar
        ? Icons.edit_calendar_rounded
        : Icons.restore_rounded;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Columna izquierda: Línea conectora y nodo de tiempo
          SizedBox(
            width: 38,
            child: Column(
              children: [
                // Icono nodo circular
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: actionColor, width: 1.5),
                  ),
                  child: Icon(actionIcon, size: 15, color: actionColor),
                ),
                // Línea vertical continua hasta el siguiente item
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: isDark
                          ? const Color(0xFF33353F)
                          : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Columna derecha: Tarjeta detallada con Diff y controles
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF252731) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header de la tarjeta: Badges, Usuario, Fechas y Botón Copiar
                  Row(
                    children: [
                      // Badge de Ambiente
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: ambColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: ambColor, width: 1),
                        ),
                        child: Text(
                          item.ambiente,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ambColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Badge de Acción
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.accion,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: actionColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Usuario que ejecutó
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 14,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                item.cdUsuario,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Fecha y hora
                      Tooltip(
                        message: _formatAbsoluteDate(item.fechaCambioUtc),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 13,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatRelativeDate(item.fechaCambioUtc),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Botón Copiar registro
                      IconButton(
                        tooltip: 'Copiar detalle del cambio',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        onPressed: () => _copiarAlPortapapeles(item),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Caja de Diff: Comparativa de Usuario y Contraseña
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1F25)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF33353F)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Comparativa de Usuario
                        Row(
                          children: [
                            SizedBox(
                              width: 80,
                              child: Text(
                                'Usuario:',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                item.userIdAntes.isEmpty
                                    ? '(vacío)'
                                    : item.userIdAntes,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  color: item.userIdAntes != item.userIdDespues
                                      ? Colors.red.shade400
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.black87),
                                  decoration:
                                      item.userIdAntes != item.userIdDespues
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: Colors.grey,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                item.userIdDespues.isEmpty
                                    ? '(vacío)'
                                    : item.userIdDespues,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: item.userIdAntes != item.userIdDespues
                                      ? Colors.green.shade600
                                      : (isDark ? Colors.white : Colors.black),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Comparativa de Contraseña con toggle de visibilidad
                        Row(
                          children: [
                            SizedBox(
                              width: 80,
                              child: Text(
                                'Contraseña:',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                isRevealed
                                    ? (item.passwordAntes.isEmpty
                                          ? '(vacía)'
                                          : item.passwordAntes)
                                    : '••••••••',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                  decoration:
                                      item.passwordAntes !=
                                              item.passwordDespues &&
                                          isRevealed
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: Colors.grey,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                isRevealed
                                    ? (item.passwordDespues.isEmpty
                                          ? '(vacía)'
                                          : item.passwordDespues)
                                    : '••••••••',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      item.passwordAntes != item.passwordDespues
                                      ? Colors.green.shade600
                                      : (isDark ? Colors.white : Colors.black),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Botón Revelar / Ocultar Contraseña
                            IconButton(
                              tooltip: isRevealed
                                  ? 'Ocultar contraseña'
                                  : 'Ver contraseña',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              icon: Icon(
                                isRevealed
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 15,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (isRevealed) {
                                    _revealedPasswordIds.remove(item.id);
                                  } else {
                                    _revealedPasswordIds.add(item.id);
                                  }
                                });
                              },
                            ),
                          ],
                        ),

                        // Comparativa de Host (si hubo cambio o si está registrado)
                        if (item.hostAntes != null ||
                            item.hostDespues != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: Text(
                                  'Host:',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  (item.hostAntes == null ||
                                          item.hostAntes!.isEmpty)
                                      ? '(no fijado)'
                                      : item.hostAntes!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    color: item.hostAntes != item.hostDespues
                                        ? Colors.red.shade400
                                        : (isDark
                                              ? Colors.white70
                                              : Colors.black87),
                                    decoration:
                                        item.hostAntes != item.hostDespues
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 13,
                                  color: Colors.grey,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  (item.hostDespues == null ||
                                          item.hostDespues!.isEmpty)
                                      ? '(no fijado)'
                                      : item.hostDespues!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: item.hostAntes != item.hostDespues
                                        ? Colors.green.shade600
                                        : (isDark
                                              ? Colors.white
                                              : Colors.black),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Comparativa de Puerto (si hubo cambio o si está registrado)
                        if (item.puertoAntes != null ||
                            item.puertoDespues != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: Text(
                                  'Puerto:',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  (item.puertoAntes == null ||
                                          item.puertoAntes!.isEmpty)
                                      ? '(no fijado)'
                                      : item.puertoAntes!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    color:
                                        item.puertoAntes != item.puertoDespues
                                        ? Colors.red.shade400
                                        : (isDark
                                              ? Colors.white70
                                              : Colors.black87),
                                    decoration:
                                        item.puertoAntes != item.puertoDespues
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 13,
                                  color: Colors.grey,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  (item.puertoDespues == null ||
                                          item.puertoDespues!.isEmpty)
                                      ? '(no fijado)'
                                      : item.puertoDespues!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        item.puertoAntes != item.puertoDespues
                                        ? Colors.green.shade600
                                        : (isDark
                                              ? Colors.white
                                              : Colors.black),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
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
}
