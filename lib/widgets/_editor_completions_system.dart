part of 'code_editor_panel.dart';

// ── Validación backend, LSP y sistema de completions ─────────────────────────

extension _EditorCompletionsMethods on _CodeEditorPanelState {
  // ── Checkers de sintaxis ────────────────────────────────────────────────────

  void _scheduleCheck(String code) {
    if (_isActiveJs) return;
    _backendDebounce?.cancel();
    _backendDebounce = Timer(
      const Duration(seconds: 3),
      () => unawaited(_runBackendValidation(code, _activeProcId ?? '')),
    );
  }

  Future<void> _runBackendValidation(String code, String procId) async {
    if (code.length > _kBackendSizeLimit) {
      if (mounted) updateState(() => _backendIssuesPerProc.remove(procId));
      return;
    }
    final proc = _openProcs.cast<Procedimiento?>().firstWhere(
      (p) => p?.cdProcedimiento == procId,
      orElse: () => null,
    );
    if (proc == null) return;
    _backendCheckVersion++;
    final version = _backendCheckVersion;
    if (!mounted) return;
    updateState(() => _backendChecking = true);
    try {
      final results = await SchemaService.instance
          .compilarProcedimientoDinamico(
            procId,
            code,
            proc.inConfiguracion,
            ambiente: widget.ambiente,
          );
      if (!mounted || version != _backendCheckVersion) return;
      final issues = results
          .map(
            (e) => PlSqlIssue(
              line: e.line,
              col: e.position,
              endCol: e.position + 1,
              message: e.text,
              severity: e.attribute.toUpperCase() == 'WARNING'
                  ? MarkerSeverity.warning
                  : MarkerSeverity.error,
              source: 'Oracle-DDL',
            ),
          )
          .toList();
      updateState(() {
        _backendIssuesPerProc[procId] = issues;
        _errorCounts[procId] = [
          ...(_compileErrorsPerProc[procId] ?? []),
          ...issues,
        ].where((e) => e.severity == MarkerSeverity.error).length;
      });
      if (_activeProcId == procId) {
        final markersToSet = [
          for (final e in [...(_compileErrorsPerProc[procId] ?? []), ...issues])
            MarkerData(
              range: Range(
                startLine: e.line,
                startColumn: e.col,
                endLine: e.line,
                endColumn: e.endCol,
              ),
              message: e.message,
              severity: e.severity,
              source: e.source,
            ),
        ];

        void applyMarkers() {
          unawaited(
            _withCtrl(
              (ctrl) => ctrl.document.setMarkers(
                markersToSet,
                owner: 'plsql-checker',
              ),
            ),
          );
        }

        if (_isSuggestWidgetVisible) {
          // Defer marker update until suggestion popup is dismissed to avoid interrupting user typing
          _pendingMarkerUpdate = applyMarkers;
        } else {
          applyMarkers();
        }
      }
    } finally {
      if (mounted && version == _backendCheckVersion) {
        updateState(() => _backendChecking = false);
      }
    }
  }

  // ── Snippets de llamada a procedimientos / funciones / types ────────────────

  /// Argumentos cacheados del objeto (o `null` si aún no se consultaron).
  List<({String name, String dataType, String inOut})>? _cachedArgs(
    String name,
  ) => SchemaService.instance.peekObjectArguments(
    name,
    ambiente: widget.ambiente,
  );

  /// Atributos cacheados de un TYPE, expresados como argumentos del
  /// constructor (o `null` si aún no se consultaron).
  List<({String name, String dataType, String inOut})>? _cachedTypeArgs(
    String name,
  ) {
    final attrs = SchemaService.instance.peekTypeAttributes(
      name,
      ambiente: widget.ambiente,
    );
    if (attrs == null) return null;
    return [
      for (final a in attrs) (name: a.name, dataType: a.dataType, inOut: ''),
    ];
  }

  /// Firma cacheada del objeto según su tipo: argumentos para procedimientos y
  /// funciones, atributos del constructor para los types.
  List<({String name, String dataType, String inOut})>? _cachedSignature(
    String name,
    String type,
  ) => switch (type) {
    'PROCEDURE' || 'FUNCTION' => _cachedArgs(name),
    'TYPE' => _cachedTypeArgs(name),
    _ => null,
  };

  /// Texto a insertar al aceptar la sugerencia.
  ///
  /// Genera un snippet con notación nombrada, un parámetro por línea:
  /// ```
  /// MI_PROC(
  ///   P_UNO => ${1:P_UNO},
  ///   P_DOS => ${2:P_DOS}
  /// );
  /// ```
  ({String text, bool isSnippet}) _callInsertText(String name, String type) {
    final signature = _cachedSignature(name, type);
    if (signature == null) {
      // tipo sin firma (package) o metadata aún no disponible → nombre simple
      return (text: name, isSnippet: false);
    }
    return _buildCallSnippet(name, type, signature);
  }

  /// Indentación aplicada a cada parámetro dentro del snippet de llamada.
  static const String _snippetIndent = '  ';

  /// Construye el snippet de llamada con notación nombrada a partir de la firma.
  ///
  /// Sólo los procedimientos terminan en `;`: las funciones y los constructores
  /// de types se usan como expresión (`v_x := MI_TYPE(...)`).
  ({String text, bool isSnippet}) _buildCallSnippet(
    String name,
    String kind,
    List<({String name, String dataType, String inOut})> rawArgs,
  ) {
    final isProc = kind.toUpperCase() == 'PROCEDURE';
    final args = _realArgs(rawArgs);
    if (args.isEmpty) {
      return (text: isProc ? '$name;' : '$name()', isSnippet: false);
    }
    String esc(String s) => s.replaceAll(r'$', r'\$');
    // Un parámetro por línea, indentado, con el paréntesis de cierre alineado
    // a la llamada:
    //   MI_PROC(
    //     P_UNO => ${1:NULL},
    //     P_DOS => ${2:W_DOS}
    //   );
    final params = [
      for (var i = 0; i < args.length; i++)
        '$_snippetIndent${esc(args[i].name)} => \${${i + 1}:${esc(_callPlaceholderFor(args[i].name, args[i].inOut))}}',
    ].join(',\n');
    final body = '${esc(name)}(\n$params\n)';
    return (text: isProc ? '$body;' : body, isSnippet: true);
  }

  /// Valor por defecto del placeholder del snippet para un parámetro:
  /// `IN` → `NULL` (se espera un literal); `OUT`/`IN OUT` → nombre de
  /// variable sugerido cambiando el prefijo `P`/`P_` del parámetro por `W`/`W_`.
  String _callPlaceholderFor(String paramName, String inOut) {
    if (inOut.isEmpty || inOut.toUpperCase() == 'IN') return 'NULL';
    if (paramName.length >= 2 &&
        (paramName[0] == 'P' || paramName[0] == 'p') &&
        paramName[1] == '_') {
      return 'W_${paramName.substring(2)}';
    }
    if (paramName.isNotEmpty && (paramName[0] == 'P' || paramName[0] == 'p')) {
      return 'W${paramName.substring(1)}';
    }
    return 'W_$paramName';
  }

  /// Descarta el pseudo-argumento `(RETURN)` que Oracle reporta en funciones.
  List<({String name, String dataType, String inOut})> _realArgs(
    List<({String name, String dataType, String inOut})> args,
  ) => args
      .where((a) => a.name.isNotEmpty && a.name != '(RETURN)')
      .toList(growable: false);

  /// Icono del popup según el tipo de objeto Oracle.
  CompletionItemKind _objectKind(String type) => switch (type) {
    'FUNCTION' => CompletionItemKind.functionType,
    'PACKAGE' => CompletionItemKind.module,
    'TYPE' => CompletionItemKind.classType,
    _ => CompletionItemKind.method,
  };

  /// Sugerencias con los atributos de un TYPE objeto (`MI_TYPE.` → campos).
  Future<List<CompletionItem>> _typeMemberCompletions(
    String typeName,
    String memberPrefix,
  ) async {
    final attrs = await SchemaService.instance.getTypeAttributes(
      typeName,
      ambiente: widget.ambiente,
    );
    final prefix = memberPrefix.toUpperCase();
    return [
      for (final a in attrs)
        if (prefix.isEmpty || a.name.startsWith(prefix))
          CompletionItem(
            label: a.name,
            kind: CompletionItemKind.field,
            detail: '${a.dataType} · $typeName',
            insertText: a.name,
            sortText: '0${a.name}',
          ),
    ];
  }

  /// Sugerencias de parámetros cuando el cursor está dentro de la llamada:
  /// `MI_PROC(` → `P_UNO => `, `P_DOS => ` … omitiendo los ya escritos.
  ///
  /// Soporta tanto objetos sueltos (`MI_PROC(`) como miembros de un package
  /// (`MI_PKG.MI_PROC(`).
  Future<List<CompletionItem>> _parameterCompletions({
    required String owner,
    String? member,
    required String written,
    required String prefix,
  }) async {
    final ownerType = _cachedSchemaObjTypes?[owner.toUpperCase()];
    List<({String name, String dataType, String inOut})> args;

    if (member != null && member.isNotEmpty) {
      if (ownerType != 'PACKAGE') return const [];
      final subs = await SchemaService.instance.getPackageSubprograms(
        owner,
        ambiente: widget.ambiente,
      );
      final sub = subs
          .cast<
            ({
              String name,
              String kind,
              List<({String name, String dataType, String inOut})> arguments,
            })?
          >()
          .firstWhere(
            (s) => s?.name == member.toUpperCase(),
            orElse: () => null,
          );
      if (sub == null) return const [];
      args = _realArgs(sub.arguments);
    } else {
      if (ownerType == 'TYPE') {
        final attrs = await SchemaService.instance.getTypeAttributes(
          owner,
          ambiente: widget.ambiente,
        );
        args = [
          for (final a in attrs)
            (name: a.name, dataType: a.dataType, inOut: ''),
        ];
      } else if (ownerType == 'PROCEDURE' || ownerType == 'FUNCTION') {
        args = _realArgs(
          await SchemaService.instance.getObjectArguments(
            owner,
            ambiente: widget.ambiente,
          ),
        );
      } else {
        return const [];
      }
    }

    final upperWritten = written.toUpperCase();
    final upperPrefix = prefix.toUpperCase();
    return [
      for (final a in args)
        if ((upperPrefix.isEmpty || a.name.startsWith(upperPrefix)) &&
            !RegExp('\\b${RegExp.escape(a.name)}\\s*=>').hasMatch(upperWritten))
          CompletionItem(
            label: a.name,
            kind: CompletionItemKind.property,
            detail: '${a.inOut} ${a.dataType}'.trim(),
            insertText: '${a.name} => ',
            sortText: '0${a.name}',
          ),
    ];
  }

  /// Sugerencias con los subprogramas de un package (`MI_PKG.` → procs/funcs).
  Future<List<CompletionItem>> _packageMemberCompletions(
    String packageName,
    String memberPrefix,
  ) async {
    final subs = await SchemaService.instance.getPackageSubprograms(
      packageName,
      ambiente: widget.ambiente,
    );
    final prefix = memberPrefix.toUpperCase();
    final items = <CompletionItem>[];
    for (final s in subs) {
      if (prefix.isNotEmpty && !s.name.startsWith(prefix)) continue;
      final args = _realArgs(s.arguments);
      final call = _buildCallSnippet(s.name, s.kind, s.arguments);
      items.add(
        CompletionItem(
          label: s.name,
          kind: s.kind.toUpperCase() == 'FUNCTION'
              ? CompletionItemKind.functionType
              : CompletionItemKind.method,
          detail: args.isEmpty
              ? '${s.kind} · $packageName'
              : '${s.kind} (${args.map((a) => a.name).join(', ')})',
          documentation: args.isEmpty
              ? null
              : args
                    .map((a) => '${a.name} ${a.inOut} ${a.dataType}'.trim())
                    .join('\n'),
          insertText: call.text,
          insertTextRules: call.isSnippet
              ? {InsertTextRule.insertAsSnippet}
              : null,
          sortText: '0${s.name}',
        ),
      );
    }
    return items;
  }

  /// Firma resumida para la columna «detail» del popup.
  String _callDetail(String name, String type) {
    final signature = _cachedSignature(name, type);
    if (signature == null) return type;
    final args = _realArgs(signature);
    if (args.isEmpty) return type;
    return '$type (${args.map((a) => a.name).join(', ')})';
  }

  /// Documentación con la lista de parámetros y sus tipos.
  String? _callDocumentation(String name, String type) {
    final signature = _cachedSignature(name, type);
    if (signature == null) return null;
    final args = _realArgs(signature);
    if (args.isEmpty) return null;
    return args
        .map((a) => '${a.name} ${a.inOut} ${a.dataType}'.trim())
        .join('\n');
  }
}
