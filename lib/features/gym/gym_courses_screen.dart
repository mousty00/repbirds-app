import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../models/gym.dart';
import '../../models/json.dart';
import '../../models/workout.dart';
import '../auth/auth_widgets.dart';
import 'gym_widgets.dart';

/// Corsi settimanali. Gli iscritti li vedono nell'app e si iscrivono da soli; la
/// palestra può anche iscriverli (ricevono una notifica) e vede chi c'è.
class GymCoursesScreen extends ConsumerWidget {
  const GymCoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(gymCoursesProvider);
    void edit([GymCourse? course]) => showGymSheet<void>(
      context,
      title: course == null ? tr('Nuovo corso') : tr('Modifica corso'),
      builder: (_) => _CourseForm(course: course),
    );
    return GymPage(
      title: tr('Corsi'),
      onRefresh: () async {
        ref.invalidate(gymCoursesProvider);
        await ref.read(gymCoursesProvider.future).catchError((_) => <GymCourse>[]);
      },
      fab: FloatingActionButton.extended(
        heroTag: 'gym-add-course',
        onPressed: edit,
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Nuovo corso')),
      ),
      children: [
        AsyncView<List<GymCourse>>(
          value: courses,
          onRetry: () => ref.invalidate(gymCoursesProvider),
          data: (list) => list.isEmpty
              ? EmptyState(
                  icon: Icons.event_rounded,
                  title: tr('Nessun corso'),
                  message: tr('Spinning, yoga, functional: gli iscritti li vedono nell\'app e si prenotano.'),
                  action: tr('Crea corso'),
                  onAction: edit,
                )
              : Column(
                  children: [
                    for (final c in list)
                      CourseCard(
                        course: c,
                        onTap: () => showGymSheet<void>(
                          context,
                          title: c.name,
                          builder: (_) => _CourseSheet(course: c),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// "Lun · Mer · 18:30 · 45 min"
String courseWhen(GymCourse c) => [
  weekdaysLabel(c.dayOfWeek),
  if (c.startTime != null) c.startTime!.label,
  if (c.durationMinutes != null) tr('{n} min', {'n': c.durationMinutes}),
].join(' · ');

/// Card di un corso (dashboard e lato iscritto). [trailing] al posto dei posti liberi.
class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.course, this.onTap, this.trailing});

  final GymCourse course;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = course;
    final seats = c.capacity == null ? tr('{n} iscritti', {'n': c.enrolledCount}) : '${c.enrolledCount}/${c.capacity}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        radius: AppRadius.md,
        child: Row(
          children: [
            const IconChip(icon: Icons.event_rounded, color: AppColors.pink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(courseWhen(c), style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                  if (c.instructor != null || c.room != null)
                    Text(
                      [c.instructor, c.room].whereType<String>().join(' · '),
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ?? Tag(seats, color: c.full ? AppColors.danger : AppColors.blue, icon: Icons.people_alt_rounded),
          ],
        ),
      ),
    );
  }
}

class _CourseForm extends ConsumerStatefulWidget {
  const _CourseForm({this.course});

  final GymCourse? course;

  @override
  ConsumerState<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends ConsumerState<_CourseForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.course?.name);
  late final _description = TextEditingController(text: widget.course?.description);
  late final _instructor = TextEditingController(text: widget.course?.instructor);
  late final _room = TextEditingController(text: widget.course?.room);
  late final _duration = TextEditingController(text: widget.course?.durationMinutes?.toString() ?? '45');
  late final _capacity = TextEditingController(text: widget.course?.capacity?.toString());
  late final Set<int> _days = {...?widget.course?.dayOfWeek};
  late TimeOfDayValue? _time = widget.course?.startTime;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _instructor, _room, _duration, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _time?.hour ?? 18, minute: _time?.minute ?? 0),
    );
    if (picked != null) setState(() => _time = TimeOfDayValue(picked.hour, picked.minute));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(gymRepositoryProvider)
          .saveCourse(
            GymCourseInput(
              id: widget.course?.id,
              name: _name.text.trim(),
              description: _text(_description),
              instructor: _text(_instructor),
              room: _text(_room),
              dayOfWeek: _days.toList()..sort(),
              startTime: _time,
              durationMinutes: int.tryParse(_duration.text),
              capacity: int.tryParse(_capacity.text),
            ),
          );
      ref.invalidate(gymCoursesProvider);
      ref.invalidate(gymProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: tr('Eliminare il corso?'),
      message: tr('Gli iscritti al corso non lo vedranno più.'),
      ok: tr('Elimina'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(gymRepositoryProvider).deleteCourse(widget.course!.id);
      ref.invalidate(gymCoursesProvider);
      ref.invalidate(gymProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(label: tr('Nome'), controller: _name, hint: tr('es. Spinning'), validator: requiredField),
          Row(
            children: [
              Expanded(
                child: LabeledField(label: tr('Istruttore'), controller: _instructor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(label: tr('Sala'), controller: _room),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Text(
              tr('Giorni'),
              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(weekdayShort[d - 1]),
                  selected: _days.contains(d),
                  onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SoftCard(
            onTap: _pickTime,
            padding: const EdgeInsets.all(16),
            radius: AppRadius.md,
            child: Row(
              children: [
                const IconChip(icon: Icons.schedule_rounded, color: AppColors.lilac),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr('Orario di inizio'), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(_time?.label ?? tr('Nessuno'), style: TextStyle(color: AppColors.inkSoft)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: tr('Durata (min)'),
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (v != null && v.isNotEmpty && (n == null || n < 5 || n > 600)) return tr('Da 5 a 600');
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  label: tr('Posti'),
                  controller: _capacity,
                  hint: tr('Senza limite'),
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  validator: (v) => v != null && v.isNotEmpty && (int.tryParse(v) ?? 0) < 1 ? tr('Almeno 1') : null,
                ),
              ),
            ],
          ),
          LabeledField(label: tr('Descrizione'), controller: _description, maxLines: 2),
          PrimaryButton(label: tr('Salva'), loading: _saving, onPressed: _save),
          if (widget.course != null)
            TextButton(
              onPressed: _delete,
              child: Text(tr('Elimina corso'), style: const TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}

/// Chi è iscritto a un corso, con "Iscrivi" per aggiungere un iscritto della palestra.
class _CourseSheet extends ConsumerStatefulWidget {
  const _CourseSheet({required this.course});

  final GymCourse course;

  @override
  ConsumerState<_CourseSheet> createState() => _CourseSheetState();
}

class _CourseSheetState extends ConsumerState<_CourseSheet> {
  final _username = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  void _reload() {
    ref.invalidate(gymEnrollmentsProvider(widget.course.id));
    ref.invalidate(gymCoursesProvider);
  }

  Future<void> _add() async {
    if (_username.text.trim().isEmpty) return;
    setState(() => _adding = true);
    try {
      await ref.read(gymRepositoryProvider).enroll(widget.course.id, _username.text.trim());
      _username.clear();
      _reload();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    final enrollments = ref.watch(gymEnrollmentsProvider(c.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(courseWhen(c), style: TextStyle(color: AppColors.inkSoft)),
        if (c.description?.isNotEmpty == true) ...[const SizedBox(height: 6), Text(c.description!)],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _username,
                inputFormatters: usernameFormatters,
                decoration: InputDecoration(hintText: tr('Username di un iscritto')),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _adding ? null : _add, child: Text(tr('Iscrivi'))),
          ],
        ),
        const SizedBox(height: 16),
        AsyncView<List<GymEnrollment>>(
          value: enrollments,
          onRetry: _reload,
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(tr('Ancora nessuno iscritto'), textAlign: TextAlign.center),
                )
              : Column(
                  children: [
                    for (final e in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: UserAvatar(username: e.user.username, imageUrl: e.user.image, size: 40),
                        title: Text('@${e.user.username}'),
                        trailing: IconButton(
                          tooltip: tr('Togli dal corso'),
                          icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger),
                          onPressed: () async {
                            try {
                              await ref.read(gymRepositoryProvider).unenroll(c.id, e.user.id);
                              _reload();
                            } on ApiException catch (err) {
                              if (context.mounted) showMessage(context, err.message, error: true);
                            }
                          },
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
