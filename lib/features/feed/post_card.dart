import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/social_repository.dart';
import '../../models/social.dart';
import '../auth/session.dart';

/// Post nel feed: autore, foto, testo, like e commenti.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post, this.openOnTap = true, this.onChanged});

  final Post post;
  final bool openOnTap;
  final ValueChanged<Post>? onChanged;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  late Post _post = widget.post;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant PostCard old) {
    super.didUpdateWidget(old);
    if (old.post != widget.post) _post = widget.post;
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
    final me = ref.read(currentUserProvider);
    final repo = ref.read(postRepositoryProvider);
    final existing = _post.likeBy(me.username);
    final before = _post;
    setState(() {
      _busy = true;
      _post = existing != null
          ? _post.copyWith(
              likes: _post.likes.where((l) => l.id != existing.id).toList(),
              numLikes: (_post.numLikes - 1).clamp(0, 1 << 30),
            )
          : _post.copyWith(
              likes: [..._post.likes, SimpleLike(id: 'pending', username: me.username)],
              numLikes: _post.numLikes + 1,
            );
    });
    try {
      if (existing != null) {
        await repo.unlike(existing.id);
      } else {
        final like = await repo.like(postId: _post.id, userId: me.id);
        setState(() {
          _post = _post.copyWith(
            likes: [..._post.likes.where((l) => l.id != 'pending'), like],
          );
        });
      }
      widget.onChanged?.call(_post);
    } on ApiException catch (e) {
      // 409 = il like c'era già, 404 = era già stato tolto: questa copia del post
      // era vecchia. Si rilegge dal server invece di mostrare un errore.
      final stale = e.statusCode == 409 || e.statusCode == 404;
      final fresh = stale ? await _reload(repo) : null;
      if (mounted) {
        setState(() => _post = fresh ?? before);
        if (fresh == null) showMessage(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Le altre liste (feed, profilo, dettaglio) hanno ancora il post vecchio.
    if (mounted) refreshPost(ref, _post);
  }

  Future<Post?> _reload(PostRepository repo) async {
    try {
      return await repo.byId(_post.id);
    } on ApiException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final liked = _post.likeBy(me.username) != null;
    final t = Theme.of(context).textTheme;

    return SoftCard(
      padding: const EdgeInsets.all(12),
      onTap: widget.openOnTap ? () => context.push('/posts/${_post.id}') : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
            child: GestureDetector(
              onTap: () => context.push('/u/${_post.user.username}'),
              child: Row(
                children: [
                  UserAvatar(username: _post.user.username, imageUrl: _post.user.image, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_post.user.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(timeAgo(_post.createdAt), style: t.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (AppImage.supports(_post.image))
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AspectRatio(
                aspectRatio: 4 / 3.4,
                child: AppImage(
                  _post.image!,
                  fallback: Container(
                    color: AppColors.blueSoft,
                    child: Icon(Icons.image_not_supported_outlined, color: AppColors.muted),
                  ),
                ),
              ),
            ),
          if (_post.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
              child: Text(_post.content, style: t.bodyLarge?.copyWith(color: AppColors.ink, height: 1.4)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
            child: Row(
              children: [
                _ActionPill(
                  icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? AppColors.pink : AppColors.inkSoft,
                  label: '${_post.numLikes}',
                  onTap: _toggleLike,
                ),
                const SizedBox(width: 8),
                _ActionPill(
                  icon: Icons.chat_bubble_outline_rounded,
                  color: AppColors.inkSoft,
                  label: '${_post.numComments}',
                  onTap: () => context.push('/posts/${_post.id}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
