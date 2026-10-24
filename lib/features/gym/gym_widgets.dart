import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../models/gym.dart';

/// Pagina della dashboard: titolo grande, azioni a destra, contenuto scorrevole.
class GymPage extends StatelessWidget {
  const GymPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.children,
    this.onRefresh,
    this.fab,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle != null) Text(subtitle!, style: t.bodyMedium?.copyWith(color: AppColors.muted)),
                  Text(title, style: t.headlineMedium, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            for (final a in actions) Padding(padding: const EdgeInsets.only(left: 10), child: a),
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    );
    return Scaffold(
      floatingActionButton: fab,
      body: SafeArea(
        bottom: false,
        child: ContentWidth(
          child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
        ),
      ),
    );
  }
}

/// Numero grande con etichetta, per la panoramica.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.color, required this.value, required this.label, this.onTap});

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      radius: AppRadius.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconChip(icon: icon, color: color, size: 36),
          const SizedBox(height: 12),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text(
            label,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet con titolo e contenuto che si alza sopra la tastiera.
Future<T?> showGymSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 16),
              builder(ctx),
            ],
          ),
        ),
      ),
    ),
  );
}

/// "€ 49,00"; null = prezzo non indicato.
String formatPrice(int? cents) {
  if (cents == null) return tr('Prezzo libero');
  return NumberFormat.simpleCurrency(locale: L10n.lang, name: 'EUR').format(cents / 100);
}

/// "30 giorni", "1 anno"…
String formatPlanDuration(int days) {
  if (days % 365 == 0) return days == 365 ? tr('1 anno') : tr('{n} anni', {'n': days ~/ 365});
  if (days % 30 == 0) return days == 30 ? tr('1 mese') : tr('{n} mesi', {'n': days ~/ 30});
  if (days % 7 == 0) return days == 7 ? tr('1 settimana') : tr('{n} settimane', {'n': days ~/ 7});
  return days == 1 ? tr('1 giorno') : tr('{n} giorni', {'n': days});
}

/// Stato di un iscritto come etichetta colorata.
Widget memberStatusTag(GymMember m) {
  final today = DateUtils.dateOnly(DateTime.now());
  if (m.status == MembershipStatus.suspended) return Tag(tr('Sospeso'), color: AppColors.amber, icon: Icons.pause_rounded);
  if (m.active) return Tag(tr('Attivo'), color: AppColors.mint, icon: Icons.check_rounded);
  if (m.startsOn.isAfter(today)) return Tag(tr('Da iniziare'), color: AppColors.blue, icon: Icons.schedule_rounded);
  return Tag(tr('Scaduto'), color: AppColors.danger, icon: Icons.event_busy_rounded);
}

/// Perché la tessera non è valida, in parole.
String refusalText(CheckIn c) => switch (c.refusal) {
  CheckInRefusal.invalidCode => tr('Tessera non valida o codice scaduto'),
  CheckInRefusal.notAMember => tr('Non è iscritto a questa palestra'),
  CheckInRefusal.suspended => tr('Abbonamento sospeso'),
  CheckInRefusal.notStarted => tr('Abbonamento non ancora iniziato'),
  CheckInRefusal.expired => tr('Abbonamento scaduto'),
  CheckInRefusal.other || null => tr('Ingresso rifiutato'),
};

/// Riga del registro ingressi.
class CheckInRow extends StatelessWidget {
  const CheckInRow({super.key, required this.checkIn});

  final CheckIn checkIn;

  @override
  Widget build(BuildContext context) {
    final c = checkIn;
    final who = c.memberName ?? (c.member != null ? '@${c.member!.username}' : tr('Tessera sconosciuta'));
    final when = c.checkedInAt == null ? '' : DateFormat('HH:mm').format(c.checkedInAt!);
    final how = switch (c.method) {
      'NFC' => 'NFC',
      'MANUAL' => tr('a mano'),
      _ => 'QR',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        radius: AppRadius.md,
        child: Row(
          children: [
            c.member != null
                ? UserAvatar(username: c.member!.username, imageUrl: c.member!.image, size: 40)
                : const IconChip(icon: Icons.help_outline_rounded, color: AppColors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    who,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    c.accepted ? (c.planName ?? tr('Entrato')) : refusalText(c),
                    style: TextStyle(color: c.accepted ? AppColors.inkSoft : AppColors.danger, fontSize: 13),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  c.accepted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: c.accepted ? AppColors.mint : AppColors.danger,
                ),
                Text('$when · $how', style: TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
