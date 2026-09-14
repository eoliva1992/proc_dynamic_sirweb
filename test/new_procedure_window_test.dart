import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/new_procedure_dialog.dart';

void main() {
  testWidgets('el alta de procedimiento es una ventana con minimizar, '
      'maximizar y cerrar', (tester) async {
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

    var closed = false;
    showNewProcedureDialog(ctx, ambiente: 'Desa').then((_) => closed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Nuevo Procedimiento Dinámico'), findsOneWidget);
    expect(find.byTooltip('Minimizar'), findsOneWidget);
    expect(find.byTooltip('Maximizar (F11)'), findsOneWidget);
    expect(find.byTooltip('Cerrar (Esc)'), findsOneWidget);

    // Se escribe algo para comprobar que minimizar no reinicia el contenido.
    await tester.enterText(find.byType(TextFormField).first, 'PR_PRUEBA');
    await tester.pump();
    expect(find.text('PR_PRUEBA'), findsOneWidget);

    // ── Minimizar deja sólo la barra de título ────────────────────────────
    await tester.tap(find.byTooltip('Minimizar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nuevo Procedimiento Dinámico'), findsNothing);
    expect(find.text('Nuevo Procedimiento'), findsOneWidget);
    expect(find.byTooltip('Restaurar'), findsOneWidget);

    // ── Restaurar: el contenido nunca se desmontó, no se recarga ──────────
    await tester.tap(find.byTooltip('Restaurar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nuevo Procedimiento Dinámico'), findsOneWidget);
    expect(
      find.text('PR_PRUEBA'),
      findsOneWidget,
      reason: 'minimizar no debe reiniciar el formulario',
    );

    // ── Cerrar completa el Future con null ────────────────────────────────
    await tester.tap(find.byTooltip('Cerrar (Esc)'));
    // El clic debe responder de inmediato: sin esperar el timeout del
    // doble-clic de la barra de título.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Nuevo Procedimiento Dinámico'), findsNothing);
    expect(closed, isTrue);
  });
}
