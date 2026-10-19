import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/ui.dart';
import '../share/share_links.dart';

/// Aiuto: la guida da rivedere, le domande più comuni e come scriverci.
/// Si apre dal punto di domanda in Oggi e dal profilo.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static List<(IconData, Color, String, String)> get _faq => [
        (
          Icons.fitness_center_rounded,
          AppColors.brand,
          tr('Come creo una scheda?'),
          tr('Tocca + al centro della barra e scegli Scheda. Aggiungi gli esercizi con serie, ripetizioni e recupero, poi salva. La trovi in Allenati.'),
        ),
        (
          Icons.play_arrow_rounded,
          AppColors.blue,
          tr('Come funziona un allenamento?'),
          tr('Apri una scheda e avviala: l\'app ti mostra l\'esercizio, conta le serie e fa partire il recupero. Se l\'app si chiude a metà, alla riapertura riprendi da dove eri rimasto.'),
        ),
        (
          Icons.groups_rounded,
          AppColors.pink,
          tr('Come mi alleno con gli amici?'),
          tr('In Insieme crea un gruppo e invita i tuoi amici. Dal gruppo organizza una sessione: quando chi l\'ha organizzata la avvia, partite tutti dallo stesso istante.'),
        ),
        (
          Icons.person_search_rounded,
          AppColors.lilac,
          tr('Come trovo i miei amici?'),
          tr('In Insieme tocca la lente e cerca per username, poi invia la richiesta d\'amicizia.'),
        ),
        (
          Icons.directions_run_rounded,
          AppColors.mint,
          tr('Come registro una corsa?'),
          tr('In Allenati apri la card Corsa: puoi fare una corsa libera o seguire un percorso, e l\'app registra il tragitto con il GPS.'),
        ),
        (
          Icons.palette_rounded,
          AppColors.amber,
          tr('Come cambio tema, lingua o suoni?'),
          tr('Dal Profilo, nella sezione Account.'),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: Column(
            children: [
              TopBar(title: tr('Aiuto')),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    SoftCard(
                      color: AppColors.inkCard,
                      onTap: () => context.push('/guide'),
                      child: Row(
                        children: [
                          const IconChip(icon: Icons.auto_stories_rounded, color: Colors.white, background: Colors.white24, size: 48),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('Rivedi la guida'),
                                    style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(tr('Come funziona RepBirds, in un minuto.'),
                                    style: t.bodyMedium?.copyWith(color: Colors.white70)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionHeader(tr('Domande frequenti')),
                    SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          for (final (i, (icon, color, q, a)) in _faq.indexed) ...[
                            _Question(icon: icon, color: color, question: q, answer: a),
                            if (i < _faq.length - 1) const Divider(indent: 70, endIndent: 16),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionHeader(tr('Ti serve altro?')),
                    SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        onTap: () => launchUrl(Uri.parse(ShareLinks.support(tr('Aiuto con RepBirds')))),
                        leading: const IconChip(icon: Icons.mail_outline_rounded, color: AppColors.blue, size: 36),
                        title: Text(tr('Scrivici'), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(ShareLinks.supportEmail, style: TextStyle(color: AppColors.muted)),
                        trailing: Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una domanda che si apre toccandola e mostra la risposta.
class _Question extends StatelessWidget {
  const _Question({required this.icon, required this.color, required this.question, required this.answer});

  final IconData icon;
  final Color color;
  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Niente righe sopra e sotto quando è aperta: i divisori sono già nella card.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: IconChip(icon: icon, color: color, size: 36),
        title: Text(question, style: const TextStyle(fontWeight: FontWeight.w600)),
        iconColor: AppColors.ink,
        collapsedIconColor: AppColors.muted,
        childrenPadding: const EdgeInsets.fromLTRB(70, 0, 20, 14),
        expandedAlignment: Alignment.centerLeft,
        children: [
          Text(answer, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft, height: 1.45)),
        ],
      ),
    );
  }
}
