import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';

/// La dashboard della palestra: al posto delle tab dell'app, cinque sezioni.
/// Su telefono una barra in basso, su tablet e web (dalla reception) una colonna a sinistra.
class GymShell extends StatelessWidget {
  const GymShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static List<(IconData, String)> get _items => [
    (Icons.space_dashboard_rounded, tr('Panoramica')),
    (Icons.badge_rounded, tr('Iscritti')),
    (Icons.card_membership_rounded, tr('Abbonamenti')),
    (Icons.fitness_center_rounded, tr('Schede')),
    (Icons.event_rounded, tr('Corsi')),
  ];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              backgroundColor: AppColors.card,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: FloatingActionButton(
                  heroTag: 'gym-entrance',
                  tooltip: tr('Ingresso'),
                  onPressed: () => context.push('/gym/entrance'),
                  child: const Icon(Icons.contactless_rounded),
                ),
              ),
              destinations: [for (final (icon, label) in _items) NavigationRailDestination(icon: Icon(icon), label: Text(label))],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [for (final (icon, label) in _items) NavigationDestination(icon: Icon(icon), label: label)],
      ),
    );
  }
}
