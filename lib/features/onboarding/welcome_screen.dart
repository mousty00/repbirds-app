import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/ui.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StepIndicator(),
                const SizedBox(height: 28),
                Text(tr('Allenati.\nInsieme.\nO da solo.'), style: t.displayMedium),
                const SizedBox(height: 14),
                Text(
                  tr('Crea le tue schede, organizza sessioni con gli amici e condividi i progressi con la community.'),
                  style: t.bodyLarge?.copyWith(color: AppColors.inkSoft, height: 1.45),
                ),
                const Expanded(child: _Hero()),
                PillActionButton(label: tr('Inizia'), onPressed: () => context.push('/auth/signup')),
                const SizedBox(height: 18),
                Center(
                  child: GestureDetector(
                    onTap: () => context.push('/auth/login'),
                    child: Text.rich(
                      TextSpan(
                        text: tr('Hai già un account? '),
                        style: t.bodyMedium,
                        children: [
                          TextSpan(
                            text: tr('Accedi'),
                            style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/auth/signup/gym'),
                    child: Text(tr('Hai una palestra? Registrala'), style: TextStyle(color: AppColors.inkSoft)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator();

  @override
  Widget build(BuildContext context) {
    Widget bar(bool active) => Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: active ? AppColors.blue : AppColors.card.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
    return Row(children: [bar(false), bar(true), bar(false)]);
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final logo = (c.maxHeight * 0.42).clamp(80.0, 150.0);
        return Stack(
          alignment: Alignment.center,
          children: [
            Align(alignment: const Alignment(0.2, -0.15), child: BrandMark(size: logo, animate: true)),
            Align(
              alignment: const Alignment(-1, -0.85),
              child: _FloatingChip(icon: Icons.fitness_center_rounded, title: tr('Schede'), subtitle: tr('Su misura')),
            ),
            Align(
              alignment: const Alignment(1, 0.62),
              child: _FloatingChip(
                icon: Icons.groups_rounded,
                title: tr('Gruppi'),
                subtitle: tr('Allenati in compagnia'),
                color: AppColors.lilac,
              ),
            ),
            Align(
              alignment: const Alignment(-1, 0.25),
              child: _FloatingChip(
                icon: Icons.favorite_rounded,
                title: tr('Community'),
                subtitle: tr('Condividi i progressi'),
                color: AppColors.pink,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip({required this.icon, required this.title, required this.subtitle, this.color = AppColors.blue});

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconChip(icon: icon, color: color, size: 36),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              Text(subtitle, style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
