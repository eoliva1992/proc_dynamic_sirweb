import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proc_dynamic_sirweb/models/procedimiento.dart';
import 'package:proc_dynamic_sirweb/services/session_service.dart';
import 'package:proc_dynamic_sirweb/widgets/app_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    SessionService.setMockPrefs(prefs);
  });

  group('SessionService', () {
    test('isRestoreEnabled defaults to true', () async {
      expect(await SessionService.isRestoreEnabled(), isTrue);
    });

    test(
      'can toggle isRestoreEnabled and clearing session when disabled',
      () async {
        await SessionService.setRestoreEnabled(false);
        expect(await SessionService.isRestoreEnabled(), isFalse);

        await SessionService.setRestoreEnabled(true);
        expect(await SessionService.isRestoreEnabled(), isTrue);
      },
    );

    test(
      'saveSession and loadSession restores procedure, source, and local file tabs',
      () async {
        final tab1 = AppTab(ambiente: 'Desa')
          ..procedimiento = const Procedimiento(
            cdProcedimiento: 'PR_VENTAS_RESTORE',
            deTexto: 'BEGIN NULL; END;',
            inConfiguracion: 'D',
            version: 2,
            stProcedimiento: '1',
          )
          ..currentEditorCode = 'BEGIN NULL; /* modified */ END;'
          ..isDirty = true;

        final tab2 = AppTab(ambiente: 'QA')
          ..sourceViewer = (
            name: 'PKG_CARTERA',
            objectType: 'PACKAGE BODY',
            ambiente: 'QA',
            initialLine: 42,
            initialSearchTerm: 'CLIENTE',
          )
          ..isDirty = false;

        final tab3 = AppTab(ambiente: 'Prod')
          ..localFilePath = r'C:\scripts\report.sql'
          ..procedimiento = const Procedimiento(
            cdProcedimiento: 'LOCAL_123',
            deTexto: 'SELECT * FROM DUAL;',
            inConfiguracion: 'S',
            version: 0,
            stProcedimiento: '1',
          )
          ..isDirty = true
          ..currentEditorCode = 'SELECT * FROM DUAL WHERE 1=1;';

        final tab4 = AppTab(ambiente: 'Desa')
          ..isSqlExecutor = true
          ..localFilePath = r'C:\scripts\analysis.sql'
          ..currentEditorCode = 'SELECT sysdate FROM dual;';

        final tab5 = AppTab(ambiente: 'QA')
          ..localFilePath = 'documento.txt'
          ..currentEditorCode = 'Configuracion local sin proc'
          ..isDirty = true;

        final tabs = [tab1, tab2, tab3, tab4, tab5];
        await SessionService.saveSession(tabs: tabs, activeTab: 2);

        final loaded = await SessionService.loadSession();
        expect(loaded, isNotNull);
        expect(loaded!.tabs.length, 5);
        expect(loaded.activeTab, 2);

        final restoredTabs = loaded.tabs.map((t) => t.toAppTab()).toList();

        // Tab 1: Procedure
        expect(
          restoredTabs[0].procedimiento?.cdProcedimiento,
          'PR_VENTAS_RESTORE',
        );
        expect(
          restoredTabs[0].procedimiento?.deTexto,
          'BEGIN NULL; /* modified */ END;',
        );
        expect(restoredTabs[0].isDirty, isTrue);
        expect(restoredTabs[0].ambiente, 'Desa');

        // Tab 2: Source viewer
        expect(restoredTabs[1].inSourceViewMode, isTrue);
        expect(restoredTabs[1].sourceViewer?.name, 'PKG_CARTERA');
        expect(restoredTabs[1].sourceViewer?.objectType, 'PACKAGE BODY');
        expect(restoredTabs[1].sourceViewer?.initialLine, 42);

        // Tab 3: Local file
        expect(restoredTabs[2].localFilePath, r'C:\scripts\report.sql');
        expect(restoredTabs[2].isDirty, isTrue);
        expect(
          restoredTabs[2].currentEditorCode,
          'SELECT * FROM DUAL WHERE 1=1;',
        );

        // Tab 4: SQL Executor
        expect(restoredTabs[3].isSqlExecutor, isTrue);
        expect(restoredTabs[3].inSqlExecutorMode, isTrue);
        expect(restoredTabs[3].localFilePath, r'C:\scripts\analysis.sql');
        expect(restoredTabs[3].currentEditorCode, 'SELECT sysdate FROM dual;');

        // Tab 5: Local file tab without predefined procedure
        expect(restoredTabs[4].localFilePath, 'documento.txt');
        expect(
          restoredTabs[4].currentEditorCode,
          'Configuracion local sin proc',
        );
        expect(restoredTabs[4].procedimiento, isNotNull);
        expect(
          restoredTabs[4].procedimiento!.deTexto,
          'Configuracion local sin proc',
        );
      },
    );

    test('loadSession returns null when disabled', () async {
      final tab = AppTab(ambiente: 'Desa')..isSqlExecutor = true;
      await SessionService.saveSession(tabs: [tab], activeTab: 0);

      await SessionService.setRestoreEnabled(false);
      expect(await SessionService.loadSession(), isNull);
    });
  });
}
