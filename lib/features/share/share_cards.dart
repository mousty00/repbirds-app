import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/ui.dart';
import '../../models/running.dart';
import '../../models/social.dart';
import '../../models/user.dart';
import '../../models/workout.dart';
import '../running/geo.dart';
import 'share_links.dart';

// Card riepilogo da condividere come immagine (storie, chat, feed). Hanno
// dimensioni fisse 4:5 così l'immagine esportata è sempre uguale, a
// prescindere dallo schermo: 340×425 punti, salvati a 3× = 1020×1275 px.

const shareCardSize = Size(340, 425);

/// Scheda: nome, autore, numeri e i primi esercizi.
class WorkoutShareCard extends StatelessWidget {
  const WorkoutShareCard({super.key, required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final sets = w.exercises.fold<int>(0, (a, e) => a + e.sets);
    final minutes = w.exercises.fold<int>(0, (a, e) => a + e.sets * (45 + e.restSeconds)) ~/ 60;
    const maxRows = 5;
    final shown = w.exercises.take(maxRows).toList();
    return _CardFrame(
      label: tr('Scheda'),
      icon: Icons.fitness_center_rounded,
      footer: ShareLinks.workout(w.id),
      children: [
        Text(w.name, style: _title, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (w.user != null) Text(tr('di @{username}', {'username': w.user!.username}), style: _subtitle),
        const SizedBox(height: 14),
        Row(
          children: [
            _Stat(value: '${w.exercises.length}', label: tr('esercizi')),
            _Stat(value: '$sets', label: tr('serie')),
            _Stat(value: minutes > 0 ? '~$minutes' : '—', label: tr('minuti')),
          ],
        ),
        const SizedBox(height: 14),
        for (final e in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    e.exerciseName ?? tr('Esercizio'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: LightColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(e.summary, style: const TextStyle(fontSize: 13, color: LightColors.inkSoft)),
              ],
            ),
          ),
        if (w.exercises.length > maxRows)
          Text(tr('+ altri {count}', {'count': w.exercises.length - maxRows}), style: const TextStyle(fontSize: 13, color: LightColors.muted)),
      ],
    );
  }
}

/// Sessione completata: quando, quanto è durata, che scheda.
class SessionShareCard extends StatelessWidget {
  const SessionShareCard({super.key, required this.session, this.workout, this.username});

  final WorkoutHistory session;

  /// La scheda della sessione, se la conosciamo (nome ed esercizi).
  final Workout? workout;
  final String? username;

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final sets = w?.exercises.fold<int>(0, (a, e) => a + e.sets) ?? 0;
    return _CardFrame(
      label: tr('Completato'),
      icon: Icons.emoji_events_rounded,
      footer: w != null ? ShareLinks.workout(w.id) : ShareLinks.webBaseUrl.replaceFirst(RegExp('^https?://'), ''),
      children: [
        Text(formatDate(session.startedAt), style: _subtitle),
        const SizedBox(height: 6),
        Text(w?.name ?? tr('Allenamento'), style: _title, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (username != null) Text('@$username', style: _subtitle),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatDuration(session.duration),
            style: const TextStyle(fontSize: 44, height: 1, fontWeight: FontWeight.w800, color: LightColors.ink),
          ),
        ),
        Text(tr('di allenamento'), style: const TextStyle(color: LightColors.inkSoft, fontSize: 14)),
        const SizedBox(height: 16),
        Row(
          children: [
            if (w != null) ...[
              _Stat(value: '${w.exercises.length}', label: tr('esercizi')),
              _Stat(value: '$sets', label: tr('serie')),
            ],
            if (session.groupId != null) _Stat(value: '👥', label: tr('di gruppo')),
          ],
        ),
        if (session.notes?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Text(
            '"${session.notes}"',
            style: const TextStyle(fontStyle: FontStyle.italic, color: LightColors.inkSoft, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

/// Profilo: foto, nome e i numeri principali.
class ProfileShareCard extends StatelessWidget {
  const ProfileShareCard({super.key, required this.user, this.sessions, this.trained, this.friends});

  final User user;
  final int? sessions;
  final Duration? trained;
  final int? friends;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      label: tr('Allenati con me'),
      icon: Icons.waving_hand_rounded,
      footer: ShareLinks.profile(user.username),
      children: [
        const Spacer(),
        Center(
          child: UserAvatar(username: user.username, imageUrl: user.image, size: 112, ring: true),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(user.displayName, style: _title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Center(child: Text('@${user.username}', style: _subtitle)),
        const SizedBox(height: 18),
        Row(
          children: [
            if (sessions != null) _Stat(value: '$sessions', label: tr('sessioni'), center: true),
            if (trained != null)
              _Stat(
                value: trained!.inHours > 0 ? '${trained!.inHours} h' : formatDuration(trained),
                label: tr('allenato'),
                center: true,
              ),
            if (friends != null) _Stat(value: '$friends', label: tr('amici'), center: true),
          ],
        ),
        const Spacer(),
      ],
    );
  }
}

/// Percorso di corsa: forma, distanza, dislivello.
class RouteShareCard extends StatelessWidget {
  const RouteShareCard({super.key, required this.route});

  final RunRoute route;

  @override
  Widget build(BuildContext context) {
    final author = route.originalAuthor ?? route.owner;
    return _CardFrame(
      label: tr('Percorso'),
      icon: Icons.route_rounded,
      footer: ShareLinks.route(route.id),
      children: [
        Text(route.name, style: _title, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(tr('di @{username}', {'username': author.username}), style: _subtitle),
        const SizedBox(height: 10),
        Expanded(
          child: TrackShape(points: route.points, color: LightColors.blue),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Stat(value: formatDistance(route.distanceM), label: tr('distanza')),
            _Stat(value: route.elevationGainM == null ? '–' : '+${route.elevationGainM} m', label: tr('dislivello')),
          ],
        ),
      ],
    );
  }
}

/// Corsa registrata: traccia, distanza, tempo, passo.
class RunShareCard extends StatelessWidget {
  const RunShareCard({super.key, required this.run});

  final RunActivity run;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      label: tr('Corsa'),
      icon: Icons.directions_run_rounded,
      footer: ShareLinks.webBaseUrl,
      children: [
        Text(formatDate(run.startedAt), style: _subtitle),
        Text(run.title, style: _title, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('@${run.user.username}', style: _subtitle),
        const SizedBox(height: 10),
        Expanded(
          child: TrackShape(points: run.track, color: LightColors.pink),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Stat(value: formatDistance(run.distanceM), label: tr('distanza')),
            _Stat(value: formatSeconds(run.durationS), label: tr('tempo')),
            _Stat(value: formatPace(run.paceSPerKm), label: tr('passo /km')),
          ],
        ),
      ],
    );
  }
}

/// Post: la foto con autore e testo.
class PostShareCard extends StatelessWidget {
  const PostShareCard({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final image = post.image;
    return _CardFrame(
      label: tr('Post'),
      icon: Icons.photo_camera_rounded,
      footer: ShareLinks.post(post.id),
      children: [
        Row(
          children: [
            UserAvatar(username: post.user.username, imageUrl: post.user.image, size: 32),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '@${post.user.username}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: LightColors.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox.expand(
              child: AppImage.supports(image)
                  ? AppImage(image!, fallback: const ColoredBox(color: LightColors.blueSoft))
                  : const ColoredBox(color: LightColors.blueSoft),
            ),
          ),
        ),
        if (post.content.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            post.content,
            style: const TextStyle(fontSize: 13.5, color: LightColors.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// La forma di un percorso o di una traccia, senza mappa sotto: le tile
/// esterne non servono e non finiscono nell'immagine.
class TrackShape extends StatelessWidget {
  const TrackShape({super.key, required this.points, required this.color});

  final List<LatLng> points;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: CustomPaint(painter: _TrackPainter(points, color), size: Size.infinite),
  );
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.points, this.color);

  final List<LatLng> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    // Proiezione equirettangolare: per qualche km va benissimo.
    final lat0 = points.first.latitude * math.pi / 180;
    final xs = [for (final p in points) p.longitude * math.cos(lat0)];
    final ys = [for (final p in points) -p.latitude];
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    const pad = 18.0;
    final w = math.max(maxX - minX, 1e-9), h = math.max(maxY - minY, 1e-9);
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final dx = (size.width - w * scale) / 2, dy = (size.height - h * scale) / 2;
    Offset at(int i) => Offset(dx + (xs[i] - minX) * scale, dy + (ys[i] - minY) * scale);

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      path,
      stroke
        ..color = Colors.white
        ..strokeWidth = 9,
    );
    canvas.drawPath(
      path,
      stroke
        ..color = color
        ..strokeWidth = 5,
    );
    canvas.drawCircle(at(0), 6, Paint()..color = LightColors.mint);
    canvas.drawCircle(at(points.length - 1), 6, Paint()..color = LightColors.ink);
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.points != points || old.color != color;
}

const _title = TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w800, color: LightColors.ink);
const _subtitle = TextStyle(fontSize: 14, color: LightColors.inkSoft, fontWeight: FontWeight.w500);

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.label, required this.icon, required this.footer, required this.children});

  final String label;
  final IconData icon;
  final String footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: shareCardSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          color: LightColors.skyTop,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ShaderMask(
                        shaderCallback: LightColors.brandGradient.createShader,
                        child: const Text(
                          'RepBirds',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Tag(label, icon: icon, color: LightColors.blue),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    footer.replaceFirst(RegExp('^https?://'), ''),
                    style: const TextStyle(fontSize: 11, color: LightColors.muted, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.center = false});

  final String value;
  final String label;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: center ? 0 : 8),
        child: Column(
          crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: LightColors.ink),
                  maxLines: 1,
                ),
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 12, color: LightColors.muted)),
          ],
        ),
      ),
    );
  }
}
