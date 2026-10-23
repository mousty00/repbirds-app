import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/workout_repository.dart';
import '../../models/workout.dart';
import '../auth/session.dart';
import '../../core/widgets/skeleton.dart';

/// I miei esercizi: creati da me più quelli salvati dal profilo di altri,
/// filtrabili per gruppo muscolare. Gli esercizi pubblici degli altri non
/// compaiono qui finché non li salvi.
class ExercisesScreen extends ConsumerStatefulWidget {
  const ExercisesScreen({super.key, this.title});

  /// Dentro la tab Allenati: il selettore di sezione al posto del titolo.
  final Widget? title;

  @override
  ConsumerState<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends ConsumerState<ExercisesScreen> {
  String _query = '';
  String? _group;

  Future<void> _delete(Exercise e) async {
    if (!await confirm(context, title: tr('Eliminare "{name}"?', {'name': e.name}), ok: tr('Elimina'), destructive: true)) return;
    try {
      await ref.read(workoutRepositoryProvider).deleteExercise(e.id);
      ref.invalidate(exercisesProvider);
    } on ApiException catch (err) {
      if (mounted) showMessage(context, err.message, error: true);
    }
  }

  Future<void> _unsave(Exercise e) async {
    if (!await confirm(context,
        title: tr('Togliere "{name}" dai tuoi esercizi?', {'name': e.name}),
        message: tr('Le schede che lo usano lo tengono.'),
        ok: tr('Togli'))) {
      return;
    }
    try {
      await ref.read(workoutRepositoryProvider).unsaveExercise(e.id);
      ref.invalidate(exercisesProvider);
    } on ApiException catch (err) {
      if (mounted) showMessage(context, err.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final exercises = ref.watch(exercisesProvider);
    final groups = {...muscleGroups, ...?exercises.value?.map((e) => e.muscleGroup)}.toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              title: tr('Esercizi'),
              titleWidget: widget.title,
              actions: [
                CircleIconButton(
                  icon: Icons.add_rounded,
                  dark: true,
                  size: 44,
                  tooltip: tr('Nuovo esercizio'),
                  onTap: () => showCreateExerciseSheet(context),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SearchPill(hint: tr('Cerca un esercizio'), onChanged: (v) => setState(() => _query = v.toLowerCase())),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final g in [null, ...groups])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(g == null ? tr('Tutti') : muscleGroupLabel(g)),
                        selected: _group == g,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _group = g),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(exercisesProvider.future),
                child: AsyncView<List<Exercise>>(
                  value: exercises,
                  onRetry: () => ref.invalidate(exercisesProvider),
                  loading: const SkeletonList(),
                  data: (list) {
                    final filtered = list.where((e) {
                      final matchQ = _query.isEmpty || e.name.toLowerCase().contains(_query);
                      final matchG = _group == null || e.muscleGroup.toLowerCase() == _group!.toLowerCase();
                      return matchQ && matchG;
                    }).toList();
                    if (filtered.isEmpty) {
                      return ListView(children: [
                        EmptyState(
                          icon: Icons.fitness_center_rounded,
                          title: tr('Nessun esercizio'),
                          message: tr('Crea un esercizio personalizzato da usare nelle tue schede, o salvane uno dal profilo di un amico.'),
                          action: tr('Crea esercizio'),
                          onAction: () => showCreateExerciseSheet(context),
                        ),
                      ]);
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        final mine = e.createdBy == me.username;
                        return SoftCard(
                          padding: const EdgeInsets.all(14),
                          radius: AppRadius.md + 2,
                          child: Row(
                            children: [
                              IconChip(icon: _iconFor(e.muscleGroup), color: _colorFor(i)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(
                                      [
                                        muscleGroupLabel(e.muscleGroup),
                                        if (!mine && e.createdBy != null) tr('di @{username}', {'username': e.createdBy}),
                                        if (e.description?.isNotEmpty == true) e.description!,
                                      ].join(' · '),
                                      style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (mine && !e.isPublic) Tag(tr('Privato'), color: AppColors.inkSoft),
                              if (mine)
                                IconButton(
                                  icon: Icon(Icons.delete_outline_rounded, color: AppColors.muted),
                                  onPressed: () => _delete(e),
                                )
                              else
                                IconButton(
                                  tooltip: tr('Togli dai miei esercizi'),
                                  icon: const Icon(Icons.bookmark_rounded, color: AppColors.lilac),
                                  onPressed: () => _unsave(e),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _colorFor(int i) => [AppColors.blue, AppColors.lilac, AppColors.pink, AppColors.mint][i % 4];

  static IconData _iconFor(String group) {
    final g = group.toLowerCase();
    if (g.contains('cardio')) return Icons.directions_run_rounded;
    if (g.contains('gamb') || g.contains('glut')) return Icons.directions_walk_rounded;
    if (g.contains('addom') || g.contains('core')) return Icons.self_improvement_rounded;
    return Icons.fitness_center_rounded;
  }
}

/// Sheet di creazione esercizio; restituisce l'esercizio creato.
Future<Exercise?> showCreateExerciseSheet(BuildContext context) {
  return showModalBottomSheet<Exercise>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => const _CreateExerciseSheet(),
  );
}

class _CreateExerciseSheet extends ConsumerStatefulWidget {
  const _CreateExerciseSheet();

  @override
  ConsumerState<_CreateExerciseSheet> createState() => _CreateExerciseSheetState();
}

class _CreateExerciseSheetState extends ConsumerState<_CreateExerciseSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _group = muscleGroups.first;
  bool _public = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showMessage(context, tr('Dai un nome all\'esercizio'), error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final ex = await ref.read(workoutRepositoryProvider).createExercise(
            name: _name.text.trim(),
            muscleGroup: _group,
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            isPublic: _public,
          );
      ref.invalidate(exercisesProvider);
      if (mounted) Navigator.pop(context, ex);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Nuovo esercizio'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: InputDecoration(hintText: tr('Nome (es. Panca piana)'))),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(hintText: tr('Descrizione (opzionale)')),
            ),
            const SizedBox(height: 16),
            Text(tr('Gruppo muscolare'), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in muscleGroups)
                  ChoiceChip(
                    label: Text(muscleGroupLabel(g)),
                    selected: _group == g,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _group = g),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _public,
              onChanged: (v) => setState(() => _public = v),
              title: Text(tr('Visibile a tutti'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(tr('Lo vedono nel tuo profilo e possono salvarlo nei loro esercizi')),
            ),
            const SizedBox(height: 12),
            PrimaryButton(label: tr('Crea esercizio'), loading: _loading, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
