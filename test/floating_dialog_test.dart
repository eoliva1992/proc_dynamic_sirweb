import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/app_navigator.dart';
import 'package:proc_dynamic_sirweb/widgets/floating_window.dart';

/// El diálogo de confirmación debe montarse en el overlay raíz (como las
/// ventanas flotantes) para que NO quede tapado por la ventana que lo abre.
void main() {
  Widget app() => MaterialApp(
    navigatorKey: rootNavigatorKey,
    home: const Scaffold(body: SizedBox.expand()),
  );

  testWidgets(
    'showFloatingDialog se dibuja por encima de la ventana flotante',
    (tester) async {
      await tester.pumpWidget(app());
      final ctx = rootNavigatorKey.currentContext!;

      showFloatingWindow(
        ctx,
        (_) => const Material(child: Center(child: Text('VENTANA'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('VENTANA'), findsOneWidget);

      final future = showFloatingDialog<bool>(
        ctx,
        (dialogCtx, close) => AlertDialog(
          title: const Text('Transferir objeto'),
          actions: [
            TextButton(
              onPressed: () => close(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => close(true),
              child: const Text('Transferir'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transferir objeto'), findsOneWidget);

      await tester.tap(find.text('Transferir'));
      await tester.pumpAndSettle();
      expect(await future, isTrue);
      expect(find.text('Transferir objeto'), findsNothing);
      // La ventana sigue abierta detrás.
      expect(find.text('VENTANA'), findsOneWidget);
    },
  );

  testWidgets('descartar con la barrera devuelve null', (tester) async {
    await tester.pumpWidget(app());
    final ctx = rootNavigatorKey.currentContext!;

    final future = showFloatingDialog<bool>(
      ctx,
      (dialogCtx, close) => const AlertDialog(title: Text('Confirmar')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirmar'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5)); // barrera
    await tester.pumpAndSettle();
    expect(await future, isNull);
    expect(find.text('Confirmar'), findsNothing);
  });

  testWidgets('abrir diálogo desde MenuAnchor y cerrar ventana o diálogo', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final ctx = rootNavigatorKey.currentContext!;

    var count = 0;

    showFloatingWindow(
      ctx,
      (close) => StatefulBuilder(
        builder: (context, setState) => Material(
          child: Column(
            children: [
              Text('COUNT: $count'),
              MenuAnchor(
                menuChildren: [
                  MenuItemButton(
                    onPressed: () async {
                      final res = await showFloatingDialog<String>(
                        ctx,
                        (dialogCtx, closeDialog) => AlertDialog(
                          title: const Text('Diálogo Menu'),
                          content: const TextField(),
                          actions: [
                            FilledButton(
                              onPressed: () => closeDialog('OK'),
                              child: const Text('Aceptar'),
                            ),
                          ],
                        ),
                      );
                      if (res != null) {
                        setState(() => count++);
                      }
                    },
                    child: const Text('Abrir diálogo'),
                  ),
                ],
                builder: (context, controller, child) => IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => controller.open(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('Abrir diálogo'), findsOneWidget);

    await tester.tap(find.text('Abrir diálogo'));
    await tester.pumpAndSettle();
    expect(find.text('Diálogo Menu'), findsOneWidget);

    // Simular escribir texto en el TextField
    await tester.enterText(find.byType(TextField), 'PROC_TEST');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(find.text('Diálogo Menu'), findsNothing);
    expect(find.text('COUNT: 1'), findsOneWidget);
  });
}
