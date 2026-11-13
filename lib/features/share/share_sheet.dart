import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../feed/create_post_screen.dart';
import 'share_cards.dart';

/// Cosa condividere: l'immagine riepilogo ([card]), il testo e il link che la
/// accompagnano, e quali strade offrire oltre al foglio di sistema.
///
/// Fuori dall'app (altre app, link, feed) si condivide solo quello che è
/// pubblico: per una cosa privata [privateHint] spiega perché e restano solo
/// [onSendInApp] e [extraActions].
class ShareContent {
  const ShareContent({
    required this.card,
    required this.message,
    required this.fileName,
    this.link,
    this.privateHint,
    this.onSendInApp,
    this.allowFeed = true,
    this.extraActions = const [],
  });

  final Widget card;

  /// Testo che accompagna immagine e link (chat, post).
  final String message;

  /// Link da aprire (scheda, profilo, percorso, post); null se non c'è una
  /// pagina pubblica da aprire, es. una corsa: si condivide solo l'immagine.
  final String? link;

  /// Nome del file immagine, senza estensione.
  final String fileName;

  /// Se presente la cosa è privata: niente condivisione fuori dall'app.
  final String? privateHint;

  /// Se presente, mostra "Invia ad amici o gruppi".
  final void Function(BuildContext context)? onSendInApp;

  /// Mostra "Pubblica nel feed" (un post con l'immagine riepilogo).
  final bool allowFeed;

  /// Altre azioni in fondo, es. "Esporta GPX".
  final List<ShareAction> extraActions;

  bool get outside => privateHint == null;
}

/// Un'azione in più del foglio Condividi. [onTap] riceve il context del foglio
/// (per posizionare il foglio di sistema su iPad).
class ShareAction {
  const ShareAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final Future<void> Function(BuildContext context) onTap;
}

/// Foglio "Condividi": anteprima dell'immagine e le azioni possibili.
Future<void> showShareSheet(BuildContext context, ShareContent content) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
    builder: (_) => _ShareSheet(content: content),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.content});

  final ShareContent content;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _boundary = GlobalKey();
  bool _busy = false;

  ShareContent get c => widget.content;

  /// L'anteprima così com'è a schermo, a 3× (1020×1275 px).
  Future<Uint8List> _capture() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> _shareOutside(BuildContext buttonContext, {required bool image}) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    setState(() => _busy = true);
    try {
      final png = image ? await _capture() : null;
      await SharePlus.instance.share(
        ShareParams(
          text: c.link == null ? c.message : '${c.message}\n${c.link}',
          subject: c.message,
          files: png == null ? null : [XFile.fromData(png, mimeType: 'image/png')],
          fileNameOverrides: png == null ? null : ['${c.fileName}.png'],
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) showMessage(context, tr('Non è stato possibile condividere'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _postToFeed() async {
    setState(() => _busy = true);
    final Uint8List png;
    try {
      png = await _capture();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(
      '/posts/new',
      extra: PostDraft(imageBytes: png, imageName: '${c.fileName}.png', text: c.message),
    );
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: c.link!));
    if (mounted) showMessage(context, tr('Link copiato'));
  }

  void _sendInApp() {
    final send = c.onSendInApp!;
    final parent = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context).pop();
    send(parent);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.stroke, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text(tr('Condividi'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            if (c.outside) ...[
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
                  child: AspectRatio(
                    aspectRatio: shareCardSize.width / shareCardSize.height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: AppShadows.float,
                      ),
                      child: FittedBox(
                        child: RepaintBoundary(key: _boundary, child: c.card),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Builder(
                builder: (buttonContext) => PrimaryButton(
                  label: c.link == null ? tr('WhatsApp, Instagram e altre app') : tr('Invia link (WhatsApp, Telegram…)'),
                  icon: Icons.ios_share_rounded,
                  loading: _busy,
                  onPressed: () => _shareOutside(buttonContext, image: c.link == null),
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              SoftCard(
                color: AppColors.lilacSoft,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded, color: AppColors.lilac),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(c.privateHint!, style: TextStyle(color: AppColors.inkSoft)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            SoftCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  if (c.onSendInApp != null)
                    _Action(
                      icon: Icons.send_rounded,
                      color: AppColors.blue,
                      label: tr('Invia ad amici o gruppi'),
                      onTap: _busy ? null : _sendInApp,
                    ),
                  if (c.outside && c.allowFeed)
                    _Action(
                      icon: Icons.dynamic_feed_rounded,
                      color: AppColors.pink,
                      label: tr('Pubblica nel feed'),
                      onTap: _busy ? null : _postToFeed,
                    ),
                  if (c.outside && c.link != null)
                    Builder(
                      builder: (actionContext) => _Action(
                        icon: Icons.image_rounded,
                        color: AppColors.lilac,
                        label: tr('Condividi immagine (Instagram…)'),
                        onTap: _busy ? null : () => _shareOutside(actionContext, image: true),
                      ),
                    ),
                  if (c.outside && c.link != null)
                    _Action(icon: Icons.link_rounded, color: AppColors.mint, label: tr('Copia link'), onTap: _copyLink),
                  for (final a in c.extraActions)
                    Builder(
                      builder: (actionContext) => _Action(
                        icon: a.icon,
                        color: AppColors.inkSoft,
                        label: a.label,
                        onTap: _busy ? null : () => a.onTap(actionContext),
                      ),
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

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: IconChip(icon: icon, color: color, size: 36),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.muted),
  );
}
