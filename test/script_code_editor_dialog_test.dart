import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/deploy_ticket.dart';
import 'package:proc_dynamic_sirweb/widgets/deploy_ticket/script_code_editor_dialog.dart';

void main() {
  testWidgets(
    'ScriptCodeEditorDialog muestra diseño estándar Constellation y lista multi-script',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialScripts = [
        const DeployTicketScript(
          nombre: 'script_1.sql',
          contenido: 'SELECT 1 FROM DUAL;',
        ),
        const DeployTicketScript(
          nombre: 'script_2.sql',
          contenido: 'SELECT 2 FROM DUAL;',
        ),
      ];

      List<DeployTicketScript>? savedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCodeEditorDialog(
              title: 'Editor de Scripts SQL',
              scripts: initialScripts,
              language: 'plsql',
              themeColor: Colors.teal.shade600,
              icon: Icons.code_rounded,
              onSaveScripts: (scripts) {
                savedResult = scripts;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verificar cabecera y conteo
      expect(find.text('Editor de Scripts SQL'), findsOneWidget);
      expect(find.text('2 PLSQL'), findsOneWidget);

      // Verificar lista lateral de scripts
      expect(find.text('script_1.sql'), findsWidgets);
      expect(find.text('script_2.sql'), findsOneWidget);

      // Botón "Nuevo Script" existe
      expect(find.text('Nuevo Script'), findsOneWidget);

      // Botones del pie de página estándar
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Aplicar a Ticket'), findsOneWidget);

      // Al pulsar "Aplicar a Ticket", debe disparar onSaveScripts con los scripts actuales
      await tester.tap(find.text('Aplicar a Ticket'));
      await tester.pump();

      expect(savedResult, isNotNull);
      expect(savedResult!.length, 2);
      expect(savedResult![0].nombre, 'script_1.sql');
      expect(savedResult![1].nombre, 'script_2.sql');
    },
  );

  testWidgets(
    'ScriptCodeEditorDialog permite agregar y eliminar scripts en el panel lateral',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialScripts = [
        const DeployTicketScript(
          nombre: 'script_inicial.sql',
          contenido: 'SELECT 1 FROM DUAL;',
        ),
      ];

      List<DeployTicketScript>? savedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCodeEditorDialog(
              title: 'Editor de Scripts SQL',
              scripts: initialScripts,
              language: 'plsql',
              themeColor: Colors.teal.shade600,
              icon: Icons.code_rounded,
              onSaveScripts: (scripts) {
                savedResult = scripts;
              },
            ),
          ),
        ),
      );

      await tester.pump();

      // Agregar nuevo script
      await tester.tap(find.text('Nuevo Script'));
      await tester.pump();

      expect(find.text('2 PLSQL'), findsOneWidget);

      // Ahora eliminar el primer script usando el botón de eliminar de la lista
      final deleteButtons = find.byTooltip('Eliminar script');
      expect(deleteButtons, findsNWidgets(2));
      await tester.tap(deleteButtons.first);
      await tester.pump();

      expect(find.text('1 PLSQL'), findsOneWidget);

      // Guardar y verificar que quedó 1 solo script
      await tester.tap(find.text('Aplicar a Ticket'));
      await tester.pump();

      expect(savedResult, isNotNull);
      expect(savedResult!.length, 1);
    },
  );

  testWidgets(
    'ScriptCodeEditorDialog muestra prefijo [BLK] y usa nomenclatura BLK1 sin guión bajo para bloques lógicos',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialScripts = [
        const DeployTicketScript(
          nombre: 'BLK1.sql',
          contenido: 'BEGIN NULL; END; /',
        ),
      ];

      List<DeployTicketScript>? savedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptCodeEditorDialog(
              title: 'Editor de Bloques Lógicos (BLK)',
              scripts: initialScripts,
              language: 'plsql',
              themeColor: Colors.cyan.shade700,
              icon: Icons.widgets_outlined,
              onSaveScripts: (scripts) {
                savedResult = scripts;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verificar que se renderiza el prefijo [BLK]
      expect(find.text('[BLK]'), findsWidgets);
      expect(find.text('BLK'), findsWidgets);
      expect(find.text('BLK1.sql'), findsWidgets);

      // Agregar nuevo script para comprobar nomenclatura sin guión bajo (BLK2.sql)
      await tester.tap(find.text('Nuevo Script'));
      await tester.pump();

      expect(find.text('2 PLSQL'), findsOneWidget);
      expect(find.text('BLK2.sql'), findsWidgets);

      // Guardar y verificar
      await tester.tap(find.text('Aplicar a Ticket'));
      await tester.pump();

      expect(savedResult, isNotNull);
      expect(savedResult!.length, 2);
      expect(savedResult![0].nombre, 'BLK1.sql');
      expect(savedResult![1].nombre, 'BLK2.sql');
    },
  );
}
