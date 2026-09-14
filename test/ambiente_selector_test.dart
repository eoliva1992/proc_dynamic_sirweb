import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/ambiente_selector.dart';

/// El selector se implementa con `PopupMenuButton` justamente porque el
/// `DropdownButton` de Material reventaba con
/// `Failed assertion: '_dropdownRoute == null'` cuando `onChanged` reconstruía
/// o desmontaba el subárbol (que es lo que hace cambiar de ambiente).
void main() {
  Widget host(String value, void Function(String) onChanged) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: AmbienteSelector(value: value, onChanged: onChanged),
      ),
    ),
  );

  /// Abre el menú (mostrando [actual]) y elige [ambiente].
  Future<void> elegir(
    WidgetTester tester,
    String actual,
    String ambiente,
  ) async {
    expect(find.text(actual), findsWidgets); // el botón muestra el actual
    await tester.tap(find.byType(AmbienteSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ambiente).last);
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el ambiente actual', (tester) async {
    await tester.pumpWidget(host('Desa', (_) {}));

    expect(find.text('Desa'), findsOneWidget);
  });

  testWidgets('elegir otro ambiente notifica el cambio', (tester) async {
    String? elegido;
    await tester.pumpWidget(host('Desa', (v) => elegido = v));

    await elegir(tester, 'Desa', 'Demo');

    expect(elegido, 'Demo');
  });

  testWidgets('elegir el mismo ambiente no notifica', (tester) async {
    var notificaciones = 0;
    await tester.pumpWidget(host('Desa', (_) => notificaciones++));

    await elegir(tester, 'Desa', 'Desa');

    expect(notificaciones, 0);
  });

  testWidgets('se puede reabrir el menú después de cambiar de ambiente', (
    tester,
  ) async {
    // Reproduce el escenario que rompía al dropdown: `onChanged` reconstruye el
    // árbol y a continuación el usuario vuelve a abrir el selector.
    var ambiente = 'Desa';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Center(
              child: AmbienteSelector(
                value: ambiente,
                onChanged: (v) => setState(() => ambiente = v),
              ),
            ),
          ),
        ),
      ),
    );

    await elegir(tester, 'Desa', 'Demo');
    expect(find.text('Demo'), findsOneWidget);

    await tester.tap(find.byType(AmbienteSelector));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Desa'), findsOneWidget); // el menú se abrió de nuevo
  });

  testWidgets('funciona dentro de un encabezado arrastrable', (tester) async {
    // El modal de ejecución pone el selector dentro de un GestureDetector
    // opaco que mueve la ventana (pan) y la maximiza (doble tap): esos gestos
    // no deben quedarse con el tap del selector.
    String? elegido;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (_) {},
            onDoubleTap: () {},
            child: Center(
              child: AmbienteSelector(
                value: 'Desa',
                onChanged: (v) => elegido = v,
              ),
            ),
          ),
        ),
      ),
    );

    await elegir(tester, 'Desa', 'Demo');

    expect(elegido, 'Demo');
  });

  testWidgets('el menú marca el ambiente activo', (tester) async {
    await tester.pumpWidget(host('QA', (_) {}));
    await tester.tap(find.byType(AmbienteSelector));
    await tester.pumpAndSettle();
    // Un check al lado del ambiente en uso, para no perderse en el listado.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
