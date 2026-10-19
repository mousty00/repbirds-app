import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/ui.dart';
import '../shell/app_shell.dart';

/// La guida è già stata vista su questo telefono? Di base no: si apre al primo
/// ingresso nell'app e si rivede da Aiuto.
class GuideNotifier extends Notifier<bool> {
  static const _key = 'repbirds.guide';
  static const _storage = FlutterSecureStorage();

  /// Letto in main() prima di avviare l'app.
  static bool seen = false;

  static Future<void> load() async {
    try {
      seen = await _storage.read(key: _key) == 'seen';
    } catch (_) {}
  }

  @override
  bool build() => seen;

  Future<void> markSeen() async {
    state = seen = true;
    try {
      await _storage.write(key: _key, value: 'seen');
    } catch (_) {}
  }
}

final guideProvider = NotifierProvider<GuideNotifier, bool>(GuideNotifier.new);

/// Una pagina della guida. [tab] è la voce della barra da evidenziare (null:
/// nessuna barra, -1: la barra senza tab scelta, per il "+").
typedef _Step = ({IconData icon, Color color, String title, String body, int? tab});

/// Guida in poche pagine su come funziona l'app: Oggi, Allenati, Insieme, il
/// "+" e il profilo, ognuna con la barra di navigazione vera e la sua voce accesa.
class GuideScreen extends ConsumerStatefulWidget {
  const GuideScreen({super.key});

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  final _pages = PageController();
  int _index = 0;

  static List<_Step> get _steps => [
        (
          icon: Icons.waving_hand_rounded,
          color: AppColors.brand,
          title: tr('Benvenuto su RepBirds'),
          body: tr('Ti mostriamo in un minuto come funziona l\'app. Puoi rivedere questa guida quando vuoi da Aiuto.'),
          tab: null,
        ),
        (
          icon: Icons.home_rounded,
          color: AppColors.blue,
          title: tr('Oggi'),
          body: tr('La cosa da fare adesso: la scheda di oggi o la sessione con il gruppo, i numeri della settimana e gli inviti degli amici.'),
          tab: 0,
        ),
        (
          icon: Icons.fitness_center_rounded,
          color: AppColors.lilac,
          title: tr('Allenati'),
          body: tr('Le tue schede e la corsa. Avvia una scheda e l\'app ti guida serie per serie con il recupero, oppure registra una corsa con il GPS.'),
          tab: 1,
        ),
        (
          icon: Icons.groups_rounded,
          color: AppColors.pink,
          title: tr('Insieme'),
          body: tr('I tuoi gruppi e il feed degli amici. Organizza una sessione, invita gli altri e partite tutti dallo stesso istante.'),
          tab: 2,
        ),
        (
          icon: Icons.add_rounded,
          color: AppColors.mint,
          title: tr('Crea'),
          body: tr('Dal pulsante + al centro della barra crei schede, esercizi, percorsi, gruppi e post.'),
          tab: -1,
        ),
        (
          icon: Icons.person_rounded,
          color: AppColors.amber,
          title: tr('Profilo'),
          body: tr('Lo storico degli allenamenti, i tuoi post e le impostazioni: tema, lingua e suoni. Se ti serve una mano, tocca il punto di domanda in Oggi.'),
          tab: 3,
        ),
      ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _last => _index == _steps.length - 1;

  Future<void> _finish() async {
    await ref.read(guideProvider.notifier).markSeen();
    if (!mounted) return;
    context.canPop() ? context.pop() : context.go('/home');
  }

  void _next() {
    if (_last) {
      _finish();
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    return PopScope(
      // Indietro dalla prima pagina chiude la guida come "Salta".
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index > 0) {
          _pages.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
        } else {
          _finish();
        }
      },
      child: Scaffold(
        body: SkyBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _Progress(count: steps.length, index: _index)),
                      const SizedBox(width: 12),
                      AnimatedOpacity(
                        opacity: _last ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: TextButton(
                          onPressed: _last ? null : _finish,
                          child: Text(tr('Salta'), style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: steps.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (_, i) => _StepPage(step: steps[i], first: i == 0),
                    ),
                  ),
                  PillActionButton(
                    label: _last ? tr('Iniziamo') : tr('Avanti'),
                    icon: _last ? Icons.check_rounded : Icons.keyboard_double_arrow_right_rounded,
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le barrette in alto, una per pagina: si allungano fino a quella corrente.
class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('Pagina {n} di {tot}', {'n': index + 1, 'tot': count}),
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              flex: i == index ? 3 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i <= index ? AppColors.blue : AppColors.card.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.step, required this.first});

  final _Step step;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tab = step.tab;
    // Entra sfumando e salendo un po' ogni volta che la pagina si costruisce.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: first
                  ? const BrandMark(size: 150, animate: true)
                  : _Badge(icon: step.icon, color: step.color),
            ),
          ),
          Text(step.title, style: t.displaySmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            step.body,
            style: t.bodyLarge?.copyWith(color: AppColors.inkSoft, height: 1.45),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          // La barra vera, ferma, con la voce di cui si parla accesa.
          SizedBox(
            height: 76,
            child: tab == null
                ? null
                : IgnorePointer(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: FloatingNavBar(
                        index: tab,
                        items: [
                          (Icons.home_rounded, tr('Oggi')),
                          (Icons.fitness_center_rounded, tr('Allenati')),
                          (Icons.groups_rounded, tr('Insieme')),
                          (Icons.person_rounded, tr('Profilo')),
                        ],
                        onTap: (_) {},
                        onCreate: () {},
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// L'icona della pagina in un cerchio tenue con un anello che respira.
class _Badge extends StatefulWidget {
  const _Badge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  State<_Badge> createState() => _BadgeState();
}

class _BadgeState extends State<_Badge> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        final v = Curves.easeInOut.transform(_pulse.value);
        return Container(
          width: 170 + 16 * v,
          height: 170 + 16 * v,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.08 + 0.04 * v)),
          child: child,
        );
      },
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.card, boxShadow: AppShadows.soft),
        child: Icon(widget.icon, size: 56, color: c),
      ),
    );
  }
}
