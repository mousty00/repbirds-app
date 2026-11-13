import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/workout_repository.dart';
import '../../models/group.dart';
import '../auth/session.dart';
import '../running/geo.dart';

/// Una sessione del gruppo: chi c'è, chi no, chi non ha risposto. Mentre è
/// aperta si rilegge ogni pochi secondi (e così si risulta "collegati"): quando
/// l'organizzatore la avvia, si entra nell'allenamento insieme, dallo stesso istante.
class GroupSessionScreen extends ConsumerStatefulWidget {
  const GroupSessionScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<GroupSessionScreen> createState() => _GroupSessionScreenState();
}

class _GroupSessionScreenState extends ConsumerState<GroupSessionScreen> {
  static const _poll = Duration(seconds: 3);

  GroupSession? _session;
  ApiException? _error;
  Timer? _timer;
  bool _busy = false;
  bool _entered = false;

  GroupRepository get _repo => ref.read(groupRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_poll, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _show(await _repo.session(widget.sessionId));
    } on ApiException catch (e) {
      if (mounted && _session == null) setState(() => _error = e);
    }
  }

  void _show(GroupSession s) {
    if (!mounted) return;
    setState(() {
      _session = s;
      _error = null;
    });
    final me = ref.read(currentUserProvider).username;
    final inIt = s.organizer.username == me || s.myStatus == Attendance.going;
    // appena l'organizzatore avvia: dentro tutti i presenti collegati, insieme
    if (s.started && inIt && !_entered && DateTime.now().difference(s.startedAt!) < const Duration(minutes: 1)) {
      _enter(s);
    }
  }

  void _enter(GroupSession s) {
    _entered = true;
    _timer?.cancel();
    context.pushReplacement(
      s.isRun
          ? '/running/run?route=${s.routeId}'
          : '/workout/${s.workoutId}/session?group=${s.groupId}&start=${Uri.encodeComponent(s.startedAt!.toUtc().toIso8601String())}',
    );
  }

  Future<void> _run(Future<GroupSession> Function() action) async {
    setState(() => _busy = true);
    try {
      _show(await action());
      ref.invalidate(groupSessionsProvider(_session!.groupId));
      ref.invalidate(upcomingSessionsProvider);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final s = _session!;
    final waiting = s.attendees.where((a) => !a.organizer && a.status == Attendance.going && a.connected).length;
    final ok = await confirm(
      context,
      title: tr('Avviare la sessione?'),
      message: waiting == 1
          ? tr('Parte adesso per te e per 1 persona collegata.')
          : tr('Parte adesso per te e per {n} persone collegate.', {'n': waiting}),
      ok: tr('Avvia'),
    );
    if (ok && mounted) await _run(() => _repo.start(s.id));
  }

  Future<void> _delete() async {
    final s = _session!;
    if (!await confirm(context, title: tr('Eliminare la sessione?'), ok: tr('Elimina'), destructive: true)) return;
    try {
      await _repo.deleteSession(s.id);
      ref.invalidate(groupSessionsProvider(s.groupId));
      ref.invalidate(upcomingSessionsProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final me = ref.watch(currentUserProvider).username;
    final isOrganizer = s != null && s.organizer.username == me;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              title: s?.groupName ?? '',
              actions: [
                if (isOrganizer && !s.started)
                  CircleIconButton(icon: Icons.delete_outline_rounded, size: 44, tooltip: tr('Elimina'), onTap: _delete),
              ],
            ),
            Expanded(
              child: s == null
                  ? (_error != null
                      ? EmptyState(icon: Icons.error_outline_rounded, title: _error!.message, action: tr('Riprova'), onAction: _load)
                      : const SkeletonDetail())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      children: [
                        _HeroCard(session: s),
                        const SizedBox(height: 14),
                        if (!isOrganizer && !s.started) ...[
                          Row(
                            children: [
                              Expanded(
                                child: _Choice(
                                  label: tr('Partecipo'),
                                  selected: s.myStatus == Attendance.going,
                                  color: AppColors.mint,
                                  onTap: _busy ? null : () => _run(() => _repo.answer(s.id, going: true)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _Choice(
                                  label: tr('Non vengo'),
                                  selected: s.myStatus == Attendance.declined,
                                  color: AppColors.danger,
                                  onTap: _busy ? null : () => _run(() => _repo.answer(s.id, going: false)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                        ],
                        _People(title: tr('Presenti'), people: s.withStatus(Attendance.going), color: AppColors.mint, showConnected: !s.started),
                        _People(title: tr('Assenti'), people: s.withStatus(Attendance.declined), color: AppColors.danger),
                        _People(title: tr('Da rispondere'), people: s.withStatus(Attendance.pending), color: AppColors.muted, showConnected: !s.started),
                      ],
                    ),
            ),
            if (s != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _BottomAction(
                  session: s,
                  isOrganizer: isOrganizer,
                  busy: _busy,
                  onStart: _start,
                  onEnter: () => _enter(s),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.session});

  final GroupSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final soft = TextStyle(color: Colors.white.withValues(alpha: 0.75));
    return Material(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: () => context.push(s.isRun ? '/running/route/${s.routeId}' : '/workout/${s.workoutId}'),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.started
                    ? tr('Partita alle {time}', {'time': formatTime(s.startedAt!.toLocal())})
                    : s.scheduledFor != null
                        ? formatDayTime(s.scheduledFor!.toLocal())
                        : tr('Da programmare'),
                style: soft,
              ),
              const SizedBox(height: 6),
              Text(s.workoutName, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
              if (s.isRun)
                Text(
                  [
                    tr('Corsa'),
                    if (s.distanceM != null) formatDistance(s.distanceM!),
                    if (s.meetingPoint != null) tr('ritrovo: {place}', {'place': s.meetingPoint!}),
                  ].join(' · '),
                  style: soft,
                ),
              const SizedBox(height: 4),
              Text(tr('Organizzata da @{username}', {'username': s.organizer.username}), style: soft),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.color, required this.onTap});

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? color : AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.ink),
            ),
          ),
        ),
      );
}

class _People extends StatelessWidget {
  const _People({required this.title, required this.people, required this.color, this.showConnected = false});

  final String title;
  final List<SessionAttendee> people;
  final Color color;
  final bool showConnected;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(tr('{title} · {n}', {'title': title, 'n': people.length})),
          for (final a in people)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SoftCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                radius: AppRadius.md,
                onTap: () => context.push('/u/${a.user.username}'),
                child: Row(
                  children: [
                    UserAvatar(username: a.user.username, imageUrl: a.user.image, size: 40),
                    const SizedBox(width: 12),
                    Expanded(child: Text('@${a.user.username}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    if (a.organizer) Tag(tr('Organizzatore'), color: AppColors.brand),
                    if (showConnected && a.connected) ...[
                      const SizedBox(width: 6),
                      Tag(tr('Collegato'), color: AppColors.mint, icon: Icons.circle),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.session,
    required this.isOrganizer,
    required this.busy,
    required this.onStart,
    required this.onEnter,
  });

  final GroupSession session;
  final bool isOrganizer;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final s = session;
    if (s.started) {
      if (!isOrganizer && s.myStatus != Attendance.going) return const SizedBox.shrink();
      return PrimaryButton(label: tr('Entra nell\'allenamento'), icon: Icons.play_arrow_rounded, onPressed: onEnter);
    }
    if (isOrganizer) {
      return PrimaryButton(label: tr('Avvia per tutti'), icon: Icons.play_arrow_rounded, loading: busy, onPressed: onStart);
    }
    if (s.myStatus != Attendance.going) return const SizedBox.shrink();
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr('In attesa che @{username} avvii la sessione: parte da sola.', {'username': s.organizer.username}),
              style: TextStyle(color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}
