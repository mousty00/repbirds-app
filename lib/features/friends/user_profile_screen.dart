import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../models/social.dart';
import '../../models/user.dart';
import '../auth/session.dart';
import '../body/body_calendar.dart';
import '../feed/moderation.dart';
import '../share/share_actions.dart';
import 'friends_screen.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/utils/formatters.dart';
import '../home/home_screen.dart' show streakDays;
import '../running/geo.dart' show formatDistance;

/// Profilo pubblico di un altro utente: numeri (agli amici), amici in comune,
/// schede, percorsi ed esercizi pubblici e i post.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    if (username == me.username) {
      // Il proprio profilo vive nella tab Profilo.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/profile');
      });
    }
    final user = ref.watch(userProfileProvider(username));
    final posts = ref.watch(userPostsProvider(username));
    final overview = ref.watch(userOverviewProvider(username)).value;
    final isFriend = (ref.watch(friendsProvider).value ?? const <Friendship>[])
        .any((f) => f.other(me.username).username == username);

    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: Column(
            children: [
              TopBar(
                title: '',
                actions: [
                  if (user.value != null)
                    CircleIconButton(
                      icon: Icons.ios_share_rounded,
                      size: 44,
                      tooltip: tr('Condividi profilo'),
                      onTap: () => shareProfile(context, user.value!),
                    ),
                  if (user.value != null && username != me.username)
                    ModerationMenu(
                      type: 'USER',
                      targetId: user.value!.id,
                      username: username,
                      onBlocked: () => context.canPop() ? context.pop() : null,
                    ),
                ],
              ),
              Expanded(
                child: AsyncView<User>(
                  value: user,
                  onRetry: () => ref.invalidate(userProfileProvider(username)),
                  loading: const SkeletonProfile(),
                  data: (u) => ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      ProfileHeader(user: u),
                      const SizedBox(height: 20),
                      if (isFriend)
                        Center(child: Tag(tr('Siete amici'), color: AppColors.mint, icon: Icons.check_rounded))
                      else
                        AddFriendButton(username: u.username, large: true),
                      if (overview != null) _Overview(overview: overview),
                      const SizedBox(height: 24),
                      ProfileTabs(
                        overview: overview,
                        calendar: BodyCalendar(username: u.username, mine: u.username == me.username),
                        posts: AsyncView<List<Post>>(
                          value: posts,
                          onRetry: () => ref.invalidate(userPostsProvider(username)),
                          loading: const SkeletonGrid(),
                          data: (list) => PostGrid(posts: list),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar grande, nome e username centrati.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.user, this.onEditAvatar});

  final User user;
  final VoidCallback? onEditAvatar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Stack(
          children: [
            UserAvatar(username: user.username, imageUrl: user.image, size: 112, ring: true),
            if (onEditAvatar != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleIconButton(icon: Icons.photo_camera_rounded, size: 38, dark: true, onTap: onEditAvatar),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text(user.displayName, style: t.headlineSmall, overflow: TextOverflow.ellipsis)),
            if (user.isAccountVerified == true) ...[
              const SizedBox(width: 6),
              const Icon(Icons.verified_rounded, color: AppColors.blue, size: 20),
            ],
          ],
        ),
        Text('@${user.username}', style: t.bodyMedium),
      ],
    );
  }
}

/// Griglia 3 colonne di anteprime dei post.
class PostGrid extends StatelessWidget {
  const PostGrid({super.key, required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text(tr('Ancora nessun post'), style: TextStyle(color: AppColors.muted))),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: posts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (_, i) {
        final p = posts[i];
        return GestureDetector(
          onTap: () => context.push('/posts/${p.id}'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppImage.supports(p.image)
                    ? AppImage(p.image!, fallback: _TextTile(text: p.content))
                    : _TextTile(text: p.content),
                if (p.numLikes > 0)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.favorite_rounded, size: 12, color: Colors.white),
                          const SizedBox(width: 3),
                          Text('${p.numLikes}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TextTile extends StatelessWidget {
  const _TextTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.lilacSoft,
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        child: Text(text, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      );
}

class _Overview extends StatelessWidget {
  const _Overview({required this.overview});

  final UserOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final streak = o.recentActivity == null ? null : streakDays(o.recentActivity!, DateTime.now());

    Widget stat(String value, String label) => Expanded(
          child: SoftCard(
            radius: 24,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              children: [
                FittedBox(child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                const SizedBox(height: 2),
                Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            if (o.training != null) ...[
              stat(o.training!.inMinutes == 0 ? '0' : formatDuration(o.training), tr('di allenamento')),
              const SizedBox(width: 10),
              stat('$streak', streak == 1 ? tr('giorno di fila') : tr('giorni di fila')),
              const SizedBox(width: 10),
            ],
            stat('${o.mutualFriends.length}', tr('amici in comune')),
          ],
        ),
        if (o.mutualFriends.isNotEmpty) ...[
          const SizedBox(height: 22),
          SectionHeader(tr('Amici in comune')),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: o.mutualFriends.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final f = o.mutualFriends[i];
                return GestureDetector(
                  onTap: () => context.push('/u/${f.username}'),
                  child: SizedBox(
                    width: 64,
                    child: Column(
                      children: [
                        UserAvatar(username: f.username, imageUrl: f.image, size: 52),
                        const SizedBox(height: 4),
                        Text(f.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Schede in alto: Post (aperta di base), Schede, Percorsi (solo agli amici), Esercizi e Calendario del fisico.
class ProfileTabs extends StatefulWidget {
  const ProfileTabs({super.key, required this.overview, required this.posts, required this.calendar});

  final UserOverview? overview;
  final Widget posts;
  final Widget calendar;

  @override
  State<ProfileTabs> createState() => _ProfileTabsState();
}

class _ProfileTabsState extends State<ProfileTabs> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final o = widget.overview;
    final tabs = <(String, IconData, Widget Function())>[
      (tr('Post'), Icons.grid_view_rounded, () => widget.posts),
      (
        tr('Schede'),
        Icons.fitness_center_rounded,
        () => _list([
              for (final w in o?.workouts ?? const <({String id, String name, int exercises})>[])
                _Item(
                  icon: Icons.fitness_center_rounded,
                  color: AppColors.brand,
                  title: w.name,
                  subtitle: w.exercises == 1 ? tr('{n} esercizio', {'n': 1}) : tr('{n} esercizi', {'n': w.exercises}),
                  onTap: () => context.push('/workout/${w.id}'),
                ),
            ], tr('Nessuna scheda pubblica')),
      ),
      if (o?.routes != null)
        (
          tr('Percorsi'),
          Icons.route_rounded,
          () => _list([
                for (final r in o!.routes!)
                  _Item(
                    icon: Icons.route_rounded,
                    color: AppColors.mint,
                    title: r.name,
                    subtitle: r.distanceM == null ? null : formatDistance(r.distanceM!),
                    onTap: () => context.push('/running/route/${r.id}'),
                  ),
              ], tr('Nessun percorso pubblico')),
        ),
      (
        tr('Esercizi'),
        Icons.sports_gymnastics_rounded,
        () => _list([
              for (final e in o?.exercises ?? const <({String id, String name, String muscleGroup})>[])
                _Item(icon: Icons.sports_gymnastics_rounded, color: AppColors.lilac, title: e.name, subtitle: e.muscleGroup),
            ], tr('Nessun esercizio pubblico')),
      ),
      (tr('Calendario'), Icons.calendar_month_rounded, () => widget.calendar),
    ];
    final tab = _tab.clamp(0, tabs.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedPill(
          options: [for (final t in tabs) t.$1],
          icons: [for (final t in tabs) t.$2],
          index: tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 16),
        tabs[tab].$3(),
      ],
    );
  }

  Widget _list(List<Widget> items, String empty) => items.isEmpty
      ? Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(child: Text(empty, style: TextStyle(color: AppColors.muted))),
        )
      : Column(children: items);
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.color, required this.title, this.subtitle, this.onTap});

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SoftCard(
          padding: const EdgeInsets.all(14),
          radius: AppRadius.md + 2,
          onTap: onTap,
          child: Row(
            children: [
              IconChip(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      );
}
