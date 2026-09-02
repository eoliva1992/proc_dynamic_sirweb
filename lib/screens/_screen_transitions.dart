part of 'main_screen.dart';

// Fades in a tab when it becomes active; subsequent activations start at 0.7
// to avoid the "content cleared" visual artifact on returning to a known tab.
class _TabFadeIn extends StatefulWidget {
  final Widget child;
  const _TabFadeIn({required super.key, required this.child});

  @override
  State<_TabFadeIn> createState() => _TabFadeInState();
}

class _TabFadeInState extends State<_TabFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _wasTickerEnabled = false;
  bool _hasBeenActiveOnce = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled && !_wasTickerEnabled) {
      _ctrl.forward(from: _hasBeenActiveOnce ? 0.7 : 0.0);
      _hasBeenActiveOnce = true;
    }
    _wasTickerEnabled = enabled;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _ctrl, child: widget.child);
  }
}

/// Fade del editor.
///
/// La key de este widget debe depender **solo** del tab, nunca del
/// procedimiento: si cambiara con cada procedimiento, Flutter remontaría todo
/// el subárbol y con él el `CodeEditorPanel`, destruyendo y recreando el
/// WebView2 de Monaco en cada apertura (el coste dominante). Para volver a
/// animar sin remontar se usa [fadeTrigger]: cuando su valor cambia se relanza
/// la animación sobre el mismo árbol de widgets.
class _EditorFadeIn extends StatefulWidget {
  final Widget child;

  /// Cambiar este valor re-dispara el fade sin remontar el subárbol.
  final Object? fadeTrigger;

  const _EditorFadeIn({
    required super.key,
    required this.child,
    this.fadeTrigger,
  });

  @override
  State<_EditorFadeIn> createState() => _EditorFadeInState();
}

class _EditorFadeInState extends State<_EditorFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
  }

  @override
  void didUpdateWidget(_EditorFadeIn old) {
    super.didUpdateWidget(old);
    if (old.fadeTrigger != widget.fadeTrigger) {
      // Arranca en 0.5 en vez de 0: el editor ya está montado, así que un fade
      // desde negro se vería como un parpadeo en lugar de una transición.
      _ctrl.forward(from: 0.5);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _ctrl, child: widget.child);
}

/// Spinner que se superpone al editor mientras se resuelve la carga de un
/// procedimiento, en lugar de sustituirlo. Así el `CodeEditorPanel` (y su
/// WebView2) nunca se desmonta durante la carga.
class _EditorLoadingOverlay extends StatelessWidget {
  final String? cdProcedimiento;

  /// `true` cuando no hay editor debajo (primera carga del tab): se pinta un
  /// fondo sólido. Si ya hay editor, se usa un velo translúcido.
  final bool opaque;

  const _EditorLoadingOverlay({this.cdProcedimiento, this.opaque = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: false,
      child: ColoredBox(
        color: opaque ? cs.surface : cs.surface.withValues(alpha: 0.55),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF0078D4),
                ),
              ),
              if (cdProcedimiento != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Cargando $cdProcedimiento…',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
