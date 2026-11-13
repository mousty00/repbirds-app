import 'package:material_ui/material_ui.dart';

import '../../core/l10n/l10n.dart';
import '../../core/utils/formatters.dart';
import '../../models/running.dart';
import '../../models/social.dart';
import '../../models/user.dart';
import '../../models/workout.dart';
import '../running/geo.dart';
import '../running/gpx_share.dart';
import 'send_workout_sheet.dart';
import 'share_cards.dart';
import 'share_links.dart';
import 'share_sheet.dart';

// Regola: fuori dall'app (altre app, link, feed) va solo quello che è pubblico.
// Una scheda privata il proprietario può solo mandarla ad amici e gruppi dentro
// l'app; un percorso privato si può solo esportare in GPX.

/// Condividi una scheda. Una scheda privata di qualcun altro (ricevuta) la
/// puoi usare, ma non passarla ad altri.
Future<void> shareWorkout(BuildContext context, Workout workout, {required bool mine}) {
  final canSendInApp = mine || workout.isPublic;
  return showShareSheet(
    context,
    ShareContent(
      card: WorkoutShareCard(workout: workout),
      message: mine
          ? tr('La mia scheda "{name}" su RepBirds 💪', {'name': workout.name})
          : tr('Scheda "{name}" su RepBirds 💪', {'name': workout.name}),
      link: ShareLinks.workout(workout.id),
      fileName: gpxFileName(workout.name),
      privateHint: workout.isPublic
          ? null
          : mine
          ? tr('La scheda è privata: puoi mandarla ad amici e gruppi. Rendila pubblica per condividerla fuori dall\'app.')
          : tr('Questa scheda è privata: puoi allenarti con lei ma non condividerla.'),
      onSendInApp: canSendInApp ? (ctx) => showSendWorkoutSheet(ctx, workout) : null,
    ),
  );
}

/// Condividi una sessione completata (dallo storico). L'immagine è tua; il link
/// alla scheda c'è solo se la scheda è pubblica.
Future<void> shareSession(BuildContext context, WorkoutHistory session, {Workout? workout, String? username}) {
  final name = workout?.name ?? tr('Allenamento');
  final mine = workout != null && workout.user?.username == username;
  return showShareSheet(
    context,
    ShareContent(
      card: SessionShareCard(session: session, workout: workout, username: username),
      message: tr('Allenamento completato: {name} 🔥', {'name': name}),
      link: workout != null && workout.isPublic ? ShareLinks.workout(workout.id) : null,
      fileName: 'allenamento-${gpxFileName(name)}',
      onSendInApp: workout != null && (mine || workout.isPublic) ? (ctx) => showSendWorkoutSheet(ctx, workout) : null,
    ),
  );
}

/// Condividi un profilo (il mio, con i numeri, o quello di un altro).
Future<void> shareProfile(
  BuildContext context,
  User user, {
  bool mine = false,
  int? sessions,
  Duration? trained,
  int? friends,
}) {
  return showShareSheet(
    context,
    ShareContent(
      card: ProfileShareCard(user: user, sessions: sessions, trained: trained, friends: friends),
      message: mine
          ? tr('Allenati con me su RepBirds! Sono @{username}', {'username': user.username})
          : tr('@{username} su RepBirds', {'username': user.username}),
      link: ShareLinks.profile(user.username),
      fileName: 'repbirds-${gpxFileName(user.username)}',
      allowFeed: mine,
    ),
  );
}

/// Condividi un percorso di corsa. Pubblico: immagine e link (lo aprono gli
/// amici dell'autore). Privato: solo GPX.
Future<void> shareRoute(BuildContext context, RunRoute route, {required Future<String> Function() loadGpx}) {
  return showShareSheet(
    context,
    ShareContent(
      card: RouteShareCard(route: route),
      message: tr('Percorso "{name}" ({distance}) su RepBirds 🏃', {
        'name': route.name,
        'distance': formatDistance(route.distanceM),
      }),
      link: ShareLinks.route(route.id),
      fileName: gpxFileName(route.name),
      privateHint: route.isPublic
          ? null
          : tr('Il percorso è privato: rendilo pubblico per condividerlo, oppure esporta il GPX.'),
      allowFeed: false,
      extraActions: [_gpxAction(loadGpx, gpxFileName(route.name))],
    ),
  );
}

/// Condividi una corsa registrata: l'immagine con traccia e numeri (la corsa in
/// sé la vede solo chi c'era, quindi niente link), più il GPX.
Future<void> shareRun(
  BuildContext context,
  RunActivity run, {
  required bool mine,
  required Future<String> Function() loadGpx,
}) {
  final file = gpxFileName('${run.title} ${formatDate(run.startedAt)}');
  return showShareSheet(
    context,
    ShareContent(
      card: RunShareCard(run: run),
      message: mine
          ? tr('Ho corso {distance} su RepBirds 🏃', {'distance': formatDistance(run.distanceM)})
          : tr('@{username} ha corso {distance} su RepBirds 🏃', {
              'username': run.user.username,
              'distance': formatDistance(run.distanceM),
            }),
      fileName: file,
      privateHint: mine ? null : tr('Puoi condividere solo le tue corse.'),
      allowFeed: mine,
      extraActions: [_gpxAction(loadGpx, file)],
    ),
  );
}

/// Condividi un post del feed.
Future<void> sharePost(BuildContext context, Post post) {
  return showShareSheet(
    context,
    ShareContent(
      card: PostShareCard(post: post),
      message: post.content.isEmpty ? tr('Post di @{username} su RepBirds', {'username': post.user.username}) : post.content,
      link: ShareLinks.post(post.id),
      fileName: 'post-${gpxFileName(post.user.username)}',
      allowFeed: false,
    ),
  );
}

ShareAction _gpxAction(Future<String> Function() load, String fileName) => ShareAction(
  icon: Icons.download_rounded,
  label: tr('Esporta GPX (Strava, Garmin…)'),
  onTap: (ctx) => shareGpx(ctx, load, fileName),
);
