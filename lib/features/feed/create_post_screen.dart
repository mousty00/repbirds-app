import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_exception.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/social_repository.dart';
import '../auth/session.dart';

/// Post già preparato, es. dall'immagine riepilogo di un allenamento condiviso.
class PostDraft {
  const PostDraft({required this.imageBytes, required this.imageName, this.text = ''});

  final Uint8List imageBytes;
  final String imageName;
  final String text;
}

/// Nuovo post: foto (obbligatoria per il backend) + testo.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key, this.draft});

  final PostDraft? draft;

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  late final _text = TextEditingController(text: widget.draft?.text);
  late Uint8List? _bytes = widget.draft?.imageBytes;
  late String _filename = widget.draft?.imageName ?? 'post.jpg';
  bool _loading = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _bytes = bytes;
      _filename = file.name;
    });
  }

  Future<void> _publish() async {
    if (_bytes == null) {
      showMessage(context, tr('Aggiungi una foto al post'), error: true);
      return;
    }
    if (_text.text.trim().isEmpty) {
      showMessage(context, tr('Scrivi qualcosa sul tuo allenamento'), error: true);
      return;
    }
    setState(() => _loading = true);
    final me = ref.read(currentUserProvider);
    try {
      await ref.read(postRepositoryProvider).create(
            userId: me.id,
            content: _text.text.trim(),
            imageBytes: _bytes!,
            imageName: _filename,
          );
      refreshPosts(ref);
      ref.invalidate(userPostsProvider(me.username));
      if (!mounted) return;
      showMessage(context, tr('Post pubblicato'));
      context.pop();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Nuovo post')),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  GestureDetector(
                    onTap: () => _pick(ImageSource.gallery),
                    child: AspectRatio(
                      aspectRatio: 4 / 3.4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.blueSoft,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          image: _bytes == null
                              ? null
                              : DecorationImage(image: MemoryImage(_bytes!), fit: BoxFit.cover),
                        ),
                        child: _bytes == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconChip(icon: Icons.add_photo_alternate_rounded, background: AppColors.card, size: 56),
                                  const SizedBox(height: 12),
                                  Text(tr('Aggiungi una foto'), style: const TextStyle(fontWeight: FontWeight.w700)),
                                ],
                              )
                            : Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: CircleIconButton(
                                    icon: Icons.close_rounded,
                                    size: 40,
                                    onTap: () => setState(() => _bytes = null),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(tr('Galleria')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pick(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(tr('Fotocamera')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SoftCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserAvatar(username: me.username, imageUrl: me.image, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _text,
                            minLines: 4,
                            maxLines: 8,
                            maxLength: 2000,
                            decoration: InputDecoration(
                              hintText: tr('Com\'è andato l\'allenamento?'),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.only(top: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: PillActionButton(
                label: tr('Pubblica'),
                icon: Icons.arrow_upward_rounded,
                loading: _loading,
                onPressed: _publish,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
