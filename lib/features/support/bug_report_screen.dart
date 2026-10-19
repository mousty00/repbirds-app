import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/user_repository.dart';

/// Segnalazione di un problema dell'app (crash, schermata sbagliata, qualcosa che non va),
/// con screenshot facoltativi. Diversa da "Segnala" sui contenuti degli altri utenti.
class BugReportScreen extends ConsumerStatefulWidget {
  const BugReportScreen({super.key});

  /// Stessi limiti di gymbro-api (BugReportService).
  static const minLength = 10;
  static const maxLength = 2000;
  static const maxImages = 5;

  @override
  ConsumerState<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends ConsumerState<BugReportScreen> {
  final _text = TextEditingController();
  final _images = <({Uint8List bytes, String name})>[];
  bool _loading = false;

  int get _left => BugReportScreen.maxImages - _images.length;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_left <= 0) {
      showMessage(context, tr('Puoi allegare al massimo {n} immagini', {'n': BugReportScreen.maxImages}), error: true);
      return;
    }
    final picker = ImagePicker();
    // screenshot ridimensionati: 5 immagini restano sotto il limite di upload del server
    // pickMultiImage vuole limit >= 2: per l'ultima immagine, o dalla fotocamera, una alla volta
    final List<XFile> files;
    if (source == ImageSource.gallery && _left > 1) {
      files = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 80, limit: _left);
    } else {
      final file = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 80);
      files = file == null ? const [] : [file];
    }
    if (files.isEmpty) return;
    final picked = [for (final f in files.take(_left)) (bytes: await f.readAsBytes(), name: f.name)];
    if (!mounted) return;
    setState(() => _images.addAll(picked));
  }

  static String get _device {
    if (kIsWeb) return 'web';
    try {
      return '${defaultTargetPlatform.name} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return defaultTargetPlatform.name;
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.length < BugReportScreen.minLength) {
      showMessage(context, tr('Descrivi il problema in almeno {n} caratteri', {'n': BugReportScreen.minLength}),
          error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(userRepositoryProvider).reportBug(
            description: text,
            device: _device,
            images: _images,
          );
      if (!mounted) return;
      showMessage(context, tr('Grazie! Abbiamo ricevuto la segnalazione'));
      context.pop();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Segnala un problema')),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  Text(
                    tr('Racconta cosa è successo e cosa ti aspettavi. Se puoi, aggiungi uno screenshot.'),
                    style: t.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  SoftCard(
                    child: TextField(
                      controller: _text,
                      minLines: 5,
                      maxLines: 10,
                      maxLength: BugReportScreen.maxLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: tr('Cosa non ha funzionato?'),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(tr('Screenshot ({n}/{max})', {'n': _images.length, 'max': BugReportScreen.maxImages})),
                  const SizedBox(height: 8),
                  if (_images.isNotEmpty) ...[
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => _Thumb(
                          bytes: _images[i].bytes,
                          onRemove: () => setState(() => _images.removeAt(i)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _left > 0 ? () => _pick(ImageSource.gallery) : null,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(tr('Galleria')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _left > 0 ? () => _pick(ImageSource.camera) : null,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(tr('Fotocamera')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: PillActionButton(
                label: tr('Invia segnalazione'),
                icon: Icons.send_rounded,
                loading: _loading,
                onPressed: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.bytes, required this.onRemove});

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Stack(
        children: [
          Image.memory(bytes, width: 96, height: 120, fit: BoxFit.cover),
          Positioned(
            top: 4,
            right: 4,
            child: CircleIconButton(icon: Icons.close_rounded, size: 32, tooltip: tr('Rimuovi'), onTap: onRemove),
          ),
        ],
      ),
    );
  }
}
