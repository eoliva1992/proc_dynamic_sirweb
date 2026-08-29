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
  final _formKey = GlobalKey<FormState>();
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
    _nameCtrl.dispose();
    _prefixCtrl.dispose();
    _descCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final snips = await SnippetService.instance.loadAll();
    if (!mounted) return;
    setState(() {
      _snippets = snips;
      _loading = false;
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
    final snippet = Snippet(
      id: _editing?.id ?? SnippetService.generateId(),
      name: _nameCtrl.text.trim(),
      prefix: _prefixCtrl.text.trim(),
      body: _bodyCtrl.text,
      description: _descCtrl.text.trim(),
      language: _language,
    );
    await SnippetService.instance.save(snippet);
    await _load();
    if (!mounted) return;
    setState(() => _editing = snippet);
  }

  Future<void> _delete() async {
    final id = _editing?.id;
    if (id == null) return;
    await SnippetService.instance.delete(id);
    _clearForm();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF252526) : cs.surface;
    final divColor = isDark ? const Color(0xFF3C3C3C) : cs.outlineVariant;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 700,
          height: 500,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: divColor, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(cs, divColor),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildList(cs, divColor),
                    Container(width: 0.5, color: divColor),
                    Expanded(child: _buildForm(cs)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, Color divColor) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme cs, Color divColor) {
    return SizedBox(
      width: 220,
      child: Column(
        children: [
          InkWell(
            onTap: _clearForm,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: divColor, width: 0.5),
                ),
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
                : _snippets.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Sin snippets guardados.\nCrea el primero.',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: _snippets.length,
                    itemBuilder: (_, i) => _buildTile(cs, _snippets[i]),
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
                        decoration: deco(),
                        style: TextStyle(fontSize: 12, color: cs.onSurface),
                        items: const [
                          DropdownMenuItem(
                            value: 'any',
                            child: Text(
                              'Cualquier',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'sql',
                            child: Text(
                              'SQL / PL·SQL',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'javascript',
                            child: Text(
                              'JavaScript',
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
                    onPressed: _delete,
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
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined, size: 14),
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
