import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/running_repository.dart';
import '../../models/running.dart';
import '../../models/social.dart';
import '../auth/session.dart';
import 'geo.dart';
import 'route_map.dart';
import 'running_screen.dart';

class RunEventDetailScreen extends ConsumerWidget {
  const RunEventDetailScreen({super.key, required this.eventId});

  final String eventId;

  void _refresh(WidgetRef ref) {
    ref.invalidate(runEventProvider(eventId));
    ref.invalidate(runEventsProvider);
  }

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() action, {String? done, bool pop = false}) async {
    try {
      await action();
      _refresh(ref);
      refreshNotifications(ref.invalidate);
      if (!context.mounted) return;
      if (done != null) showMessage(context, done);
      if (pop) context.pop();
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _invite(BuildContext context, WidgetRef ref, RunEvent event) async {
    final username = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _InviteSheet(event: event),
    );
    if (username == null || !context.mounted) return;
    await _act(context, ref, () => ref.read(runningRepositoryProvider).invite(event.id, username), done: tr('Invito inviato a @{username}', {'username': username}));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).username;
    final repo = ref.read(runningRepositoryProvider);
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: AsyncView<RunEvent>(
            value: ref.watch(runEventProvider(eventId)),
            onRetry: () => ref.invalidate(runEventProvider(eventId)),
            loading: const SkeletonDetail(),
            data: (event) {
              final mine = event.participants.where((p) => p.user.username == me).firstOrNull;
              final runs = ref.watch(eventRunsProvider(event.id));
              return Column(
                children: [
                  TopBar(
                    title: '',
                    actions: [
                      if (event.isOwner)
                        CircleIconButton(
                          icon: Icons.delete_outline_rounded,
                          size: 44,
                          tooltip: tr('Elimina'),
                          onTap: () async {
                            if (!await confirm(context, title: tr('Annullare la corsa?'), ok: tr('Annulla corsa'), destructive: true)) return;
                            if (context.mounted) await _act(context, ref, () => repo.deleteEvent(event.id), pop: true);
                          },
                        )
                      else if (mine != null && !event.isInvited)
                        CircleIconButton(
                          icon: Icons.logout_rounded,
                          size: 44,
                          tooltip: tr('Non partecipo più'),
                          onTap: () => _act(context, ref, () => repo.removeParticipant(mine.id), pop: true),
                        ),
                    ],
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(eventRunsProvider(event.id));
                        return ref.refresh(runEventProvider(eventId).future);
                      },
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Tag(formatDayTime(event.startsAt), icon: Icons.schedule_rounded, color: AppColors.ink),
                          ),
                          const SizedBox(height: 12),
                          Text(event.title, style: Theme.of(context).textTheme.displaySmall),
                          const SizedBox(height: 6),
                          Text(tr('Organizzata da @{username}', {'username': event.createdBy.username}), style: TextStyle(color: AppColors.inkSoft)),
                          const SizedBox(height: 18),
                          RouteMap(
                            route: event.route.points,
                            height: 240,
                            extraMarkers: [
                              if (event.meeting != null)
                                pointMarker(event.meeting!, color: AppColors.pink, icon: Icons.people_alt_rounded, size: 28),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SoftCard(
                            padding: const EdgeInsets.all(14),
                            radius: AppRadius.md,
                            onTap: () => context.push('/running/route/${event.route.id}'),
                            child: Row(
                              children: [
                                const IconChip(icon: Icons.route_rounded, color: AppColors.blue),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(event.route.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      Text(
                                        [
                                          formatDistance(event.route.distanceM),
                                          if (event.route.elevationGainM != null) '+${event.route.elevationGainM} m',
                                        ].join(' · '),
                                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                              ],
                            ),
                          ),
                          if (event.meetingPoint != null && event.meetingPoint!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _InfoRow(icon: Icons.place_rounded, text: tr('Ritrovo: {place}', {'place': event.meetingPoint})),
                          ],
                          if (event.notes != null && event.notes!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _InfoRow(icon: Icons.notes_rounded, text: event.notes!),
                          ],
                          if (event.isInvited) ...[
                            const SizedBox(height: 18),
                            SoftCard(
                              color: AppColors.pinkSoft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(tr('@{username} ti ha invitato', {'username': event.createdBy.username}), style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () => _act(context, ref, () => repo.reject(event.id), pop: true),
                                          child: Text(tr('Rifiuta')),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: PrimaryButton(
                                          label: tr('Partecipo'),
                                          onPressed: () => _act(context, ref, () => repo.accept(event.id), done: tr('Ci vediamo lì!')),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          SectionHeader(
                            tr('Partecipanti'),
                            action: event.isOwner ? tr('+ Invita') : null,
                            onAction: () => _invite(context, ref, event),
                          ),
                          _PersonTile(username: event.createdBy.username, image: event.createdBy.image, status: tr('Organizza')),
                          for (final p in event.participants)
                            _PersonTile(
                              username: p.user.username,
                              image: p.user.image,
                              status: p.status == RunParticipantStatus.accepted ? tr('Partecipa') : tr('Invitato'),
                              muted: p.status != RunParticipantStatus.accepted,
                              onRemove: event.isOwner
                                  ? () => _act(context, ref, () => repo.removeParticipant(p.id))
                                  : null,
                            ),
                          const SizedBox(height: 22),
                          SectionHeader(tr('Risultati')),
                          AsyncView<List<RunActivity>>(
                            value: runs,
                            loading: const SkeletonList(item: SkeletonTile(trailing: true), count: 2, spacing: 8, padding: EdgeInsets.zero),
                            onRetry: () => ref.invalidate(eventRunsProvider(event.id)),
                            data: (list) => list.isEmpty
                                ? Text(tr('Nessuno ha ancora registrato la corsa.'), style: TextStyle(color: AppColors.muted))
                                : Column(
                                    children: [
                                      for (final r in list)
                                        Padding(padding: const EdgeInsets.only(bottom: 8), child: RunTile(run: r, showUser: true)),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (event.canRun)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: PillActionButton(
                        label: tr('Inizia la corsa'),
                        icon: Icons.directions_run_rounded,
                        onPressed: () => context.push('/running/run?event=${event.id}&route=${event.route.id}'),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.inkSoft),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.inkSoft))),
        ],
      );
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.username, this.image, required this.status, this.muted = false, this.onRemove});

  final String username;
  final String? image;
  final String status;
  final bool muted;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        radius: AppRadius.md,
        onTap: () => context.push('/u/$username'),
        child: Row(
          children: [
            UserAvatar(username: username, imageUrl: image, size: 40),
            const SizedBox(width: 12),
            Expanded(child: Text('@$username', style: const TextStyle(fontWeight: FontWeight.w600))),
            Tag(status, color: muted ? AppColors.muted : AppColors.mint),
            if (onRemove != null)
              IconButton(icon: Icon(Icons.close_rounded, size: 18, color: AppColors.muted), onPressed: onRemove),
          ],
        ),
      ),
    );
  }
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.event});

  final RunEvent event;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _username = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  void _send(String v) {
    if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).username;
    final already = {widget.event.createdBy.username, ...widget.event.participants.map((p) => p.user.username)};
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Invita'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _username,
                    decoration: InputDecoration(hintText: tr('Username')),
                    inputFormatters: usernameFormatters,
                    autocorrect: false,
                    onSubmitted: _send,
                  ),
                ),
                const SizedBox(width: 10),
                CircleIconButton(icon: Icons.send_rounded, dark: true, onTap: () => _send(_username.text)),
              ],
            ),
            const SizedBox(height: 16),
            Text(tr('I tuoi amici'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncView<List<Friendship>>(
                value: ref.watch(friendsProvider),
                onRetry: () => ref.invalidate(friendsProvider),
                data: (list) {
                  final candidates = list.map((f) => f.other(me)).where((u) => !already.contains(u.username)).toList();
                  if (candidates.isEmpty) {
                    return Center(child: Text(tr('Nessun amico da invitare'), style: TextStyle(color: AppColors.muted)));
                  }
                  return ListView(
                    children: [
                      for (final u in candidates)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: UserAvatar(username: u.username, imageUrl: u.image, size: 40),
                          title: Text('@${u.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Tag(tr('Invita')),
                          onTap: () => Navigator.pop(context, u.username),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
