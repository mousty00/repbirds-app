import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/social_repository.dart';
import '../../models/social.dart';
import '../auth/session.dart';
import 'moderation.dart';
import 'post_card.dart';
import '../../core/widgets/skeleton.dart';
import '../share/share_actions.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(postRepositoryProvider).comment(postId: widget.postId, content: text);
      _comment.clear();
      ref.invalidate(postProvider(widget.postId));
      refreshPosts(ref);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(SimpleComment c) async {
    if (!await confirm(context, title: tr('Eliminare il commento?'), ok: tr('Elimina'), destructive: true)) return;
    try {
      await ref.read(postRepositoryProvider).deleteComment(c.id);
      ref.invalidate(postProvider(widget.postId));
      refreshPosts(ref);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _editPost(Post post) async {
    final controller = TextEditingController(text: post.content);
    final saved = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Modifica post'), style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 16),
            TextField(controller: controller, maxLines: 5, minLines: 3, maxLength: 2000, autofocus: true),
            const SizedBox(height: 16),
            PrimaryButton(label: tr('Salva'), onPressed: () => Navigator.pop(ctx, controller.text.trim())),
          ],
        ),
      ),
    );
    controller.dispose();
    if (saved == null || saved.isEmpty) return;
    try {
      await ref.read(postRepositoryProvider).update(id: post.id, content: saved);
      ref.invalidate(postProvider(widget.postId));
      refreshPosts(ref);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _deletePost(Post post) async {
    if (!await confirm(context, title: tr('Eliminare il post?'), message: tr('L\'azione non si può annullare.'), ok: tr('Elimina'), destructive: true)) {
      return;
    }
    try {
      await ref.read(postRepositoryProvider).delete(post.id);
      refreshPosts(ref);
      ref.invalidate(userPostsProvider(post.user.username));
      if (mounted) closePage(context);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final post = ref.watch(postProvider(widget.postId));
    final isMine = post.value?.user.username == me.username;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              title: tr('Post'),
              actions: [
                if (post.value != null)
                  CircleIconButton(
                    icon: Icons.ios_share_rounded,
                    size: 44,
                    tooltip: tr('Condividi'),
                    onTap: () => sharePost(context, post.value!),
                  ),
                if (isMine)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    color: AppColors.card,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    onSelected: (v) => v == 'edit' ? _editPost(post.value!) : _deletePost(post.value!),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'edit', child: Text(tr('Modifica'))),
                      PopupMenuItem(value: 'delete', child: Text(tr('Elimina'), style: const TextStyle(color: AppColors.danger))),
                    ],
                  )
                else if (post.value != null)
                  ModerationMenu(
                    type: 'POST',
                    targetId: post.value!.id,
                    username: post.value!.user.username,
                    onBlocked: () => closePage(context),
                  ),
              ],
            ),
            Expanded(
              child: AsyncView<Post>(
                value: post,
                onRetry: () => ref.invalidate(postProvider(widget.postId)),
                loading: const SkeletonList(item: SkeletonPost(), count: 1),
                data: (p) {
                  final comments = [...p.comments]
                    ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      PostCard(post: p, openOnTap: false),
                      const SizedBox(height: 20),
                      SectionHeader(tr('Commenti · {count}', {'count': comments.length})),
                      if (comments.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(tr('Nessun commento. Scrivi il primo!'), style: TextStyle(color: AppColors.muted)),
                        ),
                      for (final c in comments)
                        _CommentTile(
                          comment: c,
                          // il backend lascia eliminare un commento solo a chi l'ha scritto
                          canDelete: c.username == me.username,
                          onDelete: () => _deleteComment(c),
                          onBlocked: () => ref.invalidate(postProvider(widget.postId)),
                        ),
                    ],
                  );
                },
              ),
            ),
            _CommentComposer(controller: _comment, sending: _sending, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.canDelete, required this.onDelete, required this.onBlocked});

  final SimpleComment comment;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onBlocked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.push('/u/${comment.username}'),
            child: UserAvatar(username: comment.username, imageUrl: comment.userImage, size: 36),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onLongPress: canDelete ? onDelete : null,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(AppRadius.md),
                    bottomLeft: Radius.circular(AppRadius.md),
                    bottomRight: Radius.circular(AppRadius.md),
                    topLeft: Radius.circular(6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(comment.username, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(width: 8),
                        Text(timeAgo(comment.createdAt), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        const Spacer(),
                        if (canDelete)
                          GestureDetector(
                            onTap: onDelete,
                            child: Icon(Icons.close_rounded, size: 16, color: AppColors.muted),
                          )
                        else
                          ModerationMenu(
                            type: 'COMMENT',
                            targetId: comment.id,
                            username: comment.username,
                            onBlocked: onBlocked,
                            small: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(comment.content, style: TextStyle(color: AppColors.ink, height: 1.35)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra di input a pillola con pulsante invio scuro.
class _CommentComposer extends StatelessWidget {
  const _CommentComposer({required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.of(context).viewInsets.bottom * 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(40),
                boxShadow: AppShadows.soft,
              ),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                // limite del backend
                maxLength: 1000,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: tr('Scrivi un commento…'),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: AppColors.ink,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: sending ? null : onSend,
              child: SizedBox(
                width: 58,
                height: 58,
                child: sending
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onInk),
                      )
                    : Icon(Icons.send_rounded, color: AppColors.onInk),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
