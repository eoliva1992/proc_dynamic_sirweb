import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/floating_window.dart';

void main() {
  group('FloatingWindowSlots & MinimizedWindowCard', () {
    setUp(() {
      FloatingWindowSlots.release(0);
      FloatingWindowSlots.release(1);
      FloatingWindowSlots.release(2);
    });

    test('reparte slots ordenadamente y calcula offset de derecha a izquierda', () {
      final s0 = FloatingWindowSlots.take();
      final s1 = FloatingWindowSlots.take();
      expect(s0, 0);
      expect(s1, 1);

      const screenSize = Size(1920, 1080);
      final (left0, top0) = FloatingWindowSlots.offsetFor(s0, screenSize);
      final (left1, top1) = FloatingWindowSlots.offsetFor(s1, screenSize);

      // Los elementos se anclan a la derecha (left0 > left1 para slots consecutivos en la misma fila)
      expect(left0, greaterThan(left1));
      // Misma fila horizontal
      expect(top0, equals(top1));

      // Verificamos que no colisiona con el área inferior izquierda (donde vive SchemaStatusOverlay)
      expect(left0, greaterThan(1500));
      expect(left1, greaterThan(1200));

      FloatingWindowSlots.release(s0);
      FloatingWindowSlots.release(s1);
    });

    testWidgets(
      'MinimizedWindowCard renderiza título, badge y responde a acciones',
      (tester) async {
        var restored = false;
        var closed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: FloatingWindowSlots.barW,
                  height: FloatingWindowSlots.barH,
                  child: MinimizedWindowCard(
                    title: 'Mi Procedimiento Test',
                    icon: Icons.code_rounded,
                    badge: 'DEV',
                    accentColor: Colors.blue,
                    onRestore: () => restored = true,
                    onClose: () => closed = true,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Mi Procedimiento Test'), findsOneWidget);
        expect(find.text('DEV'), findsOneWidget);
        expect(find.byIcon(Icons.code_rounded), findsOneWidget);

        await tester.tap(find.byTooltip('Restaurar'));
        expect(restored, isTrue);

        await tester.tap(find.byTooltip('Cerrar'));
        expect(closed, isTrue);
      },
    );
  });
}
