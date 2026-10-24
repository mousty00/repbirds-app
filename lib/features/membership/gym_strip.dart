import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/gym/nfc_card.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../models/gym.dart';
import '../gym/gym_courses_screen.dart';

/// Nella Home, per chi ha un abbonamento attivo: la tessera a un tocco e i corsi di oggi.
/// Senza abbonamenti non mostra niente.
class GymStrip extends ConsumerWidget {
  const GymStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(membershipsProvider).value ?? const <Membership>[];
    final active = memberships.where((m) => m.active).toList();
    if (memberships.isEmpty) return const SizedBox.shrink();
    // la tessera NFC resta pronta anche senza aprire la schermata
    final card = active.firstOrNull?.card;
    if (card != null) NfcCard.setCard(card);
    final today = DateTime.now();
    final courses = (ref.watch(myCoursesProvider).value ?? const <GymCourse>[]).where((c) => c.isOn(today)).toList()
      ..sort((a, b) => (a.startTime?.label ?? '').compareTo(b.startTime?.label ?? ''));
    final m = active.firstOrNull ?? memberships.first;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoftCard(
            onTap: () => context.push('/membership'),
            padding: const EdgeInsets.all(16),
            radius: AppRadius.md,
            child: Row(
              children: [
                IconChip(icon: Icons.badge_rounded, color: m.active ? AppColors.mint : AppColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.gym.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        m.active ? tr('Tessera, schede e corsi') : tr('Abbonamento non attivo'),
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.qr_code_2_rounded, color: AppColors.ink),
              ],
            ),
          ),
          if (courses.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionHeader(tr('Corsi di oggi')),
            for (final c in courses) CourseCard(course: c, onTap: () => context.push('/membership')),
          ],
        ],
      ),
    );
  }
}
