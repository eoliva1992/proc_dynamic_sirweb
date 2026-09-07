# Plan: Rediseño UI/UX del modal de snippets

Archivo objetivo: `lib/widgets/_editor_snippets_overlay.dart` (es `part of 'code_editor_panel.dart'`).

## Mejoras aplicadas en el diseño

**Estructura y jerarquía**
- Cabecera con icono en "pill", título, subtítulo con contador de snippets y acciones (maximizar/cerrar) con hover.
- Panel izquierdo (lista) con buscador mejorado, botón "Nuevo snippet" tonal destacado y contador de resultados.
- Panel derecho (formulario) con cabecera contextual ("Nuevo snippet" / prefix editado + badge "sin guardar") y barra de acciones inferior separada con fondo.

**UX**
- Detección de cambios sin guardar (`_dirty`): confirma antes de cambiar de snippet, crear uno nuevo o cerrar con Esc.
- Atajos: `Ctrl+S` guardar, `Ctrl+N` nuevo, `F11` maximizar, `Esc` cerrar/restaurar. Se muestran como hint en el footer.
- Validaciones con mensajes reales (antes eran cadenas vacías, no se veía el motivo).
- Botón "Duplicar" para crear a partir del snippet seleccionado.
- Autofocus en el campo Nombre al crear.
- Resaltado de coincidencias de búsqueda en la lista, chip de lenguaje con color/icono, estados vacío y de error con icono y acción "Reintentar".

## Código (reemplaza `lib/widgets/_editor_snippets_overlay.dart`)

```dart
part of 'code_editor_panel.dart';

class _SnippetsManagerDialog extends StatefulWidget {
  const _SnippetsManagerDialog();

  @override
  State<_SnippetsManagerDialog> createState() => _SnippetsManagerDialogState();
}

typedef _LangMeta = ({String label, IconData icon, Color color});

const Map<String, _LangMeta> _kSnippetLanguages = {
  'any': (
    label: 'Cualquier',
    icon: Icons.all_inclusive_rounded,
    color: Color(0xFF8E8E93),
  ),
  'sql': (
    label: 'SQL / PL·SQL',
    icon: Icons.storage_rounded,
    color: Color(0xFF0078D4),
  ),
  'javascript': (
    label: 'JavaScript',
    icon: Icons.javascript_rounded,
    color: Color(0xFFD9A407),
  ),
};

class _SnippetsManagerDialogState extends State<_SnippetsManagerDialog> {
  List<Snippet> _snippets = [];
  Snippet? _editing;
  bool _loading = true;
  bool _saving = false;
  bool _maximized = false;
  String? _error;
  String _query = '';

  /// Última consulta efectivamente enviada al servidor (vacía = lista completa).
  String _lastServerQuery = '';
  Timer? _searchDebounce;

  /// Cache de "hay cambios sin guardar": evita recalcular en cada build y
  /// permite reconstruir sólo cuando el valor realmente cambia.
  bool _dirty = false;

  final _formKey = GlobalKey<FormState>();
  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  String _language = 'any';

  @override
  void initState() {
    super.initState();
    for (final c in [_nameCtrl, _prefixCtrl, _descCtrl, _bodyCtrl]) {
      c.addListener(_onFieldChanged);
    }
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    for (final c in [_nameCtrl, _prefixCtrl, _descCtrl, _bodyCtrl]) {
      c.removeListener(_onFieldChanged);
    }
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _prefixCtrl.dispose();
    _descCtrl.dispose();
    _bodyCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── Estado derivado ────────────────────────────────────────────────────

  /// Filtro local aplicado sobre la lista (ya filtrada en servidor).
  List<Snippet> get _visible => _query.trim().isEmpty
      ? _snippets
      : _snippets.where((s) => s.matches(_query.trim())).toList();

  bool get _hasUnsavedChanges {
    final base = _editing;
    if (base == null) {
      return _nameCtrl.text.trim().isNotEmpty ||
          _prefixCtrl.text.trim().isNotEmpty ||
          _descCtrl.text.trim().isNotEmpty ||
          _bodyCtrl.text.trim().isNotEmpty;
    }
    return _nameCtrl.text.trim() != base.name ||
        _prefixCtrl.text.trim() != base.prefix ||
        _descCtrl.text.trim() != base.description ||
        _bodyCtrl.text != base.body ||
        _language != base.language;
  }

  void _onFieldChanged() {
    final d = _hasUnsavedChanges;
    if (d != _dirty && mounted) setState(() => _dirty = d);
  }

  void _toggleMaximized() => setState(() => _maximized = !_maximized);

  // ── Datos ──────────────────────────────────────────────────────────────

  Future<void> _load({String? query}) async {
    final effectiveQuery = (query ?? _query).trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await SnippetService.instance.search(
        query: effectiveQuery,
        isActive: true,
        top: 200,
      );
      if (!mounted) return;
      setState(() {
        _snippets = page.items;
        _lastServerQuery = effectiveQuery;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final cached = await SnippetService.instance.loadCached();
      if (!mounted) return;
      setState(() {
        _snippets = cached;
        // El caché local es la lista completa: el filtrado pasa a ser local.
        _lastServerQuery = '';
        _loading = false;
        _error = 'Sin conexión al servidor. Mostrando caché local.';
      });
      debugPrint('Snippets load error: $e');
    }
  }

  void _onSearchChanged(String value) {
    final trimmed = value.trim();
    final wasServerFiltered = _lastServerQuery.isNotEmpty;
    setState(() => _query = value);
    _searchDebounce?.cancel();

    // Consultas cortas/vacías filtran localmente; las largas van al servidor.
    if (trimmed.length < 3) {
      // Si veníamos de una búsqueda en servidor, la lista actual es un
      // subconjunto: hay que recargar el listado completo para que el filtro
      // local vuelva a disponer de todos los snippets.
      if (wasServerFiltered) {
        _searchDebounce = Timer(const Duration(milliseconds: 350), () {
          if (mounted) _load(query: '');
        });
      }
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load(query: value);
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _searchDebounce?.cancel();
    setState(() => _query = '');
    if (_lastServerQuery.isNotEmpty) _load(query: '');
  }

  // ── Selección / formulario ─────────────────────────────────────────────

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    final ok = await _confirm(
      title: 'Descartar cambios',
      message: 'Hay cambios sin guardar en el snippet actual.\n'
          '¿Quieres descartarlos?',
      confirmLabel: 'Descartar',
      danger: true,
    );
    return ok;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: Icon(
            danger
                ? Icons.warning_amber_rounded
                : Icons.help_outline_rounded,
            color: danger ? cs.error : cs.primary,
          ),
          title: Text(title, style: const TextStyle(fontSize: 15)),
          content: Text(message, style: const TextStyle(fontSize: 13)),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: danger
                  ? FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    )
                  : null,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _select(Snippet s) async {
    if (_editing?.id == s.id && !_dirty) return;
    if (!await _confirmDiscardIfDirty()) return;
    if (!mounted) return;
    _nameCtrl.text = s.name;
    _prefixCtrl.text = s.prefix;
    _descCtrl.text = s.description;
    _bodyCtrl.text = s.body;
    setState(() {
      _editing = s;
      _language = s.language;
      _dirty = false;
    });
  }

  Future<void> _newSnippet() async {
    if (!await _confirmDiscardIfDirty()) return;
    if (!mounted) return;
    _clearForm();
    _nameFocus.requestFocus();
  }

  void _clearForm() {
    _nameCtrl.clear();
    _prefixCtrl.clear();
    _descCtrl.clear();
    _bodyCtrl.clear();
    setState(() {
      _editing = null;
      _language = 'any';
      _dirty = false;
    });
  }

  /// Crea una copia editable del snippet seleccionado (sin id → alta nueva).
  void _duplicate() {
    final base = _editing;
    if (base == null) return;
    _nameCtrl.text = '${base.name} (copia)';
    _prefixCtrl.text = '${base.prefix}_copia';
    _descCtrl.text = base.description;
    _bodyCtrl.text = base.body;
    setState(() {
      _editing = null;
      _language = base.language;
      _dirty = true;
    });
    _nameFocus.requestFocus();
    AppToast.info('Copia lista — revisa el prefix y guarda');
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppToast.warning('Revisa los campos obligatorios');
      return;
    }
    final base = _editing;
    final snippet = Snippet(
      id: base?.id ?? '',
      name: _nameCtrl.text.trim(),
      prefix: _prefixCtrl.text.trim(),
      body: _bodyCtrl.text,
      description: _descCtrl.text.trim(),
      language: _language,
      ownerUser: base?.ownerUser ?? SnippetService.currentUser,
      isActive: true,
      version: base?.version ?? 0,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await SnippetService.instance.save(snippet);
      await _load();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = saved;
        _dirty = false;
      });
      AppToast.success(base == null ? 'Snippet creado' : 'Snippet actualizado');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      AppToast.error('No se pudo guardar el snippet');
    }
  }

  Future<void> _delete() async {
    final current = _editing;
    if (current == null || !current.isPersisted) return;

    final label = current.name.isNotEmpty ? current.name : current.prefix;
    final confirmed = await _confirm(
      title: 'Eliminar snippet',
      message: '¿Seguro que quieres eliminar "$label"?\n'
          'Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SnippetService.instance.delete(current);
      _clearForm();
      await _load();
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.success('Snippet eliminado');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      AppToast.error('No se pudo eliminar el snippet');
    }
  }

  Future<void> _close() async {
    if (!await _confirmDiscardIfDirty()) return;
    if (mounted) Navigator.of(context).pop();
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F1F1F) : cs.surface;
    final panelBg = isDark ? const Color(0xFF252526) : cs.surfaceContainerLowest;
    final divColor = isDark ? const Color(0xFF3C3C3C) : cs.outlineVariant;
    final screen = MediaQuery.sizeOf(context);

    final targetW = _maximized
        ? (screen.width - 48).clamp(360.0, screen.width)
        : 820.0;
    final targetH = _maximized
        ? (screen.height - 48).clamp(320.0, screen.height)
        : 560.0;
    final listWidth = _maximized ? 320.0 : 250.0;

    return Center(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (!_saving) unawaited(_save());
          },
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              unawaited(_newSnippet()),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_maximized) {
              _toggleMaximized();
            } else {
              unawaited(_close());
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: targetW,
              height: targetH,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(_maximized ? 6 : 12),
                border: Border.all(color: divColor, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.38),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _buildHeader(cs, divColor),
                  if (_error != null) _buildErrorBanner(cs),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildList(cs, divColor, panelBg, listWidth),
                        Container(width: 0.5, color: divColor),
                        Expanded(child: _buildForm(cs, divColor)),
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

  Widget _buildHeader(ColorScheme cs, Color divColor) {
    final total = _snippets.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _toggleMaximized,
      child: Container(
        height: 54,
        padding: const EdgeInsets.only(left: 16, right: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(Icons.code_rounded, size: 16, color: cs.primary),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Snippets de usuario',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  _loading
                      ? 'Cargando…'
                      : '$total snippet${total == 1 ? '' : 's'} disponibles',
                  style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const Spacer(),
            _HeaderIconButton(
              icon: _maximized
                  ? Icons.close_fullscreen_rounded
                  : Icons.open_in_full_rounded,
              tooltip:
                  _maximized ? 'Restaurar tamaño (F11)' : 'Maximizar (F11)',
              onTap: _toggleMaximized,
            ),
            const SizedBox(width: 2),
            _HeaderIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Cerrar (Esc)',
              danger: true,
              onTap: () => unawaited(_close()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: Colors.orange.withValues(alpha: 0.13),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 14, color: Colors.orange[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(fontSize: 11, color: Colors.orange[800]),
            ),
          ),
          TextButton(
            onPressed: _loading ? null : () => _load(),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Reintentar', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    ColorScheme cs,
    Color divColor,
    Color panelBg,
    double width,
  ) {
    final items = _visible;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: width,
      color: panelBg,
      child: Column(
        children: [
          // ── Buscador + acción nueva ────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar por nombre, prefix o cuerpo…',
                    hintStyle: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 15,
                      color: cs.onSurfaceVariant,
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded, size: 14),
                            splashRadius: 12,
                            tooltip: 'Limpiar búsqueda',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                          ),
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 30, minHeight: 30),
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: cs.primary, width: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => unawaited(_newSnippet()),
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text(
                      'Nuevo snippet',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Contador de resultados ─────────────────────────────────────
          if (!_loading && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  Text(
                    _query.trim().isEmpty
                        ? 'TODOS'
                        : '${items.length} RESULTADO${items.length == 1 ? '' : 'S'}',
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  )
                : items.isEmpty
                    ? _buildEmptyList(cs)
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _SnippetListTile(
                          snippet: items[i],
                          selected: _editing?.id == items[i].id &&
                              items[i].id.isNotEmpty,
                          query: _query.trim(),
                          onTap: () => unawaited(_select(items[i])),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyList(ColorScheme cs) {
    final searching = _query.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.bookmark_add_outlined,
            size: 30,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 10),
          Text(
            searching
                ? 'Sin resultados para\n"${_query.trim()}"'
                : 'Aún no hay snippets.\nCrea el primero para reutilizar código.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (searching) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _clearSearch,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Limpiar búsqueda',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForm(ColorScheme cs, Color divColor) {
    final labelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      color: cs.onSurfaceVariant,
    );

    InputDecoration deco({String? hint}) => InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant.withValues(alpha: 0.45),
          ),
          errorStyle: const TextStyle(fontSize: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: cs.primary, width: 1),
          ),
        );

    final editing = _editing;
    final lines = '\n'.allMatches(_bodyCtrl.text).length + 1;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabecera contextual del formulario ─────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
            ),
            child: Row(
              children: [
                Icon(
                  editing == null
                      ? Icons.add_circle_outline_rounded
                      : Icons.edit_outlined,
                  size: 14,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    editing == null
                        ? 'Nuevo snippet'
                        : (editing.prefix.isNotEmpty
                            ? editing.prefix
                            : editing.name),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: editing == null ? null : 'Consolas',
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (_dirty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'sin guardar',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber[800],
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (editing != null)
                  Tooltip(
                    message: 'Duplicar snippet',
                    child: IconButton(
                      onPressed: _saving ? null : _duplicate,
                      icon: const Icon(Icons.copy_all_rounded, size: 15),
                      splashRadius: 15,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ),
              ],
            ),
          ),
          // ── Campos ─────────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('NOMBRE', style: labelStyle),
                            const SizedBox(height: 5),
                            TextFormField(
                              controller: _nameCtrl,
                              focusNode: _nameFocus,
                              decoration: deco(hint: 'Ej: SELECT básico'),
                              style: const TextStyle(fontSize: 12),
                              textInputAction: TextInputAction.next,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Obligatorio'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('PREFIX (TRIGGER)', style: labelStyle),
                            const SizedBox(height: 5),
                            TextFormField(
                              controller: _prefixCtrl,
                              decoration: deco(hint: 'Ej: sel'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'Consolas',
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (v) {
                                final t = v?.trim() ?? '';
                                if (t.isEmpty) return 'Obligatorio';
                                if (t.contains(' ')) return 'Sin espacios';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('LENGUAJE', style: labelStyle),
                            const SizedBox(height: 5),
                            DropdownButtonFormField<String>(
                              key: ValueKey(_language),
                              initialValue: _language,
                              isDense: true,
                              isExpanded: true,
                              decoration: deco(),
                              style:
                                  TextStyle(fontSize: 12, color: cs.onSurface),
                              items: [
                                for (final e in _kSnippetLanguages.entries)
                                  DropdownMenuItem(
                                    value: e.key,
                                    child: Row(
                                      children: [
                                        Icon(
                                          e.value.icon,
                                          size: 13,
                                          color: e.value.color,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            e.value.label,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _language = v);
                                _onFieldChanged();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('DESCRIPCIÓN (OPCIONAL)', style: labelStyle),
                  const SizedBox(height: 5),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: deco(
                      hint: 'Breve descripción mostrada en el autocomplete',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('CUERPO', style: labelStyle),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          r'${1:placeholder}  ·  $0 cursor final',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontFamily: 'Consolas',
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$lines línea${lines == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: TextFormField(
                      controller: _bodyCtrl,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: deco(
                        hint: 'SELECT \${1:*}\nFROM \${2:tabla}\nWHERE \$0',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        fontFamily: 'Consolas',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          // ── Barra de acciones ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
              border: Border(top: BorderSide(color: divColor, width: 0.5)),
            ),
            child: Row(
              children: [
                if (editing != null)
                  TextButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 15,
                      color: cs.error,
                    ),
                    label: Text(
                      'Eliminar',
                      style: TextStyle(fontSize: 12, color: cs.error),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  'Ctrl+S guardar · Ctrl+N nuevo · Esc cerrar',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(width: 12),
                if (_dirty)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () {
                            if (editing != null) {
                              unawaited(_select(editing));
                            } else {
                              _clearForm();
                            }
                          },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    child: const Text(
                      'Descartar',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.save_outlined, size: 15),
                  label: Text(
                    editing == null ? 'Crear snippet' : 'Guardar cambios',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón de icono de la barra de título, con feedback de hover.
class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverBg = widget.danger
        ? cs.error.withValues(alpha: 0.85)
        : cs.onSurface.withValues(alpha: 0.10);
    final fg = _hover && widget.danger ? cs.onError : cs.onSurfaceVariant;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hover ? hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 15, color: fg),
          ),
        ),
      ),
    );
  }
}

/// Fila de la lista de snippets: indicador de selección, hover, chip de
/// lenguaje y resaltado del texto buscado.
class _SnippetListTile extends StatefulWidget {
  const _SnippetListTile({
    required this.snippet,
    required this.selected,
    required this.query,
    required this.onTap,
  });

  final Snippet snippet;
  final bool selected;
  final String query;
  final VoidCallback onTap;

  @override
  State<_SnippetListTile> createState() => _SnippetListTileState();
}

class _SnippetListTileState extends State<_SnippetListTile> {
  bool _hover = false;

  /// Resalta las coincidencias de [query] dentro de [text].
  Widget _highlighted(String text, TextStyle style, ColorScheme cs) {
    final q = widget.query.toLowerCase();
    if (q.isEmpty) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + q.length),
          style: TextStyle(
            backgroundColor: cs.primary.withValues(alpha: 0.28),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = idx + q.length;
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: style, children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.snippet;
    final meta = _kSnippetLanguages[s.language] ?? _kSnippetLanguages['any']!;
    final bg = widget.selected
        ? cs.primary.withValues(alpha: 0.14)
        : _hover
            ? cs.onSurface.withValues(alpha: 0.05)
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.fromLTRB(6, 2, 6, 0),
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
            border: Border(
              left: BorderSide(
                color: widget.selected ? cs.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _highlighted(
                      s.prefix,
                      TextStyle(
                        fontSize: 12,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w600,
                        color: widget.selected ? cs.primary : cs.onSurface,
                      ),
                      cs,
                    ),
                    const SizedBox(height: 1),
                    _highlighted(
                      s.name,
                      TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
                      cs,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: meta.label,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(meta.icon, size: 11, color: meta.color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Notas:
- `unawaited` ya está disponible (viene de `dart:async`, importado en `code_editor_panel.dart`).
- Tras pegarlo, ejecuta `flutter analyze` y luego `graphify update .`.

