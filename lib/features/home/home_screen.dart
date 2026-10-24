import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../data/body_photo_repository.dart';
import '../../data/providers.dart';
import '../../models/group.dart';
import '../../models/workout.dart';
import '../auth/session.dart';
import '../../data/gym_repository.dart';
import '../body/stories.dart';
import '../membership/gym_strip.dart';
import '../shell/app_shell.dart';
import 'upcoming.dart';

/// Tab Oggi: le storie degli amici, una card grande con la cosa da fare adesso, tre numeri della
/// settimana e, sotto, inviti e sessioni in programma con gli altri.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(myWorkoutsProvider);
    ref.invalidate(historyProvider);
    ref.invalidate(upcomingSessionsProvider);
    ref.invalidate(friendRequestsProvider);
    ref.invalidate(groupInvitesProvider);
    ref.invalidate(runEventsProvider);
    ref.invalidate(bodyStoriesProvider);
    ref.invalidate(membershipsProvider);
    ref.invalidate(myCoursesProvider);
    await ref.read(historyProvider.future).catchError((_) => <WorkoutHistory>[]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final t = Theme.of(context).textTheme;
    final notifications = ref.watch(notificationCountProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, navBarClearance),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(greeting(), style: t.bodyMedium?.copyWith(color: AppColors.muted)),
                        Text(
                          user.firstName?.isNotEmpty == true ? user.firstName! : user.username,
                          style: t.headlineMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  CircleIconButton(
                    icon: Icons.help_outline_rounded,
                    tooltip: tr('Aiuto'),
                    onTap: () => context.push('/help'),
                  ),
                  const SizedBox(width: 10),
                  CircleIconButton(
                    icon: Icons.notifications_none_rounded,
                    badge: notifications,
                    tooltip: notifications > 0
                        ? tr('Notifiche, {count} da leggere', {'count': notifications})
                        : tr('Notifiche'),
                    onTap: () => context.push('/notifications'),
                  ),
                ],
              ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const StoriesBar(),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _Now(),
                    GymStrip(),
                    SizedBox(height: 14),
                    _WeekTiles(),
                  ],
                ),
              ),
              const Upcoming(),
            ],
          ),
        ),
      ),
    );
  }
}

/// La cosa da fare adesso: la sessione di gruppo di oggi, altrimenti la prossima
/// scheda di oggi. Se non c'è niente, un invito a scegliere una scheda.
class _Now extends ConsumerWidget {
  const _Now();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final workouts = ref.watch(myWorkoutsProvider).value ?? const <Workout>[];
    final history = ref.watch(historyProvider).value ?? const <WorkoutHistory>[];
    final sessions = ref.watch(upcomingSessionsProvider).value ?? const <GroupSession>[];

    final doneIds = {
      for (final h in history)
        if (h.startedAt != null && isSameDay(h.startedAt!.toLocal(), now)) h.workoutId,
    };
    final today = workouts.where((w) => w.isScheduledOn(now)).toList()
      ..sort((a, b) => (a.startTime?.label ?? '').compareTo(b.startTime?.label ?? ''));
    final next = today.where((w) => !doneIds.contains(w.id)).firstOrNull;
    final session = sessions
        .where((s) => s.scheduledFor != null && isSameDay(s.scheduledFor!.toLocal(), now) && s.myStatus != Attendance.declined)
        .firstOrNull;

    if (session != null) {
      return _Hero(
        label: tr('{group} alle {time}', {'group': session.groupName, 'time': formatTime(session.scheduledFor!.toLocal())}),
        title: session.workoutName,
        detail: tr('Allenamento di gruppo'),
        action: tr('Apri'),
        onTap: () => context.push('/group-session/${session.id}'),
      );
    }
    if (next != null) {
      return _Hero(
        label: next.startTime != null ? tr('Alle {time}', {'time': next.startTime!.label}) : tr('Oggi'),
        title: next.name,
        detail: next.exercises.length == 1 ? tr('{n} esercizio', {'n': 1}) : tr('{n} esercizi', {'n': next.exercises.length}),
        action: tr('Inizia'),
        onTap: () => context.push('/workout/${next.id}/session'),
        onCard: () => context.push('/workout/${next.id}'),
      );
    }
    final allDone = today.isNotEmpty;
    return _Hero(
      label: formatDay(now),
      title: allDone ? tr('Hai finito per oggi') : tr('Giorno libero'),
      detail: allDone ? tr('Ottimo lavoro!') : tr('Niente in programma: scegli una scheda se ti va.'),
      action: allDone ? null : tr('Scegli una scheda'),
      color: allDone ? AppColors.mint : AppColors.inkCard,
      onTap: () => context.go('/workouts'),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.label,
    required this.title,
    required this.detail,
    required this.onTap,
    this.action,
    this.onCard,
    this.color,
  });

  final String label;
  final String title;
  final String detail;
  final String? action;
  final VoidCallback onTap;
  final VoidCallback? onCard;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    const soft = TextStyle(color: Colors.white70);
    return Material(
      color: color ?? AppColors.brand,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onCard ?? onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: soft),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white)),
              const SizedBox(height: 6),
              Text(detail, style: soft),
              if (action != null) ...[
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: Colors.white,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          action!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: color ?? AppColors.brand, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tre numeri della settimana; toccandoli si apre lo storico.
class _WeekTiles extends ConsumerWidget {
  const _WeekTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider).value ?? const <WorkoutHistory>[];
    final start = startOfWeek(DateTime.now());
    final week = history.where((h) {
      final d = h.startedAt?.toLocal();
      return d != null && !d.isBefore(start);
    }).toList();
    final minutes = week.fold<int>(0, (a, h) => a + (h.duration?.inMinutes ?? 0));
    final streak = streakDays(history.map((h) => h.startedAt?.toLocal()).whereType<DateTime>(), DateTime.now());

    Widget tile(String value, String label) => Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: SoftCard(
              radius: 28,
              padding: const EdgeInsets.all(12),
              onTap: () => context.push('/history'),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(child: Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                  const SizedBox(height: 2),
                  Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
          ),
        );

    return Row(
      children: [
        tile('${week.length}', week.length == 1 ? tr('allenamento') : tr('allenamenti')),
        const SizedBox(width: 12),
        tile(minutes == 0 ? '0' : formatDuration(Duration(minutes: minutes)), tr('questa settimana')),
        const SizedBox(width: 12),
        tile('$streak', streak == 1 ? tr('giorno di fila') : tr('giorni di fila')),
      ],
    );
  }
}

/// Giorni consecutivi con almeno un allenamento, fino a oggi (o ieri, se oggi
/// non ti sei ancora allenato).
int streakDays(Iterable<DateTime> days, DateTime today) {
  final set = {for (final d in days) DateTime(d.year, d.month, d.day)};
  var day = DateTime(today.year, today.month, today.day);
  if (!set.contains(day)) day = day.subtract(const Duration(days: 1));
  var n = 0;
  while (set.contains(day)) {
    n++;
    day = day.subtract(const Duration(days: 1));
  }
  return n;
}
