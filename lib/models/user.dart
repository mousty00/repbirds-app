import 'json.dart';

/// UserDTO completo (profilo).
class User {
  const User({
    required this.id,
    required this.username,
    this.email,
    this.firstName,
    this.lastName,
    this.birthDate,
    this.image,
    this.roleName,
    this.isAccountVerified,
    this.createdAt,
  });

  final String id;
  final String username;
  final String? email;
  final String? firstName;
  final String? lastName;
  final DateTime? birthDate;
  final String? image;
  final String? roleName;
  final bool? isAccountVerified;
  final DateTime? createdAt;

  String get displayName {
    final full = [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return full.isEmpty ? username : full;
  }

  factory User.fromJson(Json j) => User(
        id: '${j['id']}',
        username: j['username'] as String? ?? '',
        email: j['email'] as String?,
        firstName: j['firstName'] as String?,
        lastName: j['lastName'] as String?,
        birthDate: parseLocalDate(j['birthDate']),
        image: j['image'] as String?,
        roleName: j['roleName'] as String?,
        isAccountVerified: j['isAccountVerified'] as bool?,
        createdAt: parseInstant(j['createdAt']),
      );

  SimpleUser toSimple() =>
      SimpleUser(id: id, username: username, image: image, isAccountVerified: isAccountVerified);
}

/// SimpleUserDTO (liste, ricerca, amicizie).
class SimpleUser {
  const SimpleUser({
    required this.id,
    required this.username,
    this.image,
    this.isAccountVerified,
  });

  final String id;
  final String username;
  final String? image;
  final bool? isAccountVerified;

  factory SimpleUser.fromJson(Json j) => SimpleUser(
        id: '${j['id']}',
        username: j['username'] as String? ?? '',
        image: j['image'] as String?,
        isAccountVerified: j['isAccountVerified'] as bool?,
      );
}

/// Quello che il profilo di un altro mostra oltre ai post. Tempo di allenamento,
/// attività recente (per la streak) e percorsi arrivano solo agli amici.
class UserOverview {
  const UserOverview({
    this.training,
    this.recentActivity,
    this.mutualFriends = const [],
    this.workouts = const [],
    this.exercises = const [],
    this.routes,
  });

  final Duration? training;
  final List<DateTime>? recentActivity;
  final List<SimpleUser> mutualFriends;
  final List<({String id, String name, int exercises})> workouts;
  /// Esercizi pubblici; [saved]: ce l'ho già nei miei esercizi.
  final List<({String id, String name, String muscleGroup, bool saved})> exercises;
  final List<({String id, String name, int? distanceM})>? routes;

  factory UserOverview.fromJson(Json j) {
    List<Json> list(String k) => [for (final e in j[k] as List? ?? const []) e as Json];
    return UserOverview(
      training: j['trainingSeconds'] == null ? null : Duration(seconds: (j['trainingSeconds'] as num).toInt()),
      recentActivity: j['recentActivity'] == null
          ? null
          : [for (final t in j['recentActivity'] as List) DateTime.parse('$t').toLocal()],
      mutualFriends: list('mutualFriends').map(SimpleUser.fromJson).toList(),
      workouts: [
        for (final w in list('workouts')) (id: '${w['id']}', name: '${w['name']}', exercises: (w['exercises'] as num?)?.toInt() ?? 0),
      ],
      exercises: [
        for (final e in list('exercises'))
          (id: '${e['id']}', name: '${e['name']}', muscleGroup: '${e['muscleGroup'] ?? ''}', saved: e['saved'] == true),
      ],
      routes: j['routes'] == null
          ? null
          : [for (final r in list('routes')) (id: '${r['id']}', name: '${r['name']}', distanceM: (r['distanceM'] as num?)?.toInt())],
    );
  }
}
