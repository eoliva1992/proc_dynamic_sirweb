import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/plsql_symbols.dart';

List<String> _names(List<PlSqlSymbol> syms, PlSqlSymbolKind kind) =>
    syms.where((s) => s.kind == kind).map((s) => s.name).toList();

void main() {
  group('parsePlSqlSymbols', () {
    test('extrae parámetros de un procedimiento con firma en una línea', () {
      const src = '''
CREATE OR REPLACE PROCEDURE PR_TEST(p_codigo IN VARCHAR2, p_total OUT NUMBER) IS
BEGIN
  NULL;
END;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.parameter), ['p_codigo', 'p_total']);
      final p = syms.firstWhere((s) => s.name == 'p_codigo');
      expect(p.dataType, 'IN VARCHAR2');
      expect(p.scope, 'PR_TEST');
    });

    test('extrae parámetros con firma multilínea y valores por defecto', () {
      const src = '''
CREATE OR REPLACE FUNCTION FN_CALC(
    p_poliza    IN  NUMBER,
    p_fecha     IN  DATE DEFAULT SYSDATE,
    p_detalle   IN OUT VARCHAR2,
    p_opcional  IN  NUMBER := 0
) RETURN NUMBER IS
  v_total NUMBER := 0;
BEGIN
  RETURN v_total;
END;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.parameter), [
        'p_poliza',
        'p_fecha',
        'p_detalle',
        'p_opcional',
      ]);
      expect(
        syms.firstWhere((s) => s.name == 'p_detalle').dataType,
        'IN OUT VARCHAR2',
      );
      expect(syms.firstWhere((s) => s.name == 'p_fecha').dataType, 'IN DATE');
      expect(_names(syms, PlSqlSymbolKind.variable), contains('v_total'));
    });

    test('extrae variables, constantes, cursores, excepciones y tipos', () {
      const src = '''
CREATE OR REPLACE PROCEDURE PR_X IS
  v_nombre     VARCHAR2(100);
  v_monto      NUMBER(12,2) := 0;
  c_maximo     CONSTANT NUMBER := 100;
  v_ref        poliza.cd_poliza%TYPE;
  CURSOR cur_polizas IS SELECT * FROM poliza;
  e_invalido   EXCEPTION;
  TYPE t_lista IS TABLE OF NUMBER;
BEGIN
  NULL;
END;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.variable), [
        'v_nombre',
        'v_monto',
        'v_ref',
      ]);
      expect(_names(syms, PlSqlSymbolKind.constant), ['c_maximo']);
      expect(_names(syms, PlSqlSymbolKind.cursor), ['cur_polizas']);
      expect(_names(syms, PlSqlSymbolKind.exception), ['e_invalido']);
      expect(_names(syms, PlSqlSymbolKind.type), ['t_lista']);
      expect(
        syms.firstWhere((s) => s.name == 'v_ref').dataType,
        'poliza.cd_poliza%TYPE',
      );
    });

    test('recorre todos los subprogramas de un package body', () {
      const src = '''
CREATE OR REPLACE PACKAGE BODY PCK_TEST IS

  g_contador NUMBER := 0;

  PROCEDURE pr_uno(p_uno IN VARCHAR2) IS
    v_local NUMBER;
  BEGIN
    NULL;
  END pr_uno;

  FUNCTION fn_dos(p_dos IN DATE) RETURN NUMBER IS
    v_otra VARCHAR2(10);
  BEGIN
    RETURN 1;
  END fn_dos;

END PCK_TEST;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.subprogram), ['pr_uno', 'fn_dos']);
      expect(_names(syms, PlSqlSymbolKind.parameter), ['p_uno', 'p_dos']);
      expect(
        _names(syms, PlSqlSymbolKind.variable),
        containsAll(['g_contador', 'v_local', 'v_otra']),
      );
      expect(syms.firstWhere((s) => s.name == 'v_local').scope, 'pr_uno');
    });

    test('ignora comentarios y literales de texto', () {
      const src = '''
CREATE OR REPLACE PROCEDURE PR_Y IS
  -- v_comentada NUMBER;
  /* v_bloque VARCHAR2(10);
     sigue el bloque */
  v_real VARCHAR2(10) := 'v_dentro_del_texto NUMBER';
BEGIN
  NULL;
END;
''';
      final syms = parsePlSqlSymbols(src);
      final vars = _names(syms, PlSqlSymbolKind.variable);
      expect(vars, ['v_real']);
      expect(vars, isNot(contains('v_comentada')));
      expect(vars, isNot(contains('v_bloque')));
      expect(vars, isNot(contains('v_dentro_del_texto')));
    });

    test('no toma sentencias ejecutables como declaraciones', () {
      const src = '''
CREATE OR REPLACE PROCEDURE PR_Z IS
  v_ok NUMBER;
BEGIN
  v_ok := 1;
  UPDATE poliza SET estado = 1 WHERE cd_poliza = v_ok;
  INSERT INTO log VALUES (v_ok);
END;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.variable), ['v_ok']);
    });

    test('devuelve vacío con código vacío', () {
      expect(parsePlSqlSymbols(''), isEmpty);
      expect(parsePlSqlSymbols('   \n  '), isEmpty);
    });
  });
}
