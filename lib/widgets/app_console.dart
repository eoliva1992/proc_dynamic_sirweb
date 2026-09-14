import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_log.dart';
import 'app_toast.dart';
import 'floating_window.dart';

// ── Consola integrada ───────────────────────────────────────────────────────
//
// Panel acoplado al borde inferior que muestra el historial de [AppLog]:
// compilaciones, transferencias entre ambientes, errores ORA/PLS y cualquier
// mensaje que la app haya mostrado como toast.

VoidCallback? _closeConsole;

/// `true` si la consola ya está abierta.
bool get isAppConsoleOpen => _closeConsole != null;

/// Abre (o trae al frente) la consola de la aplicación.
void showAppConsole(BuildContext context) {
  AppLog.instance.markSeen();
  if (_closeConsole != null) return;
  _closeConsole = showFloatingWindow(
    context,
    (close) => _ConsoleWindow(
      onClose: () {
        close();
        _closeConsole = null;
      },
    ),
  );
}

/// Cierra la consola si está abierta.
void closeAppConsole() {
  _closeConsole?.call();
  _closeConsole = null;
}

/// Botón de barra superior con contador de errores sin ver.
class AppConsoleButton extends StatelessWidget {
  const AppConsoleButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLog.instance,
      builder: (context, _) {
        final errores = AppLog.instance.unseenErrors;
        return Tooltip(
          message: errores > 0
              ? 'Consola de la aplicación — $errores error(es) nuevo(s) '
                    '(Ctrl+Shift+L)'
              : 'Consola de la aplicación (Ctrl+Shift+L)',
          child: IconButton(
            onPressed: () => showAppConsole(context),
            color: color,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.terminal_rounded),
                if (errores > 0)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      constraints: const BoxConstraints(minWidth: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5484D),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        errores > 99 ? '99+' : '$errores',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConsoleWindow extends StatefulWidget {
  const _ConsoleWindow({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_ConsoleWindow> createState() => _ConsoleWindowState();
}

class _ConsoleWindowState extends State<_ConsoleWindow> {
  static const double _minH = 140;
  double _height = 300;

  /// Niveles activos. Vacío = se muestran todos.
  final Set<LogLevel> _niveles = <LogLevel>{};
  bool _onlyServer = false;
  String _filter = '';
  final _filterCtrl = TextEditingController();

  /// La lista se dibuja con la entrada más reciente arriba: este controller
  /// sirve para volver al tope apenas se registra algo nuevo, sin scrollear.
  final _scrollCtrl = ScrollController();

  /// Entradas llegadas mientras el usuario estaba leyendo más abajo.
  int _pendientes = 0;
  int _ultimoTotal = 0;

  @override
  void initState() {
    super.initState();
    _ultimoTotal = AppLog.instance.length;
    AppLog.instance.addListener(_onLog);
  }

  @override
  void dispose() {
    AppLog.instance.removeListener(_onLog);
    _filterCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Al registrarse una entrada nueva se salta al tope (donde aparece).
  ///
  /// Si el usuario está leyendo más abajo no se le mueve la vista: se le avisa
  /// con el contador de pendientes, que lleva al tope con un clic.
  void _onLog() {
    final total = AppLog.instance.length;
    final nuevas = total - _ultimoTotal;
    _ultimoTotal = total;
    if (nuevas <= 0) {
      if (_pendientes != 0) setState(() => _pendientes = 0);
      return;
    }
    if (!_scrollCtrl.hasClients || _scrollCtrl.offset <= 80) {
      _scrollToTop();
    } else {
      setState(() => _pendientes += nuevas);
    }
  }

  void _scrollToTop() {
    if (_pendientes != 0) setState(() => _pendientes = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  /// Entradas cuyo detalle está desplegado. Por defecto todo va colapsado:
  /// la consola muestra una línea por evento y el detalle se abre a pedido.
  final Set<LogEntry> _expandidos = Set<LogEntry>.identity();

  void _toggleDetalle(LogEntry e) => setState(() {
    if (!_expandidos.remove(e)) _expandidos.add(e);
  });

  /// Despliega todos los detalles visibles, o los cierra si ya estaban abiertos.
  void _toggleTodos() {
    final conDetalle = _visible
        .where((e) => (e.detail ?? '').trim().isNotEmpty)
        .toList();
    setState(() {
      if (conDetalle.every(_expandidos.contains) && conDetalle.isNotEmpty) {
        _expandidos.removeAll(conDetalle);
      } else {
        _expandidos.addAll(conDetalle);
      }
    });
  }

  List<LogEntry> get _visible {
    final q = _filter.trim().toLowerCase();
    return AppLog.instance.entries.where((e) {
      if (_niveles.isNotEmpty && !_niveles.contains(e.level)) return false;
      if (_onlyServer && !e.source.toLowerCase().contains('servidor')) {
        return false;
      }
      if (q.isEmpty) return true;
      return e.message.toLowerCase().contains(q) ||
          e.source.toLowerCase().contains(q) ||
          (e.detail?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// Activa/desactiva un grupo de niveles desde un chip.
  void _toggleNiveles(Set<LogLevel> grupo, bool activar) {
    setState(() {
      if (activar) {
        _niveles.addAll(grupo);
      } else {
        _niveles.removeAll(grupo);
      }
    });
  }

  int _contar(Set<LogLevel> grupo) =>
      grupo.fold(0, (t, l) => t + AppLog.instance.countOf(l));

  Color _levelColor(LogLevel l) => switch (l) {
    LogLevel.error => const Color(0xFFE5484D),
    LogLevel.warning => const Color(0xFFE2A03F),
    LogLevel.success => const Color(0xFF3FB950),
    LogLevel.info => const Color(0xFF4C9AFF),
    LogLevel.debug => const Color(0xFF8B949E),
  };

  Future<void> _copyAll() async {
    final texto = _visible.reversed.map((e) => e.asText).join('\n');
    if (texto.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: texto));
    AppToast.info('Log copiado al portapapeles');
  }

  Future<void> _saveToFile() async {
    final texto = AppLog.instance.asText();
    if (texto.isEmpty) return;
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    final path = await FilePicker.saveFile(
      dialogTitle: 'Guardar log',
      fileName:
          'sirweb_${now.year}${p(now.month)}${p(now.day)}_'
          '${p(now.hour)}${p(now.minute)}.log',
      type: FileType.custom,
      allowedExtensions: ['log', 'txt'],
    );
    if (path == null) return;
    await File(path).writeAsString(texto, flush: true);
    AppToast.success('Log guardado');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFFBFBFD);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          elevation: 12,
          color: bg,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: _height,
            child: Column(
              children: [
                _resizeHandle(cs),
                _header(cs, isDark),
                Expanded(child: _list(cs, isDark)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Borde superior arrastrable para cambiar el alto de la consola.
  Widget _resizeHandle(ColorScheme cs) => MouseRegion(
    cursor: SystemMouseCursors.resizeUpDown,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        final maxH = MediaQuery.of(context).size.height - 120;
        setState(() => _height = (_height - d.delta.dy).clamp(_minH, maxH));
      },
      child: SizedBox(
        height: 8,
        child: Center(
          child: Container(
            width: 42,
            height: 3,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header(ColorScheme cs, bool isDark) {
    return Container(
      height: 38,
      // Menos padding a la derecha: los botones de acción tienen su propio
      // padding interno y así quedan alineados con el borde de la ventana.
      padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : const Color(0xFFF1F3F5),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      // El header se adapta: en ventanas angostas se van ocultando el contador,
      // los chips y el buscador antes que las acciones.
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final mostrarContador = w >= 900;
          final mostrarChips = w >= 520;
          final mostrarBuscador = w >= 400;
          return Row(
            children: [
              Icon(
                Icons.terminal_rounded,
                size: 15,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              const Text(
                'CONSOLA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              if (mostrarBuscador) ...[
                const SizedBox(width: 12),
                // Ancho fijo: si fuera flexible, el espacio que no usa quedaría
                // como hueco muerto y correría las acciones hacia el centro.
                SizedBox(
                  width: 200,
                  height: 26,
                  child: TextField(
                    controller: _filterCtrl,
                    onChanged: (v) => setState(() => _filter = v),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filtrar…',
                      hintStyle: const TextStyle(fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 14),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
              if (mostrarChips) ...[
                const SizedBox(width: 8),
                // Expanded (no Flexible): absorbe todo el sobrante para que las
                // acciones queden pegadas al borde derecho. Con scroll
                // horizontal los chips nunca desbordan la barra.
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _nivelChip(
                          'Problemas',
                          const {LogLevel.error},
                          const Color(0xFFE5484D),
                          'Sólo errores',
                        ),
                        const SizedBox(width: 5),
                        _nivelChip(
                          'Warnings',
                          const {LogLevel.warning},
                          const Color(0xFFE2A03F),
                          'Sólo advertencias',
                        ),
                        const SizedBox(width: 5),
                        _nivelChip(
                          'Info',
                          const {
                            LogLevel.info,
                            LogLevel.success,
                            LogLevel.debug,
                          },
                          const Color(0xFF4C9AFF),
                          'Transacciones y mensajes informativos',
                        ),
                        const SizedBox(width: 5),
                        FilterChip(
                          label: const Text(
                            'Servidor',
                            style: TextStyle(fontSize: 11),
                          ),
                          tooltip: 'Sólo respuestas del backend',
                          selected: _onlyServer,
                          onSelected: (v) => setState(() => _onlyServer = v),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              // Con los chips visibles ya hay un Expanded que empuja; sin ellos
              // hace falta el Spacer para pegar las acciones a la derecha.
              if (!mostrarChips) const Spacer(),
              if (mostrarContador) ...[
                ListenableBuilder(
                  listenable: AppLog.instance,
                  builder: (_, _) => Text(
                    '${AppLog.instance.length} entrada(s)',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              _iconBtn(
                Icons.unfold_more_rounded,
                'Expandir / colapsar detalles',
                _toggleTodos,
                cs,
              ),
              _iconBtn(Icons.copy_all_rounded, 'Copiar todo', _copyAll, cs),
              _iconBtn(Icons.save_alt_rounded, 'Guardar .log', _saveToFile, cs),
              _iconBtn(
                Icons.delete_sweep_outlined,
                'Limpiar',
                () => setState(AppLog.instance.clear),
                cs,
              ),
              _iconBtn(Icons.close_rounded, 'Cerrar', widget.onClose, cs),
            ],
          );
        },
      ),
    );
  }

  /// Chip de filtro por nivel con su contador y el color de la severidad.
  Widget _nivelChip(
    String label,
    Set<LogLevel> grupo,
    Color color,
    String tooltip,
  ) {
    final total = _contar(grupo);
    final activo = grupo.every(_niveles.contains);
    return FilterChip(
      label: Text(
        total > 0 ? '$label ($total)' : label,
        style: TextStyle(
          fontSize: 11,
          color: activo ? color : null,
          fontWeight: activo ? FontWeight.w600 : null,
        ),
      ),
      tooltip: tooltip,
      selected: activo,
      showCheckmark: false,
      avatar: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      selectedColor: color.withValues(alpha: 0.18),
      side: activo ? BorderSide(color: color.withValues(alpha: 0.6)) : null,
      onSelected: (v) => _toggleNiveles(grupo, v),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _iconBtn(
    IconData icon,
    String tip,
    VoidCallback onTap,
    ColorScheme cs,
  ) => Tooltip(
    message: tip,
    child: InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 15, color: cs.onSurfaceVariant),
      ),
    ),
  );

  Widget _list(ColorScheme cs, bool isDark) {
    return ListenableBuilder(
      listenable: AppLog.instance,
      builder: (context, _) {
        final items = _visible;
        if (items.isEmpty) {
          return Center(
            child: Text(
              AppLog.instance.isEmpty
                  ? 'Sin actividad registrada todavía'
                  : 'Ninguna entrada coincide con el filtro',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          );
        }
        return Stack(
          children: [
            // Orden: la entrada más reciente siempre primera (arriba).
            ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              itemBuilder: (context, i) => _row(items[i], cs, isDark),
            ),
            if (_pendientes > 0)
              Positioned(
                top: 6,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 3,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _scrollToTop,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_upward_rounded,
                              size: 13,
                              color: cs.onPrimary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$_pendientes entrada(s) nueva(s)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _row(LogEntry e, ColorScheme cs, bool isDark) {
    final color = _levelColor(e.level);
    final mono = TextStyle(
      fontFamily: 'Consolas',
      fontSize: 12,
      color: cs.onSurface,
    );
    // Códigos Oracle presentes: se destacan para identificar el error de un vistazo.
    final codigos = AppLog.oracleCodes('${e.message}\n${e.detail ?? ''}');
    final detalle = e.detail?.trimRight() ?? '';
    final tieneDetalle = detalle.isNotEmpty;
    final abierto = _expandidos.contains(e);
    final lineas = tieneDetalle ? detalle.split('\n') : const <String>[];
    return InkWell(
      // El detalle arranca colapsado: un clic en la fila lo abre o lo cierra.
      onTap: tieneDetalle ? () => _toggleDetalle(e) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  child: tieneDetalle
                      ? Icon(
                          abierto
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.chevron_right_rounded,
                          size: 15,
                          color: cs.onSurfaceVariant,
                        )
                      : null,
                ),
                Text(
                  e.hhmmss,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    e.level.label,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  e.source,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                for (final c in codigos) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: color.withValues(alpha: 0.6)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: abierto
                      ? SelectableText(e.message, style: mono)
                      : Text(
                          e.message,
                          style: mono,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                if (tieneDetalle && !abierto)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '${lineas.length} línea(s)',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                Tooltip(
                  message: 'Copiar entrada',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: e.asText));
                      AppToast.info('Entrada copiada');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (tieneDetalle && abierto)
              Padding(
                padding: const EdgeInsets.only(left: 82, top: 2, bottom: 2),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.08 : 0.06),
                    border: Border(left: BorderSide(color: color, width: 2)),
                  ),
                  child: SelectableText(
                    detalle,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11.5,
                      color: cs.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
