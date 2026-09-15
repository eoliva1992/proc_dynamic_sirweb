part of 'object_source_page.dart';

extension _ObjectSourceBackup on _ObjectSourcePageState {
  Future<void> _showBackupDialog() async {
    final isTable = widget.objectType == 'TABLE';

    var includeSpec = true;
    var includeBody = _bodyText.isNotEmpty;
    var includeTableComments = _tableDdlComments != null;
    var includeSynonym = false;
    var includeGrants = false;

    final typeColor = kTypeColors[widget.objectType] ?? const Color(0xFF0078D4);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final hasBody = _bodyText.isNotEmpty;
          final canSave =
              includeSpec ||
              (hasBody && includeBody) ||
              (isTable && includeTableComments) ||
              includeSynonym ||
              includeGrants;

          Widget checkRow(
            String label,
            bool value,
            bool enabled,
            ValueChanged<bool?> onChanged, {
            String? subtitle,
            IconData icon = Icons.check_box_outline_blank,
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
                        activeColor: typeColor,
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

          return AlertDialog(
            titlePadding: EdgeInsets.zero,
            title: ConstellationDialogTitle(
              lineColor: typeColor.withValues(alpha: 0.35),
              child: Row(
                children: [
                  Icon(Icons.download_outlined, size: 18, color: typeColor),
                  const SizedBox(width: 8),
                  const Text(
                    'Generar backup SQL',
                    style: TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seleccioná qué incluir en el script',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  // ── Fuente ──────────────────────────────────────────────
                  Text(
                    'FUENTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: typeColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  checkRow(
                    isTable ? 'DDL de tabla' : 'Especificación',
                    includeSpec,
                    _specText.isNotEmpty,
                    (v) => setDlg(() => includeSpec = v ?? false),
                    subtitle: isTable
                        ? 'CREATE TABLE + Índices + Constraints'
                        : widget.objectType == 'PACKAGE'
                        ? 'CREATE OR REPLACE PACKAGE ...'
                        : null,
                  ),
                  if (isTable && _tableDdlComments != null)
                    checkRow(
                      'Comentarios',
                      includeTableComments,
                      true,
                      (v) => setDlg(() => includeTableComments = v ?? false),
                      subtitle: 'COMMENT ON TABLE ...',
                    ),
                  if (!isTable && hasBody)
                    checkRow(
                      'Cuerpo',
                      includeBody,
                      true,
                      (v) => setDlg(() => includeBody = v ?? false),
                      subtitle: 'CREATE OR REPLACE PACKAGE BODY ...',
                    ),
                  const SizedBox(height: 10),
                  // ── Adicional ────────────────────────────────────────────
                  Text(
                    'ADICIONAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: typeColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  checkRow(
                    'Grant',
                    includeGrants,
                    true,
                    (v) => setDlg(() => includeGrants = v ?? false),
                    subtitle: isTable && _tableDdlGrants != null
                        ? 'Grants del DDL de tabla'
                        : 'GRANT EXECUTE ON OWNER.NAME TO PUBLIC',
                  ),
                  checkRow(
                    'Sinónimo público',
                    includeSynonym,
                    true,
                    (v) => setDlg(() => includeSynonym = v ?? false),
                    subtitle:
                        'CREATE OR REPLACE PUBLIC SYNONYM NAME FOR OWNER.NAME',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: canSave
                    ? () {
                        Navigator.pop(ctx);
                        _saveBackup(
                          includeSpec: includeSpec,
                          includeBody: includeBody && hasBody,
                          includeTableComments: includeTableComments,
                          includeSynonyms: includeSynonym,
                          includeGrants: includeGrants,
                        );
                      }
                    : null,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Guardar .sql'),
                style: FilledButton.styleFrom(backgroundColor: typeColor),
              ),
            ],
          );
        },
      ),
    );
  }

  // Resolves the schema owner for this object from the cached metadata or table DDL.
  String _objectOwner() {
    if (_tableDdlOwner.isNotEmpty) return _tableDdlOwner;
    final cached = SchemaService.instance.getCached(ambiente: widget.ambiente);
    return cached?.objects
            .where((o) => o.name == widget.name.toUpperCase())
            .firstOrNull
            ?.owner ??
        '';
  }

  Future<void> _saveBackup({
    required bool includeSpec,
    required bool includeBody,
    bool includeTableComments = false,
    required bool includeSynonyms,
    required bool includeGrants,
  }) async {
    final parts = <String>[];
    final isTable = widget.objectType == 'TABLE';

    if (includeSpec) {
      // For TABLE use the raw createTable; for others use the full specText
      final source = isTable ? _tableDdlCreateTable : _specText;
      if (source.isNotEmpty) parts.add('$source\n/');
    }
    if (includeTableComments && _tableDdlComments != null) {
      parts.add('${_tableDdlComments!}\n/');
    }
    if (includeBody && _bodyText.isNotEmpty) {
      parts.add('$_bodyText\n/');
    }

    if (includeSynonyms || includeGrants) {
      final owner = _objectOwner();
      final ref = owner.isNotEmpty ? '$owner.${widget.name}' : widget.name;
      if (includeGrants) {
        // For TABLE, use pre-built grants from DDL response; for others generate
        if (widget.objectType == 'TABLE' && _tableDdlGrants != null) {
          parts.add('${_tableDdlGrants!}\n/');
        } else {
          parts.add('GRANT EXECUTE ON $ref TO PUBLIC;\n/');
        }
      }
      if (includeSynonyms) {
        parts.add(
          'CREATE OR REPLACE PUBLIC SYNONYM ${widget.name} FOR $ref;\n/',
        );
      }
    }

    if (parts.isEmpty) return;

    final script = parts.join('\n\n');
    final suggested =
        '${widget.name.toLowerCase()}_${widget.ambiente.toLowerCase()}.sql';

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
}
