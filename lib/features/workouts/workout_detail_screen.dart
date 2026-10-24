import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../data/providers.dart';
import '../../data/workout_repository.dart';
import '../../models/workout.dart';
import '../auth/session.dart';
import '../share/share_actions.dart';
import 'exercise_picker.dart';
import '../../core/widgets/skeleton.dart';

class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});

  final String workoutId;

  void _refresh(WidgetRef ref) {
    ref.invalidate(workoutProvider(workoutId));
    ref.invalidate(myWorkoutsProvider);
    ref.invalidate(gymWorkoutsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    if (!await confirm(context,
        title: tr('Eliminare la scheda?'), message: tr('Verranno rimossi anche i suoi esercizi.'), ok: tr('Elimina'), destructive: true)) {
      return;
    }
    try {
      await ref.read(workoutRepositoryProvider).delete(workoutId);
      ref.invalidate(myWorkoutsProvider);
      ref.invalidate(exploreWorkoutsProvider);
      ref.invalidate(gymWorkoutsProvider);
      if (context.mounted) closePage(context);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _addExercise(BuildContext context, WidgetRef ref, Workout w) async {
    final input = await showExerciseEditor(context, workoutId: w.id, position: w.exercises.length + 1);
    if (input == null) return;
    try {
      await ref.read(workoutRepositoryProvider).addExercise(input);
      _refresh(ref);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _editExercise(BuildContext context, WidgetRef ref, WorkoutExercise we) async {
    final input = await showExerciseEditor(context, workoutId: we.workoutId, position: we.position, initial: we);
    if (input == null) return;
    try {
      await ref.read(workoutRepositoryProvider).updateExercise(input);
      _refresh(ref);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _removeExercise(BuildContext context, WidgetRef ref, WorkoutExercise we) async {
    try {
      await ref.read(workoutRepositoryProvider).removeExercise(we.id);
      _refresh(ref);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final workout = ref.watch(workoutProvider(workoutId));

    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: AsyncView<Workout>(
            value: workout,
            onRetry: () => ref.invalidate(workoutProvider(workoutId)),
            loading: const SkeletonDetail(),
            data: (w) {
              final mine = w.user?.username == me.username;
              // scheda di una palestra: resta tra i suoi iscritti, niente condivisione né gruppi
              final gymWorkout = w.gymId != null;
              final gymAccount = isGymAccount(me.roleName);
              final totalSets = w.exercises.fold<int>(0, (a, e) => a + e.sets);
              final estMinutes = w.exercises.fold<int>(0, (a, e) => a + e.sets * (45 + e.restSeconds)) ~/ 60;
              return Column(
                children: [
                  TopBar(
                    title: '',
                    actions: [
                      if (!gymWorkout && !gymAccount)
                      CircleIconButton(
                        icon: Icons.ios_share_rounded,
                        size: 44,
                        tooltip: tr('Condividi'),
                        onTap: () => shareWorkout(context, w, mine: mine),
                      ),
                      if (mine) ...[
                        CircleIconButton(
                          icon: Icons.edit_rounded,
                          size: 44,
                          tooltip: tr('Modifica'),
                          onTap: () => context.push('/workout/${w.id}/edit', extra: w),
                        ),
                        CircleIconButton(
                          icon: Icons.delete_outline_rounded,
                          size: 44,
                          tooltip: tr('Elimina'),
                          onTap: () => _delete(context, ref),
                        ),
                      ],
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        // tutto quello che conta della scheda in una card grande
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(32)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  weekdaysLabel(w.dayOfWeek),
                                  if (w.startTime != null) w.startTime!.label,
                                  if (gymWorkout) tr('Per gli iscritti') else w.isPublic ? tr('Pubblica') : tr('Privata'),
                                ].join(' · '),
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 8),
                              Text(w.name, style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white)),
                              if (gymWorkout && !mine)
                                Text(tr('di {gym}', {'gym': w.gymName ?? tr('la tua palestra')}),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))
                              else if (!mine && w.user != null)
                                GestureDetector(
                                  onTap: () => context.push('/u/${w.user!.username}'),
                                  child: Text(tr('di @{username}', {'username': w.user!.username}),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                ),
                              if (w.description?.isNotEmpty == true) ...[
                                const SizedBox(height: 8),
                                Text(w.description!, style: const TextStyle(color: Colors.white70)),
                              ],
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  _Metric(value: '${w.exercises.length}', label: tr('Esercizi')),
                                  _Metric(value: '$totalSets', label: tr('Serie')),
                                  _Metric(value: estMinutes > 0 ? '~$estMinutes' : '—', label: tr('Minuti')),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        SectionHeader(
                          tr('Esercizi'),
                          action: mine ? tr('+ Aggiungi') : null,
                          onAction: () => _addExercise(context, ref, w),
                        ),
                        if (w.exercises.isEmpty)
                          EmptyState(
                            icon: Icons.playlist_add_rounded,
                            title: tr('Scheda vuota'),
                            message: mine ? tr('Aggiungi il primo esercizio dalla libreria.') : null,
                            action: mine ? tr('Aggiungi esercizio') : null,
                            onAction: () => _addExercise(context, ref, w),
                          ),
                        for (final e in w.exercises)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ExerciseRow(
                              exercise: e,
                              editable: mine,
                              onEdit: () => _editExercise(context, ref, e),
                              onDelete: () => _removeExercise(context, ref, e),
                            ),
                          ),
                        if (mine && !gymWorkout && !gymAccount) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/group/new?workout=${w.id}'),
                            icon: const Icon(Icons.groups_rounded),
                            label: Text(tr('Allenati in gruppo con questa scheda')),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (w.exercises.isNotEmpty && !gymAccount)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: PillActionButton(
                        label: tr('Inizia allenamento'),
                        icon: Icons.play_arrow_rounded,
                        onPressed: () => context.push('/workout/${w.id}/session'),
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

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.editable, required this.onEdit, required this.onDelete});

  final WorkoutExercise exercise;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final card = SoftCard(
      padding: const EdgeInsets.all(14),
      radius: AppRadius.md + 2,
      onTap: editable ? onEdit : null,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
            child: Text('${exercise.position}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.exerciseName ?? tr('Esercizio'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(exercise.summary, style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
              ],
            ),
          ),
          Tag(tr('{seconds}s recupero', {'seconds': exercise.restSeconds}), icon: Icons.hourglass_bottom_rounded, color: AppColors.lilac),
        ],
      ),
    );
    if (!editable) return card;
    return Dismissible(
      key: ValueKey(exercise.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirm(context, title: tr('Rimuovere l\'esercizio?'), ok: tr('Rimuovi'), destructive: true),
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md + 2),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
      ),
      child: card,
    );
  }
}
