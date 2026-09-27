import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;

import '../providers/procedimientos_provider.dart';
import '../services/schema_service.dart';
import '_editor_plsql_completions.dart';
import 'monaco_snippets.dart';
import 'plsql_tables.dart';

/// Gestor de autocompletado Oracle para editores Monaco.
///
/// Ofrece paridad con el editor de procedimientos dinámicos:
/// 1. Palabras clave y plantillas estructurales Oracle SQL y PL/SQL.
/// 2. Snippets de usuario sincronizados automáticamente.
/// 3. Variables dinámicas con prefijo ':'.
/// 4. Esquema dinámico de Oracle:
///    - 'TABLA.' o 'ALIAS.' -> columnas de la tabla con tipos de datos.
///    - 'PKG.' -> subprogramas y funciones del paquete con firmas.
///    - 'TYPE.' -> atributos del tipo de objeto.
///    - 'PROC(' -> parámetros con notación nombrada ('P_PARAM => ').
///    - Palabras sueltas -> columnas de las tablas presentes en FROM/JOIN priorizadas,
///      tablas, vistas y objetos (procs/funcs/types) con snippets de llamada.
class MonacoOracleCompletionsManager {
  fm.MonacoCompletionRegistration? _kwReg;
  fm.MonacoCompletionRegistration? _snippetsReg;
  fm.MonacoCompletionRegistration? _schemaReg;
  fm.MonacoCompletionRegistration? _variablesReg;
  VoidCallback? _snippetsSub;
  bool _disposed = false;

  Map<String, String>? _cachedSchemaObjTypes;

  static final _reDotMember = RegExp(r'([A-Za-z]\w*)\.(\w*)$');
  static final _reCallOpen = RegExp(
    r'([A-Za-z]\w*)(?:\.([A-Za-z]\w*))?\s*\(([^()]*)$',
  );
  static final _reWordEnd = RegExp(r'(\w+)$');

  static String wordBefore(String line) =>
      _reWordEnd.firstMatch(line)?.group(1) ?? '';

  static String _wordBefore(String line) => wordBefore(line);

  Future<void> registerAll(
    fm.MonacoController ctrl, {
    required String Function() getText,
    required String Function() getAmbiente,
  }) async {
    _disposed = false;

    // 1. Palabras clave, tipos y snippets estáticos de Oracle SQL y PL/SQL
    try {
      _kwReg?.dispose();
      _kwReg = await ctrl.registerStaticCompletions(
        id: 'oracle-plsql-keywords',
        languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
        triggerCharacters: const [' ', '.', '('],
        items: plsqlCompletionItems,
      );
    } catch (_) {}

    // 2. Snippets de usuario
    await _registerUserSnippets(ctrl);
    _snippetsSub?.call();
    void onSnippetsRev() {
      if (!_disposed) _registerUserSnippets(ctrl);
    }

    snippetsRevision.addListener(onSnippetsRev);
    _snippetsSub = () => snippetsRevision.removeListener(onSnippetsRev);

    // 3. Variables dinámicas
    await _registerVariables(ctrl);

    // 4. Esquema dinámico Oracle
    await registerSchema(ctrl, getText: getText, getAmbiente: getAmbiente);
  }

  Future<void> _registerUserSnippets(fm.MonacoController ctrl) async {
    try {
      _snippetsReg?.dispose();
      _snippetsReg = null;
      _snippetsReg = await registerUserSnippetCompletions(
        ctrl,
        id: 'oracle-user-snippets',
      );
    } catch (_) {}
  }

  Future<void> _registerVariables(fm.MonacoController ctrl) async {
    try {
      _variablesReg?.dispose();
      _variablesReg = null;
      final vars = procedimientosProvider.variablesDinamicas;
      if (vars.isEmpty) return;
      final items = [
        for (final v in vars)
          fm.CompletionItem(
            label: ':${v.cdVariable}',
            kind: fm.CompletionItemKind.variable,
            detail: v.deVariable,
            documentation: v.deVariable,
            insertText: ':${v.cdVariable}',
            sortText: '0${v.cdVariable}',
          ),
      ];
      _variablesReg = await ctrl.registerStaticCompletions(
        id: 'oracle-bind-variables',
        languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
        triggerCharacters: const [':', ' '],
        items: items,
      );
    } catch (_) {}
  }

  Future<void> registerSchema(
    fm.MonacoController ctrl, {
    required String Function() getText,
    required String Function() getAmbiente,
  }) async {
    try {
      _schemaReg?.dispose();
      _schemaReg = null;

      final ambiente = getAmbiente();
      final schema = await SchemaService.instance.getMetadata(
        ambiente: ambiente,
      );
      if (_disposed) return;

      _cachedSchemaObjTypes = schema.objects.fold(
        <String, String>{},
        (map, o) => map!..[o.name.toUpperCase()] = o.type,
      );

      _schemaReg = await ctrl.registerCompletions(
        id: 'oracle-dynamic-schema',
        languages: [fm.MonacoLanguage.sql, fm.MonacoLanguage('plsql')],
        triggerCharacters: const ['.', ' ', '('],
        provider: (request) async {
          final line = request.lineText ?? '';
          final trigger = request.triggerCharacter;
          final fullText = getText();
          final curAmbiente = getAmbiente();

          // ── Caso 1: "PKG.", "TYPE.", "ALIAS." o "TABLA." ─────────────────
          final dotMatch = _reDotMember.firstMatch(line);
          if (dotMatch != null) {
            final ref = dotMatch.group(1)!.toUpperCase();
            final member = dotMatch.group(2)!.toUpperCase();
            final refType = _cachedSchemaObjTypes?[ref];

            // 1.a) Package → sus procedimientos y funciones
            if (refType == 'PACKAGE') {
              return fm.CompletionList(
                suggestions: await _packageMemberCompletions(
                  ref,
                  member,
                  curAmbiente,
                ),
              );
            }

            // 1.b) Type objeto → sus atributos
            if (refType == 'TYPE') {
              return fm.CompletionList(
                suggestions: await _typeMemberCompletions(
                  ref,
                  member,
                  curAmbiente,
                ),
              );
            }

            // 1.c) Tabla, vista o alias → columnas
            if (trigger == '.' || line.endsWith('.') || member.isNotEmpty) {
              final fromMap = extractSqlTables(fullText);
              final realTable = fromMap[ref] ?? ref;

              final cols = await SchemaService.instance.getColumns(
                realTable,
                ambiente: curAmbiente,
              );
              return fm.CompletionList(
                suggestions: cols
                    .where((c) => member.isEmpty || c.name.startsWith(member))
                    .map(
                      (c) => fm.CompletionItem(
                        label: c.name,
                        kind: fm.CompletionItemKind.field,
                        detail: '${c.dataType} · $realTable',
                        insertText: c.name,
                        sortText: '0${c.name}',
                      ),
                    )
                    .toList(),
              );
            }
          }

          // ── Caso 1.d: dentro de "MI_PROC(" → parámetros con notación nombrada
          final callMatch = _reCallOpen.firstMatch(line);
          if (callMatch != null) {
            final params = await _parameterCompletions(
              owner: callMatch.group(1)!,
              member: callMatch.group(2),
              written: callMatch.group(3) ?? '',
              prefix: _wordBefore(line),
              ambiente: curAmbiente,
            );
            if (params.isNotEmpty) {
              return fm.CompletionList(suggestions: params);
            }
          }

          // ── Caso 2: palabra suelta → prioriza columnas del FROM / JOIN ──────
          final word = _wordBefore(line);
          final upper = word.toUpperCase();
          final suggestions = <fm.CompletionItem>[];

          final fromMap = extractSqlTables(fullText);
          for (final realTable in fromMap.values.toSet()) {
            final cols = schema.cachedColumns.containsKey(realTable)
                ? schema.cachedColumns[realTable]!
                : await SchemaService.instance.getColumns(
                    realTable,
                    ambiente: curAmbiente,
                  );
            suggestions.addAll(
              cols
                  .where((c) => upper.isEmpty || c.name.startsWith(upper))
                  .map(
                    (c) => fm.CompletionItem(
                      label: c.name,
                      kind: fm.CompletionItemKind.field,
                      detail: '${c.dataType} · $realTable',
                      sortText: '1${c.name}',
                    ),
                  ),
            );
          }

          // Tablas
          suggestions.addAll(
            schema.tables
                .where((t) => upper.isEmpty || t.startsWith(upper))
                .map(
                  (t) => fm.CompletionItem(
                    label: t,
                    kind: fm.CompletionItemKind.classType,
                    detail: 'TABLE',
                    sortText: '2$t',
                  ),
                ),
          );

          // Vistas
          suggestions.addAll(
            schema.views
                .where((v) => upper.isEmpty || v.startsWith(upper))
                .map(
                  (v) => fm.CompletionItem(
                    label: v,
                    kind: fm.CompletionItemKind.interfaceType,
                    detail: 'VIEW',
                    sortText: '3$v',
                  ),
                ),
          );

          // Objetos (procedimientos, funciones, paquetes, tipos)
          final objMatches = schema.objects
              .where((o) => upper.isEmpty || o.name.startsWith(upper))
              .take(30)
              .toList();

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
                    ambiente: curAmbiente,
                  )
                else
                  SchemaService.instance.getObjectArguments(
                    o.name,
                    ambiente: curAmbiente,
                  ),
            ]);
          }

          suggestions.addAll(
            objMatches.map((o) {
              final call = _callInsertText(o.name, o.type, curAmbiente);
              return fm.CompletionItem(
                label: o.name,
                kind: _objectKind(o.type),
                detail: _callDetail(o.name, o.type, curAmbiente),
                documentation: _callDocumentation(o.name, o.type, curAmbiente),
                insertText: call.text,
                insertTextRules: call.isSnippet
                    ? {fm.InsertTextRule.insertAsSnippet}
                    : null,
                sortText: '4${o.name}',
              );
            }),
          );

          return fm.CompletionList(suggestions: suggestions.take(60).toList());
        },
      );
    } catch (_) {}
  }

  ({String text, bool isSnippet}) _callInsertText(
    String name,
    String type,
    String ambiente,
  ) {
    final signature = _cachedSignature(name, type, ambiente);
    if (signature == null) {
      return (text: name, isSnippet: false);
    }
    return _buildCallSnippet(name, type, signature);
  }

  List<({String name, String dataType, String inOut})>? _cachedSignature(
    String name,
    String type,
    String ambiente,
  ) {
    return switch (type) {
      'PROCEDURE' || 'FUNCTION' => SchemaService.instance.peekObjectArguments(
        name,
        ambiente: ambiente,
      ),
      'TYPE' => () {
        final attrs = SchemaService.instance.peekTypeAttributes(
          name,
          ambiente: ambiente,
        );
        if (attrs == null) return null;
        return [
          for (final a in attrs)
            (name: a.name, dataType: a.dataType, inOut: ''),
        ];
      }(),
      _ => null,
    };
  }

  String _callDetail(String name, String type, String ambiente) {
    final signature = _cachedSignature(name, type, ambiente);
    if (signature == null) return type;
    final args = signature
        .where((a) => a.name.isNotEmpty && a.name != '(RETURN)')
        .toList(growable: false);
    if (args.isEmpty) return type;
    return '$type (${args.map((a) => a.name).join(', ')})';
  }

  String? _callDocumentation(String name, String type, String ambiente) {
    final signature = _cachedSignature(name, type, ambiente);
    if (signature == null) return null;
    final args = signature
        .where((a) => a.name.isNotEmpty && a.name != '(RETURN)')
        .toList(growable: false);
    if (args.isEmpty) return null;
    return args
        .map((a) => '${a.name} ${a.inOut} ${a.dataType}'.trim())
        .join('\n');
  }

  fm.CompletionItemKind _objectKind(String type) => switch (type) {
    'FUNCTION' => fm.CompletionItemKind.functionType,
    'PACKAGE' => fm.CompletionItemKind.module,
    'TYPE' => fm.CompletionItemKind.classType,
    _ => fm.CompletionItemKind.method,
  };

  ({String text, bool isSnippet}) _buildCallSnippet(
    String name,
    String kind,
    List<({String name, String dataType, String inOut})> rawArgs,
  ) {
    final isProc = kind.toUpperCase() == 'PROCEDURE';
    final args = rawArgs
        .where((a) => a.name.isNotEmpty && a.name != '(RETURN)')
        .toList(growable: false);
    if (args.isEmpty) {
      return (text: isProc ? '$name;' : '$name()', isSnippet: false);
    }
    String esc(String s) => s.replaceAll(r'$', r'\$');
    final params = [
      for (var i = 0; i < args.length; i++)
        '  ${esc(args[i].name)} => \${${i + 1}:${esc(args[i].name)}}',
    ].join(',\n');
    final body = '${esc(name)}(\n$params\n)';
    return (text: isProc ? '$body;' : body, isSnippet: true);
  }

  Future<List<fm.CompletionItem>> _packageMemberCompletions(
    String packageName,
    String memberPrefix,
    String ambiente,
  ) async {
    final subs = await SchemaService.instance.getPackageSubprograms(
      packageName,
      ambiente: ambiente,
    );
    final prefix = memberPrefix.toUpperCase();
    final items = <fm.CompletionItem>[];
    for (final s in subs) {
      if (prefix.isNotEmpty && !s.name.startsWith(prefix)) continue;
      final args = s.arguments
          .where((a) => a.name.isNotEmpty && a.name != '(RETURN)')
          .toList(growable: false);
      final call = _buildCallSnippet(s.name, s.kind, s.arguments);
      items.add(
        fm.CompletionItem(
          label: s.name,
          kind: s.kind.toUpperCase() == 'FUNCTION'
              ? fm.CompletionItemKind.functionType
              : fm.CompletionItemKind.method,
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
              ? {fm.InsertTextRule.insertAsSnippet}
              : null,
          sortText: '0${s.name}',
        ),
      );
    }
    return items;
  }

  Future<List<fm.CompletionItem>> _typeMemberCompletions(
    String typeName,
    String memberPrefix,
    String ambiente,
  ) async {
    final attrs = await SchemaService.instance.getTypeAttributes(
      typeName,
      ambiente: ambiente,
    );
    final prefix = memberPrefix.toUpperCase();
    return [
      for (final a in attrs)
        if (prefix.isEmpty || a.name.startsWith(prefix))
          fm.CompletionItem(
            label: a.name,
            kind: fm.CompletionItemKind.field,
            detail: '${a.dataType} · $typeName',
            insertText: a.name,
            sortText: '0${a.name}',
          ),
    ];
  }

  Future<List<fm.CompletionItem>> _parameterCompletions({
    required String owner,
    String? member,
    required String written,
    required String prefix,
    required String ambiente,
  }) async {
    final ownerType = _cachedSchemaObjTypes?[owner.toUpperCase()];
    List<({String name, String dataType, String inOut})> args;

    if (member != null && member.isNotEmpty) {
      if (ownerType != 'PACKAGE') return const [];
      final subs = await SchemaService.instance.getPackageSubprograms(
        owner,
        ambiente: ambiente,
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
      args = sub.arguments
          .where((a) => a.name.isNotEmpty && a.name != '(RETURN)')
          .toList(growable: false);
    } else {
      if (ownerType == 'TYPE') {
        final attrs = await SchemaService.instance.getTypeAttributes(
          owner,
          ambiente: ambiente,
        );
        args = [
          for (final a in attrs)
            (name: a.name, dataType: a.dataType, inOut: ''),
        ];
      } else if (ownerType == 'PROCEDURE' || ownerType == 'FUNCTION') {
        final raw = await SchemaService.instance.getObjectArguments(
          owner,
          ambiente: ambiente,
        );
        args = raw
            .where((a) => a.name.isNotEmpty && a.name != '(RETURN)')
            .toList(growable: false);
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
          fm.CompletionItem(
            label: a.name,
            kind: fm.CompletionItemKind.property,
            detail: '${a.inOut} ${a.dataType}'.trim(),
            insertText: '${a.name} => ',
            sortText: '0${a.name}',
          ),
    ];
  }

  void dispose() {
    _disposed = true;
    _snippetsSub?.call();
    _snippetsSub = null;
    try {
      _kwReg?.dispose();
      _snippetsReg?.dispose();
      _schemaReg?.dispose();
      _variablesReg?.dispose();
    } catch (_) {}
    _kwReg = null;
    _snippetsReg = null;
    _schemaReg = null;
    _variablesReg = null;
  }
}
