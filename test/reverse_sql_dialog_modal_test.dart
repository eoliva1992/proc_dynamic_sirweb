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
      await tester.tap(find.text('SQL & Subconsultas'));
      await tester.pump();

      // Agregar EXISTS
      await tester.ensureVisible(find.text('Agregar EXISTS'));
      await tester.tap(find.text('Agregar EXISTS'));
      await tester.pump();

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
      'Aplicar a Ticket soporta onSave asíncrono y cierra el modal al finalizar',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        bool closed = false;
        String? savedYaml;
        String? savedScriptName;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReverseSqlConfigDialog(
                title: 'Detalle YAML RSQL: configReverse.yaml',
                scriptName: 'configReverse.yaml',
                initialYaml: '''
dbconfig:
  tables:
    - dml: MERGE
      name: PRODUCTO
      filters:
        CD_PRODUCTO: "= 10"
''',
                onClose: () => closed = true,
                onSave: (yaml, filePath, scriptName) async {
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                  savedYaml = yaml;
                  savedScriptName = scriptName;
                },
              ),
            ),
          ),
        );

        await tester.pump();

        // Expandir y cambiar el filtro
        await tester.tap(find.text('Expandir todo'));
        await tester.pump();

        final filterValField = find.widgetWithText(TextField, '= 10');
        await tester.enterText(filterValField, '= 99');
        await tester.pump();

        // Pulsar "Aplicar a Ticket"
        await tester.tap(find.text('Aplicar a Ticket'));
        await tester.pump();

        // Mientras el Future está en progreso no se ha cerrado aún
        expect(closed, isFalse);

        // Avanzar el timer del Future asíncrono
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pump();

        expect(savedScriptName, 'configReverse.yaml');
        expect(savedYaml, contains('= 99'));
        expect(closed, isTrue);
      },
    );

    testWidgets(
      'ReverseSqlVisualForm permite configurar split_file y set_columns visualmente',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        String? savedYaml;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReverseSqlConfigDialog(
                title: 'Detalle YAML RSQL: configReverse.yaml',
                scriptName: 'configReverse.yaml',
                initialYaml: '''
dbconfig:
  tables:
    - dml: MERGE
      name: PRODUCTO
      filters:
        CD_PRODUCTO: "= 10"
''',
                onClose: () {},
                onSave: (yaml, filePath, scriptName) async {
                  savedYaml = yaml;
                },
              ),
            ),
          ),
        );

        await tester.pump();

        // Expandir tabla
        await tester.tap(find.text('Expandir todo'));
        await tester.pump();

        // 1. Activar checkbox split_file
        final splitCheckbox = find.byType(Checkbox).last;
        await tester.ensureVisible(splitCheckbox);
        await tester.pump();
        await tester.tap(splitCheckbox);
        await tester.pump();

        // 2. Agregar un set_columns
        final addColumnBtn = find.widgetWithText(TextButton, 'Agregar columna');
        expect(addColumnBtn, findsOneWidget);
        await tester.ensureVisible(addColumnBtn);
        await tester.pump();
        await tester.tap(addColumnBtn);
        await tester.pump();

        // Ingresar columna y nuevo valor fijo en la última fila creada
        final colKeyFields = find.widgetWithText(TextField, 'Columna');
        expect(colKeyFields, findsWidgets);
        await tester.ensureVisible(colKeyFields.last);
        await tester.pump();
        await tester.enterText(colKeyFields.last, 'ST_REGISTRO');
        await tester.pump();

        final colValField = find.widgetWithText(
          TextField,
          'Nuevo valor fijo a asignar',
        );
        expect(colValField, findsOneWidget);
        await tester.ensureVisible(colValField);
        await tester.pump();
        await tester.enterText(colValField, "'ACTIVO'");
        await tester.pump();

        // 3. Aplicar al ticket y verificar el YAML resultante
        final applyBtn = find.text('Aplicar a Ticket');
        await tester.ensureVisible(applyBtn);
        await tester.pump();
        await tester.tap(applyBtn);
        await tester.pump();

        expect(savedYaml, isNotNull);
        expect(savedYaml, contains('split_file: true'));
        expect(savedYaml, contains('set_columns:'));
        expect(savedYaml, contains('ST_REGISTRO: "\'ACTIVO\'"'));
      },
    );

    testWidgets(
      'ReverseSqlVisualForm muestra badge de orden y permite reordenar tablas con botones subir/bajar',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        String? savedYaml;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReverseSqlConfigDialog(
                title: 'Detalle YAML RSQL: configReverse.yaml',
                scriptName: 'configReverse.yaml',
                initialYaml: '''
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
''',
                onClose: () {},
                onSave: (yaml, filePath, scriptName) async {
                  savedYaml = yaml;
                },
              ),
            ),
          ),
        );

        await tester.pump();

        // Verificar badges de posición
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('#2'), findsOneWidget);

        // Verificar badges distintivos de Agrupada / Lote
        expect(find.text('Agrupada / Lote'), findsNWidgets(2));

        // En la primera tabla (#1 PRODUCTO), mover hacia abajo
        final moveDownButtons = find.byIcon(Icons.arrow_downward_rounded);
        expect(moveDownButtons, findsWidgets);

        // El primer botón de bajar corresponde a PRODUCTO
        await tester.tap(moveDownButtons.first);
        await tester.pump();

        // Ahora COTIZACION debe estar de primero y PRODUCTO de segundo
        // Aplicamos a ticket para verificar el orden en el YAML generado
        final applyBtn = find.text('Aplicar a Ticket');
        await tester.tap(applyBtn);
        await tester.pump();

        expect(savedYaml, isNotNull);
        final cotizacionPos = savedYaml!.indexOf('name: COTIZACION');
        final productoPos = savedYaml!.indexOf('name: PRODUCTO');
        expect(cotizacionPos, isNot(-1));
        expect(productoPos, isNot(-1));
        expect(cotizacionPos, lessThan(productoPos));
      },
    );

    testWidgets(
      'desmarcar split_file reubica la tabla automáticamente agrupándola con las tablas no-split',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        ReverseSqlConfig currentConfig = const ReverseSqlConfig(
          tables: [
            ReverseSqlTableConfig(
              dml: ReverseSqlDml.merge,
              name: 'TABLA_NO_SPLIT',
              splitFile: false,
            ),
            ReverseSqlTableConfig(
              dml: ReverseSqlDml.merge,
              name: 'TABLA_SPLIT_1',
              splitFile: true,
            ),
            ReverseSqlTableConfig(
              dml: ReverseSqlDml.merge,
              name: 'TABLA_SPLIT_2',
              splitFile: true,
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

        // En la cabecera cerrada se muestran los nombres y los badges
        expect(find.text('TABLA_NO_SPLIT'), findsOneWidget);
        expect(find.text('TABLA_SPLIT_1'), findsOneWidget);
        expect(find.text('TABLA_SPLIT_2'), findsOneWidget);
        expect(find.text('Agrupada / Lote'), findsOneWidget);
        expect(find.text('Individual (split_file)'), findsNWidgets(2));

        // En lugar de expandir todo y que la última tarjeta quede fuera de pantalla por el alto de 3 tarjetas expandidas,
        // expandimos solamente la tarjeta TABLA_SPLIT_2 tocando en su nombre
        await tester.tap(find.text('TABLA_SPLIT_2'));
        await tester.pump();

        // Buscamos la etiqueta de 'split_file (Archivo individual)'
        final splitLabel = find.text('split_file (Archivo individual)');
        expect(splitLabel, findsOneWidget);

        // Al tocar sobre el botón de split_file, se desmarca split_file.
        // Por la auto-reubicación:
        // Debe reagruparse junto al bloque no-split existente (después de TABLA_NO_SPLIT, en posición 1)
        // desplazando a TABLA_SPLIT_1 a la posición 2.
        await tester.tap(splitLabel);
        await tester.pump();

        // Verificar el nuevo orden de tablas en currentConfig
        expect(currentConfig.tables.length, 3);
        expect(currentConfig.tables[0].name, 'TABLA_NO_SPLIT');
        expect(currentConfig.tables[0].splitFile, isNot(true));

        expect(currentConfig.tables[1].name, 'TABLA_SPLIT_2');
        expect(currentConfig.tables[1].splitFile, isNot(true));

        expect(currentConfig.tables[2].name, 'TABLA_SPLIT_1');
        expect(currentConfig.tables[2].splitFile, isTrue);

        // Visualmente ahora hay 2 tablas con badge Agrupada / Lote y 1 con Individual (split_file)
        expect(find.text('Agrupada / Lote'), findsNWidgets(2));
        expect(find.text('Individual (split_file)'), findsOneWidget);
      },
    );
  });
}
