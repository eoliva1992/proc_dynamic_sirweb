import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/schema_object_diff_page.dart';
import '../services/schema_recents_service.dart';
import '../services/schema_service.dart';
import 'ambiente_selector.dart';
import 'app_toast.dart';
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
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'object-details',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (ctx, _, anim2) =>
        _ObjectDetailsModal(name: name, type: type, ambiente: ambiente),
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

class _ObjectDetailsModal extends StatefulWidget {
  final String name;
  final String type;
  final String ambiente;
  const _ObjectDetailsModal({
    required this.name,
    required this.type,
    required this.ambiente,
  });

  @override
  State<_ObjectDetailsModal> createState() => _ObjectDetailsModalState();
}

class _ObjectDetailsModalState extends State<_ObjectDetailsModal> {
  bool _isFavorite = false;

  String get name => widget.name;
  String get type => widget.type;
  String get ambiente => widget.ambiente;

  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
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
    openSourceWindow(context, name: name, objectType: type, ambiente: ambiente);
  }

  void _openDiff() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SchemaObjectDiffPage(
          objectName: name,
          objectType: type,
          sourceAmbiente: ambiente,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = (size.width * 0.88).clamp(540.0, 880.0);
    final h = (size.height * 0.80).clamp(480.0, 700.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _tc(type);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  _buildHeader(context, isDark, color),
                  _buildTabBar(isDark, color),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _DetallesTab(
                          name: name,
                          type: type,
                          ambiente: ambiente,
                        ),
                        _InfoTab(name: name, type: type, ambiente: ambiente),
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
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, Color color) {
    final ambColor = AmbienteSelector.colorForAmbiente(ambiente);
    final hasSource = type != 'TABLE';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF5F7FA),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
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
            ),
            child: Icon(_ti(type), size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Consolas',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _badge(type, color),
                    const SizedBox(width: 6),
                    _badge(ambiente, ambColor),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Acciones con etiqueta ────────────────────────────────────
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
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(),
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
    child: TabBar(
      labelColor: color,
      unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
      indicatorColor: color,
      indicatorWeight: 2,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      tabs: const [
        Tab(text: 'Detalles'),
        Tab(text: 'Info'),
        Tab(text: 'Permisos'),
        Tab(text: 'Referencias'),
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

// ── Shared helpers ────────────────────────────────────────────────────────────

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

class _StatusBar extends StatelessWidget {
  final int count;
  final String label;
  const _StatusBar({required this.count, required this.label});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF0F2F5),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE2EA),
          ),
        ),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }
}

Color _rowBg(bool isDark, int i) => i.isEven
    ? (isDark ? const Color(0xFF1E1E1E) : Colors.white)
    : (isDark ? const Color(0xFF252526) : const Color(0xFFFAFAFA));

// ── Detalles tab ──────────────────────────────────────────────────────────────

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
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
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
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError)
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
            _StatusBar(count: cols.length, label: 'columnas'),
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
  late final Future<List<({String name, String dataType, String inOut})>> _f;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _f = SchemaService.instance.getObjectArguments(
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
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError)
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
                  'Error al cargar parámetros',
                  style: TextStyle(color: Colors.red.shade400, fontSize: 13),
                ),
              ],
            ),
          );
        final args = snap.data!;
        if (args.isEmpty)
          return Center(
            child: Text(
              'Sin parámetros',
              style: TextStyle(fontSize: 13, color: sc),
            ),
          );
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
            _StatusBar(count: args.length, label: 'parámetros'),
          ],
        );
      },
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
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
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
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError)
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
        if (attrs.isEmpty)
          return Center(
            child: Text(
              'Sin atributos',
              style: TextStyle(fontSize: 13, color: sc),
            ),
          );
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
                          child: Text(
                            a.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'Consolas',
                              color: tc,
                              fontWeight: FontWeight.w500,
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
                  );
                },
              ),
            ),
            _StatusBar(count: attrs.length, label: 'atributos'),
          ],
        );
      },
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
  late final Future<
    List<
      ({
        String name,
        String kind,
        List<({String name, String dataType, String inOut})> arguments,
      })
    >
  >
  _f;
  final _expanded = <String>{};
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _f = SchemaService.instance.getPackageSubprograms(
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
    final rowBg = isDark ? const Color(0xFF252526) : const Color(0xFFF8F8F8);
    final argBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    return FutureBuilder(
      future: _f,
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError)
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF0078D4),
              strokeWidth: 2,
            ),
          );
        if (snap.hasError)
          return Center(
            child: Text(
              'Error al cargar subprogramas',
              style: TextStyle(color: Colors.red.shade400, fontSize: 13),
            ),
          );
        final subs = snap.data!;
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
            _StatusBar(count: subs.length, label: 'subprogramas'),
          ],
        );
      },
    );
  }
}

// ── Permisos tab ─────────────────────────────────────────────────────────────

class _PermisosTab extends StatefulWidget {
  final String name;
  final String ambiente;
  const _PermisosTab({required this.name, required this.ambiente});
  @override
  State<_PermisosTab> createState() => _PermisosTabState();
}

class _PermisosTabState extends State<_PermisosTab>
    with AutomaticKeepAliveClientMixin {
  late final Future<
    List<({String grantee, String privilege, bool grantable, String grantor})>
  >
  _f;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _f = SchemaService.instance.getObjectPrivileges(
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
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError)
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF0078D4),
              strokeWidth: 2,
            ),
          );
        if (snap.hasError)
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error al cargar permisos\n${snap.error}',
                style: TextStyle(color: Colors.red.shade400, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          );
        final rows = snap.data!;
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
            _StatusBar(count: rows.length, label: 'permisos'),
          ],
        );
      },
    );
  }
}

// ── Referencias tab ───────────────────────────────────────────────────────────

class _ReferenciasTab extends StatefulWidget {
  final String name;
  final String ambiente;
  const _ReferenciasTab({required this.name, required this.ambiente});
  @override
  State<_ReferenciasTab> createState() => _ReferenciasTabState();
}

class _ReferenciasTabState extends State<_ReferenciasTab>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<({String name, String type, String owner})>> _f;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _f = SchemaService.instance.getObjectReferences(
      widget.name,
      ambiente: widget.ambiente,
    );
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
    return FutureBuilder(
      future: _f,
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError)
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF0078D4),
              strokeWidth: 2,
            ),
          );
        if (snap.hasError)
          return Center(
            child: Text(
              'Error al cargar referencias',
              style: TextStyle(color: Colors.red.shade400, fontSize: 13),
            ),
          );
        final rows = snap.data!;
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
            _StatusBar(count: rows.length, label: 'referencias'),
          ],
        );
      },
    );
  }
}

// ── Info tab (ALL_OBJECTS + ALL_PLSQL_OBJECT_SETTINGS) ────────────────────────

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
  late final Future<List<({String name, String value})>> _f;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _f = SchemaService.instance.getObjectInfo(
      widget.name,
      widget.type,
      ambiente: widget.ambiente,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sc = isDark ? const Color(0xFF888888) : Colors.black45;
    final tc = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final labelBg = isDark ? const Color(0xFF252526) : const Color(0xFFF0F2F5);

    return FutureBuilder(
      future: _f,
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF0078D4),
              strokeWidth: 2,
            ),
          );
        }
        if (snap.hasError) {
          final msg = snap.error.toString();
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
        final props = snap.data!;
        if (props.isEmpty) {
          return Center(
            child: Text(
              'Sin información disponible',
              style: TextStyle(fontSize: 13, color: sc),
            ),
          );
        }
        return ListView.separated(
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
        );
      },
    );
  }
}
