import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/ui.dart';
import '../../data/notification_repository.dart';
import '../../data/providers.dart';
import '../../data/social_repository.dart';
import '../../data/workout_repository.dart';
import '../../models/group.dart';
import '../../models/notification.dart';
import '../../models/social.dart';
import '../../core/widgets/skeleton.dart';

/// Richieste di amicizia, inviti ai gruppi e attività recenti (like, commenti...).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    _markAllRead();
  }

  // Aprire la schermata vale come lettura: la lista mostra ancora quali erano nuove.
  Future<void> _markAllRead() async {
    try {
      await ref.read(activityProvider.future);
      await ref.read(notificationRepositoryProvider).markAllRead();
      ref.invalidate(unreadActivityProvider);
    } catch (_) {
      // il badge resta com'è
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(friendRequestsProvider);
    final invites = ref.watch(groupInvitesProvider);
    final activity = ref.watch(activityProvider);
    final loading = requests.isLoading || invites.isLoading || activity.isLoading;
    final r = requests.value ?? const <Friendship>[];
    final i = invites.value ?? const <GroupMember>[];
    // richieste e inviti ancora aperti hanno già la loro riga con i bottoni
    final a = (activity.value ?? const <AppNotification>[])
        .where((n) => n.kind != NotificationKind.friendRequest && n.kind != NotificationKind.groupInvite)
        .toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Notifiche')),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  refreshNotifications(ref.invalidate);
                  return ref.refresh(friendRequestsProvider.future);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    if (loading && r.isEmpty && i.isEmpty && a.isEmpty)
                      const SkeletonList(item: SkeletonTile(leading: 44, circle: true, trailing: true), count: 3, padding: EdgeInsets.zero)
                    else if (r.isEmpty && i.isEmpty && a.isEmpty)
                      EmptyState(icon: Icons.notifications_none_rounded, title: tr('Tutto tranquillo'), message: tr('Nessuna richiesta, invito o attività.'))
                    else ...[
                      if (r.isNotEmpty) ...[
                        SectionHeader(tr('Richieste di amicizia · {count}', {'count': r.length})),
                        for (final (k, f) in r.indexed)
                          FadeInUp(index: k, child: Padding(padding: const EdgeInsets.only(bottom: 10), child: FriendRequestTile(request: f))),
                        const SizedBox(height: 12),
                      ],
                      if (i.isNotEmpty) ...[
                        SectionHeader(tr('Inviti ai gruppi · {count}', {'count': i.length})),
                        for (final (k, m) in i.indexed)
                          FadeInUp(index: r.length + k, child: Padding(padding: const EdgeInsets.only(bottom: 10), child: GroupInviteTile(member: m))),
                        const SizedBox(height: 12),
                      ],
                      if (a.isNotEmpty) ...[
                        SectionHeader(tr('Attività')),
                        for (final (k, n) in a.indexed)
                          FadeInUp(index: r.length + i.length + k, child: Padding(padding: const EdgeInsets.only(bottom: 10), child: ActivityTile(notification: n))),
                      ],
                    ],
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

/// Una riga di attività: chi, cosa, quando. Il tap apre il post, il gruppo o il profilo.
class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.notification});

  final AppNotification notification;

  IconData get _icon => switch (notification.kind) {
        NotificationKind.postLiked => Icons.favorite_rounded,
        NotificationKind.postCommented => Icons.chat_bubble_rounded,
        NotificationKind.groupInvite || NotificationKind.groupInviteAccepted => Icons.groups_rounded,
        NotificationKind.runInvite || NotificationKind.runInviteAccepted => Icons.directions_run_rounded,
        NotificationKind.routeSaved => Icons.bookmark_added_rounded,
        NotificationKind.workoutShared => Icons.fitness_center_rounded,
        _ => Icons.person_add_alt_1_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final actor = n.actor;
    final route = n.route;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      radius: AppRadius.md + 2,
      onTap: route == null ? null : () => context.push(route),
      child: Row(
        children: [
          if (actor != null)
            UserAvatar(username: actor.username, imageUrl: actor.image, size: 42)
          else
            const CircleAvatar(radius: 21, child: Icon(Icons.notifications_rounded)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    if (actor != null)
                      TextSpan(text: '@${actor.username} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: n.text),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: n.read ? FontWeight.w400 : FontWeight.w600),
                ),
                Text(timeAgo(n.createdAt), style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(_icon, size: 20, color: n.read ? AppColors.inkSoft : Theme.of(context).colorScheme.primary),
        ],
      ),
    );
  }
}

class FriendRequestTile extends ConsumerStatefulWidget {
  const FriendRequestTile({super.key, required this.request});

  final Friendship request;

  @override
  ConsumerState<FriendRequestTile> createState() => _FriendRequestTileState();
}

class _FriendRequestTileState extends ConsumerState<FriendRequestTile> {
  bool _busy = false;

  Future<void> _act(bool accept) async {
    setState(() => _busy = true);
    final repo = ref.read(friendshipRepositoryProvider);
    try {
      accept ? await repo.accept(widget.request.id) : await repo.reject(widget.request.id);
      ref.invalidate(friendRequestsProvider);
      ref.invalidate(friendsProvider);
      ref.invalidate(friendsPostsProvider);
      if (mounted) showMessage(context, accept ? tr('Ora siete amici!') : tr('Richiesta rifiutata'));
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = widget.request.user;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      radius: AppRadius.md + 2,
      onTap: () => context.push('/u/${from.username}'),
      child: Row(
        children: [
          UserAvatar(username: from.username, imageUrl: from.image, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@${from.username}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(tr('vuole allenarsi con te · {time}', {'time': timeAgo(widget.request.createdAt)}),
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
              ],
            ),
          ),
          if (_busy)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            CircleIconButton(icon: Icons.close_rounded, size: 40, tooltip: tr('Rifiuta'), onTap: () => _act(false)),
            const SizedBox(width: 8),
            CircleIconButton(icon: Icons.check_rounded, size: 40, dark: true, tooltip: tr('Accetta'), onTap: () => _act(true)),
          ],
        ],
      ),
    );
  }
}

class GroupInviteTile extends ConsumerStatefulWidget {
  const GroupInviteTile({super.key, required this.member});

  final GroupMember member;

  @override
  ConsumerState<GroupInviteTile> createState() => _GroupInviteTileState();
}

class _GroupInviteTileState extends ConsumerState<GroupInviteTile> {
  bool _busy = false;

  Future<void> _act(bool accept) async {
    setState(() => _busy = true);
    final repo = ref.read(groupRepositoryProvider);
    try {
      accept ? await repo.acceptInvite(widget.member.id) : await repo.rejectInvite(widget.member.id);
      ref.invalidate(groupInvitesProvider);
      ref.invalidate(groupsProvider);
      if (!mounted) return;
      showMessage(context, accept ? tr('Sei nel gruppo!') : tr('Invito rifiutato'));
      if (accept) context.push('/group/${widget.member.groupId}');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(14),
      radius: AppRadius.md + 2,
      color: AppColors.lilacSoft,
      child: Row(
        children: [
          IconChip(icon: Icons.groups_rounded, color: AppColors.lilac, background: AppColors.card, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.member.groupName ?? tr('Invito a un allenamento di gruppo'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  _subtitle(widget.member),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                ),
              ],
            ),
          ),
          if (_busy)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            CircleIconButton(icon: Icons.close_rounded, size: 40, tooltip: tr('Rifiuta'), onTap: () => _act(false)),
            const SizedBox(width: 8),
            CircleIconButton(icon: Icons.check_rounded, size: 40, dark: true, tooltip: tr('Accetta'), onTap: () => _act(true)),
          ],
        ],
      ),
    );
  }
}

/// "da @marco · sab 17 ott alle 09:00", o quando è arrivato l'invito se il
/// backend non manda il riepilogo del gruppo.
String _subtitle(GroupMember m) {
  final parts = [
    if (m.groupCreatedBy != null) tr('da @{username}', {'username': m.groupCreatedBy}),
    if (m.groupScheduledFor != null) formatDayTime(m.groupScheduledFor),
  ];
  return parts.isEmpty ? timeAgo(m.createdAt) : parts.join(' · ');
}
