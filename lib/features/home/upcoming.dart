import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/providers.dart';
import '../../models/group.dart';
import '../friends/notifications_screen.dart';

/// Inviti a cui rispondere e cosa c'è in programma con gli altri (sessioni di
/// gruppo e vecchie corse di gruppo). Niente se non c'è niente.
class Upcoming extends ConsumerWidget {
  const Upcoming({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(groupInvitesProvider).value ?? const <GroupMember>[];
    final now = DateTime.now();
    final sessions = ref.watch(upcomingSessionsProvider).value ?? const <GroupSession>[];
    final runs = (ref.watch(runEventsProvider).value ?? const []).where((e) => e.canRun && e.isUpcoming);
    final planned = <(DateTime, Widget)>[
      for (final s in sessions)
        (
          s.scheduledFor ?? now.add(const Duration(days: 365)),
          _PlanCard(
            icon: s.isRun ? Icons.directions_run_rounded : Icons.groups_rounded,
            when: s.scheduledFor,
            title: s.workoutName,
            subtitle: s.groupName,
            highlight: s.myStatus == Attendance.going,
            onTap: () => context.push('/group-session/${s.id}'),
          ),
        ),
      for (final e in runs)
        (
          e.startsAt!,
          _PlanCard(
            icon: Icons.directions_run_rounded,
            when: e.startsAt,
            title: e.title,
            subtitle: tr('Corsa'),
            highlight: true,
            onTap: () => context.push('/running/event/${e.id}'),
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (invites.isNotEmpty) ...[
          _Title(tr('Inviti · {count}', {'count': invites.length})),
          for (final m in invites)
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: GroupInviteTile(member: m)),
        ],
        if (planned.isNotEmpty) ...[
          _Title(tr('In programma')),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: planned.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => planned[i].$2,
            ),
          ),
        ],
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.icon,
    required this.when,
    required this.title,
    required this.subtitle,
    required this.highlight,
    required this.onTap,
  });

  final IconData icon;
  final DateTime? when;
  final String title;
  final String subtitle;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? Colors.white : AppColors.mint;
    return SizedBox(
      width: 200,
      child: Material(
        color: highlight ? AppColors.mint : AppColors.mint.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: fg.withValues(alpha: 0.8)),
                const Spacer(),
                Text(when != null ? formatDayTime(when!.toLocal()) : tr('Da programmare'),
                    style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 12)),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w800)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: 0.75))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
