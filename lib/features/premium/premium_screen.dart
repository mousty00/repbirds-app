import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/premium/purchases.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/premium_repository.dart';
import '../../data/providers.dart';
import '../../models/premium.dart';
import '../share/share_links.dart';

/// Se [e] è un 402 (funzione Premium) porta al paywall e torna true.
bool openPaywallIfNeeded(BuildContext context, Object e) {
  if (e is ApiException && e.statusCode == 402) {
    context.push('/premium');
    return true;
  }
  return false;
}

/// RepBirds Premium: cosa include, l'abbonamento, e le funzioni sbloccate.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  Future<List<ProductDetails>>? _products;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(premiumProvider);
    final purchase = ref.watch(premiumPurchasesProvider);
    ref.listen(premiumPurchasesProvider, (_, next) {
      if (next.error != null) showMessage(context, next.error!, error: true);
      if (next.done) showMessage(context, tr('Premium attivo. Grazie!'));
    });
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('RepBirds Premium')),
            Expanded(
              child: AsyncView<PremiumStatus>(
                value: status,
                onRetry: () => ref.invalidate(premiumProvider),
                data: (s) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(24)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
                          const SizedBox(height: 10),
                          Text(
                            s.premium ? tr('Hai Premium') : tr('Allenati meglio con Premium'),
                            style: t.headlineSmall?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.premium
                                ? (s.expiresAt == null
                                    ? tr('Senza scadenza')
                                    : (s.autoRenew == false
                                        ? tr('Scade il {date}', {'date': formatDate(s.expiresAt)})
                                        : tr('Si rinnova il {date}', {'date': formatDate(s.expiresAt)})))
                                : tr('Statistiche avanzate, programmi guidati, foto del fisico illimitate ed export.'),
                            style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Feature(
                      icon: Icons.insights_rounded,
                      color: AppColors.blue,
                      title: tr('Statistiche avanzate'),
                      text: tr('Volume, minuti e sessioni per settimana, gruppi muscolari, serie di settimane e record.'),
                      onTap: s.premium ? () => context.push('/premium/stats') : null,
                    ),
                    _Feature(
                      icon: Icons.route_rounded,
                      color: AppColors.lilac,
                      title: tr('Programmi guidati'),
                      text: tr('Schede pronte per settimane, aggiunte alle tue con un tocco.'),
                      onTap: () => context.push('/programs'),
                    ),
                    _Feature(
                      icon: Icons.photo_library_rounded,
                      color: AppColors.pink,
                      title: tr('Foto del fisico illimitate'),
                      text: tr('Senza Premium ne puoi tenere {n}.', {'n': s.freeBodyPhotos}),
                    ),
                    _Feature(
                      icon: Icons.file_download_rounded,
                      color: AppColors.mint,
                      title: tr('Export degli allenamenti'),
                      text: tr('Tutti gli allenamenti completati in un file CSV per Excel o Numbers.'),
                      onTap: s.premium ? () => exportWorkouts(context, ref) : null,
                    ),
                    const SizedBox(height: 16),
                    if (s.premium) ...[
                      if (s.platform == 'APPLE' || s.platform == 'GOOGLE')
                        OutlinedButton.icon(
                          icon: const Icon(Icons.manage_accounts_rounded),
                          label: Text(tr('Gestisci abbonamento')),
                          onPressed: () => launchUrl(
                            Uri.parse(s.platform == 'APPLE'
                                ? 'https://apps.apple.com/account/subscriptions'
                                : 'https://play.google.com/store/account/subscriptions'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                    ] else if (!PremiumPurchases.supported)
                      Text(tr('Premium si attiva dall\'app per iPhone o Android.'), textAlign: TextAlign.center, style: t.bodySmall)
                    else
                      FutureBuilder<List<ProductDetails>>(
                        future: _products ??= ref.read(premiumPurchasesProvider.notifier).products(s.products),
                        builder: (_, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final products = snap.data ?? const [];
                          if (products.isEmpty) {
                            return Text(tr('Lo store non è raggiungibile ora. Riprova più tardi.'),
                                textAlign: TextAlign.center, style: t.bodySmall);
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final p in products) ...[
                                PrimaryButton(
                                  label: '${p.id.contains('year') ? tr('Annuale') : tr('Mensile')} · ${p.price}',
                                  loading: purchase.busy,
                                  onPressed: purchase.busy ? null : () => ref.read(premiumPurchasesProvider.notifier).buy(p),
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                          );
                        },
                      ),
                    if (!s.premium && PremiumPurchases.supported) ...[
                      TextButton(
                        onPressed: purchase.busy ? null : () => ref.read(premiumPurchasesProvider.notifier).restore(),
                        child: Text(tr('Ripristina acquisti')),
                      ),
                      Text(
                        tr('L\'abbonamento si rinnova da solo finché non lo disdici dalle impostazioni dello store, almeno 24 ore prima della scadenza.'),
                        textAlign: TextAlign.center,
                        style: t.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(onPressed: () => launchUrl(Uri.parse(ShareLinks.terms)), child: Text(tr('Termini'))),
                        TextButton(onPressed: () => launchUrl(Uri.parse(ShareLinks.privacy)), child: Text(tr('Privacy policy'))),
                      ],
                    ),
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

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.color, required this.title, required this.text, this.onTap});

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(
          children: [
            IconChip(icon: icon, color: color, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleSmall),
                  const SizedBox(height: 2),
                  Text(text, style: t.bodySmall?.copyWith(color: AppColors.inkSoft)),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Scarica il CSV degli allenamenti e lo passa al foglio di condivisione.
Future<void> exportWorkouts(BuildContext context, WidgetRef ref) async {
  final box = context.findRenderObject() as RenderBox?;
  try {
    final csv = await ref.read(premiumRepositoryProvider).exportCsv();
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv')],
      fileNameOverrides: ['repbirds-allenamenti.csv'],
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  } on ApiException catch (e) {
    if (!context.mounted || openPaywallIfNeeded(context, e)) return;
    showMessage(context, e.message, error: true);
  }
}

/// Statistiche avanzate (Premium).
class AdvancedStatsScreen extends ConsumerStatefulWidget {
  const AdvancedStatsScreen({super.key});

  @override
  ConsumerState<AdvancedStatsScreen> createState() => _AdvancedStatsScreenState();
}

class _AdvancedStatsScreenState extends ConsumerState<AdvancedStatsScreen> {
  var _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(advancedStatsProvider(_weeks));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Statistiche avanzate')),
            Expanded(
              child: AsyncView<AdvancedStats>(
                value: stats,
                onRetry: () => ref.invalidate(advancedStatsProvider(_weeks)),
                data: (s) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    SegmentedPill(
                      options: [tr('4 sett.'), tr('12 sett.'), tr('1 anno')],
                      index: switch (_weeks) { 4 => 0, 12 => 1, _ => 2 },
                      onChanged: (i) => setState(() => _weeks = const [4, 12, 52][i]),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _Number(value: '${s.currentStreakWeeks}', label: tr('Settimane di fila')),
                        const SizedBox(width: 10),
                        _Number(value: '${s.longestStreakWeeks}', label: tr('Record di settimane')),
                        const SizedBox(width: 10),
                        _Number(value: '${s.totalSessions}', label: tr('Sessioni totali')),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SectionHeader(tr('Sessioni per settimana')),
                    const SizedBox(height: 8),
                    SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: MiniBars(
                        values: [for (final w in s.weeks) w.sessions.toDouble()],
                        highlight: s.weeks.length - 1,
                        color: AppColors.blueSoft,
                        height: 90,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SectionHeader(tr('Volume per settimana (kg)')),
                    const SizedBox(height: 8),
                    SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MiniBars(
                            values: [for (final w in s.weeks) w.volumeKg],
                            highlight: s.weeks.length - 1,
                            color: AppColors.lilacSoft,
                            highlightColor: AppColors.lilac,
                            height: 90,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr('Questa settimana: {kg} kg in {min} min', {
                              'kg': s.weeks.isEmpty ? 0 : s.weeks.last.volumeKg.round(),
                              'min': s.weeks.isEmpty ? 0 : s.weeks.last.minutes,
                            }),
                            style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                    if (s.muscleGroups.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      SectionHeader(tr('Serie per gruppo muscolare')),
                      const SizedBox(height: 8),
                      SoftCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            for (final (group, sets) in s.muscleGroups)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    SizedBox(width: 110, child: Text(group, overflow: TextOverflow.ellipsis)),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: LinearProgressIndicator(
                                          value: sets / s.muscleGroups.first.$2.clamp(1, 1 << 30),
                                          minHeight: 10,
                                          backgroundColor: AppColors.stroke,
                                          color: AppColors.mint,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 44, child: Text('$sets', textAlign: TextAlign.end)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (s.personalBests.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      SectionHeader(tr('Carichi massimi')),
                      const SizedBox(height: 8),
                      SoftCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            for (final (exercise, kg, reps) in s.personalBests)
                              ListTile(
                                dense: true,
                                title: Text(exercise),
                                trailing: Text(
                                  reps == null ? '${_kg(kg)} kg' : '${_kg(kg)} kg × $reps',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _kg(double kg) => kg == kg.roundToDouble() ? '${kg.round()}' : kg.toStringAsFixed(1);
}

class _Number extends StatelessWidget {
  const _Number({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: t.headlineSmall),
            Text(label, style: t.bodySmall?.copyWith(color: AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}

/// Programmi guidati: tutti li vedono, iniziarli richiede Premium.
class ProgramsScreen extends ConsumerWidget {
  const ProgramsScreen({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref, Program p) async {
    if (p.locked) {
      context.push('/premium');
      return;
    }
    final ok = await confirm(
      context,
      title: tr('Iniziare «{name}»?', {'name': p.name}),
      message: tr('Aggiungiamo {n} schede alle tue, già nei giorni giusti. I carichi li scegli tu.', {'n': p.days.length}),
      ok: tr('Inizia'),
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(premiumRepositoryProvider).startProgram(p.slug);
      ref.invalidate(myWorkoutsProvider);
      if (!context.mounted) return;
      showMessage(context, tr('Programma aggiunto alle tue schede'));
      context.go('/workouts');
    } on ApiException catch (e) {
      if (!context.mounted || openPaywallIfNeeded(context, e)) return;
      showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programs = ref.watch(programsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Programmi guidati')),
            Expanded(
              child: AsyncView<List<Program>>(
                value: programs,
                onRetry: () => ref.invalidate(programsProvider),
                data: (list) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final p = list[i];
                    return SoftCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(p.name, style: t.titleMedium)),
                              if (p.locked) const Icon(Icons.lock_rounded, size: 18, color: AppColors.amber),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(p.description, style: t.bodySmall?.copyWith(color: AppColors.inkSoft)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Tag(p.level, color: AppColors.lilac),
                              Tag(tr('{n} settimane', {'n': p.weeks}), color: AppColors.blue),
                              Tag(tr('{n} giorni a settimana', {'n': p.daysPerWeek}), color: AppColors.mint),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final d in p.days)
                            Text(
                              '• ${d.name}: ${d.items.map((it) => '${it.exercise} ${it.sets}×${it.reps}').join(', ')}',
                              style: t.bodySmall,
                            ),
                          const SizedBox(height: 12),
                          PrimaryButton(
                            label: p.locked ? tr('Sblocca con Premium') : tr('Inizia il programma'),
                            icon: p.locked ? Icons.workspace_premium_rounded : Icons.play_arrow_rounded,
                            onPressed: () => _start(context, ref, p),
                          ),
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
