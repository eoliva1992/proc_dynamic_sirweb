import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/monaco_snippets.dart';

void main() {
  // Fuente tal como lo devuelve Oracle desde USER_SOURCE (sin CREATE OR REPLACE).
  const src = '''
PROCEDURE PR_LIQUIDA (p_poliza IN NUMBER, p_total OUT NUMBER) IS
  v_prima  NUMBER := 0;
  v_desc   poliza.descripcion%TYPE;
BEGIN
  p_total := v_prima;
END;
''';

  test('plsqlSymbolCompletions devuelve items (valida el compute)', () async {
    final items = await plsqlSymbolCompletions(src);
    final labels = items.map((e) => e.label).toList();
    expect(
      labels,
      containsAll(['p_poliza', 'p_total', 'v_prima', 'v_desc']),
      reason: 'Si viene vacío, falló el parseo o el compute entre isolates',
    );
  });
}
