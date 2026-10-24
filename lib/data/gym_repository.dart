import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/network/api_client.dart';
import '../models/gym.dart';
import '../models/json.dart';
import '../models/workout.dart';
import 'providers.dart';

/// Dashboard della palestra (`/gym/**`, solo account palestra) e registrazione.
class GymRepository {
  GymRepository(this._api);

  final ApiClient _api;

  /// Il backend manda il codice di verifica via email, come per una persona.
  Future<String> signup({
    required String username,
    required String email,
    required String password,
    required String name,
    String? address,
    String? city,
    String? phone,
  }) async {
    final res = await _api.post<Json>(
      '/auth/signup/gym',
      data: {
        'username': username.trim().toLowerCase(),
        'email': email,
        'password': password,
        'name': name,
        'address': ?address,
        'city': ?city,
        'phone': ?phone,
      },
    );
    return res['message'] as String? ?? tr('Registrazione completata');
  }

  Future<Gym> me() async => Gym.fromJson(await _api.get<Json>('/gym/me'));

  Future<Gym> updateMe({required String name, String? description, String? address, String? city, String? phone}) async =>
      Gym.fromJson(
        await _api.put<Json>(
          '/gym/me',
          data: {'name': name, 'description': description, 'address': address, 'city': city, 'phone': phone},
        ),
      );

  // Abbonamenti

  Future<List<GymPlan>> plans() async => parseList(await _api.get<List<dynamic>>('/gym/plans'), GymPlan.fromJson);

  Json _plan(String name, String? description, int? priceCents, int durationDays, bool active) => {
    'name': name,
    'description': description,
    'priceCents': priceCents,
    'durationDays': durationDays,
    'active': active,
  };

  Future<GymPlan> createPlan({
    required String name,
    String? description,
    int? priceCents,
    required int durationDays,
    bool active = true,
  }) async =>
      GymPlan.fromJson(await _api.post<Json>('/gym/plans', data: _plan(name, description, priceCents, durationDays, active)));

  Future<GymPlan> updatePlan(
    String id, {
    required String name,
    String? description,
    int? priceCents,
    required int durationDays,
    bool active = true,
  }) async =>
      GymPlan.fromJson(await _api.put<Json>('/gym/plans/$id', data: _plan(name, description, priceCents, durationDays, active)));

  Future<void> deletePlan(String id) => _api.delete<dynamic>('/gym/plans/$id');

  // Iscritti

  Future<List<GymMember>> members() async => parseList(await _api.get<List<dynamic>>('/gym/members'), GymMember.fromJson);

  /// Abilita (o rinnova) una persona su un abbonamento. Senza date: da oggi per la durata dell'abbonamento.
  Future<GymMember> addMember({required String username, required String planId, DateTime? startsOn, DateTime? endsOn}) async =>
      GymMember.fromJson(
        await _api.post<Json>(
          '/gym/members',
          data: {
            'username': username.trim().toLowerCase(),
            'planId': planId,
            'startsOn': ?formatLocalDate(startsOn),
            'endsOn': ?formatLocalDate(endsOn),
          },
        ),
      );

  Future<GymMember> updateMember(
    String id, {
    String? planId,
    DateTime? startsOn,
    DateTime? endsOn,
    MembershipStatus? status,
  }) async => GymMember.fromJson(
    await _api.put<Json>(
      '/gym/members/$id',
      data: {
        'planId': ?planId,
        'startsOn': ?formatLocalDate(startsOn),
        'endsOn': ?formatLocalDate(endsOn),
        'status': ?status?.wire,
      },
    ),
  );

  Future<void> removeMember(String id) => _api.delete<dynamic>('/gym/members/$id');

  // Schede riservate agli iscritti

  Future<List<Workout>> workouts() async => parseList(await _api.get<List<dynamic>>('/gym/workouts'), Workout.fromJson);

  Future<Workout> createWorkout(WorkoutInput input) async =>
      Workout.fromJson(await _api.post<Json>('/gym/workouts', data: input.toJson()));

  // Corsi

  Future<List<GymCourse>> courses() async => parseList(await _api.get<List<dynamic>>('/gym/courses'), GymCourse.fromJson);

  Future<GymCourse> saveCourse(GymCourseInput input) async => GymCourse.fromJson(
    input.id == null
        ? await _api.post<Json>('/gym/courses', data: input.toJson())
        : await _api.put<Json>('/gym/courses/${input.id}', data: input.toJson()),
  );

  Future<void> deleteCourse(String id) => _api.delete<dynamic>('/gym/courses/$id');

  Future<List<GymEnrollment>> enrollments(String courseId) async =>
      parseList(await _api.get<List<dynamic>>('/gym/courses/$courseId/enrollments'), GymEnrollment.fromJson);

  Future<void> enroll(String courseId, String username) =>
      _api.post<dynamic>('/gym/courses/$courseId/enrollments', data: {'username': username.trim().toLowerCase()});

  Future<void> unenroll(String courseId, String userId) => _api.delete<dynamic>('/gym/courses/$courseId/enrollments/$userId');

  // Ingressi

  /// Codice letto dalla tessera (QR o NFC): la risposta dice chi è e se può entrare.
  Future<CheckIn> checkIn(String code, {required String method}) async =>
      CheckIn.fromJson(await _api.post<Json>('/gym/check-ins', data: {'code': code.trim(), 'method': method}));

  /// Ingresso a mano (telefono dimenticato), con gli stessi controlli sull'abbonamento.
  Future<CheckIn> manualCheckIn(String memberId) async =>
      CheckIn.fromJson(await _api.post<Json>('/gym/members/$memberId/check-in'));

  Future<List<CheckIn>> checkIns({int limit = 50}) async =>
      parseList(await _api.get<List<dynamic>>('/gym/check-ins', query: {'limit': limit}), CheckIn.fromJson);
}

/// Lato iscritto: i miei abbonamenti con la tessera, le schede e i corsi della palestra.
class MembershipRepository {
  MembershipRepository(this._api);

  final ApiClient _api;

  Future<List<Membership>> mine() async => parseList(await _api.get<List<dynamic>>('/memberships'), Membership.fromJson);

  Future<List<GymCourse>> myCourses() async =>
      parseList(await _api.get<List<dynamic>>('/memberships/courses'), GymCourse.fromJson);

  Future<List<Workout>> gymWorkouts(String gymId) async =>
      parseList(await _api.get<List<dynamic>>('/memberships/$gymId/workouts'), Workout.fromJson);

  Future<List<GymCourse>> gymCourses(String gymId) async =>
      parseList(await _api.get<List<dynamic>>('/memberships/$gymId/courses'), GymCourse.fromJson);

  Future<GymCourse> join(String gymId, String courseId) async =>
      GymCourse.fromJson(await _api.post<Json>('/memberships/$gymId/courses/$courseId/enroll'));

  Future<GymCourse> leave(String gymId, String courseId) async =>
      GymCourse.fromJson(await _api.delete<Json>('/memberships/$gymId/courses/$courseId/enroll'));
}

class GymCourseInput {
  const GymCourseInput({
    this.id,
    required this.name,
    this.description,
    this.instructor,
    this.room,
    this.dayOfWeek = const [],
    this.startTime,
    this.durationMinutes,
    this.capacity,
  });

  final String? id;
  final String name;
  final String? description;
  final String? instructor;
  final String? room;
  final List<int> dayOfWeek;
  final TimeOfDayValue? startTime;
  final int? durationMinutes;
  final int? capacity;

  Json toJson() => {
    'name': name,
    'description': description,
    'instructor': instructor,
    'room': room,
    'dayOfWeek': dayOfWeek,
    'startTime': startTime?.toJson(),
    'durationMinutes': durationMinutes,
    'capacity': capacity,
  };
}

final gymRepositoryProvider = Provider<GymRepository>((ref) => GymRepository(ref.watch(apiClientProvider)));

final membershipRepositoryProvider = Provider<MembershipRepository>((ref) => MembershipRepository(ref.watch(apiClientProvider)));

/// L'account loggato è una palestra: l'app mostra la dashboard al posto delle tab.
bool isGymAccount(String? roleName) => roleName?.toLowerCase() == 'gym';

// Dashboard

final gymProvider = FutureProvider<Gym>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(gymRepositoryProvider).me();
});

final gymPlansProvider = FutureProvider<List<GymPlan>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(gymRepositoryProvider).plans();
});

final gymMembersProvider = FutureProvider<List<GymMember>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(gymRepositoryProvider).members();
});

final gymWorkoutsProvider = FutureProvider<List<Workout>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(gymRepositoryProvider).workouts();
});

final gymCoursesProvider = FutureProvider<List<GymCourse>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(gymRepositoryProvider).courses();
});

final gymEnrollmentsProvider = FutureProvider.autoDispose.family<List<GymEnrollment>, String>(
  (ref, courseId) => ref.watch(gymRepositoryProvider).enrollments(courseId),
);

final gymCheckInsProvider = FutureProvider<List<CheckIn>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(gymRepositoryProvider).checkIns();
});

// Iscritto

final membershipsProvider = FutureProvider<List<Membership>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(membershipRepositoryProvider).mine();
});

final myCoursesProvider = FutureProvider<List<GymCourse>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(membershipRepositoryProvider).myCourses();
});

final gymWorkoutsForMemberProvider = FutureProvider.autoDispose.family<List<Workout>, String>(
  (ref, gymId) => ref.watch(membershipRepositoryProvider).gymWorkouts(gymId),
);

final gymCoursesForMemberProvider = FutureProvider.autoDispose.family<List<GymCourse>, String>(
  (ref, gymId) => ref.watch(membershipRepositoryProvider).gymCourses(gymId),
);
