import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/app_navigator.dart';
import 'package:proc_dynamic_sirweb/widgets/native_diff_viewer.dart';
import 'package:proc_dynamic_sirweb/widgets/procedure_diff_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openDiff(
  WidgetTester tester, {
  required String original,
  required String modified,
  String? ambiente,
  void Function(String)? onApplyToEditor,
  Size windowSize = const Size(1400, 900),
}) async {
  tester.view.physicalSize = windowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: rootNavigatorKey,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showProcedureDiff(
                context,
                title: 'Diff — DR_TEST',
                original: original,
                modified: modified,
                language: 'sql',
                ambiente: ambiente,
                onApplyToEditor: onApplyToEditor,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  const base = 'BEGIN\n  NULL;\nEND;';

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('muestra estadísticas, badges y navegación de hunks', (
    tester,
  ) async {
    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
      ambiente: 'DESA',
    );

    // Badges de roles
    expect(find.text('GUARDADO'), findsWidgets);
    expect(find.text('(DESA)'), findsOneWidget);
    expect(find.text('EDITOR'), findsWidgets);

    // Estadísticas de líneas
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);

    // Contador de hunks estilo "1 / 1"
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('inicia en vista completa y unificada por defecto', (
    tester,
  ) async {
    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
    );

    expect(find.text('Completo'), findsOneWidget);
    expect(find.text('Unificada'), findsOneWidget);
  });

  testWidgets(
    'permite alternar vista dividida/unificada y solo diffs/completo',
    (tester) async {
      await _openDiff(
        tester,
        original: base,
        modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
      );

      expect(find.text('Unificada'), findsOneWidget);
      await tester.tap(find.text('Unificada'));
      await tester.pumpAndSettle();
      expect(find.text('Dividida'), findsOneWidget);

      expect(find.text('Completo'), findsOneWidget);
      await tester.tap(find.text('Completo'));
      await tester.pumpAndSettle();
      expect(find.text('Solo diffs'), findsOneWidget);
    },
  );

  testWidgets('indica cuando no hay diferencias', (tester) async {
    await _openDiff(tester, original: base, modified: base);

    expect(find.text('✓ Sin cambios'), findsOneWidget);
  });

  testWidgets('normaliza saltos de línea CRLF para coincidir con LF', (
    tester,
  ) async {
    const crlfBase = 'BEGIN\r\n  NULL;\r\nEND;';
    const lfBase = 'BEGIN\n  NULL;\nEND;';

    await _openDiff(tester, original: crlfBase, modified: lfBase);
    expect(find.text('✓ Sin cambios'), findsOneWidget);
  });

  testWidgets('persiste la vista elegida en SharedPreferences', (tester) async {
    const modified = 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;';

    await _openDiff(tester, original: base, modified: modified);

    // Cambia a vista dividida + solo diffs
    await tester.tap(find.text('Unificada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completo'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('diff_side_by_side'), isTrue);
    expect(prefs.getBool('diff_show_all_lines'), isFalse);
  });

  testWidgets('restaura la vista guardada al reabrir el diff', (tester) async {
    SharedPreferences.setMockInitialValues({
      'diff_side_by_side': true,
      'diff_show_all_lines': false,
    });

    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
    );

    expect(find.text('Dividida'), findsOneWidget);
    expect(find.text('Solo diffs'), findsOneWidget);
  });

  testWidgets('soporta maximizar y restaurar ventana flotante', (tester) async {
    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
      windowSize: const Size(1800, 1000),
    );

    expect(find.byType(NativeDiffViewer), findsOneWidget);
    final initialSize = tester.getSize(find.byType(NativeDiffViewer));
    expect(initialSize.width, 1400.0);

    // Maximizar (1800 - 48 = 1752)
    await tester.tap(find.byTooltip('Maximizar'));
    await tester.pumpAndSettle();
    final maximizedSize = tester.getSize(find.byType(NativeDiffViewer));
    expect(maximizedSize.width, 1752.0);

    // Restaurar
    await tester.tap(find.byTooltip('Restaurar tamaño'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(NativeDiffViewer)).width, 1400.0);
  });

  testWidgets(
    'permite copiar cambios hacia el Editor y sincronizar con onApplyToEditor',
    (tester) async {
      String? appliedEditorCode;
      const dbCode = 'BEGIN\n  -- Guardado en DB\nEND;';
      const editorCode = 'BEGIN\n  -- Modificado en Editor\nEND;';

      await _openDiff(
        tester,
        original: dbCode,
        modified: editorCode,
        windowSize: const Size(1800, 900),
        onApplyToEditor: (code) {
          appliedEditorCode = code;
        },
      );

      expect(find.text('1 / 1'), findsOneWidget);

      // Copiar TODO GUARDADO → EDITOR con el botón de la toolbar
      await tester.tap(
        find.byTooltip('Copiar TODO: GUARDADO → EDITOR  (Alt+Shift+→)'),
      );
      await tester.pumpAndSettle();

      // Ahora no hay diferencias
      expect(find.text('✓ Sin cambios'), findsOneWidget);

      // Al haber cambiado el lado del editor, aparece el botón "Aplicar al editor"
      expect(find.text('Aplicar al editor'), findsWidgets);

      // En el header de la ventana
      final btnHeader = find
          .widgetWithText(FilledButton, 'Aplicar al editor')
          .last;
      await tester.tap(btnHeader);
      await tester.pumpAndSettle();

      expect(appliedEditorCode, dbCode);
    },
  );

  testWidgets('deshacer (Undo) revierte operaciones aplicadas', (tester) async {
    const dbCode = 'BEGIN\n  -- Guardado en DB\nEND;';
    const editorCode = 'BEGIN\n  -- Modificado en Editor\nEND;';

    await _openDiff(
      tester,
      original: dbCode,
      modified: editorCode,
      windowSize: const Size(1800, 900),
    );

    expect(find.text('1 / 1'), findsOneWidget);

    // Copiar todo a editor
    await tester.tap(
      find.byTooltip('Copiar TODO: GUARDADO → EDITOR  (Alt+Shift+→)'),
    );
    await tester.pumpAndSettle();
    expect(find.text('✓ Sin cambios'), findsOneWidget);

    // Asegurar visibilidad de Deshacer haciendo scroll horizontal si es necesario
    final undoFinder = find.text('Deshacer');
    await tester.scrollUntilVisible(
      undoFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Deshacer con el botón Undo
    expect(undoFinder, findsOneWidget);
    await tester.tap(undoFinder);
    await tester.pumpAndSettle();

    // Vuelve a haber 1 cambio
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('permite cerrar la ventana flotante', (tester) async {
    await _openDiff(
      tester,
      original: base,
      modified: 'BEGIN\n  DBMS_OUTPUT.PUT_LINE(1);\nEND;',
    );

    expect(find.byType(ProcedureDiffWindow), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    expect(find.byType(ProcedureDiffWindow), findsNothing);
  });
}
