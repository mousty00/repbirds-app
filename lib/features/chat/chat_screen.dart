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
import '../../features/auth/session.dart';
import '../../models/chat.dart';
import '../../models/user.dart';
import 'chats_screen.dart';

/// Una chat: i messaggi (decifrati su questo telefono) e la casella per scrivere.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _pending = <ChatMessage>[];
  var _sending = false;

  String get _id => widget.conversationId;

  @override
  void initState() {
    super.initState();
    _markRead();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    try {
      await ref.read(chatRepositoryProvider).markRead(_id);
      if (!mounted) return;
      ref.invalidate(conversationsProvider);
      ref.invalidate(chatUnreadProvider);
    } catch (_) {
      // Non è grave: i non letti si sistemano alla prossima apertura.
    }
  }

  Future<void> _send(Conversation chat) async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    final me = ref.read(currentUserProvider);
    final local = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: _id,
      sender: SimpleUser(id: me.id, username: me.username, image: me.image),
      text: text,
      createdAt: DateTime.now(),
      pending: true,
    );
    setState(() {
      _sending = true;
      _pending.insert(0, local);
      _text.clear();
    });
    try {
      final repo = ref.read(chatRepositoryProvider);
      if (chat.type == ConversationType.gym) {
        await repo.announce(text);
      } else {
        await repo.send(chat, text);
      }
      if (!mounted) return;
      ref.invalidate(chatMessagesProvider(_id));
      await ref.read(chatMessagesProvider(_id).future).catchError((_) => <ChatMessage>[]);
      if (mounted) setState(() => _pending.remove(local));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pending.remove(local);
        if (_text.text.isEmpty) _text.text = text;
      });
      showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(conversationProvider(_id));
    final messages = ref.watch(chatMessagesProvider(_id));
    final me = ref.watch(currentUserProvider);
    final c = chat.value;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              title: c?.name ?? '',
              actions: [
                if (c != null)
                  CircleIconButton(
                    icon: Icons.info_outline_rounded,
                    tooltip: tr('Dettagli'),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppColors.card,
                      builder: (_) => ChatInfoSheet(conversationId: _id),
                    ),
                  ),
              ],
            ),
            if (c != null) _Banner(chat: c),
            Expanded(
              child: AsyncView(
                value: messages,
                onRetry: () => ref.invalidate(chatMessagesProvider(_id)),
                data: (list) {
                  final all = [..._pending, ...list];
                  if (all.isEmpty) {
                    return EmptyState(
                      icon: c?.encrypted == false ? Icons.campaign_rounded : Icons.lock_rounded,
                      title: tr('Ancora nessun messaggio'),
                      message: c?.encrypted == false
                          ? tr('Qui arrivano gli avvisi della palestra.')
                          : tr('Solo voi potete leggere quello che scrivete qui.'),
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: all.length,
                    itemBuilder: (_, i) => _Bubble(
                      message: all[i],
                      mine: all[i].sender.username == me.username,
                      showSender: c?.type != ConversationType.direct,
                    ),
                  );
                },
              ),
            ),
            if (c != null && c.canWrite) _Composer(controller: _text, sending: _sending, onSend: () => _send(c)),
            if (c != null && !c.canWrite)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr('Solo la palestra può scrivere qui.'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.chat});

  final Conversation chat;

  @override
  Widget build(BuildContext context) {
    final e2e = chat.encrypted;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: e2e ? AppColors.mintSoft : AppColors.blueSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(e2e ? Icons.lock_rounded : Icons.campaign_rounded, size: 16, color: e2e ? AppColors.mint : AppColors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              e2e
                  ? tr('Cifrata end-to-end: le chiavi restano sui vostri telefoni, il server vede solo testo cifrato.')
                  : tr('Canale della palestra: non è cifrato end-to-end, la palestra e RepBirds possono leggerlo.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.showSender});

  final ChatMessage message;
  final bool mine;
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final unreadable = message.text == null;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: mine ? AppColors.ink : AppColors.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: mine ? null : AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSender && !mine)
                Text(message.sender.username, style: t.labelSmall?.copyWith(color: AppColors.lilac, fontWeight: FontWeight.w700)),
              Text(
                unreadable ? tr('Messaggio non leggibile su questo dispositivo') : message.text!,
                style: t.bodyMedium?.copyWith(
                  color: mine ? AppColors.onInk : (unreadable ? AppColors.muted : AppColors.ink),
                  fontStyle: unreadable ? FontStyle.italic : null,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeAgo(message.createdAt),
                    style: t.labelSmall?.copyWith(color: mine ? AppColors.onInk.withValues(alpha: 0.6) : AppColors.muted),
                  ),
                  if (message.pending) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.schedule_rounded, size: 11, color: AppColors.onInk.withValues(alpha: 0.6)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: tr('Scrivi un messaggio'), counterText: ''),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          CircleIconButton(icon: Icons.send_rounded, tooltip: tr('Invia'), onTap: sending ? null : onSend),
        ],
      ),
    );
  }
}

/// Dettagli: codice di sicurezza, membri, silenzia, esci dal gruppo.
class ChatInfoSheet extends ConsumerStatefulWidget {
  const ChatInfoSheet({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatInfoSheet> createState() => _ChatInfoSheetState();
}

class _ChatInfoSheetState extends ConsumerState<ChatInfoSheet> {
  Future<String>? _code;

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(conversationProvider(widget.conversationId));
      ref.invalidate(conversationsProvider);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final me = ref.watch(currentUserProvider);
    final repo = ref.read(chatRepositoryProvider);
    final chat = ref.watch(conversationProvider(widget.conversationId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: AsyncView(
          value: chat,
          data: (c) => ListView(
            shrinkWrap: true,
            children: [
              Row(
                children: [
                  ChatAvatar(chat: c, other: c.other(me.username), size: 44),
                  const SizedBox(width: 12),
                  Expanded(child: Text(c.name, style: t.titleLarge)),
                ],
              ),
              const SizedBox(height: 16),
              if (c.encrypted) ...[
                Text(tr('Codice di sicurezza'), style: t.titleSmall),
                const SizedBox(height: 4),
                Text(
                  tr('Confrontalo con gli altri di persona: se è uguale su tutti i telefoni, nessuno si è messo in mezzo.'),
                  style: t.bodySmall?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                FutureBuilder<String>(
                  future: _code ??= repo.securityCode(c.id),
                  builder: (_, s) => SoftCard(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      s.data ?? (s.hasError ? tr('Non disponibile') : '…'),
                      textAlign: TextAlign.center,
                      style: t.titleMedium?.copyWith(fontFamily: 'monospace', letterSpacing: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Silenzia notifiche')),
                value: c.muted,
                onChanged: (v) => _act(() => repo.mute(c.id, v)),
              ),
              if (c.type == ConversationType.group) ...[
                const SizedBox(height: 8),
                Text(tr('{n} membri', {'n': c.members.length}), style: t.titleSmall),
                for (final m in c.members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(username: m.user.username, imageUrl: m.user.image, size: 36),
                    title: Text(m.user.username),
                    subtitle: m.admin ? Text(tr('Amministratore')) : null,
                    trailing: c.admin && m.user.username != me.username
                        ? IconButton(
                            tooltip: tr('Rimuovi'),
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                            onPressed: () => _act(() => repo.removeMember(c.id, m.user.id)),
                          )
                        : null,
                  ),
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
                  label: Text(tr('Esci dal gruppo'), style: const TextStyle(color: AppColors.danger)),
                  onPressed: () async {
                    final ok = await confirm(context, title: tr('Esci dal gruppo'), ok: tr('Esci'), destructive: true);
                    if (!ok || !context.mounted) return;
                    try {
                      await repo.removeMember(c.id, me.id);
                      if (!context.mounted) return;
                      ref.invalidate(conversationsProvider);
                      Navigator.pop(context);
                      context.go('/chats');
                    } on ApiException catch (e) {
                      if (context.mounted) showMessage(context, e.message, error: true);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lato palestra: gli avvisi mandati a tutti i soci (non cifrati end-to-end).
class GymChannelScreen extends ConsumerStatefulWidget {
  const GymChannelScreen({super.key});

  @override
  ConsumerState<GymChannelScreen> createState() => _GymChannelScreenState();
}

class _GymChannelScreenState extends ConsumerState<GymChannelScreen> {
  final _text = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(chatRepositoryProvider).announce(text);
      _text.clear();
      ref.invalidate(gymChannelProvider);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(gymChannelProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Avvisi ai soci')),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                tr('Ogni avviso arriva a tutti i soci attivi con una notifica. Non è cifrato end-to-end.'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ),
            Expanded(
              child: AsyncView(
                value: list,
                onRetry: () => ref.invalidate(gymChannelProvider),
                data: (items) => items.isEmpty
                    ? EmptyState(icon: Icons.campaign_rounded, title: tr('Ancora nessun avviso'))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _Bubble(message: items[i], mine: true, showSender: false),
                      ),
              ),
            ),
            _Composer(controller: _text, sending: _sending, onSend: _send),
          ],
        ),
      ),
    );
  }
}
