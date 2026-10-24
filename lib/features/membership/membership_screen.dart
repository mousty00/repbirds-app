import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../models/gym.dart';
import '../../models/workout.dart';
import '../auth/session.dart';
import '../gym/gym_courses_screen.dart';
import '../gym/gym_workouts_screen.dart';
import 'membership_card.dart';

/// La mia palestra: la tessera per entrare, le schede che la palestra ha scritto
/// per gli iscritti e i corsi a cui iscriversi. Senza [membershipId] apre la prima attiva.
class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({super.key, this.membershipId});

  final String? membershipId;

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  int _tab = 0;
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final memberships = ref.watch(membershipsProvider);
    final me = ref.watch(currentUserProvider);
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: AsyncView<List<Membership>>(
            value: memberships,
            onRetry: () => ref.invalidate(membershipsProvider),
            data: (list) {
              if (list.isEmpty) {
                return Column(
                  children: [
                    TopBar(title: tr('Tessera palestra')),
                    Expanded(
                      child: EmptyState(
                        icon: Icons.badge_rounded,
                        title: tr('Nessuna palestra'),
                        message: tr(
                          'Quando la tua palestra attiva il tuo abbonamento su RepBirds, qui trovi la tessera per entrare, le schede e i corsi.',
                        ),
                      ),
                    ),
                  ],
                );
              }
              final current = list.firstWhere(
                (m) => m.id == (_selected ?? widget.membershipId),
                orElse: () => list.firstWhere((m) => m.active, orElse: () => list.first),
              );
              return Column(
                children: [
                  TopBar(title: tr('Tessera palestra')),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(membershipsProvider);
                        ref.invalidate(myCoursesProvider);
                        ref.invalidate(gymWorkoutsForMemberProvider(current.gym.id));
                        ref.invalidate(gymCoursesForMemberProvider(current.gym.id));
                        await ref.read(membershipsProvider.future).catchError((_) => <Membership>[]);
                      },
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        children: [
                          if (list.length > 1) ...[
                            SizedBox(
                              height: 40,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  for (final m in list)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(m.gym.name),
                                        selected: m.id == current.id,
                                        onSelected: (_) => setState(() => _selected = m.id),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          MembershipCardView(key: ValueKey(current.id), membership: current, user: me),
                          if (current.gym.place != null) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.place_outlined, size: 16, color: AppColors.muted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(current.gym.place!, style: TextStyle(color: AppColors.muted)),
                                ),
                              ],
                            ),
                          ],
                          if (current.active) ...[
                            const SizedBox(height: 20),
                            SegmentedPill(
                              options: [tr('Schede'), tr('Corsi')],
                              index: _tab,
                              onChanged: (i) => setState(() => _tab = i),
                            ),
                            const SizedBox(height: 16),
                            if (_tab == 0) _GymWorkouts(gymId: current.gym.id) else _GymCourses(gymId: current.gym.id),
                          ],
                        ],
                      ),
                    ),
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

class _GymWorkouts extends ConsumerWidget {
  const _GymWorkouts({required this.gymId});

  final String gymId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<Workout>>(
      value: ref.watch(gymWorkoutsForMemberProvider(gymId)),
      onRetry: () => ref.invalidate(gymWorkoutsForMemberProvider(gymId)),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.fitness_center_rounded,
              title: tr('Nessuna scheda per ora'),
              message: tr('Le schede che la palestra prepara per gli iscritti compaiono qui.'),
            )
          : Column(children: [for (final w in list) GymWorkoutRow(workout: w)]),
    );
  }
}

class _GymCourses extends ConsumerWidget {
  const _GymCourses({required this.gymId});

  final String gymId;

  Future<void> _toggle(BuildContext context, WidgetRef ref, GymCourse c) async {
    final repo = ref.read(membershipRepositoryProvider);
    try {
      c.enrolled ? await repo.leave(gymId, c.id) : await repo.join(gymId, c.id);
      ref.invalidate(gymCoursesForMemberProvider(gymId));
      ref.invalidate(myCoursesProvider);
      if (context.mounted) {
        showMessage(
          context,
          c.enrolled ? tr('Non sei più iscritto a {course}', {'course': c.name}) : tr('Iscritto a {course}', {'course': c.name}),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<GymCourse>>(
      value: ref.watch(gymCoursesForMemberProvider(gymId)),
      onRetry: () => ref.invalidate(gymCoursesForMemberProvider(gymId)),
      data: (list) => list.isEmpty
          ? EmptyState(icon: Icons.event_rounded, title: tr('Nessun corso per ora'))
          : Column(
              children: [
                for (final c in list)
                  CourseCard(
                    course: c,
                    trailing: c.enrolled
                        ? OutlinedButton(onPressed: () => _toggle(context, ref, c), child: Text(tr('Iscritto ✓')))
                        : FilledButton(
                            onPressed: c.full ? null : () => _toggle(context, ref, c),
                            child: Text(c.full ? tr('Pieno') : tr('Iscriviti')),
                          ),
                  ),
              ],
            ),
    );
  }
}
