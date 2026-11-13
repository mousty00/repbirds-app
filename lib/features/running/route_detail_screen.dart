import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/running_repository.dart';
import '../../models/running.dart';
import '../auth/session.dart';
import 'geo.dart';
import '../share/share_actions.dart';
import 'route_map.dart';

class RouteDetailScreen extends ConsumerStatefulWidget {
  const RouteDetailScreen({super.key, required this.routeId});

  final String routeId;

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  bool _copying = false;

  Future<void> _copy(RunRoute route) async {
    setState(() => _copying = true);
    try {
      final copy = await ref.read(runningRepositoryProvider).copyRoute(route.id);
      ref.invalidate(myRoutesProvider);
      if (!mounted) return;
      showMessage(context, tr('Salvato nei tuoi percorsi'));
      context.pushReplacement('/running/route/${copy.id}');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _delete(RunRoute route) async {
    final ok = await confirm(
      context,
      title: tr('Eliminare "{name}"?', {'name': route.name}),
      message: tr('Vengono eliminate anche le corse di gruppo organizzate su questo percorso. Le corse già registrate restano.'),
      ok: tr('Elimina'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(runningRepositoryProvider).deleteRoute(route.id);
      ref.invalidate(myRoutesProvider);
      ref.invalidate(runEventsProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).username;
    final value = ref.watch(runRouteProvider(widget.routeId));
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: AsyncView<RunRoute>(
            value: value,
            onRetry: () => ref.invalidate(runRouteProvider(widget.routeId)),
            loading: const SkeletonDetail(),
            data: (route) {
              final mine = route.isMine(me);
              return Column(
                children: [
                  TopBar(
                    title: '',
                    actions: [
                      CircleIconButton(
                        icon: Icons.ios_share_rounded,
                        size: 44,
                        tooltip: tr('Condividi'),
                        onTap: () => shareRoute(context, route,
                            loadGpx: () => ref.read(runningRepositoryProvider).routeGpx(route.id)),
                      ),
                      if (mine) ...[
                        CircleIconButton(
                          icon: Icons.edit_outlined,
                          size: 44,
                          tooltip: tr('Modifica'),
                          onTap: () => context.push('/running/route/${route.id}/edit'),
                        ),
                        CircleIconButton(icon: Icons.delete_outline_rounded, size: 44, tooltip: tr('Elimina'), onTap: () => _delete(route)),
                      ],
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        RouteMap(route: route.points, height: 300),
                        const SizedBox(height: 18),
                        Text(route.name, style: Theme.of(context).textTheme.displaySmall),
                        const SizedBox(height: 6),
                        Text(
                          route.originalAuthor != null
                              ? tr('Disegnato da @{username}', {'username': route.originalAuthor!.username})
                              : mine
                                  ? (route.isPublic ? tr('Pubblico: i tuoi amici lo vedono') : tr('Privato: lo vedi solo tu'))
                                  : tr('Di @{username}', {'username': route.owner.username}),
                          style: TextStyle(color: AppColors.inkSoft),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            _Metric(label: tr('Distanza'), value: formatDistance(route.distanceM)),
                            _Metric(label: tr('Dislivello'), value: route.elevationGainM == null ? '–' : '+${route.elevationGainM} m'),
                            _Metric(label: tr('Tempo'), value: estimateTime(route.distanceM)),
                          ],
                        ),
                        if (route.description != null && route.description!.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(route.description!, style: Theme.of(context).textTheme.bodyLarge),
                        ],
                        const SizedBox(height: 22),
                        if (mine)
                          OutlinedButton.icon(
                            onPressed: () => pickGroupForRun(context, ref, route.id),
                            icon: const Icon(Icons.groups_rounded),
                            label: Text(tr('Organizza una corsa di gruppo')),
                          )
                        else if (route.isPublic)
                          OutlinedButton.icon(
                            onPressed: _copying ? null : () => _copy(route),
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: Text(tr('Salva nei miei percorsi')),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: PillActionButton(
                      label: tr('Corri questo percorso'),
                      icon: Icons.directions_run_rounded,
                      onPressed: () => context.push('/running/run?route=${route.id}'),
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

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
      );
}

/// Corsa di gruppo: è una sessione di uno dei tuoi gruppi, su questo percorso.
/// Scegli il gruppo (o creane uno) e poi giorno e ora.
Future<void> pickGroupForRun(BuildContext context, WidgetRef ref, String routeId) async {
  final me = ref.read(currentUserProvider).username;
  final groups = (await ref.read(groupsProvider.future)).where((g) => g.createdBy.username == me).toList();
  if (!context.mounted) return;
  if (groups.isEmpty) {
    showMessage(context, tr('Prima crea un gruppo: le corse di gruppo sono sessioni dei tuoi gruppi.'));
    context.push('/group/new');
    return;
  }
  final groupId = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        children: [
          Text(tr('Con quale gruppo?'), style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 12),
          for (final g in groups)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const IconChip(icon: Icons.groups_rounded, color: AppColors.lilac),
              title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, g.id),
            ),
        ],
      ),
    ),
  );
  if (groupId != null && context.mounted) context.push('/group/$groupId/session/new?route=$routeId');
}
