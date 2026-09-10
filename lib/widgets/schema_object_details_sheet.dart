import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_navigator.dart';
import '../screens/schema_object_diff_page.dart';
import '../services/schema_recents_service.dart';
import '../services/schema_service.dart';
import 'ambiente_selector.dart';
import 'app_toast.dart';
import 'constellation_background.dart';
import 'minimized_object_dock.dart';
import 'source_float_window.dart';

Future<void> showObjectDetails(
  BuildContext context, {
  required String name,
  required String type,
  required String ambiente,
}) {
  SchemaRecentsService.instance.addRecent(
    SchemaObjectRef(name: name, type: type, ambiente: ambiente),
  );
  // El diálogo se monta en el root navigator, por lo que su contexto NO es
  // descendiente del SourceTabController de MainScreen. Usamos el contexto del
  // llamador (p.ej. el sidebar) — exactamente igual que el botón "Ver fuente"
  // de cada fila del sidebar.
  final callerContext = context;
  return showGeneralDialog(
    // Usamos el contexto del Navigator raíz: el del llamador puede estar
    // desactivado (p.ej. si acaba de hacer pop de otro diálogo).
    context: rootDialogContext ?? context,
    barrierDismissible: true,
    barrierLabel: 'object-details',
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, _, anim2) => _ObjectDetailsModal(
      name: name,
      type: type,
      ambiente: ambiente,
      onOpenSource: () => openSourceWindow(
        callerContext,
        name: name,
        objectType: type,
        ambiente: ambiente,
      ),
      onMinimize: () => MinimizedObjectDock.add(
        callerContext,
        name: name,
        type: type,
        ambiente: ambiente,
        onRestore: (restoreContext) => showObjectDetails(
          restoreContext,
          name: name,
          type: type,
          ambiente: ambiente,
        ),
      ),
    ),
  );
}

const _kTypeColors = {
  'TABLE': Color(0xFF0078D4),
  'VIEW': Color(0xFF107C10),
  'PROCEDURE': Color(0xFFCA5010),
  'FUNCTION': Color(0xFF8764B8),
  'PACKAGE': Color(0xFFC19C00),
  'TYPE': Color(0xFF2E7D9E),
};
const _kTypeIcons = {
  'TABLE': Icons.table_chart_outlined,
  'VIEW': Icons.visibility_outlined,
  'PROCEDURE': Icons.code_rounded,
  'FUNCTION': Icons.functions_rounded,
  'PACKAGE': Icons.inventory_2_outlined,
  'TYPE': Icons.data_object_outlined,
};
Color _tc(String t) => _kTypeColors[t] ?? Colors.grey;
IconData _ti(String t) => _kTypeIcons[t] ?? Icons.storage_outlined;

const _kAllSubprograms = '__ALL__';

/// Genera un snippet PL/SQL de ejemplo que muestra cómo *utilizar* el objeto
/// (invocación), no su código fuente. Reutilizable desde el modal de detalles
/// y desde el sidebar de objetos.
///
/// Para `PACKAGE` con más de un subprograma, abre un diálogo para elegir uno
/// específico o todos; retorna `null` si el usuario cancela esa selección.
Future<String?> buildObjectUsageSnippet(
  BuildContext context, {
  required String name,
  required String type,
  required String ambiente,
}) async {
  if (type == 'PACKAGE') {
    return _copyPackageUsage(context, name: name, ambiente: ambiente);
  }
  switch (type) {
    case 'TABLE':
    case 'VIEW':
      final cols = await SchemaService.instance.getColumns(
        name,
        ambiente: ambiente,
      );
      final colList = cols.isEmpty
          ? '*'
          : cols.map((c) => c.name).join(',\n       ');
      return 'SELECT $colList\nFROM   $name;';
    case 'PROCEDURE':
      final args = await SchemaService.instance.getObjectArguments(
        name,
        ambiente: ambiente,
      );
      return _usageForCallable(name, args, isFunction: false);
    case 'FUNCTION':
      final args = await SchemaService.instance.getObjectArguments(
        name,
        ambiente: ambiente,
      );
      return _usageForCallable(name, args, isFunction: true);
    case 'TYPE':
      final attrs = await SchemaService.instance.getTypeAttributes(
        name,
        ambiente: ambiente,
      );
      if (attrs.isEmpty) {
        return 'v_obj $name;'; // colección (TABLE/VARRAY): sin atributos
      }
      final ctorArgs = attrs
          .map((a) => '  ${a.name} /* ${a.dataType} */')
          .join(',\n');
      return 'v_obj := $name(\n$ctorArgs\n);';
    default:
      return name;
  }
}

/// Para paquetes con más de un subprograma, pregunta si se quiere copiar
/// uno específico o el uso de todos. Retorna `null` si el usuario cancela.
Future<String?> _copyPackageUsage(
  BuildContext context, {
  required String name,
  required String ambiente,
}) async {
  final subs = await SchemaService.instance.getPackageSubprograms(
    name,
    ambiente: ambiente,
  );
  if (subs.isEmpty) {
    AppToast.info('$name no expone subprogramas públicos');
    return null;
  }
  String buildFor(
    ({
      String name,
      String kind,
      List<({String name, String dataType, String inOut})> arguments,
    })
    s,
  ) => _usageForCallable(
    '$name.${s.name}',
    s.arguments,
    isFunction: s.kind == 'FUNCTION',
  );
  if (subs.length == 1) return buildFor(subs.first);

  if (!context.mounted) return null;
  final choice = await showDialog<String>(
    context: context,
    builder: (_) => _SubprogramPickerDialog(
      packageName: name,
      subprograms: subs,
      color: _tc('PACKAGE'),
    ),
  );
  if (choice == null) return null;
  if (choice == _kAllSubprograms) {
    return subs.map(buildFor).join('\n\n');
  }
  final selected = subs.firstWhere((s) => s.name == choice);
  return buildFor(selected);
}

String _usageForCallable(
  String qualifiedName,
  List<({String name, String dataType, String inOut})> args, {
  required bool isFunction,
}) {
  final callArgs = args
      .map((a) {
        final tag = a.inOut.isNotEmpty
            ? '${a.dataType} ${a.inOut}'
            : a.dataType;
        return '  ${a.name} => /* $tag */';
      })
      .join(',\n');
  final call = args.isEmpty
      ? '$qualifiedName()'
      : '$qualifiedName(\n$callArgs\n)';
  return isFunction ? 'v_resultado := $call;' : '$call;';
}

class _ObjectDetailsModal extends StatefulWidget {
  final String name;
  final String type;
  final String ambiente;

  /// Abre el fuente usando el contexto del llamador (sidebar / browser), igual
  /// que el botón "Ver fuente" de las filas del sidebar.
  final VoidCallback onOpenSource;

  /// Minimiza el modal al dock flotante (se cierra el diálogo y queda un chip).
  final VoidCallback onMinimize;
  const _ObjectDetailsModal({
    required this.name,
    required this.type,
    required this.ambiente,
    required this.onOpenSource,
    required this.onMinimize,
  });

  @override
  State<_ObjectDetailsModal> createState() => _ObjectDetailsModalState();
}

class _ObjectDetailsModalState extends State<_ObjectDetailsModal> {
  bool _isFavorite = false;

  /// Desplazamiento del modal respecto del centro (arrastre por la cabecera).
  Offset _position = Offset.zero;

  /// Estado del objeto en Oracle (`ALL_OBJECTS.STATUS`): VALID / INVALID.
  /// `null` mientras se está consultando o si no se pudo determinar.
  String? _objectStatus;
  bool _statusLoading = true;

  String get name => widget.name;
  String get type => widget.type;
  String get ambiente => widget.ambiente;

  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
    _loadObjectStatus();
  }

  Future<void> _loadObjectStatus() async {
    try {
      final props = await SchemaService.instance.getObjectInfo(
        name,
        type,
        ambiente: ambiente,
      );
      String? status;
      for (final p in props) {
        if (p.name.toUpperCase() == 'STATUS') {
          status = p.value.trim().toUpperCase();
          break;
        }
      }
      if (mounted) {
        setState(() {
          _objectStatus = status;
          _statusLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  Future<void> _loadFavoriteState() async {
    final fav = await SchemaRecentsService.instance.isFavorite(
      SchemaObjectRef(name: name, type: type, ambiente: ambiente),
    );
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    final ref = SchemaObjectRef(name: name, type: type, ambiente: ambiente);
    if (_isFavorite) {
      await SchemaRecentsService.instance.removeFavorite(ref);
    } else {
      await SchemaRecentsService.instance.addFavorite(ref);
    }
    if (mounted) setState(() => _isFavorite = !_isFavorite);
  }

  void _openSource() {
    Navigator.of(context).pop();
    // Delegamos en el contexto del llamador (sidebar), que sí estÁ dentro del
    // árbol del SourceTabController de MainScreen.
    widget.onOpenSource();
  }

  void _minimize() {
    Navigator.of(context).pop();
    widget.onMinimize();
  }

  void _openBackup() {
    showDialog<void>(
      context: context,
      builder: (_) => _ObjectBackupDialog(
        name: name,
        objectType: type,
        ambiente: ambiente,
        color: _tc(type),
      ),
    );
  }

  void _openDiff() {
    // El comparador es una ventana flotante sin barrera: cerramos el modal de
    // detalles para que quede la app utilizable por detrás.
    final ctx = rootDialogContext ?? context;
    Navigator.of(context).pop();
    showSchemaObjectDiff(
      ctx,
      objectName: name,
      objectType: type,
      sourceAmbiente: ambiente,
    );
  }

  bool _copyingImpl = false;

  Future<void> _copyImplementation() async {
    if (_copyingImpl) return;
    setState(() => _copyingImpl = true);
    try {
      final text = await buildObjectUsageSnippet(
        context,
        name: name,
        type: type,
        ambiente: ambiente,
      );
      if (text == null) return; // el usuario canceló la selección
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: text));
      AppToast.success('Ejemplo de uso copiado al portapapeles');
    } catch (e) {
      if (mounted) AppToast.error('Error al generar ejemplo de uso: $e');
    } finally {
      if (mounted) setState(() => _copyingImpl = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = (size.width * 0.88).clamp(540.0, 880.0);
    final h = (size.height * 0.80).clamp(480.0, 700.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _tc(type);
    // Posición base centrada + desplazamiento acumulado del arrastre, siempre
    // dentro de los límites de la pantalla.
    final left = ((size.width - w) / 2 + _position.dx).clamp(
      0.0,
      (size.width - w).clamp(0.0, double.infinity),
    );
    final top = ((size.height - h) / 2 + _position.dy).clamp(
      0.0,
      (size.height - h).clamp(0.0, double.infinity),
    );
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: w,
          height: h,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: color.withValues(alpha: isDark ? 0.22 : 0.16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.20),
                    blurRadius: 48,
                    spreadRadius: -4,
                    offset: const Offset(0, 20),
                  ),
                  BoxShadow(
                    color: color.withValues(alpha: isDark ? 0.10 : 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      // La cabecera actúa como barra de título: arrastrando
                      // sobre ella se mueve el modal.
                      MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onPanUpdate: (d) =>
                              setState(() => _position += d.delta),
                          onDoubleTap: () =>
                              setState(() => _position = Offset.zero),
                          child: _buildHeader(context, isDark, color),
                        ),
                      ),
                      _buildTabBar(isDark, color),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _DetallesTab(
                              name: name,
                              type: type,
                              ambiente: ambiente,
                            ),
                            _InfoTab(
                              name: name,
                              type: type,
                              ambiente: ambiente,
                            ),
                            _PermisosTab(name: name, ambiente: ambiente),
                            _ReferenciasTab(name: name, ambiente: ambiente),
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
      ],
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, Color color) {
    final ambColor = AmbienteSelector.colorForAmbiente(ambiente);
    final hasSource = type != 'TABLE';
    return ConstellationHeader(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      lineColor: color.withValues(alpha: 0.35),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF262626), const Color(0xFF212121)]
              : [const Color(0xFFF7F9FC), const Color(0xFFF0F3F8)],
        ),
        border: Border(
          bottom: BorderSide(
            color: color.withValues(alpha: isDark ? 0.25 : 0.18),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Icon(_ti(type), size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Consolas',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    _CopyNameButton(name: name, isDark: isDark),
                    const SizedBox(width: 2),
                    _CopyUsageButton(
                      loading: _copyingImpl,
                      isDark: isDark,
                      onTap: _copyImplementation,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _badge(type, color),
                    const SizedBox(width: 6),
                    _badge(ambiente, ambColor),
                    const SizedBox(width: 6),
                    _StatusBadge(
                      status: _objectStatus,
                      loading: _statusLoading,
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // -- Acciones con etiqueta ------------------------------------
          if (hasSource)
            _LabeledAction(
              icon: Icons.code_rounded,
              label: 'Fuente',
              color: color,
              isDark: isDark,
              onTap: _openSource,
            ),
          const SizedBox(width: 4),
          _LabeledAction(
            icon: Icons.download_outlined,
            label: 'Backup',
            color: color,
            isDark: isDark,
            onTap: _openBackup,
          ),
          const SizedBox(width: 4),
          _LabeledAction(
            icon: Icons.compare_arrows_rounded,
            label: 'Comparar',
            color: color,
            isDark: isDark,
            onTap: _openDiff,
          ),
          // Favorito
          const SizedBox(width: 4),
          Tooltip(
            message: _isFavorite
                ? 'Quitar de favoritos'
                : 'Agregar a favoritos',
            child: IconButton(
              onPressed: _toggleFavorite,
              icon: Icon(
                _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                size: 20,
                color: _isFavorite
                    ? const Color(0xFFF4C430)
                    : (isDark ? Colors.white38 : Colors.black38),
              ),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
                hoverColor: (_isFavorite ? const Color(0xFFF4C430) : color)
                    .withValues(alpha: 0.12),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          IconButton(
            tooltip: 'Minimizar',
            icon: const Icon(Icons.remove_rounded, size: 18),
            onPressed: _minimize,
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
              hoverColor: (isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.08,
              ),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
              hoverColor: const Color(0xFFE81123).withValues(alpha: 0.14),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDark, Color color) => Container(
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
      border: Border(
        bottom: BorderSide(
          color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
        ),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: TabBar(
      labelColor: Colors.white,
      unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorAnimation: TabIndicatorAnimation.elastic,
      indicatorColor: Colors.transparent,
      dividerColor: Colors.transparent,
      splashBorderRadius: BorderRadius.circular(8),
      indicator: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      tabs: const [
        Tab(
          height: 34,
          icon: Icon(Icons.list_alt_rounded, size: 15),
          iconMargin: EdgeInsets.only(bottom: 2),
          text: 'Detalles',
        ),
        Tab(
          height: 34,
          icon: Icon(Icons.info_outline_rounded, size: 15),
          iconMargin: EdgeInsets.only(bottom: 2),
          text: 'Info',
        ),
        Tab(
          height: 34,
          icon: Icon(Icons.lock_outline_rounded, size: 15),
          iconMargin: EdgeInsets.only(bottom: 2),
          text: 'Permisos',
        ),
        Tab(
          height: 34,
          icon: Icon(Icons.account_tree_outlined, size: 15),
          iconMargin: EdgeInsets.only(bottom: 2),
          text: 'Referencias',
        ),
      ],
    ),
  );

  static Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        color: color,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.4,
      ),
    ),
  );
}

// -- Shared helpers ------------------------------------------------------------

/// Indicador de compilación del objeto (`ALL_OBJECTS.STATUS`).
///
/// Verde = VALID, rojo = INVALID, gris = desconocido / no aplica.
class _StatusBadge extends StatelessWidget {
  final String? status;
  final bool loading;
  final bool isDark;
  const _StatusBadge({
    required this.status,
    required this.loading,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
        ),
        child: SizedBox(
          width: 42,
          height: 11,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
          ),
        ),
      );
    }

    final s = status;
    final (Color c, IconData icon, String label, String tooltip) = switch (s) {
      'VALID' => (
        const Color(0xFF107C10),
        Icons.check_circle_rounded,
        'VÁLIDO',
        'El objeto está compilado correctamente (STATUS = VALID)',
      ),
      'INVALID' => (
        const Color(0xFFD13438),
        Icons.error_rounded,
        'INVÁLIDO',
        'El objeto está inválido en Oracle: requiere recompilación '
            '(STATUS = INVALID)',
      ),
      null => (
        Colors.grey,
        Icons.help_outline_rounded,
        'SIN ESTADO',
        'No se pudo determinar el estado del objeto',
      ),
      _ => (
        Colors.grey,
        Icons.help_outline_rounded,
        s,
        'ALL_OBJECTS.STATUS = $s',
      ),
    };

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.withValues(alpha: 0.45), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: c,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Backup dialog invocable from the details modal ---------------------------

class _ObjectBackupDialog extends StatefulWidget {
  final String name;
  final String objectType;
  final String ambiente;
  final Color color;
  const _ObjectBackupDialog({
    required this.name,
    required this.objectType,
    required this.ambiente,
    required this.color,
  });
  @override
  State<_ObjectBackupDialog> createState() => _ObjectBackupDialogState();
}

class _ObjectBackupDialogState extends State<_ObjectBackupDialog> {
  bool _loading = true;
  Object? _loadError;

  // Loaded source parts
  String _specText = '';
  String _bodyText = '';
  String _tableDdlCreateTable = '';
  String? _tableDdlComments;
  String? _tableDdlGrants;
  String _tableDdlOwner = '';

  // Checkbox state
  late bool _includeSpec;
  late bool _includeBody;
  late bool _includeTableComments;
  bool _includeSynonym = false;
  bool _includeGrants = false;

  bool get _isTable => widget.objectType == 'TABLE';

  @override
  void initState() {
    super.initState();
    _fetchSource();
  }

  Future<void> _fetchSource() async {
    try {
      if (_isTable) {
        final ddl = await SchemaService.instance.getTableDdl(
          widget.name,
          ambiente: widget.ambiente,
        );
        _tableDdlCreateTable = ddl.createTable;
        _tableDdlComments = ddl.comments?.isNotEmpty == true
            ? ddl.comments
            : null;
        _tableDdlGrants = ddl.grants?.isNotEmpty == true ? ddl.grants : null;
        _tableDdlOwner = ddl.owner;
        _specText = ddl.createTable;
      } else {
        final src = await SchemaService.instance.getObjectSource(
          widget.name,
          widget.objectType,
          ambiente: widget.ambiente,
        );
        _specText = src.spec;
        _bodyText = src.body ?? '';
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _includeSpec = _specText.isNotEmpty;
          _includeBody = _bodyText.isNotEmpty;
          _includeTableComments = _tableDdlComments != null;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _loadError = e;
        });
    }
  }

  String _objectOwner() {
    if (_tableDdlOwner.isNotEmpty) return _tableDdlOwner;
    final cached = SchemaService.instance.getCached(ambiente: widget.ambiente);
    return cached?.objects
            .where((o) => o.name == widget.name.toUpperCase())
            .firstOrNull
            ?.owner ??
        '';
  }

  Future<void> _save() async {
    final parts = <String>[];
    if (_isTable) {
      if (_includeSpec && _tableDdlCreateTable.isNotEmpty)
        parts.add('$_tableDdlCreateTable\n/');
      if (_includeTableComments && _tableDdlComments != null)
        parts.add('${_tableDdlComments!}\n/');
    } else {
      if (_includeSpec && _specText.isNotEmpty) parts.add('$_specText\n/');
      if (_includeBody && _bodyText.isNotEmpty) parts.add('$_bodyText\n/');
    }
    if (_includeGrants) {
      if (_isTable && _tableDdlGrants != null) {
        parts.add('${_tableDdlGrants!}\n/');
      } else {
        final owner = _objectOwner();
        final ref = owner.isNotEmpty ? '$owner.${widget.name}' : widget.name;
        parts.add('GRANT EXECUTE ON $ref TO PUBLIC;\n/');
      }
    }
    if (_includeSynonym) {
      final owner = _objectOwner();
      final ref = owner.isNotEmpty ? '$owner.${widget.name}' : widget.name;
      parts.add('CREATE OR REPLACE PUBLIC SYNONYM ${widget.name} FOR $ref;\n/');
    }
    if (parts.isEmpty) return;
    final script = parts.join('\n\n');
    final suggested =
        '${widget.name.toLowerCase()}_${widget.ambiente.toLowerCase()}.sql';
    if (!mounted) return;
    Navigator.of(context).pop();
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Guardar backup SQL',
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: ['sql'],
      );
      if (path == null) return;
      await File(path).writeAsString(script, flush: true);
      AppToast.success('Backup guardado: ${path.split(r"\\").last}');
    } catch (e) {
      AppToast.error('Error guardando backup: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;

    Widget checkRow(
      String label,
      bool value,
      bool enabled,
      ValueChanged<bool?> onChanged, {
      String? subtitle,
    }) {
      return InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                  activeColor: color,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: enabled ? null : Colors.grey,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontFamily: 'Consolas',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final canSave =
        !_loading &&
        _loadError == null &&
        (_includeSpec ||
            (_isTable && _includeTableComments) ||
            (!_isTable && _includeBody) ||
            _includeSynonym ||
            _includeGrants);

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: ConstellationDialogTitle(
        lineColor: color.withValues(alpha: 0.35),
        child: Row(
          children: [
            Icon(Icons.download_outlined, size: 18, color: color),
            const SizedBox(width: 8),
            const Text('Generar backup SQL', style: TextStyle(fontSize: 15)),
          ],
        ),
      ),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : _loadError != null
            ? Text(
                'Error cargando fuente: $_loadError',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SeleccionÁ qué incluir en el script',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'FUENTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  checkRow(
                    _isTable ? 'DDL de tabla' : 'Especificación',
                    _includeSpec,
                    _specText.isNotEmpty,
                    (v) => setState(() => _includeSpec = v ?? false),
                    subtitle: _isTable
                        ? 'CREATE TABLE + índices + Constraints'
                        : widget.objectType == 'PACKAGE'
                        ? 'CREATE OR REPLACE PACKAGE ...'
                        : null,
                  ),
                  if (_isTable && _tableDdlComments != null)
                    checkRow(
                      'Comentarios',
                      _includeTableComments,
                      true,
                      (v) => setState(() => _includeTableComments = v ?? false),
                      subtitle: 'COMMENT ON TABLE ...',
                    ),
                  if (!_isTable && _bodyText.isNotEmpty)
                    checkRow(
                      'Cuerpo',
                      _includeBody,
                      true,
                      (v) => setState(() => _includeBody = v ?? false),
                      subtitle: 'CREATE OR REPLACE PACKAGE BODY ...',
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'ADICIONAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  checkRow(
                    'Grant',
                    _includeGrants,
                    true,
                    (v) => setState(() => _includeGrants = v ?? false),
                    subtitle: _isTable && _tableDdlGrants != null
                        ? 'Grants del DDL de tabla'
                        : 'GRANT EXECUTE ON OWNER.NAME TO PUBLIC',
                  ),
                  checkRow(
                    'SinÓnimo público',
                    _includeSynonym,
                    true,
                    (v) => setState(() => _includeSynonym = v ?? false),
                    subtitle:
                        'CREATE OR REPLACE PUBLIC SYNONYM NAME FOR OWNER.NAME',
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: canSave ? _save : null,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: const Text('Guardar .sql'),
          style: FilledButton.styleFrom(backgroundColor: color),
        ),
      ],
    );
  }
}

class _CopyNameButton extends StatefulWidget {
  final String name;
  final bool isDark;
  const _CopyNameButton({required this.name, required this.isDark});
  @override
  State<_CopyNameButton> createState() => _CopyNameButtonState();
}

class _CopyNameButtonState extends State<_CopyNameButton> {
  bool _hovered = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.name));
    AppToast.info('Copiado: ${widget.name}');
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final idleColor = widget.isDark ? Colors.white38 : Colors.black38;
    final activeColor = widget.isDark ? Colors.white70 : Colors.black54;
    return Tooltip(
      message: _copied ? 'Copiado' : 'Copiar nombre',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _copy,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 14,
              color: _copied
                  ? const Color(0xFF107C10)
                  : (_hovered ? activeColor : idleColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón de solo ícono (sin etiqueta) que copia un ejemplo de *uso* del
/// objeto (invocación PL/SQL), ubicado junto al botón de copiar nombre.
class _CopyUsageButton extends StatefulWidget {
  final bool loading;
  final bool isDark;
  final VoidCallback onTap;
  const _CopyUsageButton({
    required this.loading,
    required this.isDark,
    required this.onTap,
  });
  @override
  State<_CopyUsageButton> createState() => _CopyUsageButtonState();
}

class _CopyUsageButtonState extends State<_CopyUsageButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final idleColor = widget.isDark ? Colors.white38 : Colors.black38;
    final activeColor = widget.isDark ? Colors.white70 : Colors.black54;
    return Tooltip(
      message: 'Copiar uso',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.loading ? null : widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: widget.loading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: idleColor,
                    ),
                  )
                : Icon(
                    Icons.integration_instructions_outlined,
                    size: 14,
                    color: _hovered ? activeColor : idleColor,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo para elegir, dentro de un paquete, si se copia el uso de un
/// subprograma específico o el de todos.
class _SubprogramPickerDialog extends StatefulWidget {
  final String packageName;
  final List<
    ({
      String name,
      String kind,
      List<({String name, String dataType, String inOut})> arguments,
    })
  >
  subprograms;
  final Color color;
  const _SubprogramPickerDialog({
    required this.packageName,
    required this.subprograms,
    required this.color,
  });
  @override
  State<_SubprogramPickerDialog> createState() =>
      _SubprogramPickerDialogState();
}

class _SubprogramPickerDialogState extends State<_SubprogramPickerDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;
    final filtered = _filter.isEmpty
        ? widget.subprograms
        : widget.subprograms
              .where(
                (s) => s.name.toUpperCase().contains(_filter.toUpperCase()),
              )
              .toList();

    Widget tile({
      required IconData icon,
      required Color iconColor,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w600,
                        color: tc,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(subtitle, style: TextStyle(fontSize: 11, color: sc)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: sc),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: ConstellationDialogTitle(
        lineColor: widget.color.withValues(alpha: 0.35),
        child: Row(
          children: [
            Icon(
              Icons.integration_instructions_outlined,
              size: 18,
              color: widget.color,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Copiar uso', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.packageName} tiene ${widget.subprograms.length} '
              'subprogramas. Elegí uno o copiá el de todos.',
              style: TextStyle(fontSize: 12, color: sc),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Filtrar...',
                prefixIcon: const Icon(Icons.search, size: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 6),
            tile(
              icon: Icons.select_all_rounded,
              iconColor: widget.color,
              title: 'Todos los subprogramas',
              subtitle: '${widget.subprograms.length} ejemplos de uso',
              onTap: () => Navigator.of(context).pop(_kAllSubprograms),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Sin coincidencias',
                        style: TextStyle(fontSize: 12, color: sc),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: isDark
                            ? const Color(0xFF2D2D2D)
                            : const Color(0xFFEEEEEE),
                      ),
                      itemBuilder: (_, i) {
                        final s = filtered[i];
                        final isFunc = s.kind == 'FUNCTION';
                        return tile(
                          icon: isFunc
                              ? Icons.functions_rounded
                              : Icons.code_rounded,
                          iconColor: isFunc
                              ? const Color(0xFF8764B8)
                              : const Color(0xFFCA5010),
                          title: s.name,
                          subtitle:
                              '${isFunc ? 'FUNCTION' : 'PROCEDURE'} · ${s.arguments.length} parámetros',
                          onTap: () => Navigator.of(context).pop(s.name),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _LabeledAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  const _LabeledAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });
  @override
  State<_LabeledAction> createState() => _LabeledActionState();
}

class _LabeledActionState extends State<_LabeledAction> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.color.withValues(alpha: widget.isDark ? 0.18 : 0.10)
                : (widget.isDark
                      ? const Color(0xFF2D2D2D)
                      : const Color(0xFFF0F2F5)),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.5)
                  : (widget.isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFDDE2EA)),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 13,
                color: _hovered
                    ? widget.color
                    : (widget.isDark ? Colors.white54 : Colors.black45),
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _hovered
                      ? widget.color
                      : (widget.isDark ? Colors.white54 : Colors.black45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.color.withValues(alpha: isDark ? 0.18 : 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            widget.icon,
            size: 18,
            color: _hovered
                ? widget.color
                : (isDark ? Colors.white54 : Colors.black45),
          ),
        ),
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final List<(String, int, TextAlign)> cols;
  const _TH(this.cols);
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? const Color(0xFF252526) : const Color(0xFFF0F2F5),
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
      child: Row(
        children: [
          for (final (label, flex, align) in cols)
            Expanded(
              flex: flex,
              child: Text(
                label,
                textAlign: align,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white54 : Colors.black45,
                  letterSpacing: 0.6,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -- Exportaci�n por pesta�a ---------------------------------------------------

/// Tabla gen�rica lista para serializar (t�tulo + encabezados + filas).
typedef _ExportTable = ({
  String title,
  List<String> headers,
  List<List<String>> rows,
});

String _csvCell(String v) {
  final needsQuotes =
      v.contains(';') ||
      v.contains('"') ||
      v.contains('\n') ||
      v.contains('\r');
  final escaped = v.replaceAll('"', '""');
  return needsQuotes ? '"$escaped"' : escaped;
}

String _serializeExport(
  _ExportTable t,
  String format, {
  required String subtitle,
}) {
  final buf = StringBuffer();
  switch (format) {
    case 'md':
      buf.writeln('# ${t.title}');
      buf.writeln();
      buf.writeln('_${subtitle}_');
      buf.writeln();
      buf.writeln('| ${t.headers.join(' | ')} |');
      buf.writeln('| ${t.headers.map((h) => '---').join(' | ')} |');
      for (final r in t.rows) {
        buf.writeln(
          '| ${r.map((c) => c.replaceAll('|', r'\|')).join(' | ')} |',
        );
      }
      buf.writeln();
      buf.writeln('_${t.rows.length} registros_');
    case 'txt':
      buf.writeln(t.title);
      buf.writeln(subtitle);
      buf.writeln();
      buf.writeln(t.headers.join('\t'));
      for (final r in t.rows) {
        buf.writeln(r.join('\t'));
      }
    default: // csv
      buf.writeln(_csvCell(t.title));
      buf.writeln(_csvCell(subtitle));
      buf.writeln();
      buf.writeln(t.headers.map(_csvCell).join(';'));
      for (final r in t.rows) {
        buf.writeln(r.map(_csvCell).join(';'));
      }
  }
  return buf.toString();
}

/// Bot�n de exportaci�n que se muestra en la barra de estado de cada pesta�a.
///
/// Los datos ya est�n cargados en la pesta�a, por lo que `buildTable` es
/// s�ncrono y no hace ninguna llamada adicional al backend.
class _ExportButton extends StatelessWidget {
  final _ExportTable Function() buildTable;

  /// Nombre de archivo sugerido, sin extensi�n.
  final String baseName;

  /// L�nea de contexto (objeto, ambiente, fecha) incluida en el archivo.
  final String subtitle;
  const _ExportButton({
    required this.buildTable,
    required this.baseName,
    required this.subtitle,
  });

  Future<void> _export(String format) async {
    try {
      final table = buildTable();
      final content = _serializeExport(table, format, subtitle: subtitle);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Exportar ${table.title}',
        fileName: '$baseName.$format',
        type: FileType.custom,
        allowedExtensions: [format],
      );
      if (path == null) return;
      await File(path).writeAsString(content, flush: true);
      AppToast.success('Exportado: ${path.split(Platform.pathSeparator).last}');
    } catch (e) {
      AppToast.error('Error exportando: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white54 : Colors.black45;
    return PopupMenuButton<String>(
      tooltip: 'Exportar esta pesta�a',
      position: PopupMenuPosition.over,
      padding: EdgeInsets.zero,
      onSelected: _export,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'csv',
          height: 34,
          child: Text('Exportar a CSV', style: TextStyle(fontSize: 12)),
        ),
        PopupMenuItem(
          value: 'md',
          height: 34,
          child: Text('Exportar a Markdown', style: TextStyle(fontSize: 12)),
        ),
        PopupMenuItem(
          value: 'txt',
          height: 34,
          child: Text('Exportar a Texto', style: TextStyle(fontSize: 12)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ios_share_rounded, size: 13, color: fg),
            const SizedBox(width: 4),
            Text('Exportar', style: TextStyle(fontSize: 11, color: fg)),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final int count;
  final String label;

  /// Si se informa, se muestra un bot�n "Exportar" a la derecha del contador.
  final _ExportTable Function()? buildExport;
  final String? exportBaseName;
  final String? exportSubtitle;
  const _StatusBar({
    required this.count,
    required this.label,
    this.buildExport,
    this.exportBaseName,
    this.exportSubtitle,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 5, 10, 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF0F2F5),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count $label',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
          if (buildExport != null)
            _ExportButton(
              buildTable: buildExport!,
              baseName: exportBaseName ?? 'export',
              subtitle: exportSubtitle ?? '',
            ),
        ],
      ),
    );
  }
}

/// Nombre de archivo sugerido: `objeto_ambiente_seccion`.
String _exportBaseName(String name, String ambiente, String section) =>
    '${name.toLowerCase()}_${ambiente.toLowerCase()}_$section';

/// L�nea de contexto incluida como segunda fila del archivo exportado.
String _exportSubtitle(String name, String ambiente) =>
    '$name � ambiente $ambiente � ${DateTime.now().toIso8601String()}';

Color _rowBg(bool isDark, int i) => i.isEven
    ? (isDark ? const Color(0xFF1E1E1E) : Colors.white)
    : (isDark ? const Color(0xFF252526) : const Color(0xFFFAFAFA));

// -- Detalles tab --------------------------------------------------------------

class _DetallesTab extends StatefulWidget {
  final String name;
  final String type;
  final String ambiente;
  const _DetallesTab({
    required this.name,
    required this.type,
    required this.ambiente,
  });
  @override
  State<_DetallesTab> createState() => _DetallesTabState();
}

class _DetallesTabState extends State<_DetallesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return switch (widget.type) {
      'TABLE' ||
      'VIEW' => _ColumnsView(name: widget.name, ambiente: widget.ambiente),
      'PROCEDURE' ||
      'FUNCTION' => _ParamsView(name: widget.name, ambiente: widget.ambiente),
      'PACKAGE' => _PackageView(name: widget.name, ambiente: widget.ambiente),
      'TYPE' => _AttrsView(name: widget.name, ambiente: widget.ambiente),
      _ => const Center(child: Text('Sin detalles disponibles')),
    };
  }
}

class _ColumnsView extends StatefulWidget {
  final String name;
  final String ambiente;
  const _ColumnsView({required this.name, required this.ambiente});
  @override
  State<_ColumnsView> createState() => _ColumnsViewState();
}

class _ColumnsViewState extends State<_ColumnsView>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<({String name, String dataType})>> _f;
  List<({String name, String dataType})>? _cached;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _cached = SchemaService.instance.peekColumns(
      widget.name,
      ambiente: widget.ambiente,
    );
    _f = SchemaService.instance.getColumns(
      widget.name,
      ambiente: widget.ambiente,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;
    return FutureBuilder(
      future: _f,
      initialData: _cached,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData)
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF0078D4),
              strokeWidth: 2,
            ),
          );
        if (snap.hasError)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 32, color: Colors.red.shade400),
                const SizedBox(height: 8),
                Text(
                  'Error al cargar columnas',
                  style: TextStyle(color: Colors.red.shade400, fontSize: 13),
                ),
              ],
            ),
          );
        final cols = snap.data!;
        if (cols.isEmpty)
          return Center(
            child: Text(
              'Sin columnas',
              style: TextStyle(fontSize: 13, color: sc),
            ),
          );
        return Column(
          children: [
            const _TH([
              ('#', 1, TextAlign.right),
              ('NOMBRE', 5, TextAlign.left),
              ('TIPO DE DATO', 4, TextAlign.left),
            ]),
            Expanded(
              child: ListView.builder(
                itemCount: cols.length,
                itemBuilder: (_, i) {
                  final c = cols[i];
                  return InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: c.name));
                      AppToast.info('Copiado: ${c.name}');
                    },
                    mouseCursor: SystemMouseCursors.click,
                    child: Container(
                      color: _rowBg(isDark, i),
                      padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Text(
                              '${i + 1}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'Consolas',
                                color: sc,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 5,
                            child: Tooltip(
                              message: c.name,
                              waitDuration: const Duration(milliseconds: 500),
                              child: Text(
                                c.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Consolas',
                                  color: tc,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              c.dataType,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'Consolas',
                                color: Color(0xFF0078D4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            _StatusBar(
              count: cols.length,
              label: 'columnas',
              exportBaseName: _exportBaseName(
                widget.name,
                widget.ambiente,
                'columnas',
              ),
              exportSubtitle: _exportSubtitle(widget.name, widget.ambiente),
              buildExport: () => (
                title: 'Detalle � columnas de ${widget.name}',
                headers: ['#', 'NOMBRE', 'TIPO DE DATO'],
                rows: [
                  for (var i = 0; i < cols.length; i++)
                    ['${i + 1}', cols[i].name, cols[i].dataType],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ParamsView extends StatefulWidget {
  final String name;
  final String ambiente;
  const _ParamsView({required this.name, required this.ambiente});
  @override
  State<_ParamsView> createState() => _ParamsViewState();
}

class _ParamsViewState extends State<_ParamsView>
    with AutomaticKeepAliveClientMixin {
  List<({String name, String dataType, String inOut})>? _data;
  Object? _error;
  bool _loading = true;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    final cached = SchemaService.instance.peekObjectArguments(
      widget.name,
      ambiente: widget.ambiente,
    );
    if (cached != null) {
      _data = cached;
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final args = await SchemaService.instance.getObjectArguments(
        widget.name,
        ambiente: widget.ambiente,
      );
      if (!mounted) return;
      setState(() {
        _data = args;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;
    if (_data == null && _loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF0078D4),
          strokeWidth: 2,
        ),
      );
    }
    if (_data == null && _error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: Colors.red.shade400),
            const SizedBox(height: 8),
            Text(
              'Error al cargar parámetros',
              style: TextStyle(color: Colors.red.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }
    final args = _data!;
    if (args.isEmpty) {
      return Center(
        child: Text(
          'Sin parámetros',
          style: TextStyle(fontSize: 13, color: sc),
        ),
      );
    }
    return Column(
      children: [
        const _TH([
          ('#', 1, TextAlign.right),
          ('PARÁMETRO', 5, TextAlign.left),
          ('DIRECCIÓN', 2, TextAlign.center),
          ('TIPO DE DATO', 4, TextAlign.left),
        ]),
        Expanded(
          child: ListView.builder(
            itemCount: args.length,
            itemBuilder: (_, i) {
              final a = args[i];
              final dc = switch (a.inOut) {
                'IN' => const Color(0xFF0078D4),
                'OUT' => const Color(0xFFCA5010),
                _ => const Color(0xFF8764B8),
              };
              return InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: a.name));

                  AppToast.info('Copiado: ${a.name}');
                },
                mouseCursor: SystemMouseCursors.click,
                child: Container(
                  color: _rowBg(isDark, i),
                  padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Consolas',
                            color: sc,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 5,
                        child: Tooltip(
                          message: a.name,
                          waitDuration: const Duration(milliseconds: 500),
                          child: Text(
                            a.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'Consolas',
                              color: tc,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: a.inOut.isEmpty
                            ? const SizedBox.shrink()
                            : Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: dc.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: dc.withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    a.inOut,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: dc,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          a.dataType,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'Consolas',
                            color: Color(0xFF0078D4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _StatusBar(
          count: args.length,
          label: 'parámetros',
          exportBaseName: _exportBaseName(
            widget.name,
            widget.ambiente,
            'parametros',
          ),
          exportSubtitle: _exportSubtitle(widget.name, widget.ambiente),
          buildExport: () => (
            title: 'Detalle — parámetros de ${widget.name}',
            headers: ['#', 'NOMBRE', 'IN/OUT', 'TIPO DE DATO'],
            rows: [
              for (var i = 0; i < args.length; i++)
                ['${i + 1}', args[i].name, args[i].inOut, args[i].dataType],
            ],
          ),
        ),
      ],
    );
  }
}

class _AttrsView extends StatefulWidget {
  final String name;
  final String ambiente;
  const _AttrsView({required this.name, required this.ambiente});
  @override
  State<_AttrsView> createState() => _AttrsViewState();
}

class _AttrsViewState extends State<_AttrsView>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<({String name, String dataType})>> _f;
  List<({String name, String dataType})>? _cached;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _cached = SchemaService.instance.peekTypeAttributes(
      widget.name,
      ambiente: widget.ambiente,
    );
    _f = SchemaService.instance.getTypeAttributes(
      widget.name,
      ambiente: widget.ambiente,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;
    return FutureBuilder(
      future: _f,
      initialData: _cached,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData)
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF0078D4),
              strokeWidth: 2,
            ),
          );
        if (snap.hasError)
          return Center(
            child: Text(
              'Error al cargar atributos',
              style: TextStyle(color: Colors.red.shade400, fontSize: 13),
            ),
          );
        final attrs = snap.data!;
        if (attrs.isEmpty) {
          return Center(
            child: Text(
              'Sin atributos',
              style: TextStyle(fontSize: 13, color: sc),
            ),
          );
        }
        return Column(
          children: [
            const _TH([
              ('#', 1, TextAlign.right),
              ('ATRIBUTO', 5, TextAlign.left),
              ('TIPO DE DATO', 4, TextAlign.left),
            ]),
            Expanded(
              child: ListView.builder(
                itemCount: attrs.length,
                itemBuilder: (_, i) {
                  final a = attrs[i];
                  // Para los TYPE de colección (`TABLE OF` / `VARRAY OF`) y para
                  // los atributos cuyo tipo es otro objeto del schema, ofrecemos
                  // un acceso directo que lo abre en otro modal de detalles.
                  final ref = _resolveSchemaRef(a.dataType, widget.ambiente);
                  return Container(
                    color: _rowBg(isDark, i),
                    padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${i + 1}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Consolas',
                              color: sc,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 5,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  a.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'Consolas',
                                    color: tc,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              _CopyValueButton(
                                value: a.name,
                                tooltip: 'Copiar nombre',
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  a.dataType,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontFamily: 'Consolas',
                                    color: Color(0xFF0078D4),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              _CopyValueButton(
                                value: a.dataType,
                                tooltip: 'Copiar tipo de dato',
                              ),
                              if (ref != null) ...[
                                const SizedBox(width: 2),
                                _OpenRefButton(
                                  name: ref.name,
                                  type: ref.type,
                                  ambiente: widget.ambiente,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            _StatusBar(
              count: attrs.length,
              label: 'atributos',
              exportBaseName: _exportBaseName(
                widget.name,
                widget.ambiente,
                'atributos',
              ),
              exportSubtitle: _exportSubtitle(widget.name, widget.ambiente),
              buildExport: () => (
                title: 'Detalle — atributos de ${widget.name}',
                headers: ['#', 'NOMBRE', 'TIPO DE DATO'],
                rows: [
                  for (var i = 0; i < attrs.length; i++)
                    ['${i + 1}', attrs[i].name, attrs[i].dataType],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Resuelve si un tipo de dato Oracle corresponde a un objeto del schema
/// (TYPE / TABLE / VIEW) para ofrecer un acceso directo que lo abra en otro
/// modal de detalles. Normaliza comillas, owner calificado y `%ROWTYPE`.
///
/// Retorna `null` para tipos escalares (VARCHAR2, NUMBER, DATE, ...).
({String name, String type})? _resolveSchemaRef(
  String rawType,
  String ambiente,
) {
  var element = rawType
      .replaceAll('"', '')
      .replaceAll(RegExp(r'%ROWTYPE$', caseSensitive: false), '')
      .trim()
      .toUpperCase();
  // Quitamos el owner si viene calificado (OWNER.TIPO) y cualquier precisión.
  if (element.contains('.')) element = element.split('.').last;
  if (element.contains('(')) element = element.split('(').first.trim();
  if (element.isEmpty) return null;
  if (_kScalarTypes.hasMatch(element)) return null;

  final cached = SchemaService.instance.getCached(ambiente: ambiente);
  if (cached != null) {
    for (final o in cached.objects) {
      if (o.name.toUpperCase() == element) {
        return (name: element, type: o.type.toUpperCase());
      }
    }
    if (cached.tables.any((t) => t.toUpperCase() == element)) {
      return (name: element, type: 'TABLE');
    }
    if (cached.views.any((v) => v.toUpperCase() == element)) {
      return (name: element, type: 'VIEW');
    }
    // El schema está cacheado y el nombre no aparece: no es un objeto.
    return null;
  }
  // Sin cache disponible asumimos TYPE (el modal mostrará el error si no).
  return (name: element, type: 'TYPE');
}

final _kScalarTypes = RegExp(
  r'^(VARCHAR2?|NVARCHAR2|CHAR|NCHAR|NUMBER|INTEGER|INT|SMALLINT|DECIMAL|'
  r'NUMERIC|FLOAT|REAL|DOUBLE|BINARY_FLOAT|BINARY_DOUBLE|DATE|TIMESTAMP.*|'
  r'INTERVAL.*|CLOB|NCLOB|BLOB|BFILE|RAW|LONG|ROWID|UROWID|BOOLEAN|XMLTYPE|'
  r'PLS_INTEGER|BINARY_INTEGER)$',
);

/// Ícono compacto que copia un valor al portapapeles mostrando un check
/// temporal como confirmación. Se usa en las filas del detalle de un TYPE.
class _CopyValueButton extends StatefulWidget {
  final String value;
  final String tooltip;
  const _CopyValueButton({required this.value, required this.tooltip});

  @override
  State<_CopyValueButton> createState() => _CopyValueButtonState();
}

class _CopyValueButtonState extends State<_CopyValueButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    AppToast.info('Copiado: ${widget.value}');
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _copied
        ? const Color(0xFF107C10)
        : (isDark ? Colors.white38 : Colors.black38);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: _copy,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            _copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 12,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Botón compacto que abre el objeto referenciado en otro modal de detalles.
class _OpenRefButton extends StatelessWidget {
  final String name;
  final String type;
  final String ambiente;
  const _OpenRefButton({
    required this.name,
    required this.type,
    required this.ambiente,
  });

  @override
  Widget build(BuildContext context) {
    final color = _tc(type);
    return Tooltip(
      message: 'Abrir $type $name',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => showObjectDetails(
          context,
          name: name,
          type: type,
          ambiente: ambiente,
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Icons.open_in_new_rounded, size: 13, color: color),
        ),
      ),
    );
  }
}

class _PackageView extends StatefulWidget {
  final String name;
  final String ambiente;
  const _PackageView({required this.name, required this.ambiente});
  @override
  State<_PackageView> createState() => _PackageViewState();
}

class _PackageViewState extends State<_PackageView>
    with AutomaticKeepAliveClientMixin {
  final _expanded = <String>{};

  List<
    ({
      String name,
      String kind,
      List<({String name, String dataType, String inOut})> arguments,
    })
  >?
  _data;
  Object? _error;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    final cached = SchemaService.instance.peekPackageSubprograms(
      widget.name,
      ambiente: widget.ambiente,
    );
    if (cached != null) {
      _data = cached;
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final subs = await SchemaService.instance.getPackageSubprograms(
        widget.name,
        ambiente: widget.ambiente,
      );
      if (!mounted) return;
      setState(() {
        _data = subs;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;
    final rowBg = isDark ? const Color(0xFF252526) : const Color(0xFFF8F8F8);
    final argBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    if (_data == null && _loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF0078D4),
          strokeWidth: 2,
        ),
      );
    }
    if (_data == null && _error != null) {
      return Center(
        child: Text(
          'Error al cargar subprogramas',
          style: TextStyle(color: Colors.red.shade400, fontSize: 13),
        ),
      );
    }
    final subs = _data!;
    if (subs.isEmpty)
      return Center(
        child: Text(
          'Sin subprogramas',
          style: TextStyle(fontSize: 13, color: sc),
        ),
      );
    return Column(
      children: [
        const _TH([
          ('NOMBRE', 6, TextAlign.left),
          ('TIPO', 2, TextAlign.center),
          ('PARAMS', 2, TextAlign.center),
        ]),
        Expanded(
          child: ListView.builder(
            itemCount: subs.length,
            itemBuilder: (_, i) {
              final s = subs[i];
              final isFunc = s.kind == 'FUNCTION';
              final color = isFunc
                  ? const Color(0xFF8764B8)
                  : const Color(0xFFCA5010);
              final isOpen = _expanded.contains(s.name);
              return Column(
                children: [
                  InkWell(
                    onTap: () => setState(
                      () => isOpen
                          ? _expanded.remove(s.name)
                          : _expanded.add(s.name),
                    ),
                    child: Container(
                      color: rowBg,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          Icon(
                            isFunc
                                ? Icons.functions_rounded
                                : Icons.code_rounded,
                            size: 14,
                            color: color,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 6,
                            child: Text(
                              s.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Consolas',
                                color: tc,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isFunc ? 'FUNCTION' : 'PROCEDURE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${s.arguments.length}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: sc,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    isOpen
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 14,
                                    color: sc,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isOpen)
                    ...s.arguments.map((a) {
                      final dc = switch (a.inOut) {
                        'IN' => const Color(0xFF0078D4),
                        'OUT' => const Color(0xFFCA5010),
                        _ => const Color(0xFF8764B8),
                      };
                      return Container(
                        color: argBg,
                        padding: const EdgeInsets.fromLTRB(44, 5, 16, 5),
                        child: Row(
                          children: [
                            if (a.inOut.isNotEmpty)
                              Container(
                                width: 40,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: dc.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  a.inOut,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: dc,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else
                              const SizedBox(width: 40),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                a.name,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontFamily: 'Consolas',
                                  color: tc,
                                ),
                              ),
                            ),
                            Text(
                              a.dataType,
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'Consolas',
                                color: Color(0xFF0078D4),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  if (isOpen && s.arguments.isEmpty)
                    Container(
                      color: argBg,
                      padding: const EdgeInsets.fromLTRB(44, 5, 16, 5),
                      child: Text(
                        '(sin parámetros)',
                        style: TextStyle(
                          fontSize: 11,
                          color: sc,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        _StatusBar(
          count: subs.length,
          label: 'subprogramas',
          exportBaseName: _exportBaseName(
            widget.name,
            widget.ambiente,
            'subprogramas',
          ),
          exportSubtitle: _exportSubtitle(widget.name, widget.ambiente),
          buildExport: () => (
            title: 'Detalle — subprogramas de ${widget.name}',
            headers: [
              'SUBPROGRAMA',
              'TIPO',
              'PARÁMETRO',
              'IN/OUT',
              'TIPO DE DATO',
            ],
            rows: [
              for (final s in subs)
                if (s.arguments.isEmpty)
                  [s.name, s.kind, '', '', '']
                else
                  for (final a in s.arguments)
                    [s.name, s.kind, a.name, a.inOut, a.dataType],
            ],
          ),
        ),
      ],
    );
  }
}

// -- Permisos tab -------------------------------------------------------------

class _PermisosTab extends StatefulWidget {
  final String name;
  final String ambiente;
  const _PermisosTab({required this.name, required this.ambiente});
  @override
  State<_PermisosTab> createState() => _PermisosTabState();
}

class _PermisosTabState extends State<_PermisosTab>
    with AutomaticKeepAliveClientMixin {
  List<({String grantee, String privilege, bool grantable, String grantor})>?
  _data;
  Object? _error;
  bool _loading = true;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await SchemaService.instance.getObjectPrivileges(
        widget.name,
        ambiente: widget.ambiente,
      );
      if (!mounted) return;
      setState(() {
        _data = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;
    if (_loading && _data == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF0078D4),
          strokeWidth: 2,
        ),
      );
    }
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Error al cargar permisos\n$_error',
            style: TextStyle(color: Colors.red.shade400, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final rows = _data!;
    if (rows.isEmpty)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_open_outlined,
              size: 36,
              color: sc.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 10),
            Text(
              'Sin permisos asignados',
              style: TextStyle(fontSize: 13, color: sc),
            ),
          ],
        ),
      );
    return Column(
      children: [
        const _TH([
          ('GRANTEE', 4, TextAlign.left),
          ('PRIVILEGE', 3, TextAlign.left),
          ('GRANTOR', 3, TextAlign.left),
          ('WITH GRANT', 2, TextAlign.center),
        ]),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              return Container(
                color: _rowBg(isDark, i),
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        r.grantee,
                        style: TextStyle(
                          fontSize: 12,
                          color: tc,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),

                    Expanded(
                      flex: 3,
                      child: Text(
                        r.privilege,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0078D4),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        r.grantor,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: sc,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Icon(
                          r.grantable
                              ? Icons.check_circle_outline
                              : Icons.remove,
                          size: 15,
                          color: r.grantable
                              ? Colors.green.shade400
                              : sc.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        _StatusBar(
          count: rows.length,
          label: 'permisos',
          exportBaseName: _exportBaseName(
            widget.name,
            widget.ambiente,
            'permisos',
          ),
          exportSubtitle: _exportSubtitle(widget.name, widget.ambiente),
          buildExport: () => (
            title: 'Permisos de ${widget.name}',
            headers: ['GRANTEE', 'PRIVILEGIO', 'GRANTOR', 'GRANTABLE'],
            rows: [
              for (final r in rows)
                [r.grantee, r.privilege, r.grantor, r.grantable ? 'YES' : 'NO'],
            ],
          ),
        ),
      ],
    );
  }
}

// -- Referencias tab -----------------------------------------------------------

class _ReferenciasTab extends StatefulWidget {
  final String name;
  final String ambiente;
  const _ReferenciasTab({required this.name, required this.ambiente});
  @override
  State<_ReferenciasTab> createState() => _ReferenciasTabState();
}

class _ReferenciasTabState extends State<_ReferenciasTab>
    with AutomaticKeepAliveClientMixin {
  List<({String name, String type, String owner})>? _data;
  Object? _error;
  bool _loading = true;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await SchemaService.instance.getObjectReferences(
        widget.name,
        ambiente: widget.ambiente,
      );
      if (!mounted) return;
      setState(() {
        _data = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  static IconData _icon(String t) => switch (t.toUpperCase()) {
    'TABLE' => Icons.table_chart_outlined,
    'VIEW' => Icons.visibility_outlined,
    'PROCEDURE' => Icons.code_rounded,
    'FUNCTION' => Icons.functions_rounded,
    String s when s.startsWith('PACKAGE') => Icons.inventory_2_outlined,
    'TYPE' => Icons.data_object_outlined,
    'TRIGGER' => Icons.bolt_outlined,
    _ => Icons.storage_outlined,
  };
  static Color _color(String t) => switch (t.toUpperCase()) {
    'TABLE' => const Color(0xFF0078D4),
    'VIEW' => const Color(0xFF107C10),
    'PROCEDURE' => const Color(0xFFCA5010),
    'FUNCTION' => const Color(0xFF8764B8),
    String s when s.startsWith('PACKAGE') => const Color(0xFFC19C00),
    'TYPE' => const Color(0xFF2E7D9E),
    'TRIGGER' => const Color(0xFFD13438),
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;
    if (_loading && _data == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF0078D4),
          strokeWidth: 2,
        ),
      );
    }
    if (_error != null && _data == null) {
      return Center(
        child: Text(
          'Error al cargar referencias',
          style: TextStyle(color: Colors.red.shade400, fontSize: 13),
        ),
      );
    }
    final rows = _data!;
    if (rows.isEmpty)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 36,
              color: sc.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 10),
            Text(
              'Sin referencias encontradas',
              style: TextStyle(fontSize: 13, color: sc),
            ),
          ],
        ),
      );
    return Column(
      children: [
        const _TH([
          ('NOMBRE', 5, TextAlign.left),
          ('TIPO', 3, TextAlign.left),
          ('OWNER', 2, TextAlign.left),
        ]),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              final color = _color(r.type);
              return Container(
                color: _rowBg(isDark, i),
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
                child: Row(
                  children: [
                    Icon(_icon(r.type), size: 13, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: Text(
                        r.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Consolas',
                          color: tc,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        r.type,
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        r.owner,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Consolas',
                          color: sc,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        _StatusBar(
          count: rows.length,
          label: 'referencias',
          exportBaseName: _exportBaseName(
            widget.name,
            widget.ambiente,
            'referencias',
          ),
          exportSubtitle: _exportSubtitle(widget.name, widget.ambiente),
          buildExport: () => (
            title: 'Referencias de ${widget.name}',
            headers: ['NOMBRE', 'TIPO', 'OWNER'],
            rows: [
              for (final r in rows) [r.name, r.type, r.owner],
            ],
          ),
        ),
      ],
    );
  }
}

// -- Info tab (ALL_OBJECTS + ALL_PLSQL_OBJECT_SETTINGS) ------------------------

class _InfoTab extends StatefulWidget {
  final String name;
  final String type;
  final String ambiente;
  const _InfoTab({
    required this.name,
    required this.type,
    required this.ambiente,
  });
  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> with AutomaticKeepAliveClientMixin {
  List<({String name, String value})>? _data;
  Object? _error;
  bool _loading = true;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final props = await SchemaService.instance.getObjectInfo(
        widget.name,
        widget.type,
        ambiente: widget.ambiente,
      );
      if (!mounted) return;
      setState(() {
        _data = props;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final labelBg = isDark ? const Color(0xFF252526) : const Color(0xFFF0F2F5);

    if (_loading && _data == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF0078D4),
          strokeWidth: 2,
        ),
      );
    }
    if (_error != null && _data == null) {
      final msg = _error.toString();
      // Show pending state if the backend endpoint doesn't exist yet
      if (msg.contains('unknown tool') || msg.contains('unknow tool')) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                size: 36,
                color: sc.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 10),
              Text(
                'Pendiente de backend',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sc,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'get_object_info',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  color: sc.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Error al cargar información\n$msg',
            style: TextStyle(color: Colors.red.shade400, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final props = _data!;
    if (props.isEmpty) {
      return Center(
        child: Text(
          'Sin información disponible',
          style: TextStyle(fontSize: 13, color: sc),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: props.length,
            separatorBuilder: (context2, i2) => Divider(
              height: 1,
              color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFEEEEEE),
            ),
            itemBuilder: (_, i) {
              final p = props[i];
              final isEmpty = p.value.isEmpty || p.value == '(null)';
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 200,
                    padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                    color: labelBg,
                    child: Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w600,
                        color: sc,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    color: isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFDDE2EA),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        isEmpty ? '(null)' : p.value,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'Consolas',
                          color: isEmpty ? sc.withValues(alpha: 0.5) : tc,
                          fontStyle: isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        _StatusBar(
          count: props.length,
          label: 'propiedades',
          exportBaseName: _exportBaseName(widget.name, widget.ambiente, 'info'),
          exportSubtitle: _exportSubtitle(widget.name, widget.ambiente),
          buildExport: () => (
            title: 'Info de ${widget.name}',
            headers: ['PROPIEDAD', 'VALOR'],
            rows: [
              for (final p in props) [p.name, p.value],
            ],
          ),
        ),
      ],
    );
  }
}
