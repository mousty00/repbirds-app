import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/chat_repository.dart';
import '../../data/providers.dart';
import '../../features/auth/session.dart';
import '../../models/chat.dart';
import '../../models/social.dart';
import '../../models/user.dart';

/// Le chat: amici, gruppi e i canali delle mie palestre, le più recenti in cima.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(conversationsProvider);
    final me = ref.watch(currentUserProvider).username;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              title: tr('Messaggi'),
              actions: [
                CircleIconButton(
                  icon: Icons.edit_square,
                  tooltip: tr('Nuova chat'),
                  onTap: () => _newChat(context, ref),
                ),
              ],
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => refreshChats(ref.invalidate),
                child: AsyncView(
                  value: chats,
                  onRetry: () => ref.invalidate(conversationsProvider),
                  data: (list) => list.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 60),
                          EmptyState(
                            icon: Icons.forum_rounded,
                            title: tr('Nessuna chat'),
                            message: tr('Scrivi a un amico o crea un gruppo. I messaggi sono cifrati end-to-end.'),
                            action: tr('Nuova chat'),
                            onAction: () => _newChat(context, ref),
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _ChatTile(chat: list[i], me: me),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) => const NewChatSheet(),
    );
    if (id != null && context.mounted) {
      ref.invalidate(conversationsProvider);
      context.push('/chats/$id');
    }
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.me});

  final Conversation chat;
  final String me;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final other = chat.other(me);
    final unread = chat.unreadCount > 0;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push('/chats/${chat.id}'),
      child: Row(
        children: [
          ChatAvatar(chat: chat, other: other),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chat.name, style: t.titleMedium, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(chat.encrypted ? Icons.lock_rounded : Icons.campaign_rounded, size: 13, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        switch (chat.type) {
                          ConversationType.gym => tr('Avvisi della palestra'),
                          ConversationType.group => tr('{n} membri', {'n': chat.members.length}),
                          ConversationType.direct => tr('Cifrata end-to-end'),
                        },
                        style: t.bodySmall?.copyWith(color: AppColors.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(timeAgo(chat.lastMessageAt), style: t.bodySmall?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chat.muted) Icon(Icons.notifications_off_rounded, size: 14, color: AppColors.muted),
                  if (unread) ...[const SizedBox(width: 4), CountBadge(count: chat.unreadCount)],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.chat, this.other, this.size = 48});

  final Conversation chat;
  final SimpleUser? other;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (other != null) return UserAvatar(username: other!.username, imageUrl: other!.image, size: size);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: chat.type == ConversationType.gym ? AppColors.mintSoft : AppColors.lilacSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        chat.type == ConversationType.gym ? Icons.fitness_center_rounded : Icons.groups_rounded,
        color: chat.type == ConversationType.gym ? AppColors.mint : AppColors.lilac,
        size: size * 0.5,
      ),
    );
  }
}

/// Nuova chat: con un amico, o un gruppo con alcuni amici. Torna l'id della chat.
class NewChatSheet extends ConsumerStatefulWidget {
  const NewChatSheet({super.key});

  @override
  ConsumerState<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<NewChatSheet> {
  final _name = TextEditingController();
  final _picked = <String>{};
  var _group = false;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Conversation> Function() action) async {
    setState(() => _busy = true);
    try {
      final chat = await action();
      if (mounted) Navigator.pop(context, chat.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final me = ref.watch(currentUserProvider).username;
    final friends = ref.watch(friendsProvider);
    final repo = ref.read(chatRepositoryProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_group ? tr('Nuovo gruppo') : tr('Nuova chat'), style: t.titleLarge),
              const SizedBox(height: 12),
              SegmentedPill(
                options: [tr('Un amico'), tr('Gruppo')],
                index: _group ? 1 : 0,
                onChanged: (i) => setState(() => _group = i == 1),
              ),
              if (_group) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  maxLength: 100,
                  decoration: InputDecoration(labelText: tr('Nome del gruppo')),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: AsyncView(
                  value: friends,
                  data: (list) {
                    final accepted = [
                      for (final f in list)
                        if (f.status == FriendshipStatus.accepted) f.user.username == me ? f.friend : f.user,
                    ];
                    if (accepted.isEmpty) {
                      return EmptyState(
                        icon: Icons.person_add_alt_1_rounded,
                        title: tr('Nessun amico ancora'),
                        message: tr('Puoi scrivere solo agli amici.'),
                      );
                    }
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        for (final u in accepted)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: UserAvatar(username: u.username, imageUrl: u.image, size: 40),
                            title: Text(u.username),
                            trailing: _group
                                ? Checkbox(
                                    value: _picked.contains(u.username),
                                    onChanged: (v) => setState(() => v == true ? _picked.add(u.username) : _picked.remove(u.username)),
                                  )
                                : const Icon(Icons.chevron_right_rounded),
                            onTap: _busy
                                ? null
                                : _group
                                    ? () => setState(() => _picked.contains(u.username) ? _picked.remove(u.username) : _picked.add(u.username))
                                    : () => _run(() => repo.openDirect(u.username)),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (_group) ...[
                const SizedBox(height: 12),
                PrimaryButton(
                  label: tr('Crea gruppo'),
                  loading: _busy,
                  onPressed: _picked.isEmpty || _name.text.trim().isEmpty
                      ? null
                      : () => _run(() => repo.createGroup(_name.text.trim(), _picked.toList())),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
