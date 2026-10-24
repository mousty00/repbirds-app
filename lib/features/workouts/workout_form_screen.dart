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
import '../../models/json.dart';
import '../../models/workout.dart';
import '../auth/auth_widgets.dart';

/// Modifica di una scheda aperta da URL (link, ricarica sul web): senza la
/// scheda passata come `extra` la carica dal server.
class WorkoutEditScreen extends ConsumerWidget {
  const WorkoutEditScreen({super.key, required this.workoutId, this.initial});

  final String workoutId;
  final Workout? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initial != null) return WorkoutFormScreen(initial: initial);
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: AsyncView<Workout>(
            value: ref.watch(workoutProvider(workoutId)),
            onRetry: () => ref.invalidate(workoutProvider(workoutId)),
            data: (w) => WorkoutFormScreen(initial: w),
          ),
        ),
      ),
    );
  }
}

/// Crea o modifica una scheda (nome, descrizione, giorni, orario, visibilità).
class WorkoutFormScreen extends ConsumerStatefulWidget {
  const WorkoutFormScreen({super.key, this.initial, this.gym = false});

  final Workout? initial;

  /// Nuova scheda della palestra per i suoi iscritti: sempre privata, niente interruttore.
  final bool gym;

  @override
  ConsumerState<WorkoutFormScreen> createState() => _WorkoutFormScreenState();
}

class _WorkoutFormScreenState extends ConsumerState<WorkoutFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _description = TextEditingController(text: widget.initial?.description);
  late final Set<int> _days = {...?widget.initial?.dayOfWeek};
  late TimeOfDayValue? _time = widget.initial?.startTime;
  late bool _public = widget.initial?.isPublic ?? false;
  bool _loading = false;

  bool get _editing => widget.initial != null;

  bool get _gym => widget.gym || widget.initial?.gymId != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _time?.hour ?? 18, minute: _time?.minute ?? 0),
    );
    if (picked != null) setState(() => _time = TimeOfDayValue(picked.hour, picked.minute));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    final input = WorkoutInput(
      id: widget.initial?.id,
      name: _name.text.trim(),
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      isPublic: !_gym && _public,
      dayOfWeek: _days.toList()..sort(),
      startTime: _time,
    );
    final repo = ref.read(workoutRepositoryProvider);
    try {
      if (_editing) {
        await repo.update(input);
        ref.invalidate(workoutProvider(widget.initial!.id));
        ref.invalidate(myWorkoutsProvider);
        if (_gym) ref.invalidate(gymWorkoutsProvider);
        if (mounted) context.pop();
      } else if (_gym) {
        final created = await ref.read(gymRepositoryProvider).createWorkout(input);
        ref.invalidate(gymWorkoutsProvider);
        ref.invalidate(gymProvider);
        if (mounted) context.pushReplacement('/workout/${created.id}');
      } else {
        final created = await repo.create(input);
        ref.invalidate(myWorkoutsProvider);
        if (mounted) context.pushReplacement('/workout/${created.id}');
      }
      ref.invalidate(exploreWorkoutsProvider);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: _editing ? tr('Modifica scheda') : tr('Nuova scheda')),
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: [
                    LabeledField(
                      label: tr('Nome'),
                      controller: _name,
                      hint: tr('es. Push day'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return tr('Dai un nome alla scheda');
                        if (v.trim().length > 100) return tr('Massimo 100 caratteri');
                        return null;
                      },
                    ),
                    LabeledField(
                      label: tr('Descrizione'),
                      controller: _description,
                      hint: tr('Obiettivo, note, intensità…'),
                      maxLines: 3,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 10),
                      child: Text(tr('Giorni'), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
                    ),
                    Row(
                      children: [
                        for (var d = 1; d <= 7; d++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: _DayToggle(
                                label: weekdayShort[d - 1],
                                selected: _days.contains(d),
                                onTap: () => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SoftCard(
                      onTap: _pickTime,
                      padding: const EdgeInsets.all(16),
                      radius: AppRadius.md,
                      child: Row(
                        children: [
                          const IconChip(icon: Icons.schedule_rounded, color: AppColors.lilac),
                          const SizedBox(width: 12),
                          Expanded(child: Text(tr('Orario di inizio'), style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text(_time?.label ?? tr('Nessuno'), style: TextStyle(color: AppColors.inkSoft)),
                          if (_time != null)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(() => _time = null),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_gym)
                      SoftCard(
                        padding: const EdgeInsets.all(16),
                        radius: AppRadius.md,
                        child: Row(
                          children: [
                            const IconChip(icon: Icons.lock_rounded, color: AppColors.amber),
                            const SizedBox(width: 12),
                            Expanded(child: Text(tr('La vedono solo gli iscritti con l\'abbonamento attivo'))),
                          ],
                        ),
                      )
                    else
                    SoftCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      radius: AppRadius.md,
                      child: SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _public,
                        onChanged: (v) => setState(() => _public = v),
                        title: Text(tr('Scheda pubblica'), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(tr('Visibile nella sezione Esplora')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: PrimaryButton(label: _editing ? tr('Salva modifiche') : tr('Crea scheda'), loading: _loading, onPressed: _save),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.card,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: selected ? AppColors.ink : AppColors.stroke),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.onInk : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}
