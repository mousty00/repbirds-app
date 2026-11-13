import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'skeleton.dart';
import 'ui.dart';

/// Rende un [AsyncValue] con caricamento / errore con "Riprova" / dati.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
    this.sliver = false,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  /// Se true, caricamento ed errore sono avvolti in `SliverToBoxAdapter`
  /// (e `data` deve restituire uno sliver).
  final bool sliver;

  @override
  Widget build(BuildContext context) {
    Widget wrap(Widget w) => sliver ? SliverToBoxAdapter(child: w) : w;
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: data,
      loading: () => wrap(loading ?? const SkeletonList()),
      error: (e, _) => wrap(ErrorBlock(message: '$e', onRetry: onRetry)),
    );
  }
}

class ErrorBlock extends StatelessWidget {
  const ErrorBlock({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SoftCard(
        child: Column(
          children: [
            const IconChip(icon: Icons.cloud_off_rounded, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: Text(tr('Riprova'))),
            ],
          ],
        ),
      ),
    );
  }
}
