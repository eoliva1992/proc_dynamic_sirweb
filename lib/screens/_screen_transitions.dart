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

class _EditorFadeIn extends StatefulWidget {
  final Widget child;
  const _EditorFadeIn({required super.key, required this.child});

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
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _ctrl, child: widget.child);
}
