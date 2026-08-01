// Selecciona automáticamente la implementación según la plataforma:
//   - dart.library.io disponible → nativo (flutter_js / QuickJS real)
//   - sin dart.library.io        → web stub (usa checker manual)
export '_editor_js_engine_stub.dart'
    if (dart.library.io) '_editor_js_engine_native.dart';
