import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../models/running.dart';
import '../auth/session.dart';
import 'geo.dart';
import 'route_map.dart';

/// Hub della corsa: i miei percorsi, quelli pubblici degli amici, le corse di
/// gruppo e lo storico delle corse.
class RunningScreen extends ConsumerStatefulWidget {
  const RunningScreen({super.key, this.initialTab = 0, this.title});

  final int initialTab;

  /// Dentro la tab Allenati: il selettore di sezione al posto del titolo.
  final Widget? title;

  @override
  ConsumerState<RunningScreen> createState() => _RunningScreenState();
}

class _RunningScreenState extends ConsumerState<RunningScreen> {
  late int _tab = widget.initialTab;

  // le corse di gruppo stanno in Insieme, con le sessioni
  static List<String> get _tabs => [tr('Percorsi'), tr('Amici'), tr('Corse')];

  Future<void> _refresh() async {
    ref.invalidate(myRoutesProvider);
    ref.invalidate(friendsRoutesProvider);
    ref.invalidate(runEventsProvider);
    ref.invalidate(myRunsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TopBar(
                title: tr('Corsa'),
                titleWidget: widget.title,
                actions: [
                  CircleIconButton(
                    icon: Icons.add_road_rounded,
                    size: 44,
                    dark: true,
                    tooltip: tr('Nuovo percorso'),
                    onTap: () => context.push('/running/route/new'),
                  ),
                ],
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _tabs.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ChoiceChip(
                    label: Text(_tabs[i]),
                    selected: _tab == i,
                    showCheckmark: false,
                    selectedColor: AppColors.ink,
                    labelStyle: TextStyle(color: _tab == i ? AppColors.onInk : AppColors.ink, fontWeight: FontWeight.w600),
                    backgroundColor: AppColors.card,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    onSelected: (_) => setState(() => _tab = i),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: switch (_tab) {
                    0 => const _MyRoutes(),
                    1 => const _FriendsRoutes(),
                    _ => const _Runs(),
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: PillActionButton(
                  label: tr('Corsa libera'),
                  icon: Icons.directions_run_rounded,
                  onPressed: () => context.push('/running/run'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _listPadding = EdgeInsets.fromLTRB(20, 8, 20, 20);

class _MyRoutes extends ConsumerWidget {
  const _MyRoutes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<RunRoute>>(
      value: ref.watch(myRoutesProvider),
      onRetry: () => ref.invalidate(myRoutesProvider),
      data: (routes) => routes.isEmpty
          ? ListView(children: [
              EmptyState(
                icon: Icons.route_rounded,
                title: tr('Nessun percorso'),
                message: tr('Disegna sulla mappa il giro che vuoi fare: resta salvato per rifarlo quando vuoi.'),
                action: tr('Disegna un percorso'),
                onAction: () => context.push('/running/route/new'),
              ),
            ])
          : ListView.separated(
              padding: _listPadding,
              itemCount: routes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => FadeInUp(index: i, child: RouteCard(route: routes[i])),
            ),
    );
  }
}

class _FriendsRoutes extends ConsumerWidget {
  const _FriendsRoutes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<RunRoute>>(
      value: ref.watch(friendsRoutesProvider),
      onRetry: () => ref.invalidate(friendsRoutesProvider),
      data: (routes) => routes.isEmpty
          ? ListView(children: [
              EmptyState(
                icon: Icons.travel_explore_rounded,
                title: tr('Ancora niente'),
                message: tr('Qui trovi i percorsi che i tuoi amici rendono pubblici. Puoi salvarli e correrli da solo.'),
              ),
            ])
          : ListView.separated(
              padding: _listPadding,
              itemCount: routes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => FadeInUp(index: i, child: RouteCard(route: routes[i], showAuthor: true)),
            ),
    );
  }
}

class _Runs extends ConsumerWidget {
  const _Runs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<RunActivity>>(
      value: ref.watch(myRunsProvider),
      onRetry: () => ref.invalidate(myRunsProvider),
      data: (runs) {
        if (runs.isEmpty) {
          return ListView(children: [
            EmptyState(icon: Icons.directions_run_rounded, title: tr('Nessuna corsa'), message: tr('Le corse che registri compaiono qui, con mappa, tempi e passo.')),
          ]);
        }
        final total = runs.fold<int>(0, (sum, r) => sum + r.distanceM);
        return ListView(
          padding: _listPadding,
          children: [
            SoftCard(
              color: AppColors.blue,
              child: Row(
                children: [
                  const Icon(Icons.directions_run_rounded, color: Colors.white, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(runs.length == 1 ? tr('{n} corsa', {'n': runs.length}) : tr('{n} corse', {'n': runs.length}),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  Text(formatDistance(total),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final r in runs) Padding(padding: const EdgeInsets.only(bottom: 10), child: RunTile(run: r)),
          ],
        );
      },
    );
  }
}

class RouteCard extends ConsumerWidget {
  const RouteCard({super.key, required this.route, this.showAuthor = false});

  final RunRoute route;
  final bool showAuthor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).username;
    final author = route.originalAuthor ?? (route.isMine(me) ? null : route.owner);
    return SoftCard(
      padding: const EdgeInsets.all(10),
      onTap: () => context.push('/running/route/${route.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(child: RouteMap(route: route.points, interactive: false, height: 140)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(route.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                    if (route.isMine(me))
                      Tag(route.isPublic ? tr('Pubblico') : tr('Privato'),
                          icon: route.isPublic ? Icons.public_rounded : Icons.lock_rounded,
                          color: route.isPublic ? AppColors.mint : AppColors.inkSoft),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _Stat(Icons.straighten_rounded, formatDistance(route.distanceM)),
                    if (route.elevationGainM != null) _Stat(Icons.terrain_rounded, '+${route.elevationGainM} m'),
                    _Stat(Icons.timer_outlined, estimateTime(route.distanceM)),
                    if (showAuthor || author != null) _Stat(Icons.person_rounded, '@${author?.username ?? route.owner.username}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.inkSoft),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );
}

class RunEventCard extends StatelessWidget {
  const RunEventCard({super.key, required this.event});

  final RunEvent event;

  @override
  Widget build(BuildContext context) {
    final people = 1 + event.accepted.length;
    return SoftCard(
      color: event.isInvited ? AppColors.pinkSoft : AppColors.blueSoft,
      onTap: () => context.push('/running/event/${event.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tag(formatDayTime(event.startsAt), icon: Icons.schedule_rounded, color: AppColors.ink),
              const Spacer(),
              if (event.isInvited) Tag(tr('Invito'), color: AppColors.pink),
            ],
          ),
          const SizedBox(height: 12),
          Text(event.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${event.route.name} · ${formatDistance(event.route.distanceM)} · '
            '${people == 1 ? tr('{n} partecipante', {'n': people}) : tr('{n} partecipanti', {'n': people})}',
            style: TextStyle(color: AppColors.inkSoft),
          ),
          if (event.meetingPoint != null && event.meetingPoint!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(tr('Ritrovo: {place}', {'place': event.meetingPoint}), style: TextStyle(color: AppColors.inkSoft)),
          ],
        ],
      ),
    );
  }
}

class RunTile extends StatelessWidget {
  const RunTile({super.key, required this.run, this.showUser = false});

  final RunActivity run;
  final bool showUser;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(14),
      radius: AppRadius.md,
      onTap: () => context.push('/running/runs/${run.id}'),
      child: Row(
        children: [
          showUser
              ? UserAvatar(username: run.user.username, imageUrl: run.user.image, size: 40)
              : const IconChip(icon: Icons.directions_run_rounded, color: AppColors.pink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(showUser ? '@${run.user.username}' : run.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  showUser ? formatSeconds(run.durationS) : formatDayTime(run.startedAt),
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatDistance(run.distanceM), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${formatPace(run.paceSPerKm)} /km', style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}
