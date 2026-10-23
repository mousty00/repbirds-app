import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../body/body_photo_prompt.dart';
import '../exercises/exercises_screen.dart';

/// Il "+" al centro della barra: scegli cosa creare.
void showCreateSheet(BuildContext context) {
  final items = <(IconData, String, Color, VoidCallback)>[
    (Icons.fitness_center_rounded, tr('Scheda'), AppColors.brand, () => context.push('/workout/new')),
    (Icons.sports_gymnastics_rounded, tr('Esercizio'), AppColors.lilac, () => showCreateExerciseSheet(context)),
    (Icons.route_rounded, tr('Percorso'), AppColors.mint, () => context.push('/running/route/new')),
    (Icons.groups_rounded, tr('Gruppo'), AppColors.amber, () => context.push('/group/new')),
    (Icons.photo_camera_rounded, tr('Post'), AppColors.danger, () => context.push('/posts/new')),
    (Icons.accessibility_new_rounded, tr('Foto del fisico'), AppColors.pink, () => showBodyPhotoPrompt(context)),
  ];
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Crea'), style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 14),
            for (final (icon, label, color, onTap) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SoftCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () {
                    Navigator.pop(ctx);
                    onTap();
                  },
                  child: Row(
                    children: [
                      IconChip(icon: icon, color: color),
                      const SizedBox(width: 14),
                      Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                      Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
