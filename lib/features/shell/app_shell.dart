import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/ui.dart';
import '../auth/session.dart';
import '../workouts/saved_session.dart';
import 'create_sheet.dart';

/// Le tab (Oggi, Allenati, Insieme e il profilo, con la tua foto) nella barra
/// di navigazione flottante a pillola, con al centro il "+" per creare.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with SingleTickerProviderStateMixin {
  /// Una volta per avvio: se il sistema aveva chiuso l'app a metà allenamento, lo riapre.
  static bool _resumeChecked = false;

  /// Cambio di tab: la nuova entra in dissolvenza salendo di poco.
  late final _tabIn = AnimationController(vsync: this, duration: AppMotion.medium, value: 1);
  late final _tabCurve = CurvedAnimation(parent: _tabIn, curve: AppMotion.curve);
  late int _index = widget.shell.currentIndex;

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    final index = widget.shell.currentIndex;
    if (index == _index) return;
    _index = index;
    if (!AppMotion.reduced(context)) _tabIn.forward(from: 0);
  }

  @override
  void dispose() {
    _tabCurve.dispose();
    _tabIn.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (_resumeChecked) return;
    _resumeChecked = true;
    SavedSession.load().then((s) {
      if (s != null && mounted) context.push(s.route);
    });
  }

  StatefulNavigationShell get shell => widget.shell;

  static List<(IconData, String)> get _items => [
        (Icons.home_rounded, tr('Oggi')),
        (Icons.fitness_center_rounded, tr('Allenati')),
        (Icons.groups_rounded, tr('Insieme')),
        (Icons.person_rounded, tr('Profilo')),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: FadeTransition(
        opacity: _tabCurve,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(_tabCurve),
          child: shell,
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.only(bottom: 12),
        child: Center(
          heightFactor: 1,
          child: FloatingNavBar(
            index: shell.currentIndex,
            items: _items,
            avatar: Consumer(
              builder: (_, ref, _) {
                final me = ref.watch(sessionProvider).value;
                return me == null ? const SizedBox.shrink() : UserAvatar(username: me.username, imageUrl: me.image, size: 48);
              },
            ),
            onTap: (i) {
              if (i != shell.currentIndex) HapticFeedback.selectionClick();
              shell.goBranch(i, initialLocation: i == shell.currentIndex);
            },
            onCreate: () => showCreateSheet(context),
          ),
        ),
      ),
    );
  }
}

/// Radice di una tab diversa dalla Home: il gesto/tasto indietro di sistema
/// riporta alla Home invece di chiudere l'app.
class BackToHome extends StatelessWidget {
  const BackToHome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/home');
      },
      child: child,
    );
  }
}

class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.index, required this.items, required this.onTap, this.avatar, this.onCreate});

  final int index;

  /// Al posto dell'icona dell'ultima voce (il profilo): la foto o le iniziali.
  final Widget? avatar;
  final List<(IconData, String)> items;
  final ValueChanged<int> onTap;

  /// Se c'è, un "+" in mezzo alle voci.
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final middle = items.length ~/ 2;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(48),
        border: Border.all(color: AppColors.isDark ? AppColors.stroke : AppColors.card),
        boxShadow: AppShadows.float,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (onCreate != null && i == middle)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Semantics(
                  label: tr('Crea'),
                  button: true,
                  child: Pressable(
                    scale: 0.9,
                    child: GestureDetector(
                      onTap: onCreate,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.brand),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
              child: _NavItem(
                icon: items[i].$1,
                label: items[i].$2,
                picture: i == items.length - 1 ? avatar : null,
                selected: i == index,
                onTap: () => onTap(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap, this.picture});

  final IconData icon;
  final Widget? picture;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: Pressable(
        scale: 0.92,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: selected ? 60 : 52,
            height: selected ? 60 : 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AppColors.ink : AppColors.bg,
              boxShadow: selected
                  ? [BoxShadow(color: AppColors.ink.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))]
                  : null,
            ),
            padding: picture != null ? const EdgeInsets.all(3) : null,
            child: picture != null
                ? ClipOval(child: FittedBox(fit: BoxFit.cover, child: picture))
                : AnimatedSwitcher(
                    duration: AppMotion.medium,
                    child: Icon(
                      icon,
                      key: ValueKey(selected),
                      color: selected ? AppColors.onInk : AppColors.inkSoft,
                      size: 24,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Spazio in fondo alle liste delle tab per non finire sotto la barra flottante.
const navBarClearance = 110.0;
