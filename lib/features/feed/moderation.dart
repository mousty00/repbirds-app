import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/social_repository.dart';
import '../../data/user_repository.dart';

/// Segnala e blocca: richiesti da App Store e Play Store per i contenuti degli utenti.

/// (valore inviato al backend, etichetta mostrata)
List<(String, String)> get _reasons => [
      ('Spam', tr('Spam')),
      ('Contenuto offensivo o violento', tr('Contenuto offensivo o violento')),
      ('Nudità o contenuti sessuali', tr('Nudità o contenuti sessuali')),
      ('Molestie', tr('Molestie')),
      ('Altro', tr('Altro')),
    ];

/// [type]: POST, COMMENT o USER.
Future<void> reportContent(BuildContext context, WidgetRef ref, {required String type, required String targetId}) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tr('Perché lo segnali?'), style: Theme.of(ctx).textTheme.headlineSmall),
          ),
          for (final (r, label) in _reasons) ListTile(title: Text(label), onTap: () => Navigator.pop(ctx, r)),
        ],
      ),
    ),
  );
  if (reason == null) return;
  try {
    await ref.read(userRepositoryProvider).report(type: type, targetId: targetId, reason: reason);
    if (context.mounted) showMessage(context, tr('Segnalazione inviata, la esamineremo entro 24 ore'));
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  }
}

/// Ritorna true se l'utente è stato bloccato.
Future<bool> blockUser(BuildContext context, WidgetRef ref, String username) async {
  final ok = await confirm(
    context,
    title: tr('Bloccare @{username}?', {'username': username}),
    message: tr('Non vedrai più i suoi post e commenti, e non potrà contattarti né mandarti richieste.'),
    ok: tr('Blocca'),
    destructive: true,
  );
  if (!ok) return false;
  try {
    await ref.read(friendshipRepositoryProvider).blockUser(username);
    refreshPosts(ref);
    ref.invalidate(friendsProvider);
    ref.invalidate(userPostsProvider(username));
    if (context.mounted) showMessage(context, tr('@{username} bloccato', {'username': username}));
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
    return false;
  }
}

/// Menu "…" con Segnala e Blocca, per contenuti di altri utenti.
class ModerationMenu extends ConsumerWidget {
  const ModerationMenu({super.key, required this.type, required this.targetId, required this.username, this.onBlocked, this.small = false});

  final String type;
  final String targetId;
  final String username;
  final VoidCallback? onBlocked;
  final bool small;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz_rounded, size: small ? 18 : 24, color: small ? AppColors.muted : null),
      padding: small ? EdgeInsets.zero : const EdgeInsets.all(8),
      constraints: const BoxConstraints(),
      tooltip: tr('Altro'),
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      onSelected: (v) async {
        if (v == 'report') {
          await reportContent(context, ref, type: type, targetId: targetId);
        } else if (await blockUser(context, ref, username)) {
          onBlocked?.call();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'report', child: Text(tr('Segnala'))),
        PopupMenuItem(value: 'block', child: Text(tr('Blocca @{username}', {'username': username}), style: const TextStyle(color: AppColors.danger))),
      ],
    );
  }
}
