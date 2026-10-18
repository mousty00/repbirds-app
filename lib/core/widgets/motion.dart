import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Durate e curve delle animazioni: brevi e sobrie, uguali in tutta l'app.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 120);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 360);

  static const curve = Curves.easeOutCubic;

  /// Ritardo tra un elemento e il successivo nelle entrate scaglionate.
  static const stagger = Duration(milliseconds: 45);

  /// Oltre questo indice gli elementi compaiono senza animazione: sono fuori
  /// dallo schermo e arrivano scorrendo.
  static const maxStaggered = 8;

  /// Animazioni ridotte nelle impostazioni di accessibilità del telefono.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Pagina che entra in dissolvenza salendo di poco. Per le schermate che
/// sostituiscono tutto (splash, benvenuto, le tab dopo il login), dove lo
/// scorrimento laterale di sistema non avrebbe senso.
CustomTransitionPage<void> fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.medium,
    transitionsBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Entrata di un elemento di una lista o di una card: dissolvenza e piccola
/// salita, in ritardo di [index] passi rispetto al primo. Si anima una volta
/// sola, quando la schermata si apre: non mentre si scorre una lista lunga.
class FadeInUp extends StatefulWidget {
  const FadeInUp({super.key, required this.child, this.index = 0, this.offset = 16});

  final Widget child;
  final int index;

  /// Di quanti pixel sale.
  final double offset;

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp> with SingleTickerProviderStateMixin {
  bool _started = false;
  AnimationController? _controller;
  late Animation<double> _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context) || widget.index > AppMotion.maxStaggered) return;
    // Costruito da una lista già scorsa: arriva scorrendo, senza entrata.
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != null && scroll.hasPixels && scroll.pixels > 0) return;
    final delay = AppMotion.stagger * widget.index;
    final total = delay + AppMotion.slow;
    final controller = AnimationController(vsync: this, duration: total);
    _progress = CurvedAnimation(
      parent: controller,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: AppMotion.curve),
    );
    _controller = controller..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return widget.child;
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (_, child) {
        final t = _progress.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * widget.offset), child: child),
        );
      },
    );
  }
}

/// Rimpicciolisce di poco il figlio mentre lo si tiene premuto, come un
/// tasto vero. Non intercetta i tocchi: il figlio li riceve come prima.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true, this.scale = 0.96});

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || AppMotion.reduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: _down ? AppMotion.fast : AppMotion.medium,
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
