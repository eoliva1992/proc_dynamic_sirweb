import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metadatos descriptivos de un estilo de cursor para la UI de configuración.
@immutable
class EditorCursorMeta {
  final CursorStyle style;
  final String id;
  final String name;
  final String description;
  final IconData icon;

  const EditorCursorMeta({
    required this.style,
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
  });
}

/// Catálogo completo de estilos de cursor soportados por Monaco.
const kEditorCursorStyles = <EditorCursorMeta>[
  EditorCursorMeta(
    style: CursorStyle.underlineThin,
    id: 'underline-thin',
    name: 'Subrayado delgado',
    description: 'Línea horizontal muy fina bajo el carácter actual.',
    icon: Icons.horizontal_rule_rounded,
  ),
  EditorCursorMeta(
    style: CursorStyle.underline,
    id: 'underline',
    name: 'Subrayado estándar',
    description: 'Línea horizontal estándar bajo el carácter actual.',
    icon: Icons.minimize_rounded,
  ),
  EditorCursorMeta(
    style: CursorStyle.line,
    id: 'line',
    name: 'Línea vertical',
    description: 'Cursor clásico vertical parpadeante entre caracteres.',
    icon: Icons.format_paint_outlined,
  ),
  EditorCursorMeta(
    style: CursorStyle.lineThin,
    id: 'line-thin',
    name: 'Línea fina',
    description: 'Línea vertical ultrafina entre caracteres.',
    icon: Icons.more_vert_rounded,
  ),
  EditorCursorMeta(
    style: CursorStyle.block,
    id: 'block',
    name: 'Bloque sólido',
    description: 'Bloque relleno que cubre todo el carácter activo.',
    icon: Icons.square_rounded,
  ),
  EditorCursorMeta(
    style: CursorStyle.blockOutline,
    id: 'block-outline',
    name: 'Bloque contorno',
    description: 'Rectángulo hueco alrededor del carácter activo.',
    icon: Icons.crop_square_rounded,
  ),
];

final kEditorCursorMetaById = {for (final m in kEditorCursorStyles) m.id: m};

/// Store global y persistente para el estilo del cursor de los editores Monaco.
///
/// Gestiona la preferencia del usuario guardada en [SharedPreferences] y notifica
/// a todos los editores reactivamente para aplicar el cambio en caliente.
class EditorCursorStore extends ChangeNotifier {
  static const _prefKey = 'editor_cursor_style';
  static const defaultStyleId = 'underline-thin';

  CursorStyle _cursorStyle = CursorStyle.underlineThin;

  CursorStyle get cursorStyle => _cursorStyle;
  String get cursorStyleId => _cursorStyle.id;

  EditorCursorMeta get currentMeta =>
      kEditorCursorMetaById[cursorStyleId] ?? kEditorCursorStyles.first;

  /// Carga la preferencia guardada en [SharedPreferences].
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null) {
      final match = kEditorCursorStyles.where((m) => m.id == saved).firstOrNull;
      if (match != null) {
        _cursorStyle = match.style;
      }
    }
    notifyListeners();
  }

  /// Establece un nuevo estilo de cursor y lo persiste en disco.
  Future<void> setCursorStyle(CursorStyle style) async {
    if (_cursorStyle == style) return;
    _cursorStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, style.id);
  }

  /// Establece el estilo de cursor a partir del identificador de texto.
  Future<void> setCursorStyleById(String id) async {
    final match = kEditorCursorStyles.where((m) => m.id == id).firstOrNull;
    if (match != null) {
      await setCursorStyle(match.style);
    }
  }
}

/// Instancia singleton global del store de estilo de cursor.
final editorCursorStore = EditorCursorStore();
