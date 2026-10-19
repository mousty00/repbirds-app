import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/social_repository.dart';
import '../../data/user_repository.dart';
import '../../models/social.dart';
import '../../models/user.dart';
import '../auth/session.dart';
import 'notifications_screen.dart';
import '../../core/widgets/skeleton.dart';

/// Amici, richieste ricevute e ricerca utenti.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key, this.title});

  /// Dentro la tab Community: il selettore di sezione al posto del titolo.
  final Widget? title;

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<List<SimpleUser>>? _results;
  int _tab = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim();
      setState(() {
        _query = q;
        _results = q.isEmpty ? null : ref.read(userRepositoryProvider).search(q);
      });
    });
  }

  Future<void> _block(Friendship f, String username) async {
    if (!await confirm(context, title: tr('Bloccare @{username}?', {'username': username}), message: tr('Non vedrete più i rispettivi contenuti.'), ok: tr('Blocca'), destructive: true)) {
      return;
    }
    try {
      await ref.read(friendshipRepositoryProvider).block(f.id);
      ref.invalidate(friendsProvider);
      ref.invalidate(friendsPostsProvider);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final friends = ref.watch(friendsProvider);
    final requests = ref.watch(friendRequestsProvider);
    final requestCount = requests.value?.length ?? 0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Amici'), titleWidget: widget.title),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: SearchPill(controller: _search, hint: tr('Cerca per username'), onChanged: _onSearch, inputFormatters: usernameFormatters),
            ),
            if (_query.isNotEmpty)
              Expanded(child: _SearchResults(future: _results, me: me.username))
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SegmentedPill(
                  options: [tr('Amici'), requestCount > 0 ? tr('Richieste · {count}', {'count': requestCount}) : tr('Richieste')],
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _tab == 0
                    ? RefreshIndicator(
                        onRefresh: () => ref.refresh(friendsProvider.future),
                        child: AsyncView<List<Friendship>>(
                          value: friends,
                          onRetry: () => ref.invalidate(friendsProvider),
                          loading: const SkeletonList(item: SkeletonTile(leading: 44, circle: true, padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)), padding: EdgeInsets.fromLTRB(20, 0, 20, 24)),
                          data: (list) => list.isEmpty
                              ? ListView(children: [
                                  EmptyState(
                                    icon: Icons.person_search_rounded,
                                    title: tr('Nessun amico, per ora'),
                                    message: tr('Cerca qualcuno per username e mandagli una richiesta.'),
                                  ),
                                ])
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                  itemCount: list.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                                  itemBuilder: (_, i) {
                                    final other = list[i].other(me.username);
                                    return UserRow(
                                      user: other,
                                      trailing: PopupMenuButton<String>(
                                        icon: Icon(Icons.more_horiz_rounded, color: AppColors.muted),
                                        color: AppColors.card,
                                        onSelected: (_) => _block(list[i], other.username),
                                        itemBuilder: (_) => [
                                          PopupMenuItem(value: 'block', child: Text(tr('Blocca'), style: const TextStyle(color: AppColors.danger))),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.refresh(friendRequestsProvider.future),
                        child: AsyncView<List<Friendship>>(
                          value: requests,
                          onRetry: () => ref.invalidate(friendRequestsProvider),
                          loading: const SkeletonList(item: SkeletonTile(leading: 44, circle: true, trailing: true, padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)), padding: EdgeInsets.fromLTRB(20, 0, 20, 24)),
                          data: (list) => list.isEmpty
                              ? ListView(children: [EmptyState(icon: Icons.inbox_rounded, title: tr('Nessuna richiesta in attesa'))])
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                  itemCount: list.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                                  itemBuilder: (_, i) => FriendRequestTile(request: list[i]),
                                ),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.future, required this.me});

  final Future<List<SimpleUser>>? future;
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendNames = {
      for (final f in ref.watch(friendsProvider).value ?? const <Friendship>[]) f.other(me).username,
    };
    return FutureBuilder<List<SimpleUser>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SkeletonList(item: SkeletonTile(leading: 44, circle: true, padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)), padding: EdgeInsets.fromLTRB(20, 0, 20, 24));
        if (snap.hasError) return ErrorBlock(message: '${snap.error}');
        final users = (snap.data ?? const []).where((u) => u.username != me).toList();
        if (users.isEmpty) {
          return Center(child: Text(tr('Nessun utente trovato'), style: TextStyle(color: AppColors.muted)));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          itemCount: users.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => UserRow(
            user: users[i],
            trailing: friendNames.contains(users[i].username)
                ? Tag(tr('Amici'), color: AppColors.mint, icon: Icons.check_rounded)
                : AddFriendButton(username: users[i].username),
          ),
        );
      },
    );
  }
}

class UserRow extends StatelessWidget {
  const UserRow({super.key, required this.user, this.trailing});

  final SimpleUser user;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      radius: AppRadius.md + 2,
      onTap: () => context.push('/u/${user.username}'),
      child: Row(
        children: [
          UserAvatar(username: user.username, imageUrl: user.image, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text('@${user.username}',
                      style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                ),
                if (user.isAccountVerified == true) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified_rounded, size: 16, color: AppColors.blue),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Pulsante "Aggiungi" che invia la richiesta di amicizia. Lo stato viene
/// dalle richieste inviate sul server: se la richiesta è già partita mostra
/// "Inviata" e un tap la ritira (non ne manda una seconda).
class AddFriendButton extends ConsumerStatefulWidget {
  const AddFriendButton({super.key, required this.username, this.large = false});

  final String username;
  final bool large;

  @override
  ConsumerState<AddFriendButton> createState() => _AddFriendButtonState();
}

class _AddFriendButtonState extends ConsumerState<AddFriendButton> {
  bool _busy = false;

  Friendship? _pending(List<Friendship> sent) {
    for (final f in sent) {
      if (f.friend.username == widget.username) return f;
    }
    return null;
  }

  Future<void> _toggle(Friendship? pending) async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(friendshipRepositoryProvider);
    try {
      if (pending != null) {
        await repo.cancel(pending.id);
        if (mounted) showMessage(context, tr('Richiesta a @{username} annullata', {'username': widget.username}));
      } else {
        await repo.add(widget.username);
        if (mounted) showMessage(context, tr('Richiesta inviata a @{username}', {'username': widget.username}));
      }
    } on ApiException catch (e) {
      // 409/404: lo stato mostrato era vecchio (richiesta già inviata o già
      // ritirata). Basta riallinearsi, senza errore.
      if (e.statusCode != 409 && e.statusCode != 404 && mounted) {
        showMessage(context, e.message, error: true);
      }
    }
    // Il pulsante resta in caricamento finché lo stato non arriva dal server.
    if (!mounted) return;
    ref
      ..invalidate(friendsProvider)
      ..invalidate(sentFriendRequestsProvider);
    try {
      await ref.read(sentFriendRequestsProvider.future);
    } catch (_) {
      // il pulsante mostra l'ultimo stato noto
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = ref.watch(sentFriendRequestsProvider);
    final pending = _pending(sent.value ?? const []);
    final sentNow = pending != null;
    final busy = _busy || (!sent.hasValue && sent.isLoading);
    if (widget.large) {
      return PrimaryButton(
        label: sentNow ? tr('Richiesta inviata · Annulla') : tr('Aggiungi agli amici'),
        icon: sentNow ? Icons.close_rounded : Icons.person_add_alt_1_rounded,
        loading: busy,
        color: sentNow ? AppColors.mint : null,
        onPressed: busy ? null : () => _toggle(pending),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        backgroundColor: sentNow ? AppColors.mint : AppColors.ink,
      ),
      onPressed: busy ? null : () => _toggle(pending),
      child: Text(sentNow ? tr('Inviata') : tr('Aggiungi'), style: const TextStyle(fontSize: 13)),
    );
  }
}
