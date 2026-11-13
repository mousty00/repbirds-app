import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/billing_repository.dart';
import '../../models/billing.dart';
import 'gym_widgets.dart';

/// Nome leggibile di un piano RepBirds.
String tierLabel(String tier) => switch (tier) {
      'STARTER' => 'Starter',
      'PRO' => 'Pro',
      'BUSINESS' => 'Business',
      _ => tr('Gratis'),
    };

/// Apre una pagina di Stripe (pagamento, portale, configurazione incassi) nel browser.
Future<void> openStripe(BuildContext context, Future<String> Function() url) async {
  try {
    final link = await url();
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  }
}

/// Lato palestra: il piano RepBirds (quanti soci copre), gli incassi online e i pagamenti.
class GymBillingScreen extends ConsumerStatefulWidget {
  const GymBillingScreen({super.key});

  @override
  ConsumerState<GymBillingScreen> createState() => _GymBillingScreenState();
}

class _GymBillingScreenState extends ConsumerState<GymBillingScreen> {
  // al ritorno dalla pagina di Stripe si rilegge tutto
  late final _lifecycle = AppLifecycleListener(onResume: _refresh);

  void _refresh() {
    ref.invalidate(gymBillingProvider);
    ref.invalidate(gymPaymentsProvider);
  }

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
    final billing = ref.watch(gymBillingProvider);
    final repo = ref.read(billingRepositoryProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Piano e pagamenti')),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: AsyncView<GymBilling>(
                  value: billing,
                  onRetry: _refresh,
                  data: (b) => ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      SoftCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(tr('Piano {name}', {'name': tierLabel(b.tier)}), style: t.titleLarge)),
                                if (b.pastDue) Tag(tr('Pagamento non riuscito'), color: AppColors.danger),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              b.memberLimit == null
                                  ? tr('{n} soci attivi, senza limite', {'n': b.activeMembers})
                                  : tr('{n} soci attivi su {max}', {'n': b.activeMembers, 'max': b.memberLimit!}),
                              style: t.bodyMedium,
                            ),
                            if (b.memberLimit != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: (b.activeMembers / b.memberLimit!).clamp(0, 1).toDouble(),
                                  minHeight: 10,
                                  backgroundColor: AppColors.stroke,
                                  color: b.activeMembers >= b.memberLimit! ? AppColors.danger : AppColors.mint,
                                ),
                              ),
                            ],
                            if (b.currentPeriodEnd != null) ...[
                              const SizedBox(height: 8),
                              Text(tr('Prossimo rinnovo: {date}', {'date': formatDate(b.currentPeriodEnd)}),
                                  style: t.bodySmall?.copyWith(color: AppColors.muted)),
                            ],
                            if (b.canManageSubscription) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.receipt_long_rounded),
                                label: Text(tr('Fatture e metodo di pagamento')),
                                onPressed: () => openStripe(context, repo.portal),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SectionHeader(tr('Piani')),
                      const SizedBox(height: 8),
                      for (final tier in b.tiers)
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
                                      Text(tierLabel(tier.tier), style: t.titleMedium),
                                      Text(
                                        [
                                          tier.memberLimit == null
                                              ? tr('Soci illimitati')
                                              : tr('Fino a {n} soci', {'n': tier.memberLimit!}),
                                          tier.priceCents == 0
                                              ? tr('Gratis')
                                              : tr('{price} al mese', {'price': formatPrice(tier.priceCents)}),
                                        ].join(' · '),
                                        style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
                                      ),
                                    ],
                                  ),
                                ),
                                if (tier.tier == b.tier)
                                  Tag(tr('Attuale'), color: AppColors.mint)
                                else if (tier.priceCents > 0 && !b.canManageSubscription)
                                  FilledButton(
                                    onPressed: () => openStripe(context, () => repo.checkout(tier.tier)),
                                    child: Text(tr('Scegli')),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (b.canManageSubscription)
                        Text(tr('Per cambiare piano usa «Fatture e metodo di pagamento».'),
                            style: t.bodySmall?.copyWith(color: AppColors.muted)),
                      const SizedBox(height: 20),
                      SectionHeader(tr('Abbonamenti pagati in app')),
                      const SizedBox(height: 8),
                      SoftCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.onlinePayments
                                  ? tr('I soci possono pagare gli abbonamenti nell\'app. I soldi arrivano sul tuo conto, meno una commissione del {fee}%.',
                                      {'fee': _percent(b.feePercent)})
                                  : tr('Fai pagare gli abbonamenti direttamente nell\'app: il socio paga con carta, Apple Pay o Google Pay e la tessera si rinnova da sola.'),
                              style: t.bodyMedium,
                            ),
                            if (!b.onlinePayments) ...[
                              const SizedBox(height: 12),
                              PrimaryButton(
                                label: b.paymentsConnected ? tr('Completa la configurazione') : tr('Attiva i pagamenti'),
                                icon: Icons.account_balance_rounded,
                                onPressed: () => openStripe(context, repo.connect),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (b.paymentsConnected) ...[
                        const SizedBox(height: 20),
                        SectionHeader(tr('Ultimi pagamenti')),
                        const SizedBox(height: 8),
                        const _Payments(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _percent(double p) => p == p.roundToDouble() ? '${p.round()}' : p.toStringAsFixed(1);
}

class _Payments extends ConsumerWidget {
  const _Payments();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return AsyncView<List<GymPayment>>(
      value: ref.watch(gymPaymentsProvider),
      onRetry: () => ref.invalidate(gymPaymentsProvider),
      data: (list) => list.isEmpty
          ? Text(tr('Ancora nessun pagamento'), style: t.bodySmall?.copyWith(color: AppColors.muted))
          : SoftCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final p in list)
                    ListTile(
                      dense: true,
                      title: Text('${p.username} · ${p.planName ?? ''}'),
                      subtitle: Text(timeAgo(p.paidAt ?? p.createdAt)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatPrice(p.netCents), style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            switch (p.status) {
                              'PAID' => tr('Pagato'),
                              'FAILED' => tr('Non riuscito'),
                              _ => tr('In attesa'),
                            },
                            style: t.labelSmall?.copyWith(color: p.status == 'PAID' ? AppColors.mint : AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
