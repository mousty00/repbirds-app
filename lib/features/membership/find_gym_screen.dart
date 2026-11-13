import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/billing_repository.dart';
import '../../data/gym_repository.dart';
import '../../models/billing.dart';
import '../gym/gym_billing_screen.dart' show openStripe;
import '../gym/gym_widgets.dart';

/// Trova una palestra su RepBirds per vederne gli abbonamenti (e pagarli, se la palestra incassa in app).
class FindGymScreen extends ConsumerStatefulWidget {
  const FindGymScreen({super.key});

  @override
  ConsumerState<FindGymScreen> createState() => _FindGymScreenState();
}

class _FindGymScreenState extends ConsumerState<FindGymScreen> {
  var _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(gymSearchProvider(_query));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Trova una palestra')),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SearchPill(
                hint: tr('Nome o città'),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _query = v.trim()));
                },
              ),
            ),
            Expanded(
              child: AsyncView<List<PublicGym>>(
                value: results,
                onRetry: () => ref.invalidate(gymSearchProvider(_query)),
                data: (list) => list.isEmpty
                    ? EmptyState(icon: Icons.fitness_center_rounded, title: tr('Nessuna palestra trovata'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final g = list[i];
                          return SoftCard(
                            padding: const EdgeInsets.all(14),
                            onTap: () => context.push('/gyms/${g.id}'),
                            child: Row(
                              children: [
                                const IconChip(icon: Icons.fitness_center_rounded, color: AppColors.mint, size: 44),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(g.name, style: t.titleMedium),
                                      if (g.place.isNotEmpty)
                                        Text(g.place, style: t.bodySmall?.copyWith(color: AppColors.inkSoft)),
                                    ],
                                  ),
                                ),
                                if (g.payOnline) Tag(tr('Paga in app'), color: AppColors.blue),
                              ],
                            ),
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

/// Una palestra con i suoi abbonamenti; se incassa in app si paga con Stripe e la tessera si attiva da sola.
class PublicGymScreen extends ConsumerStatefulWidget {
  const PublicGymScreen({super.key, required this.gymId});

  final String gymId;

  @override
  ConsumerState<PublicGymScreen> createState() => _PublicGymScreenState();
}

class _PublicGymScreenState extends ConsumerState<PublicGymScreen> {
  // dopo il pagamento si torna nell'app: la tessera nuova compare da sola
  late final _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(membershipsProvider));

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(publicGymProvider(widget.gymId));
    final repo = ref.read(billingRepositoryProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: gym.value?.name ?? ''),
            Expanded(
              child: AsyncView<PublicGym>(
                value: gym,
                onRetry: () => ref.invalidate(publicGymProvider(widget.gymId)),
                data: (g) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    if (g.description?.isNotEmpty == true) Text(g.description!, style: t.bodyMedium),
                    if (g.place.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.place_rounded, size: 16, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Expanded(child: Text(g.place, style: t.bodySmall)),
                      ]),
                    ],
                    if (g.phone?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.phone_rounded, size: 16, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Text(g.phone!, style: t.bodySmall),
                      ]),
                    ],
                    const SizedBox(height: 20),
                    SectionHeader(tr('Abbonamenti')),
                    const SizedBox(height: 8),
                    if (g.plans.isEmpty)
                      Text(tr('Questa palestra non ha ancora abbonamenti in vendita.'), style: t.bodySmall)
                    else
                      for (final p in g.plans)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SoftCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.name, style: t.titleMedium),
                                      Text('${formatPlanDuration(p.durationDays)} · ${formatPrice(p.priceCents)}',
                                          style: t.bodySmall?.copyWith(color: AppColors.inkSoft)),
                                      if (p.description?.isNotEmpty == true) Text(p.description!, style: t.bodySmall),
                                    ],
                                  ),
                                ),
                                if (g.payOnline && (p.priceCents ?? 0) > 0)
                                  FilledButton(
                                    onPressed: () => openStripe(context, () => repo.payPlan(g.id, p.id)),
                                    child: Text(tr('Paga')),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    if (!g.payOnline)
                      Text(tr('Per iscriverti passa in palestra: ti attivano loro la tessera su RepBirds.'),
                          style: t.bodySmall?.copyWith(color: AppColors.muted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
