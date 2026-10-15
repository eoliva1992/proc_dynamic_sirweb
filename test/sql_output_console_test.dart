import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/sql_execution.dart';
import 'package:proc_dynamic_sirweb/widgets/sql_executor/sql_output_console.dart';

void main() {
  testWidgets('SqlOutputConsole muestra botón de limpiar e invoca onClear', (
    tester,
  ) async {
    var clearInvoked = false;
    final entries = [
      SqlExecutionLogEntry(
        id: 1,
        timestamp: DateTime.now(),
        ambiente: 'Desa',
        kind: SqlStatementKind.select,
        statementPreview: 'SELECT 1 FROM dual',
        status: SqlLogStatus.success,
        message: 'OK',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SqlOutputConsole(
            entries: entries,
            onClear: () {
              clearInvoked = true;
            },
          ),
        ),
      ),
    );

    expect(find.byTooltip('Limpiar mensajes'), findsOneWidget);
    await tester.tap(find.byTooltip('Limpiar mensajes'));
    await tester.pumpAndSettle();

    // Diálogo de confirmación
    expect(
      find.text('Limpiar mensajes'),
      findsOneWidget,
    ); // título del AlertDialog
    expect(
      find.text('¿Deseas vaciar todos los mensajes de ejecución?'),
      findsOneWidget,
    );

    // Si cancela, no debe invocar onClear
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(clearInvoked, isFalse);

    // Abrir de nuevo y confirmar
    await tester.tap(find.byTooltip('Limpiar mensajes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpiar'));
    await tester.pumpAndSettle();

    expect(clearInvoked, isTrue);
  });

  testWidgets(
    'SqlOutputConsole con onReplay muestra tooltip "Limpiar historial"',
    (tester) async {
      var clearInvoked = false;
      final entries = [
        SqlExecutionLogEntry(
          id: 1,
          timestamp: DateTime.now(),
          ambiente: 'Desa',
          kind: SqlStatementKind.select,
          statementPreview: 'SELECT 1 FROM dual',
          status: SqlLogStatus.success,
          message: 'OK',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SqlOutputConsole(
              entries: entries,
              onReplay: (_) {},
              onClear: () {
                clearInvoked = true;
              },
            ),
          ),
        ),
      );

      expect(find.byTooltip('Limpiar historial'), findsOneWidget);
      await tester.tap(find.byTooltip('Limpiar historial'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '¿Deseas vaciar todo el historial de ejecuciones registrado?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();

      expect(clearInvoked, isTrue);
    },
  );

  testWidgets(
    'SqlOutputConsole botón copiar copia solo el cuerpo sin título ni timestamps',
    (tester) async {
      final entries = [
        SqlExecutionLogEntry(
          id: 1,
          timestamp: DateTime.now(),
          ambiente: 'Desa',
          kind: SqlStatementKind.select,
          statementPreview: 'SELECT 1 FROM dual',
          status: SqlLogStatus.success,
          message: '1 fila obtenida en 12ms',
        ),
      ];

      // Modo mensajes (sin onReplay)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SqlOutputConsole(entries: entries)),
        ),
      );

      expect(find.byTooltip('Copiar todos los mensajes'), findsOneWidget);
      await tester.tap(find.byTooltip('Copiar todos los mensajes'));
      await tester.pump();

      // Botón individual de tarjeta en mensajes
      expect(find.byTooltip('Copiar mensaje'), findsOneWidget);
      await tester.tap(find.byTooltip('Copiar mensaje'));
      await tester.pump();

      // Modo historial (con onReplay)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SqlOutputConsole(entries: entries, onReplay: (_) {}),
          ),
        ),
      );

      expect(find.byTooltip('Copiar todo el historial'), findsOneWidget);
      await tester.tap(find.byTooltip('Copiar todo el historial'));
      await tester.pump();

      // Botón individual de tarjeta en historial
      expect(find.byTooltip('Copiar SQL'), findsOneWidget);
      await tester.tap(find.byTooltip('Copiar SQL'));
      await tester.pump();
    },
  );
}
