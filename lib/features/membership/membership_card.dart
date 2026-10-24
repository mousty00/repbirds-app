import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/gym/card_code.dart';
import '../../core/gym/nfc_card.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/gym.dart';
import '../../models/user.dart';

/// La tessera: palestra, nome, abbonamento e il QR che cambia ogni 30 secondi.
/// Su Android la stessa tessera risponde anche al lettore NFC della palestra.
class MembershipCardView extends StatefulWidget {
  const MembershipCardView({super.key, required this.membership, required this.user});

  final Membership membership;
  final User user;

  @override
  State<MembershipCardView> createState() => _MembershipCardViewState();
}

class _MembershipCardViewState extends State<MembershipCardView> {
  Timer? _tick;
  DateTime _now = DateTime.now();
  bool _nfc = false;

  @override
  void initState() {
    super.initState();
    final card = widget.membership.card;
    if (card != null) {
      NfcCard.setCard(card);
      NfcCard.available().then((on) {
        if (mounted) setState(() => _nfc = on);
      });
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.membership;
    final card = m.card;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.float,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fitness_center_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.gym.name,
                  style: t.titleLarge?.copyWith(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_nfc && card != null) const Icon(Icons.contactless_rounded, color: Colors.white),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.user.displayName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          Text(
            [
              m.planName ?? tr('Abbonamento'),
              tr('fino al {date}', {'date': formatDate(m.endsOn)}),
            ].join(' · '),
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          if (card != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: QrImageView(
                  data: CardCode.at(card, _now),
                  size: 200,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  semanticsLabel: tr('QR della tessera'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                tr('Il codice cambia tra {s}s', {'s': CardCode.untilNext(card, _now).inSeconds + 1}),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                _nfc ? tr('Avvicina il telefono al lettore o mostra il QR') : tr('Mostra il QR alla reception'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Text(
                m.status == MembershipStatus.suspended
                    ? tr('Abbonamento sospeso: chiedi alla reception')
                    : tr('Abbonamento non attivo: rinnovalo in palestra'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
