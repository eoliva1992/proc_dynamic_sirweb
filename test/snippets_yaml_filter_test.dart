import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/snippet.dart';

void main() {
  test('filtro de snippets excluye yaml para editores Oracle y lo incluye para editor local', () {
    final list = [
      Snippet(id: '1', name: 'SQL snippet', prefix: 'sel', body: 'SELECT 1;', language: 'sql'),
      Snippet(id: '2', name: 'YAML snippet', prefix: 'cfg', body: 'name: app', language: 'yaml'),
      Snippet(id: '3', name: 'Any snippet', prefix: 'log', body: 'print', language: 'any'),
      Snippet(id: '4', name: 'JS snippet', prefix: 'fn', body: '() => {}', language: 'javascript'),
    ];

    // Simula filtrado en editor de documentos locales
    final forLocal = list.where((s) {
      final lang = s.language.toLowerCase().trim();
      return lang == 'yaml' || lang == 'any';
    }).map((s) => s.prefix).toList();

    expect(forLocal, contains('cfg'));
    expect(forLocal, contains('log'));
    expect(forLocal, isNot(contains('sel')));
    expect(forLocal, isNot(contains('fn')));

    // Simula filtrado en editores Oracle / PLSQL
    final forOracle = list.where((s) {
      final lang = s.language.toLowerCase().trim();
      return lang != 'yaml';
    }).map((s) => s.prefix).toList();

    expect(forOracle, contains('sel'));
    expect(forOracle, contains('log'));
    expect(forOracle, contains('fn'));
    expect(forOracle, isNot(contains('cfg')));
  });
}
