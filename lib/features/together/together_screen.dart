import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../models/group.dart';
import '../../models/social.dart';
import '../feed/post_card.dart';
import '../feed/post_detail_screen.dart';
import '../groups/group_detail_screen.dart';
import '../shell/app_shell.dart';

/// Tab Insieme, divisa in due: i tuoi gruppi (con ricerca) e il feed degli
/// amici. Inviti e sessioni in programma stanno in Oggi. Su un pieghevole
/// aperto gruppo o post si aprono accanto alla lista (vedi [TwoPane]).
class TogetherScreen extends ConsumerStatefulWidget {
  const TogetherScreen({super.key});

  @override
  ConsumerState<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends ConsumerState<TogetherScreen> {
  int _tab = 0;
  String _q = '';

  /// Il gruppo o il post aperto nel pannello accanto alla lista.
  Widget? _open;

  /// Nel pannello se c'è posto, altrimenti a tutto schermo come sempre.
  VoidCallback? _opener(Widget page) => TwoPane.active(context) ? () => setState(() => _open = page) : null;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_tab == 0) {
      await ref.refresh(groupsProvider.future).catchError((_) => <WorkoutGroup>[]);
    } else {
      await ref.refresh(friendsPostsProvider.future).catchError((_) => <Post>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return TwoPane(
      start: _list(context),
      end: open == null
          ? Center(child: EmptyState(icon: Icons.groups_rounded, title: tr('Scegli un gruppo o un post')))
          : PaneScope(onClose: () => setState(() => _open = null), child: open),
    );
  }

  Widget _list(BuildContext context) {
    final groups = _tab == 0;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
              // Titolo e schede tornano su appena scorri verso l'alto, senza
              // dover risalire tutta la pagina.
              SliverAppBar(
                floating: true,
                snap: true,
                automaticallyImplyLeading: false,
                backgroundColor: AppColors.bg,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                toolbarHeight: 140,
                titleSpacing: 20,
                title: Column(
                  children: [
                    SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          Expanded(child: Text(tr('Insieme'), style: Theme.of(context).textTheme.headlineMedium)),
                          if (!groups)
                            CircleIconButton(icon: Icons.person_search_rounded, tooltip: tr('Cerca'), onTap: () => context.push('/search')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SegmentedPill(options: [tr('Gruppi'), tr('Amici')], index: _tab, onChanged: (i) => setState(() => _tab = i)),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, navBarClearance),
                sliver: SliverList.list(children: [if (groups) ..._groups() else _feed()]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _groups() {
    final value = ref.watch(groupsProvider);
    final all = value.value ?? const <WorkoutGroup>[];
    final shown = all.where((g) => g.name.toLowerCase().contains(_q)).toList();
    if (value.isLoading && all.isEmpty) {
      return const [SkeletonList(count: 3, padding: EdgeInsets.zero)];
    }
    if (all.isEmpty) {
      return [
        EmptyState(
          icon: Icons.groups_rounded,
          title: tr('Nessun gruppo'),
          message: tr('Crea un allenamento di gruppo e invita i tuoi amici.'),
          action: tr('Nuovo gruppo'),
          onAction: () => context.push('/group/new'),
        ),
      ];
    }
    return [
      SearchPill(controller: _search, hint: tr('Cerca nei tuoi gruppi'), onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
      const SizedBox(height: 14),
      if (shown.isEmpty) EmptyState(icon: Icons.search_off_rounded, title: tr('Nessun risultato')),
      for (final g in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _GroupRow(group: g, onTap: _opener(GroupDetailScreen(key: ValueKey(g.id), groupId: g.id))),
        ),
    ];
  }

  Widget _feed() => AsyncView<List<Post>>(
        value: ref.watch(friendsPostsProvider),
        onRetry: () => ref.invalidate(friendsPostsProvider),
        loading: const SkeletonList(item: SkeletonPost(), count: 2, spacing: 14, padding: EdgeInsets.zero),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.dynamic_feed_rounded,
                title: tr('Ancora nessun post'),
                message: tr('Quando i tuoi amici pubblicano un allenamento lo vedrai qui.'),
                action: tr('Trova amici'),
                onAction: () => context.push('/friends'),
              )
            : Column(
                children: [
                  for (final p in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: PostCard(post: p, onOpen: _opener(PostDetailScreen(key: ValueKey(p.id), postId: p.id))),
                    ),
                ],
              ),
      );
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, this.onTap});

  final WorkoutGroup group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final people = 1 + group.acceptedMembers.length;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      radius: AppRadius.md + 2,
      onTap: onTap ?? () => context.push('/group/${group.id}'),
      child: Row(
        children: [
          const IconChip(icon: Icons.groups_rounded, color: AppColors.lilac),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                Text(people == 1 ? tr('{n} persona', {'n': 1}) : tr('{n} persone', {'n': people}),
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    );
  }
}
