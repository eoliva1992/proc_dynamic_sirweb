import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/app_navigator.dart';
import 'package:proc_dynamic_sirweb/services/app_log.dart';
import 'package:proc_dynamic_sirweb/widgets/app_console.dart';

void main() {
  setUp(AppLog.instance.clear);

  group('AppLog', () {
    test('registra entradas con la más nueva primero', () {
      AppLog.instance.info('primera');
      AppLog.instance.error('segunda');

      final e = AppLog.instance.entries;
      expect(e, hasLength(2));
      expect(e.first.message, 'segunda');
      expect(e.first.level, LogLevel.error);
      expect(e.last.message, 'primera');
    });

    test('compilation() sin errores registra un éxito', () {
      AppLog.instance.compilation(
        objectName: 'OBJ_RECIBOS',
        objectType: 'TYPE',
        ambiente: 'QA',
        errors: const [],
      );
      final e = AppLog.instance.entries.single;
      expect(e.level, LogLevel.success);
      expect(e.message, contains('OBJ_RECIBOS'));
      expect(e.message, contains('QA'));
    });

    test('compilation() con errores guarda línea y columna en el detalle', () {
      AppLog.instance.compilation(
        objectName: 'PCK_X',
        objectType: 'PACKAGE',
        ambiente: 'Desa',
        part: 'BODY',
        errors: const [
          (
            line: 12,
            position: 5,
            text: 'PLS-00103: se encontró el símbolo',
            attribute: 'ERROR',
          ),
        ],
      );
      final e = AppLog.instance.entries.single;
      expect(e.level, LogLevel.error);
      expect(e.message, contains('PCK_X'));
      // El encabezado describe el error concreto, no sólo la cantidad.
      expect(e.message, contains('línea 12'));
      expect(e.message, contains('PLS-00103'));
      expect(e.detail, contains('col 5'));
      expect(AppLog.instance.unseenErrors, 1);
    });

    test('compilation() indica cuántos errores más hay', () {
      AppLog.instance.compilation(
        objectName: 'P1',
        objectType: 'PROCEDURE',
        ambiente: 'QA',
        errors: const [
          (
            line: 1,
            position: 1,
            text: 'PLS-00103: primero',
            attribute: 'ERROR',
          ),
          (
            line: 9,
            position: 2,
            text: 'PLS-00201: segundo',
            attribute: 'ERROR',
          ),
        ],
      );
      final e = AppLog.instance.entries.single;
      expect(e.message, contains('PLS-00103'));
      expect(e.message, contains('+1 más'));
      expect(e.detail, contains('PLS-00201'));
    });

    test('exception() describe tipo, mensaje, datos y códigos Oracle', () {
      AppLog.instance.exception(
        'Transferir OBJ_RECIBOS a QA',
        Exception('ORA-04042: el objeto no existe'),
        stack: StackTrace.current,
        source: 'Transferencia',
        datos: {'Objeto': 'OBJ_RECIBOS (Tipo)', 'Destino': 'QA'},
      );
      final e = AppLog.instance.entries.single;
      expect(e.level, LogLevel.error);
      expect(e.message, contains('Transferir OBJ_RECIBOS a QA'));
      expect(e.message, contains('ORA-04042'));
      expect(e.detail, contains('Tipo      : _Exception'));
      expect(e.detail, contains('el objeto no existe'));
      expect(e.detail, contains('Destino'));
      expect(e.detail, contains('Códigos   : ORA-04042'));
      expect(e.detail, contains('Stack'));
    });

    test('describe() y oracleCodes() extraen la causa', () {
      expect(
        AppLog.describe(Exception('ORA-00904: identificador no válido')),
        'ORA-00904: identificador no válido',
      );
      expect(AppLog.oracleCodes('ORA-06550 y PLS-00103 y otra vez ORA-06550'), [
        'ORA-06550',
        'PLS-00103',
      ]);
    });

    test('server() guarda endpoint, HTTP, argumentos y respuesta cruda', () {
      AppLog.instance.server(
        'compile_object_ddl',
        message: 'Error de sintaxis DDL: ORA-04042: el objeto no existe',
        statusCode: 200,
        argumentos: {
          'objectName': 'OBJ_RECIBOS',
          'ambiente': 'QA',
          'source': 'GRANT EXECUTE ON X TO PUBLIC',
        },
        respuesta: '{"success":false,"error":"ORA-04042"}',
      );
      final e = AppLog.instance.entries.single;
      expect(e.level, LogLevel.error);
      expect(e.source, 'Servidor');
      expect(e.message, startsWith('compile_object_ddl —'));
      expect(e.detail, contains('Endpoint  : compile_object_ddl'));
      expect(e.detail, contains('HTTP      : 200'));
      expect(e.detail, contains('Códigos   : ORA-04042'));
      expect(e.detail, contains('"objectName": "OBJ_RECIBOS"'));
      expect(e.detail, contains('GRANT EXECUTE ON X TO PUBLIC'));
      expect(e.detail, contains('"success":false'));
    });

    test('server() recorta los argumentos y la respuesta largos', () {
      AppLog.instance.server(
        'compile_object_ddl',
        message: 'falló',
        argumentos: {'source': 'X' * 2000},
        respuesta: 'Y' * 4000,
      );
      final d = AppLog.instance.entries.single.detail!;
      expect(d, contains('+1400 chars'));
      expect(d, contains('+2500 chars'));
      expect(d.length, lessThan(4000));
    });

    test('ddl() registra el fallo con el mensaje ORA', () {
      AppLog.instance.ddl(
        'GRANT EXECUTE ON INTEGRACION.OBJ_RECIBOS TO PUBLIC',
        ambiente: 'QA',
        errorMessage: 'ORA-04042: el objeto no existe',
      );
      final e = AppLog.instance.entries.single;
      expect(e.level, LogLevel.error);
      expect(e.message, contains('GRANT EXECUTE'));
      expect(e.detail, contains('ORA-04042'));
    });

    test('respeta el máximo de entradas', () {
      for (var i = 0; i < AppLog.maxEntries + 20; i++) {
        AppLog.instance.info('m$i');
      }
      expect(AppLog.instance.length, AppLog.maxEntries);
      expect(
        AppLog.instance.entries.first.message,
        'm${AppLog.maxEntries + 19}',
      );
    });

    test('asText() exporta de la más vieja a la más nueva', () {
      AppLog.instance.info('uno');
      AppLog.instance.info('dos');
      final texto = AppLog.instance.asText();
      expect(texto.indexOf('uno') < texto.indexOf('dos'), isTrue);
    });

    test('transaction() registra la operación con datos y duración', () {
      AppLog.instance.transaction(
        'Guardar DR_TEST',
        source: 'Procedimientos',
        duracion: const Duration(milliseconds: 1450),
        datos: {'Ambiente': 'Desa', 'Usuario': 'eoliva', 'Vacio': ''},
      );
      final e = AppLog.instance.entries.single;
      expect(e.level, LogLevel.info);
      expect(e.source, 'Procedimientos');
      expect(e.message, 'Guardar DR_TEST · 1.4 s');
      expect(e.detail, contains('Ambiente  : Desa'));
      expect(e.detail, contains('Usuario   : eoliva'));
      // Los datos vacíos no ensucian el detalle.
      expect(e.detail, isNot(contains('Vacio')));
    });

    test('transaction() admite otros niveles (p. ej. warning de conexión)', () {
      AppLog.instance.transaction(
        'Conexión: online → offline',
        source: 'Conexion',
        level: LogLevel.warning,
      );
      final e = AppLog.instance.entries.single;
      expect(e.level, LogLevel.warning);
      expect(e.message, 'Conexión: online → offline');
    });

    test('countOf() cuenta por nivel para los filtros de la consola', () {
      AppLog.instance
        ..info('t1')
        ..info('t2')
        ..warning('w')
        ..error('e');
      expect(AppLog.instance.countOf(LogLevel.info), 2);
      expect(AppLog.instance.countOf(LogLevel.warning), 1);
      expect(AppLog.instance.countOf(LogLevel.error), 1);
      expect(AppLog.instance.countOf(LogLevel.success), 0);
    });
  });

  testWidgets('la consola muestra los errores de compilación registrados', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );

    AppLog.instance.compilation(
      objectName: 'OBJ_RECIBOS',
      objectType: 'TYPE',
      ambiente: 'QA',
      errors: const [
        (
          line: 3,
          position: 1,
          text: 'ORA-00904: identificador no válido',
          attribute: 'ERROR',
        ),
      ],
    );

    showAppConsole(rootNavigatorKey.currentContext!);
    await tester.pumpAndSettle();

    expect(find.text('CONSOLA'), findsOneWidget);
    expect(find.textContaining('OBJ_RECIBOS'), findsWidgets);
    expect(find.textContaining('ORA-00904'), findsWidgets);

    closeAppConsole();
    await tester.pumpAndSettle();
    expect(find.text('CONSOLA'), findsNothing);
  });

  testWidgets('la entrada nueva queda primera y la vista vuelve al tope', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    for (var i = 0; i < 40; i++) {
      AppLog.instance.info('vieja $i');
    }

    showAppConsole(rootNavigatorKey.currentContext!);
    await tester.pumpAndSettle();

    // Se baja en la lista y llega una entrada nueva: no se mueve la vista,
    // se avisa con el contador.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    AppLog.instance.error('ERROR RECIENTE');
    await tester.pumpAndSettle();
    expect(find.textContaining('entrada(s) nueva(s)'), findsOneWidget);

    // Al tocar el aviso se vuelve al tope, donde está la más reciente.
    await tester.tap(find.textContaining('entrada(s) nueva(s)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('entrada(s) nueva(s)'), findsNothing);
    final scroll = tester.widget<ListView>(find.byType(ListView));
    expect(scroll.controller!.offset, 0);
    expect(AppLog.instance.entries.first.message, 'ERROR RECIENTE');

    // Estando en el tope, la siguiente entrada aparece sin scrollear.
    AppLog.instance.warning('OTRA MÁS');
    await tester.pumpAndSettle();
    expect(find.textContaining('entrada(s) nueva(s)'), findsNothing);
    expect(find.text('OTRA MÁS'), findsOneWidget);
    expect(scroll.controller!.offset, 0);

    closeAppConsole();
    await tester.pumpAndSettle();
  });

  testWidgets('los chips filtran por nivel: Problemas, Warnings, Info', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    AppLog.instance
      ..error('FALLO GRAVE')
      ..warning('AVISO MENOR')
      ..info('TRANSACCION OK');

    showAppConsole(rootNavigatorKey.currentContext!);
    await tester.pumpAndSettle();

    // Los chips viven en una fila con scroll horizontal: hay que asegurarse de
    // que estén visibles antes de tocarlos.
    Future<void> tapChip(String label) async {
      final chip = find.ancestor(
        of: find.text(label),
        matching: find.byType(FilterChip),
      );
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    // Sin filtros se ve todo y cada chip muestra su contador.
    expect(find.text('FALLO GRAVE'), findsOneWidget);
    expect(find.text('AVISO MENOR'), findsOneWidget);
    expect(find.text('TRANSACCION OK'), findsOneWidget);
    expect(find.text('Problemas (1)'), findsOneWidget);
    expect(find.text('Warnings (1)'), findsOneWidget);
    expect(find.text('Info (1)'), findsOneWidget);
    expect(find.text('Servidor'), findsOneWidget);

    // Sólo warnings.
    await tapChip('Warnings (1)');
    expect(find.text('AVISO MENOR'), findsOneWidget);
    expect(find.text('FALLO GRAVE'), findsNothing);
    expect(find.text('TRANSACCION OK'), findsNothing);

    // Warnings + info.
    await tapChip('Info (1)');
    expect(find.text('AVISO MENOR'), findsOneWidget);
    expect(find.text('TRANSACCION OK'), findsOneWidget);
    expect(find.text('FALLO GRAVE'), findsNothing);

    // Al desmarcar todo se vuelve a ver el log completo.
    await tapChip('Warnings (1)');
    await tapChip('Info (1)');
    expect(find.text('FALLO GRAVE'), findsOneWidget);
    expect(find.text('AVISO MENOR'), findsOneWidget);
    expect(find.text('TRANSACCION OK'), findsOneWidget);

    closeAppConsole();
    await tester.pumpAndSettle();
  });

  testWidgets('las acciones del header quedan pegadas al borde derecho', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    AppLog.instance.info('algo');
    showAppConsole(rootNavigatorKey.currentContext!);
    await tester.pumpAndSettle();

    // El botón de cerrar debe terminar junto al borde derecho de la consola
    // (la ventana tiene 12 px de margen lateral).
    final anchoPantalla =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final cerrar = tester.getRect(find.byIcon(Icons.close_rounded));
    expect(anchoPantalla - cerrar.right, lessThan(30));

    closeAppConsole();
    await tester.pumpAndSettle();
  });

  testWidgets('el detalle arranca colapsado y se abre al tocar la fila', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    AppLog.instance.server(
      'compile_object_ddl',
      message: 'Error de sintaxis DDL',
      statusCode: 200,
      argumentos: {'objectName': 'OBJ_RECIBOS'},
      respuesta: 'DETALLE-SECRETO-DEL-SERVIDOR',
    );

    showAppConsole(rootNavigatorKey.currentContext!);
    await tester.pumpAndSettle();

    // Colapsado: se ve el resumen y el chevron, no el detalle.
    expect(find.textContaining('compile_object_ddl'), findsWidgets);
    expect(find.textContaining('DETALLE-SECRETO-DEL-SERVIDOR'), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.textContaining('línea(s)'), findsOneWidget);

    // Un clic en la fila lo despliega.
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('DETALLE-SECRETO-DEL-SERVIDOR'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

    // Y otro clic lo vuelve a cerrar.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('DETALLE-SECRETO-DEL-SERVIDOR'), findsNothing);

    // El botón de la barra expande todos los detalles de una.
    await tester.tap(find.byIcon(Icons.unfold_more_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('DETALLE-SECRETO-DEL-SERVIDOR'), findsOneWidget);

    closeAppConsole();
    await tester.pumpAndSettle();
  });
}
