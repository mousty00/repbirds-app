import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/body_photo_repository.dart';

/// Foto del fisico per il calendario del profilo: dopo un allenamento
/// ([workoutHistoryId]) o quando vuoi, dal profilo o dalla barra delle storie.
/// Privata se non si sceglie altrimenti; come storia ([story] la propone già
/// scelta) è pubblica e per 24 ore la vedono gli amici.
/// True se la foto è stata salvata.
Future<bool> showBodyPhotoPrompt(BuildContext context, {String? workoutHistoryId, bool story = false}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _BodyPhotoSheet(workoutHistoryId: workoutHistoryId, story: story),
  );
  return saved ?? false;
}

class _BodyPhotoSheet extends ConsumerStatefulWidget {
  const _BodyPhotoSheet({this.workoutHistoryId, this.story = false});

  final String? workoutHistoryId;
  final bool story;

  @override
  ConsumerState<_BodyPhotoSheet> createState() => _BodyPhotoSheetState();
}

class _BodyPhotoSheetState extends ConsumerState<_BodyPhotoSheet> {
  bool _public = false;
  late bool _story = widget.story;
  bool _saving = false;

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
    if (file == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(bodyPhotoRepositoryProvider).upload(
            imageBytes: await file.readAsBytes(),
            imageName: file.name,
            isPublic: _public || _story,
            asStory: _story,
            workoutHistoryId: widget.workoutHistoryId,
          );
      ref.invalidate(bodyPhotosProvider);
      if (_story) ref.invalidate(bodyStoriesProvider);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconChip(icon: Icons.accessibility_new_rounded, color: AppColors.lilac),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('Foto del fisico'), style: t.headlineSmall)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.workoutHistoryId != null
                  ? tr('Scatta una foto dopo l\'allenamento: la trovi nel calendario del tuo profilo e a fine mese puoi confrontare i progressi.')
                  : tr('La trovi nel calendario del tuo profilo e a fine mese puoi confrontare i progressi.'),
              style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            SoftCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    value: _story,
                    onChanged: _saving ? null : (v) => setState(() => _story = v),
                    secondary: Icon(Icons.amp_stories_rounded, color: AppColors.inkSoft),
                    title: Text(tr('Pubblica come storia'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(tr('Pubblica: i tuoi amici la vedono nelle storie per 24 ore.')),
                  ),
                  SwitchListTile(
                    value: _public || _story,
                    onChanged: _saving || _story ? null : (v) => setState(() => _public = v),
                    secondary: Icon(_public || _story ? Icons.public_rounded : Icons.lock_rounded, color: AppColors.inkSoft),
                    title: Text(tr('Visibile a tutti'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_public || _story ? tr('Chi apre il tuo profilo la vede nel calendario.') : tr('La vedi solo tu.')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_saving)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else ...[
              PrimaryButton(
                label: tr('Scatta una foto'),
                icon: Icons.photo_camera_rounded,
                onPressed: () => _pick(ImageSource.camera),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded),
                label: Text(tr('Scegli dalla galleria')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Non ora'), style: TextStyle(color: AppColors.inkSoft)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
