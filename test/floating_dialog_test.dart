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
}
