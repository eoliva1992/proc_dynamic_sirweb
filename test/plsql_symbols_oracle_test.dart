import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/plsql_symbols.dart';

List<String> _names(List<PlSqlSymbol> syms, PlSqlSymbolKind kind) =>
    syms.where((s) => s.kind == kind).map((s) => s.name).toList();

void main() {
  group('fuentes tal como los devuelve Oracle', () {
    test('nombre calificado con esquema y entrecomillado', () {
      const src = '''
CREATE OR REPLACE EDITIONABLE PROCEDURE "SIR"."PR_LIQUIDA" 
(
  p_poliza   IN  NUMBER,
  p_total    OUT NUMBER
) 
AS
  v_prima NUMBER := 0;
BEGIN
  p_total := v_prima;
END;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.subprogram), ['PR_LIQUIDA']);
      expect(_names(syms, PlSqlSymbolKind.parameter), ['p_poliza', 'p_total']);
      expect(_names(syms, PlSqlSymbolKind.variable), ['v_prima']);
    });

    test('nombre con esquema sin comillas', () {
      const src = '''
CREATE OR REPLACE PROCEDURE SIR.PR_X (p_a IN VARCHAR2) IS
BEGIN
  NULL;
END;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.subprogram), ['PR_X']);
      expect(_names(syms, PlSqlSymbolKind.parameter), ['p_a']);
    });

    test('función con RETURN antes del IS y firma multilínea', () {
      const src = '''
CREATE OR REPLACE EDITIONABLE FUNCTION "SIR"."FN_TOTAL"
(
  p_desde IN DATE,
  p_hasta IN DATE
)
RETURN NUMBER
IS
  v_res NUMBER;
BEGIN
  RETURN v_res;
END FN_TOTAL;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.subprogram), ['FN_TOTAL']);
      expect(_names(syms, PlSqlSymbolKind.parameter), ['p_desde', 'p_hasta']);
      expect(_names(syms, PlSqlSymbolKind.variable), ['v_res']);
    });

    test('package body entrecomillado con varios subprogramas', () {
      const src = '''
CREATE OR REPLACE EDITIONABLE PACKAGE BODY "SIR"."PCK_POLIZA" AS

  PROCEDURE "PR_ALTA" (p_uno IN VARCHAR2) IS
    v_uno NUMBER;
  BEGIN
    NULL;
  END;

  FUNCTION fn_baja (p_dos IN NUMBER) RETURN NUMBER IS
    v_dos NUMBER;
  BEGIN
    RETURN 0;
  END;

END PCK_POLIZA;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.parameter), ['p_uno', 'p_dos']);
      expect(
        _names(syms, PlSqlSymbolKind.subprogram),
        containsAll(['PR_ALTA', 'fn_baja']),
      );
      expect(
        _names(syms, PlSqlSymbolKind.variable),
        containsAll(['v_uno', 'v_dos']),
      );
    });

    test('parámetro con %TYPE y default en firma multilínea', () {
      const src = '''
PROCEDURE PR_Y
(
    p_cd_poliza  IN  poliza.cd_poliza%TYPE,
    p_fecha      IN  DATE DEFAULT SYSDATE,
    p_obs        IN  VARCHAR2 := NULL
)
IS
BEGIN
  NULL;
END;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.parameter), [
        'p_cd_poliza',
        'p_fecha',
        'p_obs',
      ]);
      expect(
        syms.firstWhere((s) => s.name == 'p_cd_poliza').dataType,
        'IN poliza.cd_poliza%TYPE',
      );
    });

    test('procedimiento sin parámetros no rompe el parseo', () {
      const src = '''
CREATE OR REPLACE PROCEDURE "SIR"."PR_SIN_PARAMS" IS
  v_a NUMBER;
BEGIN
  NULL;
END;
''';
      final syms = parsePlSqlSymbols(src);
      expect(_names(syms, PlSqlSymbolKind.parameter), isEmpty);
      expect(_names(syms, PlSqlSymbolKind.variable), ['v_a']);
    });
  });
}
