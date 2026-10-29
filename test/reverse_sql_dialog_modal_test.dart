import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/reverse_sql_config.dart';
import 'package:proc_dynamic_sirweb/widgets/deploy_ticket/reverse_sql_config_dialog.dart';
import 'package:proc_dynamic_sirweb/widgets/deploy_ticket/reverse_sql_visual_form.dart';

void main() {
  group('ReverseSqlVisualForm - filtros interactivos', () {
    testWidgets('borrar el texto de la columna no elimina la fila de filtro', (
      tester,
    ) async {
      ReverseSqlConfig currentConfig = const ReverseSqlConfig(
        tables: [
          ReverseSqlTableConfig(
            dml: ReverseSqlDml.merge,
            name: 'productobiendato',
            filters: {'cd_producto': '= 100'},
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ReverseSqlVisualForm(
                  config: currentConfig,
                  onChanged: (updated) {
                    setState(() => currentConfig = updated);
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();

      // Verificar que existe el campo de la columna con 'cd_producto'
      expect(find.text('cd_producto'), findsOneWidget);

      // Borrar totalmente el texto del campo 'cd_producto'
      final keyField = find.widgetWithText(TextField, 'cd_producto');
      await tester.enterText(keyField, '');
      await tester.pump();

      // La fila NO debe eliminarse automáticamente; el TextField sigue presente (ahora con el hintText)
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Condición / Filtro (WHERE)'), findsOneWidget);
      expect(find.text('= 100'), findsOneWidget);

      // Comprobar que solo se elimina cuando se pulsa el botón de eliminar filtro (icono close_rounded)
      final deleteFilterBtn = find.byTooltip('Eliminar filtro');
      expect(deleteFilterBtn, findsOneWidget);
      await tester.tap(deleteFilterBtn);
      await tester.pump();

      // Ahora sí debe haberse eliminado la fila
      expect(find.text('= 100'), findsNothing);
      expect(find.byTooltip('Eliminar filtro'), findsNothing);
    });

    testWidgets(
      'agregar un nuevo filtro crea una fila y no se elimina si se limpia el texto sugerido',
      (tester) async {
        ReverseSqlConfig currentConfig = const ReverseSqlConfig(
          tables: [
            ReverseSqlTableConfig(
              dml: ReverseSqlDml.merge,
              name: 'mi_tabla',
              filters: {},
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return ReverseSqlVisualForm(
                    config: currentConfig,
                    onChanged: (updated) {
                      setState(() => currentConfig = updated);
                    },
                  );
                },
              ),
            ),
          ),
        );

        await tester.pump();

        // Inicialmente sin filtros
        expect(
          find.text('Sin filtros (extraerá toda la tabla o según SQL)'),
          findsOneWidget,
        );

        // Click en "Agregar Filtro"
        await tester.tap(find.text('Agregar Filtro'));
        await tester.pump();

        // Se agregó la fila con campo por defecto 'campo_1'
        expect(find.text('campo_1'), findsOneWidget);

        // Limpiar el campo 'campo_1' por completo
        final keyField = find.widgetWithText(TextField, 'campo_1');
        await tester.enterText(keyField, '');
        await tester.pump();

        // La fila sigue viva
        expect(find.byTooltip('Eliminar filtro'), findsOneWidget);
      },
    );
  });

  group('ReverseSqlConfigDialog - Estándar Modal', () {
    testWidgets('se renderiza como modal centrado con cabecera Constellation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReverseSqlConfigDialog(
              title: 'Configuración RSQL Modal',
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      await tester.pump();

      // Verificar título en la cabecera
      expect(find.text('Configuración RSQL Modal'), findsOneWidget);
      expect(find.text('Visual'), findsOneWidget);
      expect(find.text('YAML'), findsOneWidget);
      expect(find.text('Aplicar a Ticket'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);

      // Probar botón cerrar
      final closeBtn = find.byTooltip('Cerrar');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pump();

      expect(closed, isTrue);
    });
  });
}
