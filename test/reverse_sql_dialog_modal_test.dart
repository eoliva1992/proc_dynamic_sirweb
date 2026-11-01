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

      // Al iniciar colapsado, expandimos la tarjeta para interactuar con los filtros
      await tester.tap(find.text('Expandir todo'));
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

        // Al iniciar colapsado, expandimos la tarjeta para interactuar con los filtros
        await tester.tap(find.text('Expandir todo'));
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

    testWidgets('gestiona cláusulas IN (ins) de forma visual interactiva', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      ReverseSqlConfig currentConfig = const ReverseSqlConfig(
        tables: [
          ReverseSqlTableConfig(
            dml: ReverseSqlDml.merge,
            name: 'mi_tabla',
            ins: {'cd_ramo': '1, 2, 3'},
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

      // Al iniciar colapsado, expandimos la tarjeta para interactuar con sus secciones
      await tester.tap(find.text('Expandir todo'));
      await tester.pump();

      // Debe mostrar la columna cd_ramo y los valores
      expect(find.text('cd_ramo'), findsOneWidget);
      expect(find.text('1, 2, 3'), findsOneWidget);
      expect(find.text('Valores IN (ins):'), findsOneWidget);

      // Agregar otra cláusula IN
      await tester.ensureVisible(find.text('Agregar IN'));
      await tester.tap(find.text('Agregar IN'));
      await tester.pump();

      expect(find.text('campo_2'), findsOneWidget);
      expect(currentConfig.tables.first.ins.containsKey('campo_2'), isTrue);

      // Modificar valores
      final valField = find.widgetWithText(TextField, '1, 2, 3, 4');
      await tester.ensureVisible(valField);
      await tester.enterText(valField, '10, 20');
      await tester.pump();
      expect(currentConfig.tables.first.ins['campo_2'], '10, 20');

      // Eliminar el primer IN (cd_ramo)
      final deleteBtns = find.byTooltip('Eliminar IN');
      expect(deleteBtns, findsNWidgets(2));
      await tester.ensureVisible(deleteBtns.first);
      await tester.tap(deleteBtns.first);
      await tester.pump();

      expect(currentConfig.tables.first.ins.containsKey('cd_ramo'), isFalse);
      expect(currentConfig.tables.first.ins.containsKey('campo_2'), isTrue);
    });

    testWidgets('gestiona cláusulas NOT IN (not_ins) y subconsultas EXISTS', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      ReverseSqlConfig currentConfig = const ReverseSqlConfig(
        tables: [
          ReverseSqlTableConfig(dml: ReverseSqlDml.merge, name: 'mi_tabla'),
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

      // Al iniciar colapsado, expandimos la tarjeta para interactuar con sus secciones
      await tester.tap(find.text('Expandir todo'));
      await tester.pump();

      // Agregar NOT IN (en la pestaña de Filtros & Valores)
      await tester.ensureVisible(find.text('Agregar NOT IN'));
      await tester.tap(find.text('Agregar NOT IN'));
      await tester.pump();

      expect(find.text('Valores NOT IN (not_ins):'), findsOneWidget);
      expect(currentConfig.tables.first.notIns.isNotEmpty, isTrue);

      // Cambiar a la pestaña "SQL & Subconsultas" para gestionar EXISTS
      final tabSql = find.text('SQL & Subconsultas');
      await tester.ensureVisible(tabSql);
      await tester.tap(tabSql);
      await tester.pumpAndSettle();

      // Agregar EXISTS
      await tester.ensureVisible(find.text('Agregar EXISTS'));
      await tester.tap(find.text('Agregar EXISTS'));
      await tester.pumpAndSettle();

      expect(find.text('Subconsultas EXISTS:'), findsOneWidget);
      expect(currentConfig.tables.first.exists.isNotEmpty, isTrue);
    });
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
      // El indicador de progreso no debe mostrarse de manera incondicional o permanente
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Probar botón cerrar
      final closeBtn = find.byTooltip('Cerrar (Esc)');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pump();

      expect(closed, isTrue);
    });

    testWidgets(
      'inicia con todas las tablas colapsadas, permite buscar tablas y expandir/colapsar todo',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const initialConfigYaml = '''
dbconfig:
  tables:
    - dml: MERGE
      name: PRODUCTO
      filters:
        CD_PRODUCTO: "= 10"
    - dml: INSERT
      name: COTIZACION
      filters:
        ID_COTIZACION: "= 20"
''';

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ReverseSqlConfigDialog(initialYaml: initialConfigYaml),
            ),
          ),
        );

        await tester.pump();

        // 1. Verificar que ambas tablas están listadas
        expect(find.text('PRODUCTO'), findsOneWidget);
        expect(find.text('COTIZACION'), findsOneWidget);
        expect(find.text('Tablas configuradas (2)'), findsOneWidget);

        // 2. Verificar que inician colapsadas (no deben mostrarse los campos internos de edición)
        expect(find.text('Nombre de Tabla (name) *'), findsNothing);
        expect(find.text('Operación DML'), findsNothing);

        // 3. Probar botón "Expandir todo"
        final expandAllBtn = find.widgetWithText(
          OutlinedButton,
          'Expandir todo',
        );
        expect(expandAllBtn, findsOneWidget);
        await tester.tap(expandAllBtn);
        await tester.pump();

        // Al expandir ambas tablas en un ListView, al menos una está visible en el viewport
        expect(find.text('Nombre de Tabla (name) *'), findsWidgets);
        expect(find.text('Operación DML'), findsWidgets);

        // 4. Probar botón "Colapsar todo"
        final collapseAllBtn = find.widgetWithText(
          OutlinedButton,
          'Colapsar todo',
        );
        expect(collapseAllBtn, findsOneWidget);
        await tester.tap(collapseAllBtn);
        await tester.pump();

        expect(find.text('Nombre de Tabla (name) *'), findsNothing);

        // 5. Probar buscador de tablas
        final searchField = find.widgetWithText(
          TextField,
          'Buscar por tabla o DML...',
        );
        expect(searchField, findsOneWidget);

        // Filtrar por 'COTI'
        await tester.enterText(searchField, 'COTI');
        await tester.pump();

        expect(find.text('Mostrando 1 de 2 tablas'), findsOneWidget);
        expect(find.text('COTIZACION'), findsOneWidget);
        expect(find.text('PRODUCTO'), findsNothing);

        // Filtrar por término inexistente
        await tester.enterText(searchField, 'INEXISTENTE_XYZ');
        await tester.pump();

        expect(
          find.text('No se encontraron tablas para "INEXISTENTE_XYZ"'),
          findsOneWidget,
        );
        expect(find.text('Limpiar búsqueda'), findsOneWidget);

        // Limpiar búsqueda
        await tester.tap(find.text('Limpiar búsqueda'));
        await tester.pump();

        expect(find.text('PRODUCTO'), findsOneWidget);
        expect(find.text('COTIZACION'), findsOneWidget);
      },
    );

    testWidgets(
      'permite reordenar tablas mediante los botones de flecha arriba y abajo',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const initialConfigYaml = '''
dbconfig:
  tables:
    - dml: MERGE
      name: TABLA_UNO
      filters:
        ID: "= 1"
    - dml: INSERT
      name: TABLA_DOS
      filters:
        ID: "= 2"
    - dml: UPDATE
      name: TABLA_TRES
      filters:
        ID: "= 3"
''';

        ReverseSqlConfig? savedConfig;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReverseSqlConfigDialog(
                initialYaml: initialConfigYaml,
                onSave: (yaml, path, name) {
                  savedConfig = ReverseSqlConfig.parseYaml(yaml);
                },
              ),
            ),
          ),
        );

        await tester.pump();

        // Verificar badges de orden inicial
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('#2'), findsOneWidget);
        expect(find.text('#3'), findsOneWidget);

        // Mover TABLA_UNO hacia abajo con su botón de flecha abajo
        final moveDownButtons = find.byTooltip('Mover hacia abajo (ejecutar después)');
        expect(moveDownButtons, findsWidgets);

        // El primer botón habilitado corresponde a TABLA_UNO (#1)
        await tester.tap(moveDownButtons.first);
        await tester.pump();

        // Ahora TABLA_DOS debe estar en la posición #1 y TABLA_UNO en la posición #2
        // Guardamos para comprobar el orden en el YAML generado
        await tester.tap(find.text('Aplicar a Ticket'));
        await tester.pump();

        expect(savedConfig, isNotNull);
        expect(savedConfig!.tables.map((t) => t.name).toList(), [
          'TABLA_DOS',
          'TABLA_UNO',
          'TABLA_TRES',
        ]);
      },
    );
  });
}
