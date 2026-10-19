import '../core/l10n/l10n.dart';
import 'json.dart';
import 'user.dart';

/// Tipi di notifica del backend (`NotificationType`).
enum NotificationKind {
  friendRequest('FRIEND_REQUEST'),
  friendAccepted('FRIEND_ACCEPTED'),
  groupInvite('GROUP_INVITE'),
  groupInviteAccepted('GROUP_INVITE_ACCEPTED'),
  postLiked('POST_LIKED'),
  postCommented('POST_COMMENTED'),
  runInvite('RUN_INVITE'),
  runInviteAccepted('RUN_INVITE_ACCEPTED'),
  routeSaved('ROUTE_SAVED'),
  workoutShared('WORKOUT_SHARED'),
  groupSessionCreated('GROUP_SESSION_CREATED'),
  groupSessionStarted('GROUP_SESSION_STARTED'),
  bodyPhotoMonthly('BODY_PHOTO_MONTHLY'),
  unknown('');

  const NotificationKind(this.wire);

  final String wire;

  static NotificationKind parse(Object? v) =>
      values.firstWhere((k) => k.wire == v, orElse: () => NotificationKind.unknown);
}

/// Una notifica di `GET /notifications`. [referenceId] punta all'amicizia,
/// all'invito, al gruppo o al post a seconda di [kind].
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    this.actor,
    this.referenceId,
    this.detail,
    this.read = false,
    this.createdAt,
  });

  final String id;
  final NotificationKind kind;
  final SimpleUser? actor;
  final String? referenceId;
  final String? detail;
  final bool read;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Json j) => AppNotification(
        id: '${j['id']}',
        kind: NotificationKind.parse(j['type']),
        actor: j['actor'] is Map ? SimpleUser.fromJson(Map<String, dynamic>.from(j['actor'] as Map)) : null,
        referenceId: j['referenceId']?.toString(),
        detail: j['detail'] as String?,
        read: j['read'] == true,
        createdAt: parseInstant(j['createdAt']),
      );

  /// Testo mostrato in lista, dopo "@utente".
  String get text => switch (kind) {
        NotificationKind.friendRequest => tr('ti ha inviato una richiesta di amicizia'),
        NotificationKind.friendAccepted => tr('ha accettato la tua richiesta di amicizia'),
        NotificationKind.groupInvite =>
          detail != null ? tr('ti ha invitato in {group}', {'group': detail}) : tr('ti ha invitato in un gruppo'),
        NotificationKind.groupInviteAccepted =>
          detail != null ? tr('è entrato in {group}', {'group': detail}) : tr('è entrato nel tuo gruppo'),
        NotificationKind.postLiked => tr('ha messo mi piace al tuo post'),
        NotificationKind.postCommented => tr('ha commentato: {comment}', {'comment': detail ?? ''}),
        NotificationKind.runInvite =>
          detail != null ? tr('ti ha invitato a correre: {run}', {'run': detail}) : tr('ti ha invitato a correre'),
        NotificationKind.runInviteAccepted =>
          detail != null ? tr('parteciperà a {run}', {'run': detail}) : tr('parteciperà alla tua corsa'),
        NotificationKind.routeSaved => detail != null
            ? tr('ha salvato il tuo percorso {route}', {'route': detail})
            : tr('ha salvato il tuo percorso'),
        NotificationKind.workoutShared => detail != null
            ? tr('ti ha mandato la scheda {workout}', {'workout': detail})
            : tr('ti ha mandato la scheda'),
        NotificationKind.groupSessionCreated => detail != null
            ? tr('ha messo in programma un allenamento in {group}: ci sei?', {'group': detail})
            : tr('ha messo in programma un allenamento: ci sei?'),
        NotificationKind.groupSessionStarted => detail != null
            ? tr('ha avviato la sessione di {workout}: entra!', {'workout': detail})
            : tr('ha avviato la sessione: entra!'),
        NotificationKind.bodyPhotoMonthly =>
          tr('Il mese è finito: confronta la prima e l\'ultima foto del tuo fisico'),
        NotificationKind.unknown => tr('ha interagito con te'),
      };

  /// Dove porta il tap (sulla riga o sulla push), null se non c'è una schermata.
  String? get route => routeFor(kind, referenceId, actor?.username, detail);

  static String? routeFor(NotificationKind kind, String? referenceId, [String? actorUsername, String? detail]) {
    switch (kind) {
      case NotificationKind.bodyPhotoMonthly:
        // detail è il mese, es. 2026-10; senza (dalla push) il mese da confrontare adesso
        return detail != null ? '/body-photos/compare?month=$detail' : '/body-photos/compare';
      case NotificationKind.postLiked:
      case NotificationKind.postCommented:
        return referenceId != null ? '/posts/$referenceId' : null;
      case NotificationKind.groupInviteAccepted:
        return referenceId != null ? '/group/$referenceId' : null;
      case NotificationKind.runInvite:
      case NotificationKind.runInviteAccepted:
        return referenceId != null ? '/running/event/$referenceId' : '/together';
      case NotificationKind.routeSaved:
        return referenceId != null ? '/running/route/$referenceId' : '/running';
      case NotificationKind.groupSessionCreated:
      case NotificationKind.groupSessionStarted:
        return referenceId != null ? '/group-session/$referenceId' : '/groups';
      case NotificationKind.workoutShared:
        return referenceId != null ? '/workout/$referenceId' : null;
      case NotificationKind.friendAccepted:
        return actorUsername != null ? '/u/$actorUsername' : '/friends';
      case NotificationKind.friendRequest:
      case NotificationKind.groupInvite:
        return '/notifications';
      case NotificationKind.unknown:
        return null;
    }
  }
}
