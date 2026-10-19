import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/body_photo_repository.dart';
import '../../models/body_photo.dart';

/// Il confronto di fine mese: la prima e l'ultima foto del fisico del mese,
/// fianco a fianco.
class BodyCompareScreen extends ConsumerWidget {
  const BodyCompareScreen({super.key, required this.username, required this.month});

  final String username;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (username: username, month: monthOf(month));
    final photos = ref.watch(bodyPhotosProvider(key));
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: toBeginningOfSentenceCase(formatMonthYear(month))),
            Expanded(
              child: AsyncView<List<BodyPhoto>>(
                value: photos,
                onRetry: () => ref.invalidate(bodyPhotosProvider(key)),
                data: (list) {
                  if (list.length < 2) {
                    return ListView(children: [
                      EmptyState(
                        icon: Icons.compare_rounded,
                        title: tr('Servono almeno due foto'),
                        message: tr('Aggiungi una foto del fisico alla fine degli allenamenti di questo mese.'),
                      ),
                    ]);
                  }
                  final first = list.first;
                  final last = list.last;
                  final days = DateTime(last.takenAt.year, last.takenAt.month, last.takenAt.day)
                      .difference(DateTime(first.takenAt.year, first.takenAt.month, first.takenAt.day))
                      .inDays;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _Side(label: tr('Prima'), photo: first)),
                          const SizedBox(width: 12),
                          Expanded(child: _Side(label: tr('Dopo'), photo: last)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SoftCard(
                        child: Row(
                          children: [
                            Expanded(child: _Stat(value: '$days', label: days == 1 ? tr('giorno') : tr('giorni'))),
                            Expanded(child: _Stat(value: '${list.length}', label: tr('foto nel mese'))),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.photo});

  final String label;
  final BodyPhoto photo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: AppImage.supports(photo.imageUrl)
                ? AppImage(photo.imageUrl!, fallback: ColoredBox(color: AppColors.stroke))
                : ColoredBox(color: AppColors.stroke),
          ),
        ),
        const SizedBox(height: 6),
        Text(formatDate(photo.takenAt), style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }
}
