import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/slide_up_panel.dart';

/// El panel de problemas del editor se monta como capa flotante: debe
/// aparecer y desaparecer con animación, sin ocupar espacio cuando está
/// oculto (así no redimensiona el editor de Monaco).
void main() {
  const panelKey = Key('contenido-panel');
  const panelHeight = 200.0;

  Future<void> pump(WidgetTester tester, bool visible) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SlideUpPanel(
                  visible: visible,
                  height: panelHeight,
                  child: const SizedBox(
                    key: panelKey,
                    height: panelHeight,
                    child: Text('problemas'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('oculto no monta nada', (tester) async {
    await pump(tester, false);
    await tester.pumpAndSettle();

    expect(find.byKey(panelKey), findsNothing);
  });

  testWidgets('al mostrarse se desliza desde abajo', (tester) async {
    await pump(tester, false);
    await tester.pumpAndSettle();

    await pump(tester, true);
    await tester.pump(); // arranca la animación

    // A mitad de la animación ya está montado pero aún desplazado y traslúcido.
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.byKey(panelKey), findsOneWidget);

    final opacityMid = tester
        .widget<Opacity>(
          find.ancestor(
            of: find.byKey(panelKey),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;
    expect(opacityMid, greaterThan(0.0));
    expect(opacityMid, lessThan(1.0));

    final midTop = tester.getTopLeft(find.byKey(panelKey)).dy;

    // Al terminar, el panel está totalmente opaco y más arriba que a mitad.
    await tester.pumpAndSettle();
    final finalTop = tester.getTopLeft(find.byKey(panelKey)).dy;
    expect(finalTop, lessThan(midTop));
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byKey(panelKey),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      1.0,
    );
  });

  testWidgets('al ocultarse anima y termina desmontado', (tester) async {
    await pump(tester, true);
    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsOneWidget);

    await pump(tester, false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Sigue visible mientras dura la animación de salida.
    expect(find.byKey(panelKey), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsNothing);
  });

  testWidgets('el panel no ocupa espacio del layout al abrirse', (
    tester,
  ) async {
    // Reproduce la estructura real: editor arriba, panel como overlay.
    Future<void> pumpLayout(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: SizedBox.expand(key: Key('editor')),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SlideUpPanel(
                        visible: visible,
                        height: panelHeight,
                        child: const SizedBox(
                          key: panelKey,
                          height: panelHeight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await pumpLayout(false);
    await tester.pumpAndSettle();
    final sizeCerrado = tester.getSize(find.byKey(const Key('editor')));

    await pumpLayout(true);
    await tester.pumpAndSettle();
    final sizeAbierto = tester.getSize(find.byKey(const Key('editor')));

    expect(
      sizeAbierto,
      sizeCerrado,
      reason: 'el editor cambió de tamaño al abrir el panel',
    );
  });
}
