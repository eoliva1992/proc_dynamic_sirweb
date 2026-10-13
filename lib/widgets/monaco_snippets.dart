import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;

import '../services/snippet_service.dart';
import 'code_editor_panel.dart' show showSnippetsManager;
import 'plsql_symbols.dart';

// ── Snippets de usuario en editores Monaco ───────────────────────────────────
//
// Extrae la implementación de snippets del editor de procedimientos dinámicos
// (`code_editor_panel.dart`) para poder reutilizarla tal cual en cualquier otro
// editor Monaco de la app (p. ej. el editor de fuentes de objetos de esquema).

/// Se incrementa cada vez que el usuario modifica sus snippets.
///
/// Los editores abiertos escuchan este notificador para volver a registrar sus
/// completions sin tener que conocerse entre sí.
final ValueNotifier<int> snippetsRevision = ValueNotifier<int>(0);

/// Abre el gestor de snippets y notifica a los editores abiertos al cerrarlo.
Future<void> openSnippetsManager(BuildContext context) async {
  await showSnippetsManager(context);
  snippetsRevision.value++;
}

/// Registra los snippets del usuario como *completions* de Monaco.
///
/// Devuelve la registración para poder liberarla (`dispose`) o reemplazarla
/// luego de editar los snippets. Retorna `null` si no hay snippets.
///
/// Si [isLocalDocumentEditor] es `true`, se incluyen los snippets específicos de
/// YAML y texto plano (`yaml`, `any`).
/// Si es `false` (editores Oracle / SQL / PL-SQL), los snippets marcados con
/// lenguaje `yaml` se excluyen para que solo aparezcan en el editor de documentos locales.
Future<fm.MonacoCompletionRegistration?> registerUserSnippetCompletions(
  fm.MonacoController ctrl, {
  String id = 'user-snippets',
  bool isLocalDocumentEditor = false,
}) async {
  try {
    final allSnippets = await SnippetService.instance.loadAll();
    if (allSnippets.isEmpty) return null;

    final snippets = allSnippets.where((s) {
      final lang = s.language.toLowerCase().trim();
      if (isLocalDocumentEditor) {
        // En editor local: snippets de yaml o genéricos (any).
        // También admitimos otros si estuvieran disponibles en texto plano.
        return lang == 'yaml' || lang == 'any';
      }
      // En editores de procedimientos Oracle / SQL: no mostrar snippets yaml.
      return lang != 'yaml';
    }).toList();

    if (snippets.isEmpty) return null;

    final languages = isLocalDocumentEditor
        ? [fm.MonacoLanguage.yaml, fm.MonacoLanguage.plaintext]
        : [
            fm.MonacoLanguage.sql,
            fm.MonacoLanguage('plsql'),
            fm.MonacoLanguage.javascript,
          ];

    return await ctrl.registerStaticCompletions(
      id: id,
      languages: languages,
      triggerCharacters: const [' '],
      items: [
        for (final s in snippets)
          fm.CompletionItem(
            label: s.prefix,
            kind: fm.CompletionItemKind.snippet,
            detail: s.name,
            documentation: s.description.isNotEmpty ? s.description : null,
            insertText: s.body,
            insertTextRules: {fm.InsertTextRule.insertAsSnippet},
            // Por encima de las palabras clave del lenguaje.
            sortText: '0${s.prefix}',
          ),
      ],
    );
  } catch (_) {
    // Sin snippets disponibles (offline, error de red…): el editor sigue
    // funcionando normalmente.
    return null;
  }
}

// ── Símbolos declarados en el fuente ─────────────────────────────────────────

/// Icono de autocompletado según el tipo de símbolo.
fm.CompletionItemKind _kindOf(PlSqlSymbolKind k) => switch (k) {
  PlSqlSymbolKind.parameter => fm.CompletionItemKind.variable,
  PlSqlSymbolKind.variable => fm.CompletionItemKind.variable,
  PlSqlSymbolKind.constant => fm.CompletionItemKind.constant,
  PlSqlSymbolKind.cursor => fm.CompletionItemKind.reference,
  PlSqlSymbolKind.exception => fm.CompletionItemKind.event,
  PlSqlSymbolKind.type => fm.CompletionItemKind.typeParameter,
  PlSqlSymbolKind.subprogram => fm.CompletionItemKind.functionType,
};

/// Convierte el fuente PL/SQL en items de autocompletado con los parámetros y
/// variables declaradas.
///
/// El parseo corre en un isolate (`compute`) para no bloquear la UI en fuentes
/// grandes (packages de miles de líneas).
Future<List<fm.CompletionItem>> plsqlSymbolCompletions(String code) async {
  if (code.trim().isEmpty) return const [];
  final List<PlSqlSymbol> symbols;
  try {
    symbols = await compute(parsePlSqlSymbols, code);
  } catch (_) {
    return const [];
  }
  return [
    for (final s in symbols)
      fm.CompletionItem(
        label: s.name,
        kind: _kindOf(s.kind),
        detail: s.detail,
        insertText: s.name,
        // Por encima de las palabras clave del lenguaje, igual que en el
        // editor de procedimientos dinámicos.
        sortText: '0${s.name}',
      ),
  ];
}
