import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/ui.dart';
import '../../data/body_photo_repository.dart';
import '../../models/body_photo.dart';
import 'body_photo_prompt.dart';

/// Calendario mensile delle foto del fisico di [username]. Il proprietario
/// ([mine]) vede anche le private, ne aggiunge quando vuole (anche come
/// storia) e può cambiarne la visibilità o eliminarle.
class BodyCalendar extends ConsumerStatefulWidget {
  const BodyCalendar({super.key, required this.username, this.mine = false});

  final String username;
  final bool mine;

  @override
  ConsumerState<BodyCalendar> createState() => _BodyCalendarState();
}

class _BodyCalendarState extends ConsumerState<BodyCalendar> {
  DateTime _month = monthOf(DateTime.now());

  ({String username, DateTime month}) get _key => (username: widget.username, month: _month);

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(bodyPhotosProvider(_key));
    final list = photos.value ?? const <BodyPhoto>[];
    final now = DateTime.now();
    final isCurrent = _month == monthOf(now);
    final compare = list.length >= 2
        ? () => context.push('/body-photos/compare?user=${Uri.encodeComponent(widget.username)}&month=${monthKey(_month)}')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          widget.mine ? tr('Il mio fisico') : tr('Fisico'),
          action: compare == null ? null : tr('Confronta'),
          onAction: compare,
        ),
        if (widget.mine && compare != null && _suggestComparison(now)) ...[
          _CompareBanner(onTap: compare),
          const SizedBox(height: 12),
        ],
        SoftCard(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: tr('Mese precedente'),
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => _shift(-1),
                  ),
                  Expanded(
                    child: Text(
                      toBeginningOfSentenceCase(formatMonthYear(_month)),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Mese successivo'),
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: isCurrent ? null : () => _shift(1),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _MonthGrid(
                month: _month,
                photos: list,
                loading: photos.isLoading && !photos.hasValue,
                onOpen: (photo) => showBodyPhotoViewer(context, photos: list, initial: photo, mine: widget.mine),
              ),
              if (photos.hasError)
                TextButton(onPressed: () => ref.invalidate(bodyPhotosProvider(_key)), child: Text(tr('Riprova')))
              else if (photos.hasValue && list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    widget.mine ? tr('Nessuna foto questo mese.') : tr('Nessuna foto pubblica questo mese.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
              if (widget.mine) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add_a_photo_rounded),
                  label: Text(tr('Aggiungi foto')),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _add() async {
    if (!await showBodyPhotoPrompt(context) || !mounted) return;
    showMessage(context, tr('Foto salvata nel calendario'));
    setState(() => _month = monthOf(DateTime.now()));
  }

  /// Negli ultimi tre giorni del mese corrente, o nella prima settimana per il
  /// mese appena finito: il momento del confronto.
  bool _suggestComparison(DateTime now) {
    if (_month != comparisonMonth(now)) return false;
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return now.day <= 7 || now.day > lastDay - 3;
  }
}

class _CompareBanner extends StatelessWidget {
  const _CompareBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: AppColors.lilac,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.compare_rounded, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Il tuo mese a confronto'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                Text(tr('Metti fianco a fianco la prima e l\'ultima foto del mese.'),
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.photos, required this.loading, required this.onOpen});

  final DateTime month;
  final List<BodyPhoto> photos;
  final bool loading;
  final ValueChanged<BodyPhoto> onOpen;

  @override
  Widget build(BuildContext context) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final offset = DateTime(month.year, month.month).weekday - 1; // lunedì per primo
    final byDay = <int, List<BodyPhoto>>{};
    for (final p in photos) {
      byDay.putIfAbsent(p.takenAt.day, () => []).add(p);
    }
    final monday = DateTime(2024, 1, 1);
    final today = DateTime.now();

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  DateFormat('EEEEE', L10n.lang).format(monday.add(Duration(days: i))).toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.8,
          children: [
            for (var i = 0; i < offset; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              _DayCell(
                day: d,
                photos: byDay[d] ?? const [],
                today: isSameDay(today, DateTime(month.year, month.month, d)),
                loading: loading,
                onOpen: onOpen,
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.photos, required this.today, required this.loading, required this.onOpen});

  final int day;
  final List<BodyPhoto> photos;
  final bool today;
  final bool loading;
  final ValueChanged<BodyPhoto> onOpen;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    final label = Text(
      '$day',
      style: TextStyle(
        fontSize: 12,
        fontWeight: today ? FontWeight.w800 : FontWeight.w500,
        color: photos.isEmpty ? (today ? AppColors.brand : AppColors.inkSoft) : Colors.white,
      ),
    );
    if (photos.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: loading ? AppColors.stroke.withValues(alpha: 0.5) : AppColors.bg,
          borderRadius: radius,
          border: today ? Border.all(color: AppColors.brand, width: 1.5) : null,
        ),
        child: Center(child: label),
      );
    }
    final last = photos.last;
    return Semantics(
      button: true,
      label: tr('Foto del {day}', {'day': formatDate(last.takenAt)}),
      child: GestureDetector(
        onTap: () => onOpen(photos.first),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (AppImage.supports(last.imageUrl))
                AppImage(last.imageUrl!, fallback: const ColoredBox(color: AppColors.lilac))
              else
                const ColoredBox(color: AppColors.lilac),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
              ),
              Positioned(top: 3, left: 5, child: label),
              if (photos.length > 1)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                    child: Text('${photos.length}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le foto del mese a schermo intero, una dopo l'altra, partendo da [initial].
Future<void> showBodyPhotoViewer(BuildContext context,
    {required List<BodyPhoto> photos, required BodyPhoto initial, bool mine = false}) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _BodyPhotoViewer(photos: photos, initial: photos.indexOf(initial).clamp(0, photos.length - 1), mine: mine),
  ));
}

class _BodyPhotoViewer extends ConsumerStatefulWidget {
  const _BodyPhotoViewer({required this.photos, required this.initial, required this.mine});

  final List<BodyPhoto> photos;
  final int initial;
  final bool mine;

  @override
  ConsumerState<_BodyPhotoViewer> createState() => _BodyPhotoViewerState();
}

class _BodyPhotoViewerState extends ConsumerState<_BodyPhotoViewer> {
  late final List<BodyPhoto> _photos = [...widget.photos];
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  bool _busy = false;

  BodyPhoto get _current => _photos[_index];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _setPublic(bool value) async {
    setState(() => _busy = true);
    try {
      final updated = await ref.read(bodyPhotoRepositoryProvider).setVisibility(_current.id, value);
      setState(() => _photos[_index] = _current.copyWith(isPublic: updated.isPublic, isStory: updated.isStory));
      ref.invalidate(bodyPhotosProvider);
      ref.invalidate(bodyStoriesProvider);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: tr('Eliminare la foto?'), ok: tr('Elimina'), destructive: true);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(bodyPhotoRepositoryProvider).delete(_current.id);
      ref.invalidate(bodyPhotosProvider);
      ref.invalidate(bodyStoriesProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        showMessage(context, e.message, error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _current;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(formatDate(p.takenAt)),
        actions: [
          if (widget.mine)
            IconButton(
              tooltip: tr('Elimina'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final url = _photos[i].imageUrl;
                return InteractiveViewer(
                  child: AppImage.supports(url)
                      ? AppImage(url!, fit: BoxFit.contain, fallback: const Icon(Icons.broken_image_rounded, color: Colors.white54))
                      : const Icon(Icons.broken_image_rounded, color: Colors.white54),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.workoutName != null)
                    Text(tr('Dopo {workout}', {'workout': p.workoutName}),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  Text(formatDayTime(p.takenAt), style: const TextStyle(color: Colors.white70)),
                  if (p.isLiveStory(DateTime.now()))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Tag(tr('Nelle storie ancora per {n} h', {'n': math.max(1, p.storyUntil!.difference(DateTime.now()).inHours)}),
                          icon: Icons.amp_stories_rounded, color: AppColors.pink),
                    ),
                  if (widget.mine)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: p.isPublic,
                      onChanged: _busy ? null : _setPublic,
                      secondary: Icon(p.isPublic ? Icons.public_rounded : Icons.lock_rounded, color: Colors.white70),
                      title: Text(tr('Visibile a tutti'), style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        p.isPublic
                            ? (p.isLiveStory(DateTime.now())
                                ? tr('Rendendola privata esce anche dalle storie.')
                                : tr('Chi apre il tuo profilo la vede nel calendario.'))
                            : tr('La vedi solo tu.'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
