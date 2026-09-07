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
      if (mounted) setState(() => _backendIssuesPerProc.remove(procId));
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
    setState(() => _backendChecking = true);
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
      setState(() {
        _backendIssuesPerProc[procId] = issues;
        _errorCounts[procId] = [
          ...(_compileErrorsPerProc[procId] ?? []),
          ...issues,
        ].where((e) => e.severity == MarkerSeverity.error).length;
      });
      if (_activeProcId == procId) {
        await _withCtrl(
          (ctrl) => ctrl.document.setMarkers([
            for (final e in [
              ...(_compileErrorsPerProc[procId] ?? []),
              ...issues,
            ])
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
          ], owner: 'plsql-checker'),
        );
      }
    } finally {
      if (mounted && version == _backendCheckVersion) {
        setState(() => _backendChecking = false);
      }
    }
  }

  // ── LSP ──────────────────────────────────────────────────────────────────────

  Future<void> _tryConnectLsp(MonacoController ctrl) async {
    try {
      final server = await LspServerProcess.start('sql-language-server', [
        'up',
        '--method',
        'stdio',
      ]);
      await ctrl.connectLanguageServer(
        id: 'sql-lsp',
        transport: server.transport,
        initializationTimeout: const Duration(seconds: 15),
      );
    } catch (_) {
      // sql-language-server no instalado — saltar silenciosamente
    }
  }

  // ── Variables dinámicas ───────────────────────────────────────────────────────

  List<VariableDinamica> _filteredVariables() {
    final activeConfig = _openProcs
        .cast<Procedimiento?>()
        .firstWhere(
          (p) => p?.cdProcedimiento == _activeProcId,
          orElse: () => null,
        )
        ?.inConfiguracion;
    if (activeConfig == null) return [];
    return procedimientosProvider.variablesDinamicas
        .where((v) => v.inConfiguracion == activeConfig)
        .toList();
  }

  // ── Schema completions ────────────────────────────────────────────────────────

  Future<void> _registerSchemaCompletions(MonacoController ctrl) async {
    _schemaReg?.dispose();
    _schemaReg = null;

    // El ambiente debe propagarse: `SchemaService` cachea por entorno y sin
    // este argumento siempre resolvería 'Desa', devolviendo completions del
    // esquema equivocado al trabajar en Demo/QA/Prod.
    final ambiente = widget.ambiente;

    SchemaService.instance
        .getMetadata(ambiente: ambiente)
        .then((schema) async {
          if (!mounted) return;

          _cachedSchemaObjTypes = schema.objects.fold(
            <String, String>{},
            (map, o) => map!..[o.name.toUpperCase()] = o.type,
          );

          _schemaReg = await _withCtrl(
            (ctrl) => ctrl.registerCompletions(
              id: 'oracle-schema',
              languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
              triggerCharacters: ['.', ' '],
              provider: (request) async {
                final line = request.lineText ?? '';
                final trigger = request.triggerCharacter;
                final fullText = _editorFullText;

                // Caso 1: "PKG." → subprogramas; "TYPE." → atributos;
                // "ALIAS." → columnas
                final dotMatch = _CodeEditorPanelState._reDotMember.firstMatch(
                  line,
                );
                if (dotMatch != null) {
                  final ref = dotMatch.group(1)!.toUpperCase();
                  final member = dotMatch.group(2)!.toUpperCase();
                  final refType = _cachedSchemaObjTypes?[ref];
                  if (refType == 'PACKAGE') {
                    return CompletionList(
                      suggestions: await _packageMemberCompletions(ref, member),
                    );
                  }
                  if (refType == 'TYPE') {
                    return CompletionList(
                      suggestions: await _typeMemberCompletions(ref, member),
                    );
                  }
                  if (trigger == '.' ||
                      line.endsWith('.') ||
                      member.isNotEmpty) {
                    final fromMap = _extractFromTables(fullText);
                    final realTable = fromMap[ref] ?? ref;
                    final cols = await SchemaService.instance.getColumns(
                      realTable,
                      ambiente: ambiente,
                    );
                    return CompletionList(
                      suggestions: cols
                          .where(
                            (c) => member.isEmpty || c.name.startsWith(member),
                          )
                          .map(
                            (c) => CompletionItem(
                              label: c.name,
                              kind: CompletionItemKind.field,
                              detail: '${c.dataType} · $realTable',
                              insertText: c.name,
                              sortText: '0${c.name}',
                            ),
                          )
                          .toList(),
                    );
                  }
                }

                // Dentro de "MI_PROC(" → parámetros con notación nombrada
                final callMatch = _CodeEditorPanelState._reCallOpen.firstMatch(
                  line,
                );
                if (callMatch != null) {
                  final params = await _parameterCompletions(
                    owner: callMatch.group(1)!,
                    member: callMatch.group(2),
                    written: callMatch.group(3) ?? '',
                    prefix: _wordBefore(line),
                  );
                  if (params.isNotEmpty) {
                    return CompletionList(suggestions: params);
                  }
                }

                // Caso 2: palabra suelta → prioriza columnas del FROM
                final word = _wordBefore(line);
                final upper = word.toUpperCase();
                final suggestions = <CompletionItem>[];

                final fromMap = _extractFromTables(fullText);
                for (final realTable in fromMap.values.toSet()) {
                  final cols = schema.cachedColumns.containsKey(realTable)
                      ? schema.cachedColumns[realTable]!
                      : await SchemaService.instance.getColumns(
                          realTable,
                          ambiente: ambiente,
                        );
                  suggestions.addAll(
                    cols
                        .where((c) => upper.isEmpty || c.name.startsWith(upper))
                        .map(
                          (c) => CompletionItem(
                            label: c.name,
                            kind: CompletionItemKind.field,
                            detail: '${c.dataType} · $realTable',
                            sortText: '1${c.name}',
                          ),
                        ),
                  );
                }

                suggestions.addAll(
                  schema.tables
                      .where((t) => upper.isEmpty || t.startsWith(upper))
                      .map(
                        (t) => CompletionItem(
                          label: t,
                          kind: CompletionItemKind.classType,
                          detail: 'TABLE',
                          sortText: '2$t',
                        ),
                      ),
                );

                suggestions.addAll(
                  schema.views
                      .where((v) => upper.isEmpty || v.startsWith(upper))
                      .map(
                        (v) => CompletionItem(
                          label: v,
                          kind: CompletionItemKind.interfaceType,
                          detail: 'VIEW',
                          sortText: '3$v',
                        ),
                      ),
                );

                final objMatches = schema.objects
                    .where((o) => upper.isEmpty || o.name.startsWith(upper))
                    .take(20)
                    .toList();

                // Precarga los argumentos / atributos (con caché) de los objetos
                // candidatos para poder ofrecer un snippet de llamada completo.
                if (upper.length >= 2) {
                  final pending = objMatches
                      .where(
                        (o) =>
                            o.type == 'PROCEDURE' ||
                            o.type == 'FUNCTION' ||
                            o.type == 'TYPE',
                      )
                      .take(10);
                  await Future.wait([
                    for (final o in pending)
                      if (o.type == 'TYPE')
                        SchemaService.instance.getTypeAttributes(
                          o.name,
                          ambiente: widget.ambiente,
                        )
                      else
                        SchemaService.instance.getObjectArguments(
                          o.name,
                          ambiente: widget.ambiente,
                        ),
                  ]);
                }

                suggestions.addAll(
                  objMatches.map((o) {
                    final call = _callInsertText(o.name, o.type);
                    return CompletionItem(
                      label: o.name,
                      kind: _objectKind(o.type),
                      detail: _callDetail(o.name, o.type),
                      documentation: _callDocumentation(o.name, o.type),
                      insertText: call.text,
                      insertTextRules: call.isSnippet
                          ? {InsertTextRule.insertAsSnippet}
                          : null,
                      sortText: '4${o.name}',
                    );
                  }),
                );

                return CompletionList(
                  suggestions: suggestions.take(50).toList(),
                );
              },
            ),
          );
        })
        .catchError((_) {});
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
    //     P_UNO => ${1:P_UNO},
    //     P_DOS => ${2:P_DOS}
    //   );
    final params = [
      for (var i = 0; i < args.length; i++)
        '$_snippetIndent${esc(args[i].name)} => \${${i + 1}:${esc(args[i].name)}}',
    ].join(',\n');
    final body = '${esc(name)}(\n$params\n)';
    return (text: isProc ? '$body;' : body, isSnippet: true);
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

  /// Extrae `{ ALIAS_UPPER → TABLA_REAL_UPPER }` del texto completo del documento.
  Map<String, String> _extractFromTables(String sql) {
    final hash = sql.hashCode ^ sql.length;
    if (hash == _fromExtractHash) return _fromExtractResult;
    final result = <String, String>{};

    void add(String table, String? alias) {
      final t = table.toUpperCase();
      result[t] = t;
      if (alias != null && alias.isNotEmpty) {
        result[alias.toUpperCase()] = t;
      }
    }

    final fromBlock =
        _CodeEditorPanelState._reFromBlock.firstMatch(sql)?.group(1) ?? '';
    for (final m in _CodeEditorPanelState._reAliasBlock.allMatches(fromBlock)) {
      final candidate = m.group(2)!.toUpperCase();
      const reserved = {
        'ON',
        'WHERE',
        'SET',
        'AND',
        'OR',
        'JOIN',
        'LEFT',
        'RIGHT',
        'INNER',
        'OUTER',
        'FULL',
        'CROSS',
        'GROUP',
        'ORDER',
        'HAVING',
      };
      if (!reserved.contains(candidate)) {
        add(m.group(1)!, m.group(2));
      }
    }
    for (final m in _CodeEditorPanelState._reFromSimple.allMatches(sql)) {
      add(m.group(1)!, null);
    }
    for (final m in _CodeEditorPanelState._reJoin.allMatches(sql)) {
      add(m.group(1)!, m.group(2));
    }

    _fromExtractHash = sql.hashCode ^ sql.length;
    _fromExtractResult = result;
    return result;
  }

  /// Devuelve la palabra que está escribiendo el usuario al final de la línea.
  String _wordBefore(String line) {
    final match = _CodeEditorPanelState._reWordEnd.firstMatch(line);
    return match?.group(1) ?? '';
  }

  void _onEditorThemeChanged() {
    // El store es global: puede notificar entre el dispose del webview y el
    // removeListener de este State, así que va por el guard de _withCtrl.
    unawaited(_withCtrl((ctrl) => ctrl.setTheme(editorThemeStore.monacoTheme)));
  }

  // ── Registros de completions ──────────────────────────────────────────────────

  Future<void> _registerVariableCompletions() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    await _variablesReg?.dispose();
    _variablesReg = null;
    final vars = _filteredVariables();
    if (vars.isEmpty) return;
    final items = [
      for (final v in vars)
        CompletionItem(
          label: ':${v.cdVariable}',
          kind: CompletionItemKind.variable,
          detail: v.deVariable,
          documentation: v.deVariable,
          insertText: ':${v.cdVariable}',
        ),
    ];
    _variablesReg = await ctrl.registerStaticCompletions(
      id: 'plsql-variables',
      languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
      triggerCharacters: [':', ' ', '.', '('],
      items: items,
    );
  }

  Future<void> _registerSnippetCompletions() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    await _snippetsReg?.dispose();
    _snippetsReg = null;
    final snippets = await SnippetService.instance.loadAll();
    if (snippets.isEmpty) return;
    _snippetsReg = await ctrl.registerStaticCompletions(
      id: 'user-snippets',
      languages: [
        MonacoLanguage.sql,
        MonacoLanguage('plsql'),
        MonacoLanguage.javascript,
      ],
      triggerCharacters: [' '],
      items: [
        for (final s in snippets)
          CompletionItem(
            label: s.prefix,
            kind: CompletionItemKind.snippet,
            detail: s.name,
            documentation: s.description.isNotEmpty ? s.description : null,
            insertText: s.body,
            insertTextRules: {InsertTextRule.insertAsSnippet},
            sortText: '0${s.prefix}',
          ),
      ],
    );
  }

  Future<void> _registerDeclareVarCompletions() async {
    final ctrl = _ctrl;
    if (ctrl == null || _isActiveJs) return;
    final code = _editorFullText.isNotEmpty
        ? _editorFullText
        : widget.procedimiento.deTexto;
    final outlineItems = await compute(_parseOutlineItems, code);
    await _declareVarsReg?.dispose();
    _declareVarsReg = null;
    final seen = <String>{};
    final items = <CompletionItem>[];
    for (final item in outlineItems) {
      if (item.type != _OutlineItemType.variable &&
          item.type != _OutlineItemType.cursor) {
        continue;
      }
      if (!seen.add(item.name.toUpperCase())) continue;
      items.add(
        CompletionItem(
          label: item.name,
          kind: CompletionItemKind.variable,
          insertText: item.name,
          sortText: '0${item.name}',
        ),
      );
    }
    if (items.isEmpty) return;
    _declareVarsReg = await ctrl.registerStaticCompletions(
      id: 'plsql-declare-vars',
      languages: [MonacoLanguage.sql, MonacoLanguage('plsql')],
      triggerCharacters: [':', ' ', '.', '('],
      items: items,
    );
  }

  void _openSnippetsManager() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'snippets-dismiss',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (_, _, _) => const _SnippetsManagerDialog(),
    ).then((_) {
      if (mounted) _registerSnippetCompletions();
    });
  }
}
