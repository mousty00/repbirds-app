import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../models/workout.dart';
import 'gym_widgets.dart';

/// Schede che la palestra scrive per i suoi iscritti: le vedono solo loro, con
/// l'abbonamento attivo. Si aprono e si modificano (esercizi compresi) come ogni scheda.
class GymWorkoutsScreen extends ConsumerWidget {
  const GymWorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workouts = ref.watch(gymWorkoutsProvider);
    return GymPage(
      title: tr('Schede'),
      subtitle: tr('Visibili solo ai tuoi iscritti'),
      onRefresh: () async {
        ref.invalidate(gymWorkoutsProvider);
        await ref.read(gymWorkoutsProvider.future).catchError((_) => <Workout>[]);
      },
      fab: FloatingActionButton.extended(
        heroTag: 'gym-add-workout',
        onPressed: () => context.push('/gym/workouts/new'),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Nuova scheda')),
      ),
      children: [
        AsyncView<List<Workout>>(
          value: workouts,
          onRetry: () => ref.invalidate(gymWorkoutsProvider),
          data: (list) => list.isEmpty
              ? EmptyState(
                  icon: Icons.fitness_center_rounded,
                  title: tr('Nessuna scheda'),
                  message: tr('Prepara le schede per i tuoi iscritti: le trovano nell\'app sotto la tessera.'),
                  action: tr('Crea scheda'),
                  onAction: () => context.push('/gym/workouts/new'),
                )
              : Column(children: [for (final w in list) GymWorkoutRow(workout: w)]),
        ),
      ],
    );
  }
}

/// Riga di una scheda della palestra (dashboard e schermata della tessera).
class GymWorkoutRow extends StatelessWidget {
  const GymWorkoutRow({super.key, required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final w = workout;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        onTap: () => context.push('/workout/${w.id}'),
        padding: const EdgeInsets.all(16),
        radius: AppRadius.md,
        child: Row(
          children: [
            const IconChip(icon: Icons.fitness_center_rounded, color: AppColors.amber),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    [
                      tr('{n} esercizi', {'n': w.exercises.length}),
                      weekdaysLabel(w.dayOfWeek),
                    ].join(' · '),
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
