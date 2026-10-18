import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../models/workout.dart';
import '../auth/session.dart';
import '../shell/app_shell.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/motion.dart';

/// Tab Allenati: le tue schede e la Corsa. Con [explore] invece le schede
/// pubbliche degli altri, da cui partire per una nuova.
class WorkoutsScreen extends ConsumerWidget {
  const WorkoutsScreen({super.key, this.explore = false});

  final bool explore;

  void _create(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Nuova scheda'), style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 14),
              for (final (icon, title, subtitle, route) in [
                (Icons.edit_note_rounded, tr('Da zero'), tr('Esercizi, giorni e orario'), '/workout/new'),
                (Icons.explore_rounded, tr('Dalla community'), tr('Parti da una scheda pubblica'), '/workouts/explore'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SoftCard(
                    padding: const EdgeInsets.all(16),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push(route);
                    },
                    child: Row(
                      children: [
                        IconChip(icon: icon, color: AppColors.brand),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(subtitle, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            ],
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final provider = explore ? exploreWorkoutsProvider : myWorkoutsProvider;
    final workouts = ref.watch(provider);

    return Scaffold(
      body: SafeArea(
        bottom: explore,
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(provider.future),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: explore
                    ? TopBar(title: tr('Dalla community'))
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                        child: Row(
                          children: [
                            Expanded(child: Text(tr('Allenati'), style: Theme.of(context).textTheme.headlineMedium)),
                            CircleIconButton(icon: Icons.add_rounded, dark: true, tooltip: tr('Nuova scheda'), onTap: () => _create(context)),
                          ],
                        ),
                      ),
              ),
              if (!explore)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  sliver: SliverToBoxAdapter(child: _RunCard(onTap: () => context.push('/running'))),
                ),
              AsyncView<List<Workout>>(
                value: workouts,
                sliver: true,
                onRetry: () => ref.invalidate(provider),
                loading: const SkeletonList(
                  item: SkeletonTile(leading: 56, trailing: true, padding: EdgeInsets.all(18), radius: AppRadius.lg),
                  count: 4,
                  spacing: 12,
                  padding: EdgeInsets.symmetric(horizontal: 20),
                ),
                data: (list) {
                  final shown = explore ? list.where((w) => w.user?.username != me.username).toList() : list;
                  if (shown.isEmpty) {
                    return SliverToBoxAdapter(
                      child: EmptyState(
                        icon: explore ? Icons.explore_rounded : Icons.assignment_rounded,
                        title: explore ? tr('Niente da esplorare') : tr('Nessuna scheda'),
                        message: explore
                            ? tr('Le schede pubbliche della community appariranno qui.')
                            : tr('Crea la tua prima scheda: esercizi, serie, giorni e orario.'),
                        action: explore ? null : tr('Crea scheda'),
                        onAction: () => _create(context),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, explore ? 24 : navBarClearance),
                    sliver: SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => FadeInUp(index: i, child: WorkoutCard(workout: shown[i], index: i, showOwner: explore)),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La Corsa sta qui come una card sola: dentro corsa libera, percorsi e corse fatte.
class _RunCard extends StatelessWidget {
  const _RunCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Corsa'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      Text(tr('Libera o su un percorso'), style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                const Icon(Icons.directions_run_rounded, color: Colors.white, size: 34),
              ],
            ),
          ),
        ),
      );
}

/// Card scheda con colore pastello a rotazione.
class WorkoutCard extends StatelessWidget {
  const WorkoutCard({super.key, required this.workout, this.index = 0, this.showOwner = false});

  final Workout workout;
  final int index;
  final bool showOwner;

  static const _accents = [AppColors.blue, AppColors.lilac, AppColors.pink, AppColors.mint];

  @override
  Widget build(BuildContext context) {
    final accent = _accents[index % _accents.length];
    final totalSets = workout.exercises.fold<int>(0, (a, e) => a + e.sets);
    return SoftCard(
      onTap: () => context.push('/workout/${workout.id}'),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.fitness_center_rounded, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        workout.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (workout.isPublic) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.public_rounded, size: 15, color: AppColors.muted),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  showOwner && workout.user != null
                      ? tr('@{username} · {count} esercizi', {'username': workout.user!.username, 'count': workout.exercises.length})
                      : '${weekdaysLabel(workout.dayOfWeek)}${workout.startTime != null ? ' · ${workout.startTime!.label}' : ''}',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${workout.exercises.length}', style: Theme.of(context).textTheme.titleLarge),
              Text(totalSets > 0 ? tr('{count} serie', {'count': totalSets}) : tr('esercizi'),
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
