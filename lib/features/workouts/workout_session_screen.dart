import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/notifications/rest_alarm.dart';
import '../../core/sound/sounds.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/workout_repository.dart';
import '../../models/workout.dart';
import '../body/body_photo_prompt.dart';
import 'saved_session.dart';
import 'session_progress.dart';

/// Sessione live, una card alla volta: la serie da fare, oppure solo il
/// recupero. Durata e recupero si calcolano dagli orari, quindi restano giusti
/// anche se esci dall'app; a fine recupero arriva una notifica.
class WorkoutSessionScreen extends ConsumerStatefulWidget {
  const WorkoutSessionScreen({super.key, required this.workoutId, this.groupId, this.startedAt});

  final String workoutId;
  final String? groupId;

  /// Inizio comune di una sessione di gruppo; altrimenti adesso.
  final DateTime? startedAt;

  @override
  ConsumerState<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends ConsumerState<WorkoutSessionScreen> with WidgetsBindingObserver {
  late DateTime _startedAt = widget.startedAt?.toLocal() ?? DateTime.now();
  /// Sessione salvata da riprendere (stessa scheda), letta all'apertura.
  SavedSession? _resume;
  bool _resumeChecked = false;
  final _notes = TextEditingController();
  SessionProgress? _progress;
  Timer? _ticker;
  DateTime? _restEndsAt;
  int _restTotal = 0;
  WorkoutExercise? _lastDone;
  bool _saving = false;

  Duration get _elapsed => DateTime.now().difference(_startedAt);
  int get _restLeft {
    final end = _restEndsAt;
    if (end == null) return 0;
    final ms = end.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RestAlarm.requestPermission();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    SavedSession.load().then((s) {
      if (!mounted) return;
      setState(() {
        _resumeChecked = true;
        if (s != null && s.workoutId == widget.workoutId) {
          _resume = s;
          _startedAt = s.startedAt;
          _restEndsAt = s.restEndsAt != null && s.restEndsAt!.isAfter(DateTime.now()) ? s.restEndsAt : null;
          _restTotal = s.restTotal;
          _notes.text = s.notes;
        }
      });
      _syncLiveActivity();
    });
  }

  DateTime? _liveEndsAt;

  /// Live Activity allineata al recupero (parte e finisce con lui).
  void _syncLiveActivity() {
    if (_restEndsAt == _liveEndsAt) return;
    _liveEndsAt = _restEndsAt;
    RestAlarm.liveActivity(_restEndsAt, title: tr('Recupero'), subtitle: _workoutName);
  }

  String get _workoutName => ref.read(workoutProvider(widget.workoutId)).value?.name ?? 'RepBirds';

  /// Salva lo stato a ogni passo: se il sistema chiude l'app, si riparte da qui.
  void _save() {
    _syncLiveActivity();
    final p = _progress;
    if (p == null) return;
    SavedSession(
      workoutId: widget.workoutId,
      groupId: widget.groupId,
      startedAt: _startedAt,
      done: p.done,
      focus: p.focusIndex,
      restEndsAt: _restEndsAt,
      restTotal: _restTotal,
      notes: _notes.text,
    ).save();
  }

  void _tick() {
    if (_restEndsAt != null && _restLeft == 0) {
      _restEndsAt = null;
      _save();
      HapticFeedback.heavyImpact();
      Sounds.play(Sound.restEnd);
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _save();
      final end = _restEndsAt;
      if (end != null && end.isAfter(DateTime.now())) {
        RestAlarm.schedule(end, title: tr('Recupero finito'), body: tr('Tocca a te: prossima serie!'));
        RestAlarm.showCountdown(end, title: tr('Recupero'), subtitle: _workoutName);
      }
    } else if (state == AppLifecycleState.resumed) {
      RestAlarm.cancel();
      // finito mentre eri fuori: la notifica è già arrivata, niente suono doppio
      if (_restEndsAt != null && _restLeft == 0) {
        setState(() => _restEndsAt = null);
        _save();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RestAlarm.cancel();
    RestAlarm.liveActivity(null);
    _ticker?.cancel();
    _notes.dispose();
    super.dispose();
  }

  void _completeSet(SessionProgress p) {
    final e = p.completeSet();
    if (e == null) return;
    Sounds.play(Sound.rep);
    setState(() {
      _lastDone = e;
      // dopo l'ultima serie di tutta la scheda niente recupero
      if (!p.allDone && e.restSeconds > 0) {
        _restTotal = e.restSeconds;
        _restEndsAt = DateTime.now().add(Duration(seconds: e.restSeconds));
      }
    });
    _save();
  }

  void _addRest(int seconds) {
    setState(() {
      _restEndsAt = _restEndsAt?.add(Duration(seconds: seconds));
      _restTotal += seconds;
    });
    _save();
  }

  void _skipRest() {
    setState(() => _restEndsAt = null);
    _save();
  }

  void _undoLast(SessionProgress p) {
    setState(() {
      if (_lastDone != null) p.undo(_lastDone!);
      _lastDone = null;
      _restEndsAt = null;
    });
    _save();
  }

  Future<void> _finish(Workout w) async {
    final ok = await confirm(context, title: tr('Terminare l\'allenamento?'), message: tr('La sessione verrà salvata nello storico.'), ok: tr('Termina'));
    if (!ok) return;
    setState(() => _saving = true);
    try {
      final historyId = await ref.read(workoutRepositoryProvider).logSession(
            workoutId: w.id,
            groupId: widget.groupId,
            startedAt: _startedAt,
            completedAt: DateTime.now(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      ref.invalidate(historyProvider);
      if (widget.groupId != null) ref.invalidate(groupHistoryProvider(widget.groupId!));
      await SavedSession.clear();
      Sounds.play(Sound.finish);
      if (!mounted) return;
      showMessage(context, tr('Allenamento salvato. Grande! 💪'));
      final photo = await showBodyPhotoPrompt(context, workoutHistoryId: historyId);
      if (!mounted) return;
      if (photo) showMessage(context, tr('Foto salvata nel calendario'));
      context.pop();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    final leave = await confirm(context, title: tr('Abbandonare la sessione?'), message: tr('I progressi non verranno salvati.'), ok: tr('Esci'), destructive: true);
    if (!leave || !mounted) return;
    await SavedSession.clear();
    if (mounted) context.pop();
  }

  void _showList(Workout w, SessionProgress p) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => _ExerciseListSheet(
        progress: p,
        notes: _notes,
        saving: _saving,
        onPick: (e) {
          Navigator.pop(ctx);
          setState(() {
            p.focus(e);
            _restEndsAt = null;
          });
          _save();
        },
        onFinish: () {
          Navigator.pop(ctx);
          _finish(w);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workout = ref.watch(workoutProvider(widget.workoutId));
    // Pieghevole mezzo aperto e appoggiato: la serie o il recupero sopra la piega,
    // da leggere da lontano; tutti i comandi sotto, sulla parte appoggiata.
    final fold = tabletopFold(context);
    final top = MediaQuery.paddingOf(context).top + 4;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: AsyncView<Workout>(
            value: workout,
            onRetry: () => ref.invalidate(workoutProvider(widget.workoutId)),
            loading: const SkeletonDetail(),
            data: (w) {
              if (!_resumeChecked) return const SkeletonDetail();
              final p = _progress ??= SessionProgress(w.exercises)..restore(_resume?.done ?? const {}, _resume?.focus ?? 0);
              final resting = _restEndsAt != null;
              final bar = Row(
                children: [
                  CircleIconButton(icon: Icons.close_rounded, size: 44, tooltip: tr('Esci'), onTap: _leave),
                  Expanded(
                    child: resting
                        ? const SizedBox.shrink()
                        : Text(
                            formatClock(_elapsed),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                  ),
                  CircleIconButton(
                    icon: Icons.checklist_rounded,
                    size: 44,
                    tooltip: tr('Esercizi della scheda'),
                    onTap: () => _showList(w, p),
                  ),
                ],
              );
              final card = resting
                  ? _RestCard(left: _restLeft, total: _restTotal, elapsed: _elapsed)
                  : p.allDone
                      ? _DoneCard(progress: p)
                      : _SetCard(progress: p);
              final Widget actions = resting
                  ? Row(
                      children: [
                        Expanded(child: _SoftButton(label: tr('Annulla serie'), onTap: () => _undoLast(p))),
                        const SizedBox(width: 10),
                        Expanded(child: _SoftButton(label: tr('+15 s'), onTap: () => _addRest(15))),
                        const SizedBox(width: 10),
                        Expanded(child: _SoftButton(label: tr('Salta'), onTap: _skipRest)),
                      ],
                    )
                  : p.allDone
                      ? PrimaryButton(label: tr('Termina e salva'), icon: Icons.check_rounded, loading: _saving, onPressed: () => _finish(w))
                      : PrimaryButton(
                          label: tr('Serie fatta'),
                          icon: Icons.check_rounded,
                          color: AppColors.mint,
                          onPressed: () => _completeSet(p),
                        );
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: fold == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [bar, const SizedBox(height: 12), Expanded(child: card), const SizedBox(height: 12), actions],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: math.max(0, fold.top - top - 12), child: card),
                          SizedBox(height: fold.height + 24),
                          bar,
                          const Spacer(),
                          actions,
                          const Spacer(),
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// La serie da fare: esercizio, serie, ripetizioni e peso. Sull'ultima serie,
/// e solo lì, cosa arriva dopo. Sul viola del logo, testo bianco.
class _SetCard extends StatelessWidget {
  const _SetCard({required this.progress});

  final SessionProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final e = p.current!;
    final next = p.isLastSet ? p.next : null;
    final weight = e.weight != null && e.weight! > 0 ? ' × ${_kg(e.weight!)}' : '';
    final muted = TextStyle(color: Colors.white.withValues(alpha: 0.65));
    return _BigCard(
      color: AppColors.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Esercizio {n} di {total}', {'n': p.currentIndex! + 1, 'total': p.exercises.length}), style: muted),
          const SizedBox(height: 4),
          Text(
            e.exerciseName ?? tr('Esercizio'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const Spacer(),
          Text(
            p.isLastSet ? tr('Ultima serie') : tr('Serie {n} di {total}', {'n': p.currentSet, 'total': e.sets}),
            style: muted,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${e.reps}$weight',
              style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w800, height: 1.1),
            ),
          ),
          Text(tr('ripetizioni'), style: muted),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < e.sets; i++)
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < p.doneOf(e) ? AppColors.mint : null,
                    border: i < p.doneOf(e)
                        ? null
                        : Border.all(color: Colors.white.withValues(alpha: i == p.doneOf(e) ? 1 : 0.35), width: 1.5),
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (next != null) ...[
            Divider(color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 6),
            Text(tr('A seguire'), style: muted),
            Text(
              next.exerciseName ?? tr('Esercizio'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  static String _kg(double w) => '${w == w.roundToDouble() ? w.toInt() : w} kg';
}

/// Durante il recupero solo il conto alla rovescia; la durata dell'allenamento
/// in piccolo nella stessa card.
class _RestCard extends StatelessWidget {
  const _RestCard({required this.left, required this.total, required this.elapsed});

  final int left;
  final int total;
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    // giallo mentre riposi, rosso negli ultimi 10 secondi: si capisce senza leggere
    final ending = left <= 10;
    final fg = ending ? Colors.white : LightColors.ink;
    final soft = TextStyle(color: fg.withValues(alpha: 0.75));
    return _BigCard(
      color: ending ? AppColors.danger : AppColors.amber,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(tr('Recupero'), style: soft.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatClock(Duration(seconds: left)),
              style: TextStyle(
                color: fg,
                fontSize: 110,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total > 0 ? left / total : 0,
                minHeight: 6,
                color: fg,
                backgroundColor: fg.withValues(alpha: 0.2),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            tr('Allenamento {time}', {'time': formatClock(elapsed)}),
            style: soft.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.progress});

  final SessionProgress progress;

  @override
  Widget build(BuildContext context) {
    return _BigCard(
      color: AppColors.mint,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 64),
          const SizedBox(height: 12),
          Text(
            tr('Tutti gli esercizi fatti!'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            tr('{done} / {total} serie completate', {'done': progress.doneSets, 'total': progress.totalSets}),
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _BigCard extends StatelessWidget {
  const _BigCard({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(36)),
        child: child,
      );
}

class _SoftButton extends StatelessWidget {
  const _SoftButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SoftCard(
        onTap: onTap,
        radius: AppRadius.md,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

/// Gli esercizi della scheda, con il check verde su quelli finiti. Toccandone
/// uno ci vai; in fondo le note e "Termina e salva".
class _ExerciseListSheet extends StatelessWidget {
  const _ExerciseListSheet({
    required this.progress,
    required this.notes,
    required this.saving,
    required this.onPick,
    required this.onFinish,
  });

  final SessionProgress progress;
  final TextEditingController notes;
  final bool saving;
  final ValueChanged<WorkoutExercise> onPick;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              Text(tr('Esercizi della scheda'), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                tr('{done} / {total} serie completate', {'done': p.doneSets, 'total': p.totalSets}),
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              for (final e in p.exercises)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: p.isComplete(e) ? null : () => onPick(e),
                  leading: p.isComplete(e)
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.mint, size: 28)
                      : Icon(
                          e == p.current ? Icons.play_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: e == p.current ? AppColors.blue : AppColors.muted,
                          size: 28,
                        ),
                  title: Text(e.exerciseName ?? tr('Esercizio'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(e.summary),
                  trailing: Text('${p.doneOf(e)}/${e.sets}', style: TextStyle(color: AppColors.inkSoft)),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(hintText: tr('Note sulla sessione (opzionale)')),
              ),
              const SizedBox(height: 14),
              PrimaryButton(label: tr('Termina e salva'), icon: Icons.check_rounded, loading: saving, onPressed: onFinish),
            ],
          ),
        ),
      ),
    );
  }
}
