import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/workout_repository.dart';
import '../../models/workout.dart';
import '../../core/widgets/skeleton.dart';
import '../auth/session.dart';
import '../share/share_actions.dart';

/// Storico delle sessioni completate.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final me = ref.watch(currentUserProvider);
    final workouts = {for (final w in ref.watch(myWorkoutsProvider).value ?? const <Workout>[]) w.id: w};

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Storico')),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(historyProvider.future),
                child: AsyncView<List<WorkoutHistory>>(
                  value: history,
                  onRetry: () => ref.invalidate(historyProvider),
                  loading: const SkeletonList(item: SkeletonTile(leading: 48)),
                  data: (list) {
                    if (list.isEmpty) {
                      return ListView(children: [
                        EmptyState(
                          icon: Icons.history_rounded,
                          title: tr('Nessuna sessione'),
                          message: tr('Completa un allenamento e lo troverai qui.'),
                        ),
                      ]);
                    }
                    final total = list.fold<Duration>(Duration.zero, (a, h) => a + (h.duration ?? Duration.zero));
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        FadeInUp(
                          child: SoftCard(
                            color: AppColors.blue,
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _Summary(value: '${list.length}', label: tr('sessioni totali')),
                                ),
                                Expanded(
                                  child: _Summary(value: formatDuration(total), label: tr('tempo allenato')),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        for (final (i, h) in list.indexed)
                          FadeInUp(
                            index: i + 1,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Dismissible(
                                key: ValueKey(h.id),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) => confirm(context, title: tr('Eliminare la sessione?'), ok: tr('Elimina'), destructive: true),
                                onDismissed: (_) async {
                                  try {
                                    await ref.read(workoutRepositoryProvider).deleteHistory(h.id);
                                  } on ApiException catch (e) {
                                    if (context.mounted) showMessage(context, e.message, error: true);
                                  }
                                  ref.invalidate(historyProvider);
                                },
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 24),
                                  child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                ),
                                child: SoftCard(
                                  padding: const EdgeInsets.all(14),
                                  radius: AppRadius.md + 2,
                                  child: Row(
                                    children: [
                                      _DateBadge(date: h.startedAt),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(workouts[h.workoutId]?.name ?? tr('Allenamento'),
                                                style: const TextStyle(fontWeight: FontWeight.w700)),
                                            Text(
                                              [formatTime(h.startedAt), formatDuration(h.duration), if (h.groupId != null) tr('di gruppo')]
                                                  .where((s) => s.isNotEmpty)
                                                  .join(' · '),
                                              style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                                            ),
                                            if (h.notes?.isNotEmpty == true)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Text(h.notes!, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.ios_share_rounded, color: AppColors.inkSoft),
                                        tooltip: tr('Condividi'),
                                        onPressed: () => shareSession(context, h,
                                            workout: workouts[h.workoutId], username: me.username),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
        ],
      );
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final d = date;
    final months = [tr('gen'), tr('feb'), tr('mar'), tr('apr'), tr('mag'), tr('giu'), tr('lug'), tr('ago'), tr('set'), tr('ott'), tr('nov'), tr('dic')];
    return Container(
      width: 52,
      height: 56,
      decoration: BoxDecoration(color: AppColors.blueSoft, borderRadius: BorderRadius.circular(16)),
      alignment: Alignment.center,
      child: d == null
          ? const Icon(Icons.event_rounded, color: AppColors.blue)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${d.day}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.blue)),
                Text(months[d.month - 1], style: const TextStyle(fontSize: 11, color: AppColors.blue)),
              ],
            ),
    );
  }
}
