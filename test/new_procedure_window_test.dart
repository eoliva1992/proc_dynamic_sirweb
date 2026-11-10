import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proc_dynamic_sirweb/services/plantilla_service.dart';
import 'package:proc_dynamic_sirweb/widgets/new_procedure_dialog.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
    PlantillaService.setHttpClientForTesting(
      MockClient((request) async {
        return http.Response(jsonEncode({'data': []}), 200);
      }),
    );
  });

  tearDownAll(() {
    PlantillaService.setHttpClientForTesting(null);
  });

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

    // En el paso 1 (Configuración), la tarjeta por defecto "Dato" está presente
    expect(find.text('Dato'), findsOneWidget);

    // Barra de búsqueda del paso 1
    final searchConfig = find.byType(TextField).first;
    expect(searchConfig, findsOneWidget);

    // Filtrar por término que no existe
    await tester.enterText(searchConfig, 'XYZ_INEXISTENTE');
    await tester.pump();
    expect(find.text('No se encontraron configuraciones'), findsOneWidget);

    // Limpiar búsqueda y verificar restauración de opciones
    await tester.tap(find.text('Restablecer búsqueda'));
    await tester.pump();
    expect(find.text('Dato'), findsOneWidget);
    expect(find.text('JavaScript'), findsOneWidget);

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
      find.text('Dato'),
      findsOneWidget,
      reason: 'minimizar no debe reiniciar el estado del wizard',
    );

    // ── Navegación del Wizard: Seleccionar JavaScript y avanzar ────────────
    expect(find.text('JavaScript'), findsOneWidget);
    await tester.tap(find.text('JavaScript'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Botón Continuar hacia Paso 2 (Plantilla)
    final btnContinuar = find.text('Siguiente: Elegir Plantilla');
    expect(btnContinuar, findsOneWidget);
    await tester.tap(btnContinuar);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Paso 2:'), findsOneWidget);

    if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
      await tester.pump(const Duration(seconds: 1));
    }

    // Si aún está cargando o ya resolvió:
    if (find.text('VISTA PREVIA DEL CÓDIGO').evaluate().isNotEmpty) {
      expect(find.text('VISTA PREVIA DEL CÓDIGO'), findsOneWidget);
      expect(find.text('Comenzar en blanco'), findsOneWidget);
      expect(find.byIcon(Icons.view_headline_rounded), findsOneWidget);

      // Alternar a vista de lista
      await tester.tap(find.byIcon(Icons.view_headline_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    }

    // Avanzar al Editor
    final btnContinuarPaso2 = find.text('Continuar al Editor');
    expect(btnContinuarPaso2, findsOneWidget);
    await tester.tap(btnContinuarPaso2);
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // En Paso 3 (Editor) se encuentra el campo del código
    final codeField = find.byType(TextFormField).first;
    await tester.enterText(codeField, 'PR_PRUEBA');
    await tester.pump();
    expect(find.text('PR_PRUEBA'), findsOneWidget);

    // Escribir en el código no debe alterar ni resetear el formulario
    await tester.enterText(codeField, 'PR_MODIFICADO');
    await tester.pump();
    expect(find.text('PR_MODIFICADO'), findsOneWidget);

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
