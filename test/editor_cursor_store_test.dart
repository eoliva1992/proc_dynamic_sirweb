import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/services/editor_cursor_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('EditorCursorStore initializes with default underlineThin', () {
    final store = EditorCursorStore();
    expect(store.cursorStyle, CursorStyle.underlineThin);
    expect(store.cursorStyleId, 'underline-thin');
    expect(store.currentMeta.name, 'Subrayado delgado');
  });

  test(
    'EditorCursorStore changes cursor style and notifies listeners',
    () async {
      final store = EditorCursorStore();
      var notified = false;
      store.addListener(() {
        notified = true;
      });

      await store.setCursorStyle(CursorStyle.block);
      expect(store.cursorStyle, CursorStyle.block);
      expect(store.cursorStyleId, 'block');
      expect(notified, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('editor_cursor_style'), 'block');
    },
  );

  test('EditorCursorStore loads saved style from SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({
      'editor_cursor_style': 'line-thin',
    });

    final store = EditorCursorStore();
    await store.loadFromPrefs();
    expect(store.cursorStyle, CursorStyle.lineThin);
    expect(store.cursorStyleId, 'line-thin');
    expect(store.currentMeta.name, 'Línea fina');
  });

  test('kEditorCursorStyles contains all 6 supported Monaco cursor styles', () {
    expect(kEditorCursorStyles.length, 6);
    final ids = kEditorCursorStyles.map((m) => m.id).toList();
    expect(
      ids,
      containsAll([
        'underline-thin',
        'underline',
        'line',
        'line-thin',
        'block',
        'block-outline',
      ]),
    );
  });
}
