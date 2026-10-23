import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/ui.dart';
import '../../data/body_photo_repository.dart';
import '../../models/body_photo.dart';
import '../auth/session.dart';
import 'body_photo_prompt.dart';
import 'photo_editor.dart';

/// Le storie già guardate su questo telefono, per spegnere l'anello di chi non
/// ha niente di nuovo. Bastano gli ultimi id: una storia dura 24 ore.
class StoriesSeen extends Notifier<Set<String>> {
  static const _key = 'repbirds.storiesSeen';
  static const _storage = FlutterSecureStorage();
  static const _keep = 300;

  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null) state = {...state, ...(jsonDecode(raw) as List).map((e) => '$e')};
    } catch (_) {}
  }

  void markSeen(String photoId) {
    if (state.contains(photoId)) return;
    final next = {...state, photoId};
    state = next.length > _keep ? next.skip(next.length - _keep).toSet() : next;
    _storage.write(key: _key, value: jsonEncode(state.toList())).catchError((_) {});
  }
}

final storiesSeenProvider = NotifierProvider<StoriesSeen, Set<String>>(StoriesSeen.new);

/// Posta una foto del fisico come storia; true se è stata pubblicata.
Future<bool> addStory(BuildContext context) => showBodyPhotoPrompt(context, story: true);

/// Barra delle storie in cima a Oggi: la mia per prima (o il "+" per
/// aggiungerla), poi gli amici con una storia nelle ultime 24 ore.
class StoriesBar extends ConsumerWidget {
  const StoriesBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final stories = ref.watch(bodyStoriesProvider).value ?? const <BodyStories>[];
    final seen = ref.watch(storiesSeenProvider);
    final mine = stories.where((s) => s.user.username == me.username).firstOrNull;
    final friends = stories.where((s) => s.user.username != me.username).toList();
    final all = [?mine, ...friends];

    Future<void> add() async {
      if (await addStory(context) && context.mounted) showMessage(context, tr('Storia pubblicata'));
    }

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _Bubble(
            username: me.username,
            image: me.image,
            label: tr('La tua storia'),
            state: mine == null ? _Ring.none : (_unseen(mine, seen) ? _Ring.unseen : _Ring.seen),
            add: true,
            onTap: mine == null ? add : () => showStoryViewer(context, stories: all, initial: 0),
            onAdd: add,
          ),
          for (final (i, s) in friends.indexed)
            _Bubble(
              username: s.user.username,
              image: s.user.image,
              label: s.user.username,
              state: _unseen(s, seen) ? _Ring.unseen : _Ring.seen,
              onTap: () => showStoryViewer(context, stories: all, initial: i + (mine == null ? 0 : 1)),
            ),
        ],
      ),
    );
  }

  static bool _unseen(BodyStories s, Set<String> seen) => s.photos.any((p) => !seen.contains(p.id));
}

enum _Ring { none, unseen, seen }

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.username,
    required this.image,
    required this.label,
    required this.state,
    required this.onTap,
    this.add = false,
    this.onAdd,
  });

  final String username;
  final String? image;
  final String label;
  final _Ring state;
  final VoidCallback onTap;
  final bool add;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    final ring = switch (state) {
      _Ring.unseen => BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [AppColors.pink, AppColors.brand, AppColors.blue]),
        ),
      _Ring.seen => BoxDecoration(shape: BoxShape.circle, color: AppColors.stroke),
      _Ring.none => null,
    };
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: size + 6,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: size + 6,
                      height: size + 6,
                      padding: const EdgeInsets.all(3),
                      decoration: ring,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
                        child: UserAvatar(username: username, imageUrl: image, size: size - 4),
                      ),
                    ),
                    if (add)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: GestureDetector(
                          onTap: onAdd,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.blue,
                              border: Border.all(color: AppColors.bg, width: 2),
                            ),
                            child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Le storie a schermo intero, partendo dall'utente [initial]: avanzano da
/// sole, tocco a destra per la prossima, a sinistra per la precedente, giù per
/// chiudere. Sulle mie c'è il cestino.
Future<void> showStoryViewer(BuildContext context, {required List<BodyStories> stories, required int initial}) {
  if (stories.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    pageBuilder: (_, _, _) => StoryViewer(stories: stories, initial: initial.clamp(0, stories.length - 1)),
    transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
  ));
}

class StoryViewer extends ConsumerStatefulWidget {
  const StoryViewer({super.key, required this.stories, required this.initial});

  final List<BodyStories> stories;
  final int initial;

  /// Quanto resta a schermo ogni foto.
  static const perPhoto = Duration(seconds: 5);

  @override
  ConsumerState<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends ConsumerState<StoryViewer> with SingleTickerProviderStateMixin {
  late final List<BodyStories> _stories = [...widget.stories];
  late int _user = widget.initial;
  int _photo = 0;
  late final AnimationController _timer = AnimationController(vsync: this, duration: StoryViewer.perPhoto)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  bool _busy = false;

  BodyStories get _current => _stories[_user];
  BodyPhoto get _currentPhoto => _current.photos[_photo];

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  void _show() {
    ref.read(storiesSeenProvider.notifier).markSeen(_currentPhoto.id);
    _timer.forward(from: 0);
  }

  void _next() {
    if (_photo < _current.photos.length - 1) {
      setState(() => _photo++);
    } else if (_user < _stories.length - 1) {
      setState(() {
        _user++;
        _photo = 0;
      });
    } else {
      _close();
      return;
    }
    _show();
  }

  void _previous() {
    if (_photo > 0) {
      setState(() => _photo--);
    } else if (_user > 0) {
      setState(() {
        _user--;
        _photo = _current.photos.length - 1;
      });
    }
    _show();
  }

  void _close() {
    _timer.stop();
    if (mounted) Navigator.of(context).pop();
  }

  /// Riapre la mia storia nell'editor e ne sostituisce la foto: resta al suo posto e scade quando doveva.
  Future<void> _edit() async {
    _timer.stop();
    setState(() => _busy = true);
    final photo = _currentPhoto;
    final bytes = photo.imageUrl == null ? null : await AppImage.load(photo.imageUrl!);
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _busy = false);
      showMessage(context, tr('Non riesco ad aprire questa foto.'), error: true);
      _timer.forward();
      return;
    }
    final edited = await showPhotoEditor(context, bytes, done: tr('Salva'));
    if (!mounted) return;
    if (edited == null) {
      setState(() => _busy = false);
      _timer.forward();
      return;
    }
    try {
      final updated = await ref.read(bodyPhotoRepositoryProvider).replaceImage(photo.id, edited);
      ref.invalidate(bodyStoriesProvider);
      ref.invalidate(bodyPhotosProvider);
      if (!mounted) return;
      final photos = [..._current.photos];
      photos[_photo] = updated;
      setState(() {
        _stories[_user] = BodyStories(user: _current.user, photos: photos);
        _busy = false;
      });
      showMessage(context, tr('Storia aggiornata'));
      _timer.forward(from: 0);
    } catch (e) {
      if (mounted) {
        showMessage(context, e is ApiException ? e.message : tr('Qualcosa è andato storto. Riprova.'), error: true);
        setState(() => _busy = false);
        _timer.forward();
      }
    }
  }

  Future<void> _delete() async {
    _timer.stop();
    final ok = await confirm(context,
        title: tr('Eliminare la foto?'), message: tr('Sparisce dalle storie e dal calendario.'), ok: tr('Elimina'), destructive: true);
    if (!mounted) return;
    if (!ok) {
      _timer.forward();
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(bodyPhotoRepositoryProvider).delete(_currentPhoto.id);
      ref.invalidate(bodyStoriesProvider);
      ref.invalidate(bodyPhotosProvider);
      if (!mounted) return;
      final photos = [..._current.photos]..removeAt(_photo);
      if (photos.isEmpty) {
        _stories.removeAt(_user);
        if (_stories.isEmpty || _user >= _stories.length) {
          _close();
          return;
        }
        _photo = 0;
      } else {
        _stories[_user] = BodyStories(user: _current.user, photos: photos);
        _photo = _photo.clamp(0, photos.length - 1);
      }
      setState(() => _busy = false);
      _show();
    } on ApiException catch (e) {
      if (mounted) {
        showMessage(context, e.message, error: true);
        setState(() => _busy = false);
        _timer.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final s = _current;
    final p = _currentPhoto;
    final mine = s.user.username == me.username;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => d.localPosition.dx < MediaQuery.sizeOf(context).width / 3 ? _previous() : _next(),
        onLongPressStart: (_) => _timer.stop(),
        onLongPressEnd: (_) => _timer.forward(),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 200) _close();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppImage.supports(p.imageUrl)
                ? AppImage(p.imageUrl!, fit: BoxFit.contain, fallback: const Icon(Icons.broken_image_rounded, color: Colors.white54))
                : const Icon(Icons.broken_image_rounded, color: Colors.white54),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < s.photos.length; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: AnimatedBuilder(
                                  animation: _timer,
                                  builder: (_, _) => LinearProgressIndicator(
                                    value: i < _photo ? 1 : (i == _photo ? _timer.value : 0),
                                    minHeight: 3,
                                    color: Colors.white,
                                    backgroundColor: Colors.white30,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: mine
                              ? null
                              : () {
                                  _close();
                                  context.push('/u/${s.user.username}');
                                },
                          child: UserAvatar(username: s.user.username, imageUrl: s.user.image, size: 36),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: mine ? tr('La tua storia') : s.user.username,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: '  ${timeAgo(p.takenAt)}', style: const TextStyle(color: Colors.white70)),
                            ]),
                            style: const TextStyle(color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (mine)
                          IconButton(
                            tooltip: tr('Modifica'),
                            color: Colors.white,
                            icon: const Icon(Icons.edit_rounded),
                            onPressed: _busy ? null : _edit,
                          ),
                        if (mine)
                          IconButton(
                            tooltip: tr('Elimina'),
                            color: Colors.white,
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: _busy ? null : _delete,
                          ),
                        IconButton(
                          tooltip: tr('Chiudi'),
                          color: Colors.white,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _close,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (p.workoutName != null)
              Positioned(
                left: 20,
                right: 20,
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
                child: Text(
                  tr('Dopo {workout}', {'workout': p.workoutName}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
