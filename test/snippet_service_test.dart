import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/snippet.dart';
import 'package:proc_dynamic_sirweb/services/snippet_service.dart';

/// Integration test against the local snippets API (http://localhost:5179).
/// Skipped automatically when the server is not running.
///
/// `flutter_test` stubs all HTTP traffic with a 400 response, so the override
/// is disabled to allow real network calls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  final service = SnippetService.instance;

  test('CRUD + búsqueda de snippets contra el servidor', () async {
    {
      // 1. Consulta inicial (verifica que el servidor responde)
      try {
        await service.search(top: 1);
      } catch (e) {
        markTestSkipped('Servidor de snippets no disponible: $e');
        return;
      }

      final prefix = 'tst${DateTime.now().millisecondsSinceEpoch}';

      // 2. Registro
      final created = await service.save(
        Snippet(
          id: '',
          name: 'Snippet de prueba',
          prefix: prefix,
          body: 'SELECT \${1:*} FROM \${2:tabla} WHERE \$0',
          description: 'creado por test automatizado',
          language: 'sql',
          ownerUser: 'TEST',
        ),
      );
      expect(created.isPersisted, isTrue);
      expect(created.prefix, prefix);
      expect(created.version, greaterThanOrEqualTo(1));

      // 3. Búsqueda (server-side)
      final found = await service.search(query: prefix, top: 20);
      expect(found.items.any((s) => s.id == created.id), isTrue);

      // 4. Modificación
      final updated = await service.save(
        created.copyWith(name: 'Snippet de prueba (editado)'),
      );
      expect(updated.name, 'Snippet de prueba (editado)');
      expect(updated.version, greaterThan(created.version));

      // 5. Baja lógica
      await service.delete(updated);
      final afterDelete = await service.search(query: prefix, isActive: true);
      expect(afterDelete.items.any((s) => s.id == created.id), isFalse);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('filtro local del buscador', () {
    const s = Snippet(
      id: '1',
      name: 'SELECT básico',
      prefix: 'sel',
      body: 'SELECT * FROM dual',
      description: 'consulta simple',
    );
    expect(s.matches('sel'), isTrue);
    expect(s.matches('BÁSICO'), isTrue);
    expect(s.matches('dual'), isTrue);
    expect(s.matches('inexistente'), isFalse);
    expect(s.matches(''), isTrue);
  });
}
