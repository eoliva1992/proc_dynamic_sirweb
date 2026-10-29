import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/server_config_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ServerConfigDialog se renderiza con 3 pestañas profesionales', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ServerConfigDialog())),
    );

    // Renderizado del diálogo y tabs
    expect(find.byType(ServerConfigDialog), findsOneWidget);
    expect(find.text('Servidor SirWeb'), findsOneWidget);
    expect(find.text('Ambientes Oracle & Credenciales'), findsOneWidget);
    expect(find.text('Historial de Auditoría'), findsOneWidget);

    // Título en ConstellationHeader
    expect(
      find.text('Configuración del Servidor y Credenciales Oracle'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Pestaña de Historial de Auditoría muestra buscador interactivo y selector de ambiente',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ServerConfigDialog())),
      );

      // Cambiar a la pestaña 3 (Historial de Auditoría)
      await tester.tap(find.text('Historial de Auditoría'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Comprobar elementos de la barra de herramientas del historial
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Buscar por usuario, ambiente o ID...'), findsOneWidget);
      expect(find.text('Ambiente:'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsWidgets);
    },
  );

  testWidgets(
    'Pestaña de Ambientes Oracle muestra estado o formulario estilizado',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ServerConfigDialog())),
      );

      // Cambiar a la pestaña 2 (Ambientes Oracle & Credenciales)
      await tester.tap(find.text('Ambientes Oracle & Credenciales'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Comprobar que renderiza la pestaña de ambientes (formulario o estado de conexión)
      final hasSelector = find
          .text('Seleccionar Ambiente:')
          .evaluate()
          .isNotEmpty;
      final hasRetryOrLoading =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
          find.text('Reintentar conexión').evaluate().isNotEmpty;

      expect(hasSelector || hasRetryOrLoading, isTrue);
    },
  );
}
