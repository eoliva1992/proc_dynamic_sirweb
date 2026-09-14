import 'package:flutter/painting.dart' show FontStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/code_highlight.dart';

/// Devuelve el tipo asignado al primer fragmento cuyo texto sea [text].
CodeTokenKind kindOf(List<CodeToken> tokens, String text) =>
    tokens.firstWhere((t) => t.text == text).kind;

void main() {
  group('tokenizeCode · PL/SQL', () {
    test('reconoce palabras clave sin distinguir mayúsculas', () {
      final t = tokenizeCode('begin SELECT 1; End;', 'sql');
      expect(kindOf(t, 'begin'), CodeTokenKind.keyword);
      expect(kindOf(t, 'SELECT'), CodeTokenKind.keyword);
      expect(kindOf(t, 'End'), CodeTokenKind.keyword);
    });

    test('un bloque sin lenguaje se trata como PL/SQL', () {
      // En este editor casi todo el código de las respuestas es PL/SQL.
      final t = tokenizeCode('BEGIN NULL; END;', null);
      expect(kindOf(t, 'BEGIN'), CodeTokenKind.keyword);
    });

    test('separa tipos, funciones conocidas y literales', () {
      final t = tokenizeCode("v_x VARCHAR2(10) := NVL(a, 'hola');", 'plsql');
      expect(kindOf(t, 'VARCHAR2'), CodeTokenKind.type);
      expect(kindOf(t, 'NVL'), CodeTokenKind.function);
      expect(kindOf(t, "'hola'"), CodeTokenKind.string);
      expect(kindOf(t, '10'), CodeTokenKind.number);
    });

    test('lo que va seguido de paréntesis se pinta como llamada', () {
      // Los paquetes del propio esquema no están en ninguna lista.
      final t = tokenizeCode('PCK_POLIZA.CALCULA(1);', 'sql');
      expect(kindOf(t, 'CALCULA'), CodeTokenKind.function);
    });

    test('la comilla duplicada no corta el literal', () {
      final t = tokenizeCode("s := 'no''cierra aquí' || x;", 'sql');
      expect(kindOf(t, "'no''cierra aquí'"), CodeTokenKind.string);
    });

    test('un literal sin cerrar no se come el resto como error', () {
      final t = tokenizeCode("v := 'sin cerrar", 'sql');
      expect(t.last.kind, CodeTokenKind.string);
      expect(t.last.text, "'sin cerrar");
    });

    test('comentario de línea y de bloque', () {
      final t = tokenizeCode('-- nota\n/* otra */ x', 'sql');
      expect(kindOf(t, '-- nota'), CodeTokenKind.comment);
      expect(kindOf(t, '/* otra */'), CodeTokenKind.comment);
    });

    test('un comentario de bloque cortado por el streaming se cierra solo', () {
      final t = tokenizeCode('/* a medio escri', 'sql');
      expect(t.single.kind, CodeTokenKind.comment);
    });

    test('las bind variables se distinguen del texto normal', () {
      final t = tokenizeCode('WHERE cd_dato = :p_cd_dato', 'sql');
      expect(kindOf(t, ':p_cd_dato'), CodeTokenKind.param);
    });

    test('los identificadores corrientes quedan en texto plano', () {
      final t = tokenizeCode('SELECT cd_poliza FROM poliza', 'sql');
      expect(
        t.where((x) => x.kind == CodeTokenKind.plain).map((x) => x.text).join(),
        contains('cd_poliza'),
      );
    });

    test('conserva el texto original al recomponer', () {
      const src = "BEGIN\n  -- x\n  v := NVL(:p, 'a''b');\nEND;";
      expect(tokenizeCode(src, 'sql').map((t) => t.text).join(), src);
    });
  });

  group('tokenizeCode · otros lenguajes', () {
    test('reconoce palabras clave, tipos y cadenas', () {
      final t = tokenizeCode('final Widget w = Text("hola");', 'dart');
      expect(kindOf(t, 'final'), CodeTokenKind.keyword);
      expect(kindOf(t, 'Widget'), CodeTokenKind.type);
      expect(kindOf(t, '"hola"'), CodeTokenKind.string);
    });

    test('la barra doble y la almohadilla abren comentario', () {
      expect(
        kindOf(tokenizeCode('// nota', 'dart'), '// nota'),
        CodeTokenKind.comment,
      );
      expect(
        kindOf(tokenizeCode('# nota', 'python'), '# nota'),
        CodeTokenKind.comment,
      );
    });

    test('la barra invertida escapa dentro de la cadena', () {
      final t = tokenizeCode(r'var s = "a\"b";', 'js');
      expect(kindOf(t, r'"a\"b"'), CodeTokenKind.string);
    });

    test('conserva el texto original al recomponer', () {
      const src = 'if (x > 1) {\n  return foo("a"); // ok\n}';
      expect(tokenizeCode(src, 'js').map((t) => t.text).join(), src);
    });
  });

  group('highlightCode', () {
    test('cada tema usa su paleta', () {
      final oscuro = highlightCode('BEGIN', 'sql', isDark: true);
      final claro = highlightCode('BEGIN', 'sql', isDark: false);
      expect(oscuro.single.style!.color, SyntaxPalette.dark.keyword);
      expect(claro.single.style!.color, SyntaxPalette.light.keyword);
    });

    test('los comentarios van en cursiva, como en VS Code', () {
      final spans = highlightCode('-- nota', 'sql', isDark: true);
      expect(spans.single.style!.fontStyle, FontStyle.italic);
    });

    test('el código vacío no produce fragmentos', () {
      expect(highlightCode('', 'sql', isDark: true), isEmpty);
    });
  });
}
