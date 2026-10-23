import 'json.dart';
import 'user.dart';

/// Foto del fisico nel calendario del profilo (`/body-photos`). Privata di
/// default: la vede solo chi l'ha scattata; se pubblica la vedono tutti. Se
/// postata come storia è pubblica e per 24 ore compare agli amici nella barra
/// delle storie; poi resta nel calendario.
class BodyPhoto {
  const BodyPhoto({
    required this.id,
    this.imageUrl,
    this.isPublic = false,
    required this.takenAt,
    this.workoutHistoryId,
    this.workoutName,
    this.isStory = false,
    this.storyUntil,
  });

  final String id;
  final String? imageUrl;
  final bool isPublic;
  final DateTime takenAt;
  final String? workoutHistoryId;

  /// Scheda dell'allenamento dopo cui è stata scattata, se c'è.
  final String? workoutName;

  final bool isStory;

  /// Quando la storia esce dalla barra degli amici (null se non è una storia).
  final DateTime? storyUntil;

  /// Ancora nella barra delle storie.
  bool isLiveStory(DateTime now) => isStory && isPublic && storyUntil != null && storyUntil!.isAfter(now);

  factory BodyPhoto.fromJson(Json j) => BodyPhoto(
        id: '${j['id']}',
        imageUrl: j['imageUrl'] as String?,
        isPublic: j['isPublic'] == true,
        takenAt: parseInstant(j['takenAt']) ?? DateTime.now(),
        workoutHistoryId: j['workoutHistoryId']?.toString(),
        workoutName: j['workoutName'] as String?,
        isStory: j['isStory'] == true,
        storyUntil: parseInstant(j['storyUntil']),
      );

  BodyPhoto copyWith({bool? isPublic, bool? isStory}) => BodyPhoto(
        id: id,
        imageUrl: imageUrl,
        isPublic: isPublic ?? this.isPublic,
        takenAt: takenAt,
        workoutHistoryId: workoutHistoryId,
        workoutName: workoutName,
        isStory: isStory ?? this.isStory,
        storyUntil: storyUntil,
      );
}

/// Le storie ancora attive di un utente (`/body-photos/stories`), dalla più vecchia.
class BodyStories {
  const BodyStories({required this.user, required this.photos});

  final SimpleUser user;
  final List<BodyPhoto> photos;

  factory BodyStories.fromJson(Json j) => BodyStories(
        user: SimpleUser.fromJson(Map<String, dynamic>.from(j['user'] as Map)),
        photos: parseList(j['photos'], BodyPhoto.fromJson),
      );
}

/// Primo giorno del mese di [d], a mezzanotte locale.
DateTime monthOf(DateTime d) => DateTime(d.year, d.month);

/// "2026-10", come il dettaglio della notifica di fine mese.
String monthKey(DateTime month) => '${month.year}-${month.month.toString().padLeft(2, '0')}';

DateTime? parseMonthKey(String? s) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(s ?? '');
  return m == null ? null : DateTime(int.parse(m[1]!), int.parse(m[2]!));
}

/// Il mese da confrontare: quello corrente, ma nei primi giorni del mese
/// quello appena finito (la notifica arriva l'ultimo giorno, la si apre dopo).
DateTime comparisonMonth(DateTime now) =>
    now.day <= 7 ? DateTime(now.year, now.month - 1) : monthOf(now);
