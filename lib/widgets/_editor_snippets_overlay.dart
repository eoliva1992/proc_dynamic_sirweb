part of 'code_editor_panel.dart';

class _SnippetsManagerDialog extends StatefulWidget {
  const _SnippetsManagerDialog();

  @override
  State<_SnippetsManagerDialog> createState() => _SnippetsManagerDialogState();
}

class _SnippetsManagerDialogState extends State<_SnippetsManagerDialog> {
  List<Snippet> _snippets = [];
  Snippet? _editing;
  bool _loading = true;
  bool _saving = false;
  bool _maximized = false;
  String? _error;
  String _query = '';
  Timer? _searchDebounce;
  final _formKey = GlobalKey<FormState>();
  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _language = 'any';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _prefixCtrl.dispose();
    _descCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  /// Local filter applied on top of the (already server-filtered) list.
  List<Snippet> get _visible => _query.isEmpty
      ? _snippets
      : _snippets.where((s) => s.matches(_query)).toList();

  void _toggleMaximized() => setState(() => _maximized = !_maximized);

  Future<void> _load({String? query}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await SnippetService.instance.search(
        query: query ?? _query,
        isActive: true,
        top: 200,
      );
      if (!mounted) return;
      setState(() {
        _snippets = page.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final cached = await SnippetService.instance.loadCached();
      if (!mounted) return;
      setState(() {
        _snippets = cached;
        _loading = false;
        _error = 'Sin conexión al servidor. Mostrando caché local.';
      });
      debugPrint('Snippets load error: $e');
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();
    // Short queries filter locally; longer ones hit the server.
    if (value.trim().length < 3) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load(query: value);
    });
  }

  void _select(Snippet s) {
    setState(() {
      _editing = s;
      _language = s.language;
    });
    _nameCtrl.text = s.name;
    _prefixCtrl.text = s.prefix;
    _descCtrl.text = s.description;
    _bodyCtrl.text = s.body;
  }

  void _clearForm() {
    setState(() {
      _editing = null;
      _language = 'any';
    });
    _nameCtrl.clear();
    _prefixCtrl.clear();
    _descCtrl.clear();
    _bodyCtrl.clear();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF252526) : cs.surface;
    final divColor = isDark ? const Color(0xFF3C3C3C) : cs.outlineVariant;
    final screen = MediaQuery.sizeOf(context);

    // Maximized keeps a small margin around the available area.
    final targetW = _maximized
        ? (screen.width - 48).clamp(360.0, screen.width)
        : 700.0;
    final targetH = _maximized
        ? (screen.height - 48).clamp(320.0, screen.height)
        : 500.0;
    // Wider layout gives more room to the snippets list.
    final listWidth = _maximized ? 300.0 : 220.0;

    return Center(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_maximized) {
              _toggleMaximized();
            } else {
              Navigator.of(context).pop();
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
                borderRadius: BorderRadius.circular(_maximized ? 6 : 10),
                border: Border.all(color: divColor, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _buildHeader(cs, divColor),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildList(cs, divColor, listWidth),
                        Container(width: 0.5, color: divColor),
                        Expanded(child: _buildForm(cs)),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Double-tap on the title bar toggles maximize, like a real window.
      onDoubleTap: _toggleMaximized,
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 16, right: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.code_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              'Snippets de usuario',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: _maximized
                  ? 'Restaurar tamaño (F11)'
                  : 'Maximizar (F11)',
              child: InkWell(
                onTap: _toggleMaximized,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    _maximized
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Tooltip(
              message: 'Cerrar (Esc)',
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ColorScheme cs, Color divColor, double width) {
    final items = _visible;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: width,
      child: Column(
        children: [
          // ---- Search box -------------------------------------------------
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar snippet…',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 15,
                  color: cs.onSurfaceVariant,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : InkWell(
                        onTap: () {
                          _searchCtrl.clear();
                          _searchDebounce?.cancel();
                          setState(() => _query = '');
                          _load(query: '');
                        },
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
              ),
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: Colors.orange.withValues(alpha: 0.12),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 10, color: Colors.orange[800]),
              ),
            ),
          InkWell(
            onTap: _clearForm,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
                color: _editing == null
                    ? cs.primaryContainer.withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  Icon(Icons.add, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Nuevo snippet',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
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
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _query.isEmpty
                          ? 'Sin snippets guardados.\nCrea el primero.'
                          : 'Sin resultados para\n"$_query".',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => _buildTile(cs, items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(ColorScheme cs, Snippet s) {
    final selected = _editing?.id == s.id;
    return InkWell(
      onTap: () => _select(s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.prefix,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Consolas',
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    s.name,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (s.language != 'any')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  s.language,
                  style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ColorScheme cs) {
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: cs.onSurfaceVariant,
    );

    InputDecoration deco({String? hint}) => InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 12,
        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
      ),
    );

    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name + prefix + language
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nombre', style: labelStyle),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: deco(hint: 'Ej: SELECT básico'),
                        style: const TextStyle(fontSize: 12),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '' : null,
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
                      Text('Prefix (trigger)', style: labelStyle),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _prefixCtrl,
                        decoration: deco(hint: 'Ej: sel'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'Consolas',
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '' : null,
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
                      Text('Lenguaje', style: labelStyle),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_language),
                        initialValue: _language,
                        isDense: true,
                        isExpanded: true,
                        decoration: deco(),
                        style: TextStyle(fontSize: 12, color: cs.onSurface),
                        items: const [
                          DropdownMenuItem(
                            value: 'any',
                            child: Text(
                              'Cualquier',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'sql',
                            child: Text(
                              'SQL / PL·SQL',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'javascript',
                            child: Text(
                              'JavaScript',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _language = v);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Descripción (opcional)', style: labelStyle),
            const SizedBox(height: 4),
            TextFormField(
              controller: _descCtrl,
              decoration: deco(
                hint: 'Breve descripción mostrada en el autocomplete',
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Cuerpo', style: labelStyle),
                const SizedBox(width: 8),
                // Tab-stop syntax reminder
                Text(
                  r'${1:placeholder}  ·  $0 cursor final',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'Consolas',
                    color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: TextFormField(
                controller: _bodyCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: deco(
                  hint: 'SELECT \${1:*}\nFROM \${2:tabla}\nWHERE \$0',
                ),
                style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
                validator: (v) => (v == null || v.isEmpty) ? '' : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_editing != null)
                  TextButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 14,
                      color: Colors.red[400],
                    ),
                    label: Text(
                      'Eliminar',
                      style: TextStyle(fontSize: 12, color: Colors.red[400]),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.save_outlined, size: 14),
                  label: Text(
                    _editing == null ? 'Crear snippet' : 'Guardar cambios',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
