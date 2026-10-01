import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/main.dart';
import 'package:proc_dynamic_sirweb/providers/procedimientos_provider.dart';
import 'package:proc_dynamic_sirweb/widgets/usuario_dialog.dart';

void main() {
  setUp(() {
    procedimientosProvider.setCdUsuario('ADMIN');
  });

  Widget buildHost({
    VoidCallback? onSaved,
    String? initialValue,
    ThemeData? theme,
  }) {
    return MaterialApp(
      theme: theme ?? ThemeData.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () {
                  showUsuarioDialog(
                    context,
                    onSaved: onSaved,
                    initialValue: initialValue,
                  );
                },
                child: const Text('Abrir Diálogo'),
              ),
            );
          },
        ),
      ),
    );
  }

  testWidgets('muestra elementos del encabezado, campo y botones', (
    tester,
  ) async {
    await tester.pumpWidget(buildHost(initialValue: 'PRUEBA'));
    await tester.tap(find.text('Abrir Diálogo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Identificación de Usuario'), findsOneWidget);
    expect(
      find.text('Código para registrar autoría y cambios en Sirweb'),
      findsOneWidget,
    );
    expect(find.text('CÓDIGO DE USUARIO'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('PRUEBA'), findsOneWidget);
    expect(find.byTooltip('Cerrar'), findsOneWidget);
  });

  testWidgets('muestra banner informativo cuando el usuario inicial es vacío', (
    tester,
  ) async {
    await tester.pumpWidget(buildHost(initialValue: ''));
    await tester.tap(find.text('Abrir Diálogo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Requerido para guardar, compilar o activar procedimientos.'),
      findsOneWidget,
    );
  });

  testWidgets('el botón de limpiar borra el texto del campo', (tester) async {
    await tester.pumpWidget(buildHost(initialValue: 'DEV1'));
    await tester.tap(find.text('Abrir Diálogo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('DEV1'), findsOneWidget);
    final clearButton = find.byTooltip('Borrar texto');
    expect(clearButton, findsOneWidget);

    await tester.tap(clearButton);
    await tester.pump();

    expect(find.text('DEV1'), findsNothing);
    expect(find.byTooltip('Borrar texto'), findsNothing);
  });

  testWidgets(
    'escribir en minúsculas se formatea automáticamente a mayúsculas',
    (tester) async {
      await tester.pumpWidget(buildHost(initialValue: ''));
      await tester.tap(find.text('Abrir Diálogo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField), 'jperez');
      await tester.pump();

      expect(find.text('JPEREZ'), findsOneWidget);
    },
  );

  testWidgets(
    'guardar actualiza el provider y llama a onSaved si no está vacío',
    (tester) async {
      var savedCalled = false;
      await tester.pumpWidget(
        buildHost(initialValue: 'TESTUSER', onSaved: () => savedCalled = true),
      );
      await tester.tap(find.text('Abrir Diálogo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Guardar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(procedimientosProvider.cdUsuario, 'TESTUSER');
      expect(savedCalled, isTrue);
      expect(find.text('Identificación de Usuario'), findsNothing);
    },
  );

  testWidgets('enviar con enter guarda y cierra el diálogo', (tester) async {
    var savedCalled = false;
    await tester.pumpWidget(
      buildHost(initialValue: 'ENTERUSER', onSaved: () => savedCalled = true),
    );
    await tester.tap(find.text('Abrir Diálogo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(procedimientosProvider.cdUsuario, 'ENTERUSER');
    expect(savedCalled, isTrue);
    expect(find.text('Identificación de Usuario'), findsNothing);
  });

  testWidgets('guardar vacío actualiza el provider pero no ejecuta onSaved', (
    tester,
  ) async {
    var savedCalled = false;
    await tester.pumpWidget(
      buildHost(initialValue: '', onSaved: () => savedCalled = true),
    );
    await tester.tap(find.text('Abrir Diálogo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(procedimientosProvider.cdUsuario, '');
    expect(savedCalled, isFalse);
    expect(find.text('Identificación de Usuario'), findsNothing);
  });

  testWidgets(
    'cancelar cierra el diálogo sin modificar el provider ni invocar onSaved',
    (tester) async {
      procedimientosProvider.setCdUsuario('ORIGINAL');
      var savedCalled = false;
      await tester.pumpWidget(
        buildHost(initialValue: 'MODIFIED', onSaved: () => savedCalled = true),
      );
      await tester.tap(find.text('Abrir Diálogo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(procedimientosProvider.cdUsuario, 'ORIGINAL');
      expect(savedCalled, isFalse);
      expect(find.text('Identificación de Usuario'), findsNothing);
    },
  );

  testWidgets('el botón de cerrar en el encabezado descarta el diálogo', (
    tester,
  ) async {
    procedimientosProvider.setCdUsuario('ORIGINAL');
    var savedCalled = false;
    await tester.pumpWidget(
      buildHost(initialValue: 'MODIFIED', onSaved: () => savedCalled = true),
    );
    await tester.tap(find.text('Abrir Diálogo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(procedimientosProvider.cdUsuario, 'ORIGINAL');
    expect(savedCalled, isFalse);
    expect(find.text('Identificación de Usuario'), findsNothing);
  });

  testWidgets('renderiza correctamente en ventana compacta sin overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildHost(initialValue: 'COMPACTO'));
    await tester.tap(find.text('Abrir Diálogo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Identificación de Usuario'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renderiza en tema claro y oscuro según la configuración del tema',
    (tester) async {
      for (final themeId in ['oracle-dark', 'github-light', 'synthwave-84']) {
        await tester.pumpWidget(
          buildHost(
            initialValue: 'THEMETEST',
            theme: ProcDynamicApp.buildThemeFor(themeId),
          ),
        );
        await tester.tap(find.text('Abrir Diálogo'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Identificación de Usuario'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Cerrar para la siguiente iteración
        await tester.tap(find.text('Cancelar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
    },
  );
}
