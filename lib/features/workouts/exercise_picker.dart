import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../models/workout.dart';
import '../exercises/exercises_screen.dart';
import '../../core/widgets/skeleton.dart';

/// Sheet per aggiungere/modificare un esercizio della scheda.
Future<WorkoutExerciseInput?> showExerciseEditor(
  BuildContext context, {
  required String workoutId,
  required int position,
  WorkoutExercise? initial,
}) {
  return showModalBottomSheet<WorkoutExerciseInput>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ExerciseEditor(workoutId: workoutId, position: position, initial: initial),
  );
}

class _ExerciseEditor extends ConsumerStatefulWidget {
  const _ExerciseEditor({required this.workoutId, required this.position, this.initial});

  final String workoutId;
  final int position;
  final WorkoutExercise? initial;

  @override
  ConsumerState<_ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends ConsumerState<_ExerciseEditor> {
  late String? _exerciseId = widget.initial?.exerciseId;
  late String? _exerciseName = widget.initial?.exerciseName;
  late int _sets = widget.initial?.sets ?? 3;
  late int _reps = widget.initial?.reps ?? 10;
  late double _weight = widget.initial?.weight ?? 0;
  late int _rest = widget.initial?.restSeconds ?? 90;
  String _query = '';

  void _save() {
    if (_exerciseId == null) {
      showMessage(context, tr('Scegli un esercizio'), error: true);
      return;
    }
    Navigator.pop(
      context,
      WorkoutExerciseInput(
        id: widget.initial?.id,
        workoutId: widget.workoutId,
        exerciseId: _exerciseId!,
        sets: _sets,
        reps: _reps,
        weight: _weight > 0 ? _weight : null,
        restSeconds: _rest,
        position: widget.position,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(exercisesProvider);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.initial == null ? tr('Aggiungi esercizio') : tr('Modifica esercizio'), style: t.headlineSmall),
                  ),
                  CircleIconButton(
                    icon: Icons.add_rounded,
                    size: 40,
                    tooltip: tr('Nuovo esercizio'),
                    onTap: () async {
                      final created = await showCreateExerciseSheet(context);
                      if (created != null) {
                        setState(() {
                          _exerciseId = created.id;
                          _exerciseName = created.name;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SearchPill(hint: tr('Cerca esercizio'), onChanged: (v) => setState(() => _query = v.toLowerCase())),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: AsyncView<List<Exercise>>(
                value: exercises,
                onRetry: () => ref.invalidate(exercisesProvider),
                loading: const SkeletonList(
                  item: SkeletonTile(leading: 0),
                  spacing: 8,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                ),
                data: (list) {
                  final filtered = list
                      .where((e) => _query.isEmpty || e.name.toLowerCase().contains(_query) || e.muscleGroup.toLowerCase().contains(_query))
                      .toList();
                  if (filtered.isEmpty) {
                    return Center(child: Text(tr('Nessun esercizio trovato'), style: TextStyle(color: AppColors.muted)));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      final selected = e.id == _exerciseId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: selected ? AppColors.ink : AppColors.card,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            onTap: () => setState(() {
                              _exerciseId = e.id;
                              _exerciseName = e.name;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: selected ? AppColors.onInk : AppColors.ink,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    muscleGroupLabel(e.muscleGroup),
                                    style: TextStyle(fontSize: 12, color: selected ? AppColors.onInk.withValues(alpha: 0.7) : AppColors.muted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                boxShadow: AppShadows.float,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_exerciseName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(_exerciseName!, style: t.titleMedium),
                      ),
                    Row(
                      children: [
                        Expanded(child: Stepper2(label: tr('Serie'), value: '$_sets', onMinus: () => setState(() => _sets = (_sets - 1).clamp(1, 20)), onPlus: () => setState(() => _sets = (_sets + 1).clamp(1, 20)))),
                        const SizedBox(width: 8),
                        Expanded(child: Stepper2(label: tr('Ripetizioni'), value: '$_reps', onMinus: () => setState(() => _reps = (_reps - 1).clamp(1, 100)), onPlus: () => setState(() => _reps = (_reps + 1).clamp(1, 100)))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Stepper2(
                            label: tr('Peso (kg)'),
                            value: _weight == _weight.roundToDouble() ? '${_weight.toInt()}' : _weight.toStringAsFixed(1),
                            onMinus: () => setState(() => _weight = (_weight - 2.5).clamp(0, 500)),
                            onPlus: () => setState(() => _weight = (_weight + 2.5).clamp(0, 500)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Stepper2(
                            label: tr('Recupero'),
                            value: '${_rest}s',
                            onMinus: () => setState(() => _rest = (_rest - 15).clamp(0, 600)),
                            onPlus: () => setState(() => _rest = (_rest + 15).clamp(0, 600)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(label: widget.initial == null ? tr('Aggiungi alla scheda') : tr('Salva'), onPressed: _save),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contatore compatto − valore +.
class Stepper2 extends StatelessWidget {
  const Stepper2({super.key, required this.label, required this.value, required this.onMinus, required this.onPlus});

  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback onTap) => Material(
          color: AppColors.card,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 18)),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
                Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          btn(Icons.remove_rounded, onMinus),
          const SizedBox(width: 4),
          btn(Icons.add_rounded, onPlus),
        ],
      ),
    );
  }
}
