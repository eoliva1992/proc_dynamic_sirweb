import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/editor_selection.dart';

void main() {
  group('EditorSelection.fromJson', () {
    test('construye la selección desde el JSON del webview', () {
      final s = EditorSelection.fromJson({
        'startLine': 10,
        'endLine': 14,
        'text': 'BEGIN NULL; END;',
      });
      expect(s, isNotNull);
      expect(s!.startLine, 10);
      expect(s.endLine, 14);
      expect(s.lineCount, 5);
    });

    test('descarta la selección vacía o en blanco', () {
      // Monaco considera «selección» un cursor arrastrado sin soltar texto.
      expect(EditorSelection.fromJson(null), isNull);
      expect(
        EditorSelection.fromJson({'startLine': 1, 'endLine': 1, 'text': '   '}),
        isNull,
      );
    });

    test('tolera un JSON con la forma equivocada', () {
      // Viene de JavaScript: no se puede confiar en los tipos.
      expect(EditorSelection.fromJson({'text': 'x'}), isNull);
      expect(
        EditorSelection.fromJson({'startLine': 0, 'endLine': 2, 'text': 'x'}),
        isNull,
      );
    });

    test('endLine nunca queda por debajo de startLine', () {
      final s = EditorSelection.fromJson({
        'startLine': 8,
        'endLine': 3,
        'text': 'x',
      });
      expect(s!.endLine, 8);
      expect(s.lineCount, 1);
    });
  });

  group('EditorSelection.label', () {
    test('una sola línea usa el formato archivo:línea', () {
      const s = EditorSelection(startLine: 112, endLine: 112, text: 'x');
      expect(s.label('DR_REGLA'), 'DR_REGLA:112');
    });

    test('un bloque usa el rango', () {
      const s = EditorSelection(startLine: 112, endLine: 140, text: 'x');
      expect(s.label('DR_REGLA'), 'DR_REGLA:112-140');
    });

    test('sin nombre de procedimiento cae en «editor»', () {
      const s = EditorSelection(startLine: 1, endLine: 1, text: 'x');
      expect(s.label('   '), 'editor:1');
    });
  });
}
