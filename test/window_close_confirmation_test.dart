import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/procedimiento.dart';
import 'package:proc_dynamic_sirweb/widgets/app_tab.dart';

void main() {
  group('Window close editor dirty detection', () {
    test(
      'tabs in search mode with isDirty=false should not require confirmation',
      () {
        final tab = AppTab();
        expect(tab.isDirty, isFalse);
        expect(tab.inSearchMode, isTrue);

        final isDirtyEditor =
            tab.isDirty && (tab.procedimiento != null || tab.inSourceViewMode);
        expect(isDirtyEditor, isFalse);
      },
    );

    test('procedure tab with isDirty=true is detected as dirty editor', () {
      final tab = AppTab()
        ..procedimiento = const Procedimiento(
          cdProcedimiento: 'PR_TEST_CLOSE',
          deTexto: 'BEGIN NULL; END;',
          inConfiguracion: 'D',
          version: 1,
          stProcedimiento: '1',
        )
        ..isDirty = true;

      expect(tab.isDirty, isTrue);
      expect(tab.procedimiento, isNotNull);

      final isDirtyEditor =
          tab.isDirty && (tab.procedimiento != null || tab.inSourceViewMode);
      expect(isDirtyEditor, isTrue);
    });

    test(
      'procedure tab with isDirty=false is NOT detected as dirty editor',
      () {
        final tab = AppTab()
          ..procedimiento = const Procedimiento(
            cdProcedimiento: 'PR_TEST_CLEAN',
            deTexto: 'BEGIN NULL; END;',
            inConfiguracion: 'D',
            version: 1,
            stProcedimiento: '1',
          )
          ..isDirty = false;

        final isDirtyEditor =
            tab.isDirty && (tab.procedimiento != null || tab.inSourceViewMode);
        expect(isDirtyEditor, isFalse);
      },
    );

    test('source viewer tab with isDirty=true is detected as dirty editor', () {
      final tab = AppTab()
        ..sourceViewer = (
          name: 'PKG_TEST',
          objectType: 'PACKAGE BODY',
          ambiente: 'Desa',
          initialLine: null,
          initialSearchTerm: null,
        )
        ..isDirty = true;

      expect(tab.inSourceViewMode, isTrue);
      final isDirtyEditor =
          tab.isDirty && (tab.procedimiento != null || tab.inSourceViewMode);
      expect(isDirtyEditor, isTrue);
    });

    test('local file tab with isDirty=true is detected as dirty editor', () {
      final tab = AppTab()
        ..localFilePath = r'C:\test\script.sql'
        ..procedimiento = const Procedimiento(
          cdProcedimiento: 'script.sql',
          deTexto: 'SELECT 1 FROM DUAL;',
          inConfiguracion: 'D',
          version: 1,
          stProcedimiento: '1',
        )
        ..isDirty = true;

      final isDirtyEditor =
          tab.isDirty && (tab.procedimiento != null || tab.inSourceViewMode);
      expect(isDirtyEditor, isTrue);
    });

    test('sql executor tab with isDirty=true is detected as dirty editor', () {
      final tab = AppTab()
        ..isSqlExecutor = true
        ..currentEditorCode = 'SELECT * FROM DUAL;'
        ..isDirty = true;

      expect(tab.inSqlExecutorMode, isTrue);
      final isDirtyEditor =
          tab.isDirty &&
          (tab.procedimiento != null ||
              tab.inSourceViewMode ||
              tab.inSqlExecutorMode);
      expect(isDirtyEditor, isTrue);
    });

    test(
      'sql executor tab with isDirty=false is NOT detected as dirty editor',
      () {
        final tab = AppTab()
          ..isSqlExecutor = true
          ..currentEditorCode = ''
          ..isDirty = false;

        expect(tab.inSqlExecutorMode, isTrue);
        final isDirtyEditor =
            tab.isDirty &&
            (tab.procedimiento != null ||
                tab.inSourceViewMode ||
                tab.inSqlExecutorMode);
        expect(isDirtyEditor, isFalse);
      },
    );

    test('multiple tabs filter correctly isolates only dirty editors', () {
      final tab1 = AppTab(); // search mode
      final tab2 = AppTab()
        ..procedimiento = const Procedimiento(
          cdProcedimiento: 'PR_DIRTY',
          deTexto: 'BEGIN NULL; END;',
          inConfiguracion: 'D',
          version: 1,
          stProcedimiento: '1',
        )
        ..isDirty = true;
      final tab3 = AppTab()
        ..procedimiento = const Procedimiento(
          cdProcedimiento: 'PR_CLEAN',
          deTexto: 'BEGIN NULL; END;',
          inConfiguracion: 'D',
          version: 1,
          stProcedimiento: '1',
        )
        ..isDirty = false;
      final tab4 = AppTab()
        ..sourceViewer = (
          name: 'PKG_DIRTY',
          objectType: 'PACKAGE',
          ambiente: 'Desa',
          initialLine: null,
          initialSearchTerm: null,
        )
        ..isDirty = true;
      final tab5 = AppTab()
        ..isSqlExecutor = true
        ..currentEditorCode = 'SELECT 1 FROM DUAL;'
        ..isDirty = true;

      final allTabs = [tab1, tab2, tab3, tab4, tab5];
      final dirtyEditors = allTabs.where((tab) {
        if (!tab.isDirty) return false;
        return tab.procedimiento != null ||
            tab.inSourceViewMode ||
            tab.inSqlExecutorMode;
      }).toList();

      expect(dirtyEditors.length, 3);
      expect(dirtyEditors[0].procedimiento?.cdProcedimiento, 'PR_DIRTY');
      expect(dirtyEditors[1].sourceViewer?.name, 'PKG_DIRTY');
      expect(dirtyEditors[2].inSqlExecutorMode, isTrue);
    });
  });
}
