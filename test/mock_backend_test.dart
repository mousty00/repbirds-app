import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymbro_app/core/mock/mock_backend.dart';
import 'package:gymbro_app/models/group.dart';
import 'package:gymbro_app/models/notification.dart';
import 'package:gymbro_app/models/page.dart';
import 'package:gymbro_app/models/running.dart';
import 'package:gymbro_app/models/social.dart';
import 'package:gymbro_app/models/user.dart';
import 'package:gymbro_app/models/workout.dart';

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://mock/api'))..interceptors.add(MockBackend(latency: Duration.zero, enabled: () => true));
  });

  Future<dynamic> get(String path, [Map<String, dynamic>? q]) async => (await dio.get<dynamic>(path, queryParameters: q)).data;
  Future<dynamic> post(String path, [Object? data, Map<String, dynamic>? q]) async =>
      (await dio.post<dynamic>(path, data: data, queryParameters: q)).data;

  test('login e casi di errore simulati', () async {
    final res = await post('/auth/login', {'username': 'qualsiasi', 'password': 'x'});
    expect(User.fromJson(res['result'] as Map<String, dynamic>).username, 'mousty');

    await expectLater(
      post('/auth/login', {'username': 'nonverificato', 'password': 'x'}),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 403)),
    );
    await expectLater(
      post('/auth/login', {'username': 'a', 'password': 'sbagliata'}),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 401)),
    );
  });

  test('schede: crea, aggiungi esercizio, rileggi', () async {
    final created = await post('/workouts/create', {'name': 'Test', 'isPublic': false, 'dayOfWeek': [1], 'startTime': '07:00:00'});
    final id = (created['result'] as Map)['id'] as String;
    await post('/workout-exercises/create', {'workoutId': id, 'exerciseId': 'e0', 'sets': 3, 'reps': 10, 'restSeconds': 60, 'position': 1});
    final w = Workout.fromJson(await get('/workouts/$id') as Map<String, dynamic>);
    expect(w.exercises.single.exerciseName, 'Panca piana');
    expect(w.startTime!.label, '07:00');
    final mine = (await get('/workouts/profile') as List).map((e) => Workout.fromJson(e as Map<String, dynamic>));
    expect(mine.any((x) => x.id == id), isTrue);
  });

  test('like, commento e feed amici', () async {
    final feed = PageResult.fromJson(await get('/posts') as Map<String, dynamic>, Post.fromJson);
    final target = feed.results.firstWhere((p) => p.likeBy('mousty') == null);
    final like = await post('/likes/create', {'postId': target.id, 'userId': 'u1'});
    await post('/comments/create', {'postId': target.id, 'content': 'Forza!'});
    final after = Post.fromJson(await get('/posts/${target.id}') as Map<String, dynamic>);
    expect(after.numLikes, target.numLikes + 1);
    expect(after.likeBy('mousty')?.id, like['id']);
    expect(after.comments.last.content, 'Forza!');

    final friends = (await get('/friendship/posts') as List).map((e) => Post.fromJson(e as Map<String, dynamic>));
    expect(friends.every((p) => p.user.username != 'luca.cali'), isTrue);
  });

  test('richiesta di amicizia e invito al gruppo accettati', () async {
    final requests = (await get('/friendship/requests') as List).map((e) => Friendship.fromJson(e as Map<String, dynamic>)).toList();
    expect(requests.single.user.username, 'sara.runs');
    await get('/friendship/accept/${requests.single.id}');
    expect(await get('/friendship/requests'), isEmpty);

    final invites = PageResult.fromJson(await get('/group_members') as Map<String, dynamic>, GroupMember.fromJson)
        .results
        .where((m) => m.status == GroupMemberStatus.invited)
        .toList();
    expect(invites.single.groupName, isNotNull);
    await post('/group_members/accept-invitation/${invites.single.id}');
    final groups = PageResult.fromJson(await get('/workout_groups') as Map<String, dynamic>, WorkoutGroup.fromJson).results;
    expect(groups.any((g) => g.id == invites.single.groupId), isTrue);
  });

  test('post con foto in multipart', () async {
    final form = FormData()
      ..files.add(MapEntry('request', MultipartFile.fromString('{"userId":"u1","content":"Nuovo"}')))
      ..files.add(MapEntry('imageFile', MultipartFile.fromBytes([1, 2, 3], filename: 'a.jpg')));
    final res = await post('/posts/create', form);
    final p = Post.fromJson(res['result'] as Map<String, dynamic>);
    expect(p.image, startsWith(MockBackend.uploadScheme));
    expect(MockBackend.uploads[p.image!.substring(MockBackend.uploadScheme.length)], [1, 2, 3]);
  });

  test('segnalazione di un problema con screenshot in multipart', () async {
    final res = await post('/bug-reports', FormData.fromMap({
      'description': 'Il timer si blocca alla terza serie',
      'images': [MultipartFile.fromBytes([1, 2, 3], filename: 'a.png')],
    }));
    expect(res['message'], 'Bug report received');

    await expectLater(
      post('/bug-reports', FormData.fromMap({'description': 'rotto'})),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 400)),
    );
  });

  test('notifiche: lista, badge, lettura e registrazione dispositivo', () async {
    final page = PageResult.fromJson(await get('/notifications') as Map<String, dynamic>, AppNotification.fromJson);
    expect(page.results, isNotEmpty);
    expect(page.results.first.actor, isNotNull);
    final commented = page.results.firstWhere((n) => n.kind == NotificationKind.postCommented);
    expect(commented.route, startsWith('/posts/'));

    expect((await get('/notifications/unread-count'))['count'], greaterThan(0));
    await post('/notifications/${commented.id}/read');
    await post('/notifications/read-all');
    expect((await get('/notifications/unread-count'))['count'], 0);

    await post('/devices', {'token': 'tok', 'platform': 'ANDROID'});
    await dio.delete<dynamic>('/devices', queryParameters: {'token': 'tok'});
  });

  test('notifiche: cancella una o tutte', () async {
    Future<List<AppNotification>> list() async =>
        PageResult.fromJson(await get('/notifications') as Map<String, dynamic>, AppNotification.fromJson).results;
    final before = await list();
    await dio.delete<dynamic>('/notifications/${before.first.id}');
    expect((await list()).map((n) => n.id), isNot(contains(before.first.id)));
    await expectLater(
      dio.delete<dynamic>('/notifications/${before.first.id}'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 404)),
    );

    await dio.delete<dynamic>('/notifications');
    expect(await list(), isEmpty);
    expect((await get('/notifications/unread-count'))['count'], 0);
  });

  test('corsa: percorso salvato, percorso pubblico di un amico salvato, corsa di gruppo e corsa registrata', () async {
    final plan = RoutePlan.fromJson(await post('/routes/plan', {
      'waypoints': [
        [45.46, 9.19],
        [45.47, 9.18],
      ],
    }) as Map<String, dynamic>);
    expect(plan.distanceM, greaterThan(1000));

    final created = await post('/routes/create', {
      'name': 'Giro test',
      'isPublic': false,
      'waypoints': [
        [45.46, 9.19],
        [45.47, 9.18],
      ],
      'points': plan.rawPoints,
    });
    final route = RunRoute.fromJson(Map<String, dynamic>.from(created['result'] as Map));
    final mine = PageResult.fromJson(await get('/routes') as Map<String, dynamic>, RunRoute.fromJson).results;
    expect(mine.first.id, route.id);

    // il percorso pubblico di giulia (amica) si salva come copia privata, una volta sola
    final friends = PageResult.fromJson(await get('/routes/friends') as Map<String, dynamic>, RunRoute.fromJson).results;
    final hers = friends.single;
    expect(hers.owner.username, 'giulia.fit');
    final copy = RunRoute.fromJson(Map<String, dynamic>.from((await post('/routes/${hers.id}/save'))['result'] as Map));
    expect(copy.originalAuthor?.username, 'giulia.fit');
    expect(copy.isPublic, isFalse);
    await expectLater(
      post('/routes/${hers.id}/save'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 409)),
    );

    // invito di giulia: accetto e registro la corsa per l'evento
    final events = PageResult.fromJson(await get('/run-events') as Map<String, dynamic>, RunEvent.fromJson).results;
    final invite = events.firstWhere((e) => e.isInvited);
    await post('/run-events/${invite.id}/accept');
    final accepted = RunEvent.fromJson(await get('/run-events/${invite.id}') as Map<String, dynamic>);
    expect(accepted.canRun, isTrue);

    final now = DateTime.now().toUtc();
    final saved = await post('/runs/create', {
      'eventId': invite.id,
      'startedAt': now.subtract(const Duration(minutes: 10)).toIso8601String(),
      'completedAt': now.toIso8601String(),
      'durationS': 600,
      'track': [
        [45.46, 9.19, null, 0.0],
        [45.47, 9.18, null, 600.0],
      ],
    });
    final run = RunActivity.fromJson(Map<String, dynamic>.from(saved['result'] as Map));
    expect(run.routeId, invite.route.id);
    expect(run.paceSPerKm, isNotNull);
    final results = (await get('/run-events/${invite.id}/runs') as List).map((e) => RunActivity.fromJson(e as Map<String, dynamic>));
    expect(results.map((r) => r.id), contains(run.id));

    final created2 = await post('/run-events/create', {
      'routeId': route.id,
      'title': 'Uscita',
      'startsAt': now.add(const Duration(days: 1)).toIso8601String(),
      'invitedUsernames': ['marco_lifts'],
    });
    final event = RunEvent.fromJson(Map<String, dynamic>.from(created2['result'] as Map));
    expect(event.isOwner, isTrue);
    expect(event.participants.single.status, RunParticipantStatus.invited);
  });

  test('sessioni di gruppo: rispondo, l\'organizzatore avvia, tutti vedono lo stesso inizio', () async {
    final group = (await post('/workout_groups/create', {'name': 'Squadra', 'status': 'active'}))['result'] as Map;
    expect(group['workout'], isNull);
    final created = await post('/group-sessions', {'groupId': group['id'], 'workoutId': 'w1'}) as Map;
    expect(created['startedAt'], isNull);
    final started = await post('/group-sessions/${created['id']}/start') as Map;
    expect(started['startedAt'], isNotNull);
    final read = await get('/group-sessions/${created['id']}') as Map;
    expect(read['startedAt'], started['startedAt']);

    // nella sessione di un altro gruppo dico "partecipo"
    final other = ((await get('/group-sessions/upcoming')) as List).cast<Map>().firstWhere((s) => (s['organizer'] as Map)['username'] != 'mousty');
    final answered = await post('/group-sessions/${other['id']}/attendance', {'going': true}) as Map;
    expect(answered['myStatus'], 'going');
    expect((answered['attendees'] as List).map((a) => (a as Map)['status']), contains('going'));
  });

  test('una sessione di gruppo può essere una corsa su un percorso', () async {
    final group = (await post('/workout_groups/create', {'name': 'Runner', 'status': 'active'}))['result'] as Map;
    final route = ((await get('/routes')) as Map)['results'][0] as Map;
    final s = await post('/group-sessions', {'groupId': group['id'], 'routeId': route['id'], 'meetingPoint': 'Parco'}) as Map;
    expect(s['workout'], isNull);
    expect((s['route'] as Map)['id'], route['id']);
    expect(s['meetingPoint'], 'Parco');
    await expectLater(post('/group-sessions', {'groupId': group['id']}), throwsA(anything));
  });

  test('profilo di un amico: numeri, amici in comune e contenuti pubblici', () async {
    final friend = UserOverview.fromJson(await get('/users/username/giulia.fit/overview') as Map<String, dynamic>);
    expect(friend.training, isNotNull);
    expect(friend.recentActivity, isNotEmpty);
    expect(friend.workouts.map((w) => w.name), contains('Full body 45\''));
    expect(friend.mutualFriends.map((u) => u.username), contains('marco_lifts'));

    final stranger = UserOverview.fromJson(await get('/users/username/luca.cali/overview') as Map<String, dynamic>);
    expect(stranger.training, isNull);
    expect(stranger.routes, isNull);
  });
  test('esercizi: i miei e i salvati; quelli pubblici degli altri solo nel loro profilo finché non li salvo', () async {
    Future<List<String>> mine() async =>
        [for (final e in ((await get('/exercises') as Map)['results'] as List)) '${(e as Map)['id']}'];
    final giulia = UserOverview.fromJson(await get('/users/username/giulia.fit/overview') as Map<String, dynamic>);
    final notSaved = giulia.exercises.firstWhere((e) => !e.saved);
    expect(await mine(), isNot(contains(notSaved.id)));

    await dio.post<dynamic>('/exercises/${notSaved.id}/save');
    expect(await mine(), contains(notSaved.id));
    final again = UserOverview.fromJson(await get('/users/username/giulia.fit/overview') as Map<String, dynamic>);
    expect(again.exercises.firstWhere((e) => e.id == notSaved.id).saved, isTrue);

    await dio.delete<dynamic>('/exercises/${notSaved.id}/save');
    expect(await mine(), isNot(contains(notSaved.id)));
  });

  test('richiesta inviata: si vede tra le inviate e si può ritirare', () async {
    await post('/friendship/create', null, {'friendUsername': 'luca.cali'});
    final sent = (await get('/friendship/sent') as List).map((e) => Friendship.fromJson(e as Map<String, dynamic>)).toList();
    final request = sent.singleWhere((f) => f.friend.username == 'luca.cali');

    await expectLater(
      post('/friendship/create', null, {'friendUsername': 'luca.cali'}),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 409)),
    );

    await dio.delete<dynamic>('/friendship/cancel/${request.id}');
    expect((await get('/friendship/sent') as List), isEmpty);
    await expectLater(
      dio.delete<dynamic>('/friendship/cancel/${request.id}'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 404)),
    );
  });

  test('like doppio rifiutato come sul backend', () async {
    final feed = PageResult.fromJson(await get('/posts') as Map<String, dynamic>, Post.fromJson);
    final liked = feed.results.firstWhere((p) => p.likeBy('mousty') != null);
    await expectLater(
      post('/likes/create', {'postId': liked.id, 'userId': 'u1'}),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 409)),
    );
  });
}
