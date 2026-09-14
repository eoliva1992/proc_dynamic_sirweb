import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/code_editor_panel.dart'
    show showSnippetsManager;

void main() {
  testWidgets('el gestor de snippets se puede minimizar y restaurar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    showSnippetsManager(ctx);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Snippets de usuario'), findsOneWidget);
    expect(find.byTooltip('Minimizar'), findsOneWidget);

    // El formulario está visible antes de minimizar.
    expect(find.byType(Form), findsOneWidget);
    final normalRect = tester.getRect(find.byType(AnimatedPositioned).first);
    expect(normalRect.height, greaterThan(300));

    await tester.tap(find.byTooltip('Minimizar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Minimizado: la ventana se reduce a la barra de título…
    final minRect = tester.getRect(find.byType(AnimatedPositioned).first);
    expect(minRect.height, lessThan(60));
    expect(find.text('Snippets de usuario'), findsOneWidget);
    expect(find.byTooltip('Restaurar'), findsOneWidget);
    // …pero el contenido sigue montado: al restaurar no se recarga.
    expect(
      find.byType(Form),
      findsOneWidget,
      reason: 'minimizar no debe desmontar el contenido',
    );

    // Restaurar devuelve el tamaño completo.
    await tester.tap(find.byTooltip('Restaurar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Form), findsOneWidget);
    expect(
      tester.getRect(find.byType(AnimatedPositioned).first).height,
      normalRect.height,
    );
  });

  testWidgets('la ventana aparece y se cierra con animación', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    showSnippetsManager(ctx);

    // ── Entrada: arranca a escala reducida ────────────────────────────────
    // El animador es el ScaleTransition más externo sobre la ventana.
    final windowScale = find
        .ancestor(
          of: find.text('Snippets de usuario'),
          matching: find.byType(ScaleTransition),
        )
        .last;

    await tester.pump();
    expect(
      tester.widget<ScaleTransition>(windowScale).scale.value,
      lessThan(1.0),
    );

    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<ScaleTransition>(windowScale).scale.value, 1.0);

    // ── Salida: sigue montada mientras dura la animación ──────────────────
    await tester.tap(find.byTooltip('Cerrar (Esc)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      find.text('Snippets de usuario'),
      findsOneWidget,
      reason: 'debe seguir visible mientras se desvanece',
    );

    await tester.pumpAndSettle();
    expect(find.text('Snippets de usuario'), findsNothing);
  });
}
