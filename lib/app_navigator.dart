import 'package:flutter/widgets.dart';

/// Key del Navigator raíz de la ventana principal.
///
/// Permite abrir diálogos / overlays sin depender de un [BuildContext] que
/// pueda estar desactivado (p.ej. después de un `Navigator.pop()`).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Contexto seguro para abrir diálogos: el del overlay del Navigator raíz.
///
/// Se usa el overlay (y no `rootNavigatorKey.currentContext`) porque
/// `Navigator.of()` busca un Navigator *ancestro*: desde el contexto del propio
/// Navigator no lo encontraría, mientras que desde su overlay sí.
BuildContext? get rootDialogContext =>
    rootNavigatorKey.currentState?.overlay?.context;
