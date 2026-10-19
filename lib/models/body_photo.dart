import 'json.dart';

/// Foto del fisico nel calendario del profilo (`/body-photos`). Privata di
/// default: la vede solo chi l'ha scattata; se pubblica la vedono tutti.
class BodyPhoto {
  const BodyPhoto({
    required this.id,
    this.imageUrl,
    this.isPublic = false,
    required this.takenAt,
    this.workoutHistoryId,
    this.workoutName,
  });

  final String id;
  final String? imageUrl;
  final bool isPublic;
  final DateTime takenAt;
  final String? workoutHistoryId;

  /// Scheda dell'allenamento dopo cui è stata scattata, se c'è.
  final String? workoutName;

  factory BodyPhoto.fromJson(Json j) => BodyPhoto(
        id: '${j['id']}',
        imageUrl: j['imageUrl'] as String?,
        isPublic: j['isPublic'] == true,
        takenAt: parseInstant(j['takenAt']) ?? DateTime.now(),
        workoutHistoryId: j['workoutHistoryId']?.toString(),
        workoutName: j['workoutName'] as String?,
      );

  BodyPhoto copyWith({bool? isPublic}) => BodyPhoto(
        id: id,
        imageUrl: imageUrl,
        isPublic: isPublic ?? this.isPublic,
        takenAt: takenAt,
        workoutHistoryId: workoutHistoryId,
        workoutName: workoutName,
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
