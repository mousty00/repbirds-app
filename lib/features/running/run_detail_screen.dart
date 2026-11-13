import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
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

class RunDetailScreen extends ConsumerWidget {
  const RunDetailScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).username;
    final repo = ref.read(runningRepositoryProvider);
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: AsyncView<RunActivity>(
            value: ref.watch(runProvider(runId)),
            onRetry: () => ref.invalidate(runProvider(runId)),
            loading: const SkeletonDetail(),
            data: (run) {
              final mine = run.user.username == me;
              return Column(
                children: [
                  TopBar(
                    title: '',
                    actions: [
                      CircleIconButton(
                        icon: Icons.ios_share_rounded,
                        size: 44,
                        tooltip: tr('Condividi'),
                        onTap: () => shareRun(context, run, mine: mine, loadGpx: () => repo.runGpx(run.id)),
                      ),
                      if (mine)
                        CircleIconButton(
                          icon: Icons.delete_outline_rounded,
                          size: 44,
                          tooltip: tr('Elimina'),
                          onTap: () async {
                            if (!await confirm(context, title: tr('Eliminare la corsa?'), ok: tr('Elimina'), destructive: true)) return;
                            try {
                              await repo.deleteRun(run.id);
                              ref.invalidate(myRunsProvider);
                              if (run.eventId != null) ref.invalidate(eventRunsProvider(run.eventId!));
                              if (context.mounted) context.pop();
                            } on ApiException catch (e) {
                              if (context.mounted) showMessage(context, e.message, error: true);
                            }
                          },
                        ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        Text(run.title, style: Theme.of(context).textTheme.displaySmall),
                        const SizedBox(height: 6),
                        Text(
                          '${mine ? '' : '@${run.user.username} · '}${formatDayTime(run.startedAt)}',
                          style: TextStyle(color: AppColors.inkSoft),
                        ),
                        const SizedBox(height: 18),
                        RouteMap(track: run.track, height: 300),
                        const SizedBox(height: 18),
                        SoftCard(
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  _Big(label: tr('Distanza'), value: formatDistance(run.distanceM)),
                                  _Big(label: tr('Tempo'), value: formatSeconds(run.durationS)),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  _Big(label: tr('Passo medio'), value: '${formatPace(run.paceSPerKm)} /km'),
                                  _Big(label: tr('Dislivello'), value: run.elevationGainM == null ? '–' : '+${run.elevationGainM} m'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (run.eventId != null)
                          OutlinedButton.icon(
                            onPressed: () => context.push('/running/event/${run.eventId}'),
                            icon: const Icon(Icons.groups_rounded),
                            label: Text(tr('Vedi la corsa di gruppo')),
                          )
                        else if (run.routeId != null)
                          OutlinedButton.icon(
                            onPressed: () => context.push('/running/route/${run.routeId}'),
                            icon: const Icon(Icons.route_rounded),
                            label: Text(tr('Vedi il percorso')),
                          ),
                      ],
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

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
      );
}
