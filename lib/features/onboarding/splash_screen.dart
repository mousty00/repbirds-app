import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sound/sounds.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/rep_bird.dart';
import '../auth/session.dart';

/// Diventa true quando l'animazione dello splash è finita: fino ad allora il
/// router resta sullo splash anche se la sessione è già pronta.
final splashDoneProvider = NotifierProvider<SplashDone, bool>(SplashDone.new);

class SplashDone extends Notifier<bool> {
  @override
  bool build() => false;

  void done() => state = true;
}

/// Splash animato: tinta unita del brand (come lo splash nativo, così il
/// passaggio non si vede), l'uccellino entra con un rimbalzo, sbatte l'occhio
/// e fa vedere il bicipite, poi compare il nome.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  /// Mentre si aspetta il server: il bicipite continua a pompare piano.
  late final _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isAnimating || _intro.isCompleted) return;
    Sounds.play(Sound.launch);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _intro.value = 1;
      _finish();
    } else {
      _intro.forward().then((_) => _finish());
    }
  }

  void _finish() {
    if (!mounted) return;
    _idle.repeat(reverse: true);
    // dopo il frame: il router cambia schermata in risposta
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(splashDoneProvider.notifier).done();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _idle.dispose();
    super.dispose();
  }

  double _interval(double begin, double end, [Curve curve = Curves.linear]) =>
      curve.transform(((_intro.value - begin) / (end - begin)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final t = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.brand,
        body: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _idle]),
            builder: (context, _) {
              // entrata: cade dall'alto e atterra con un rimbalzo elastico
              final drop = _interval(0, 0.42, Curves.bounceOut);
              final pop = _interval(0, 0.5, Curves.elasticOut);
              // schiacciata all'atterraggio, poi torna tonda
              final land = _interval(0.2, 0.4);
              final squash = math.sin(land * math.pi) * 0.1;
              // due flessioni del bicipite, poi una lenta mentre si aspetta
              final pumps = _interval(0.48, 0.9);
              final flex = math.sin(pumps * math.pi * 2).abs() + _idle.value * 0.6 * _intro.value;
              final blink = math.sin(_interval(0.6, 0.68) * math.pi);
              final title = _interval(0.55, 0.85, Curves.easeOutBack);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(
                    offset: Offset(0, -260 * (1 - drop)),
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.diagonal3Values(
                        (0.4 + 0.6 * pop) * (1 + squash),
                        (0.4 + 0.6 * pop) * (1 - squash),
                        1,
                      ),
                      child: RepBird(size: 200, eyeColor: AppColors.brand, flex: flex.clamp(0, 1), blink: blink),
                    ),
                  ),
                  // ombra che si allarga quando l'uccellino tocca terra
                  Container(
                    width: 90 * (0.3 + 0.7 * drop),
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.12 * drop),
                      borderRadius: const BorderRadius.all(Radius.elliptical(45, 5)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: title.clamp(0, 1),
                    child: Transform.translate(
                      offset: Offset(0, 24 * (1 - title)),
                      child: Text(
                        'RepBirds',
                        style: t.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 64,
                    child: session.hasError && _intro.isCompleted
                        ? Column(
                            children: [
                              Text(tr('Non riesco a contattare il server.'),
                                  style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: Colors.white),
                                onPressed: () => ref.invalidate(sessionProvider),
                                child: Text(tr('Riprova')),
                              ),
                            ],
                          )
                        : null,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
