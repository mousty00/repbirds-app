import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../models/group.dart';
import '../models/json.dart';
import '../models/page.dart';
import '../models/workout.dart';

/// Schede, esercizi, storico (`/workouts`, `/exercises`, `/workout-exercises`,
/// `/workout-history`).
class WorkoutRepository {
  WorkoutRepository(this._api);

  final ApiClient _api;

  Future<List<Workout>> mine() async =>
      parseList(await _api.get<List<dynamic>>('/workouts/profile'), Workout.fromJson);

  /// Schede pubbliche + le mie.
  Future<PageResult<Workout>> explore({int page = 0}) async {
    final res = await _api.get<Json>('/workouts', query: {'page': page, 'size': 30});
    return PageResult.fromJson(res, Workout.fromJson);
  }

  Future<Workout> byId(String id) async => Workout.fromJson(await _api.get<Json>('/workouts/$id'));

  Future<Workout> create(WorkoutInput input) async {
    final res = await _api.post<Json>('/workouts/create', data: input.toJson());
    return Workout.fromJson(Map<String, dynamic>.from(res['result'] as Map));
  }

  Future<void> update(WorkoutInput input) => _api.put<dynamic>('/workouts/update', data: input.toJson());

  Future<void> delete(String id) => _api.delete<dynamic>('/workouts/delete/$id');

  /// Manda la scheda ad amici e/o a tutti i membri dei gruppi indicati: ricevono
  /// una notifica e possono aprirla anche se è privata. Restituisce quante
  /// persone l'hanno ricevuta.
  Future<int> share(String id, {List<String> usernames = const [], List<String> groupIds = const []}) async {
    final res = await _api.post<Json>('/workouts/$id/share', data: {'usernames': usernames, 'groupIds': groupIds});
    return parseInt(res['recipients']);
  }

  // Esercizi della scheda

  Future<void> addExercise(WorkoutExerciseInput input) =>
      _api.post<dynamic>('/workout-exercises/create', data: input.toJson());

  Future<void> updateExercise(WorkoutExerciseInput input) =>
      _api.put<dynamic>('/workout-exercises/update', data: input.toJson());

  Future<void> removeExercise(String id) => _api.delete<dynamic>('/workout-exercises/delete/$id');

  // Libreria esercizi: i miei e quelli che ho salvato da altri

  Future<List<Exercise>> exercises() async {
    final res = await _api.get<Json>('/exercises', query: {'page': 0, 'size': 100, 'sort': 'name'});
    return PageResult.fromJson(res, Exercise.fromJson).results;
  }

  Future<Exercise> createExercise({
    required String name,
    required String muscleGroup,
    String? description,
    bool isPublic = true,
  }) async {
    final res = await _api.post<Json>('/exercises/create', data: {
      'name': name,
      'muscleGroup': muscleGroup,
      'description': description,
      'isPublic': isPublic,
    });
    return Exercise.fromJson(Map<String, dynamic>.from(res['result'] as Map));
  }

  Future<void> deleteExercise(String id) => _api.delete<dynamic>('/exercises/delete/$id');

  /// Mette nella mia lista l'esercizio pubblico di un altro.
  Future<void> saveExercise(String id) => _api.post<dynamic>('/exercises/$id/save');

  /// Toglie dalla mia lista un esercizio salvato; le schede che lo usano lo tengono.
  Future<void> unsaveExercise(String id) => _api.delete<dynamic>('/exercises/$id/save');

  // Storico

  Future<List<WorkoutHistory>> history() async {
    final res = await _api.get<Json>('/workout-history/user', query: {
      'page': 0,
      'size': 100,
      'sort': 'startedAt,desc',
    });
    return PageResult.fromJson(res, WorkoutHistory.fromJson).results;
  }

  Future<List<WorkoutHistory>> groupHistory(String groupId) async {
    final res = await _api.get<Json>('/workout-history/group/$groupId', query: {
      'page': 0,
      'size': 50,
      'sort': 'startedAt,desc',
    });
    return PageResult.fromJson(res, WorkoutHistory.fromJson).results;
  }

  /// Salva la sessione nello storico e ne restituisce l'id (per legarci la foto del fisico).
  Future<String?> logSession({
    required String workoutId,
    String? groupId,
    required DateTime startedAt,
    required DateTime completedAt,
    String? notes,
  }) async {
    final res = await _api.post<dynamic>('/workout-history', data: {
      'workoutId': workoutId,
      'groupId': groupId,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'completedAt': completedAt.toUtc().toIso8601String(),
      'notes': notes,
    });
    final result = res is Map ? res['result'] : null;
    return result is Map ? result['id']?.toString() : null;
  }

  Future<void> deleteHistory(String id) => _api.delete<dynamic>('/workout-history/delete/$id');
}

/// Gruppi di allenamento e membri (`/workout_groups`, `/group_members`).
class GroupRepository {
  GroupRepository(this._api);

  final ApiClient _api;

  Future<List<WorkoutGroup>> all() async {
    final res = await _api.get<Json>('/workout_groups', query: {'page': 0, 'size': 100});
    return PageResult.fromJson(res, WorkoutGroup.fromJson).results;
  }

  Future<WorkoutGroup> byId(String id) async =>
      WorkoutGroup.fromJson(await _api.get<Json>('/workout_groups/$id'));

  /// Un gruppo fisso: solo il nome, le schede vanno sulle sessioni.
  Future<WorkoutGroup> create({required String name}) async {
    final res = await _api.post<Json>('/workout_groups/create', data: {'name': name, 'status': 'active'});
    return WorkoutGroup.fromJson(Map<String, dynamic>.from(res['result'] as Map));
  }

  // Sessioni del gruppo (`/group-sessions`)

  Future<List<GroupSession>> sessions(String groupId) async =>
      parseList(await _api.get<List<dynamic>>('/group-sessions/group/$groupId'), GroupSession.fromJson);

  /// Le prossime sessioni di tutti i miei gruppi, non ancora partite.
  Future<List<GroupSession>> upcomingSessions() async =>
      parseList(await _api.get<List<dynamic>>('/group-sessions/upcoming'), GroupSession.fromJson);

  /// Leggerla segna anche me come collegato (la schermata la rilegge mentre aspetta l'avvio).
  Future<GroupSession> session(String id) async => GroupSession.fromJson(await _api.get<Json>('/group-sessions/$id'));

  /// Con una scheda ([workoutId]) o una corsa su un percorso ([routeId]).
  Future<GroupSession> createSession({
    required String groupId,
    String? workoutId,
    String? routeId,
    DateTime? scheduledFor,
    String? meetingPoint,
  }) async =>
      GroupSession.fromJson(await _api.post<Json>('/group-sessions', data: {
        'groupId': groupId,
        'workoutId': workoutId,
        'routeId': routeId,
        'scheduledFor': scheduledFor?.toUtc().toIso8601String(),
        'meetingPoint': meetingPoint,
      }));

  Future<GroupSession> answer(String id, {required bool going}) async =>
      GroupSession.fromJson(await _api.post<Json>('/group-sessions/$id/attendance', data: {'going': going}));

  Future<GroupSession> start(String id) async => GroupSession.fromJson(await _api.post<Json>('/group-sessions/$id/start'));

  Future<void> deleteSession(String id) => _api.delete<dynamic>('/group-sessions/$id');

  Future<void> delete(String id) => _api.delete<dynamic>('/workout_groups/delete/$id');

  /// Le mie partecipazioni, inclusi gli inviti in attesa.
  Future<List<GroupMember>> myMemberships() async {
    final res = await _api.get<Json>('/group_members', query: {'page': 0, 'size': 100});
    return PageResult.fromJson(res, GroupMember.fromJson).results;
  }

  Future<void> invite({required String groupId, required String username}) =>
      _api.post<dynamic>('/group_members/create', data: {'groupId': groupId, 'invitedUsername': username.trim().toLowerCase()});

  Future<void> acceptInvite(String memberId) =>
      _api.post<dynamic>('/group_members/accept-invitation/$memberId');

  Future<void> rejectInvite(String memberId) =>
      _api.post<dynamic>('/group_members/reject-invitation/$memberId');

  /// Uscire da un gruppo o rimuovere un membro (se sei il creatore).
  Future<void> removeMember(String memberId) => _api.delete<dynamic>('/group_members/delete/$memberId');
}

final workoutRepositoryProvider =
    Provider<WorkoutRepository>((ref) => WorkoutRepository(ref.watch(apiClientProvider)));

final groupRepositoryProvider =
    Provider<GroupRepository>((ref) => GroupRepository(ref.watch(apiClientProvider)));
