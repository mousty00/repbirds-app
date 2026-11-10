import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/network/api_client.dart';
import 'package:repbirds_app/core/storage/token_storage.dart';
import 'package:repbirds_app/data/offline_store.dart';
import 'package:repbirds_app/data/workout_repository.dart';

class _Tokens extends TokenStorage {
  @override
  Future<String?> get accessToken async => 'token';

  @override
  Future<String?> get refreshToken async => 'refresh';
}

/// Rete finta: [online] decide se il server risponde; le sessioni ricevute finiscono in [posted].
class _Net implements HttpClientAdapter {
  bool online = true;
  final posted = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (!online) throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    if (o.path.endsWith('/workouts/profile')) {
      return _json([
        {'id': 'w1', 'name': 'Gambe', 'dayOfWeek': [1], 'workoutExercises': []},
      ]);
    }
    if (o.path.endsWith('/workout-history')) {
      posted.add(Map<String, dynamic>.from(o.data as Map));
      return _json({'result': {'id': 'h${posted.length}'}});
    }
    return _json({}, status: 404);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

void main() {
  late _Net net;
  late WorkoutRepository repo;

  setUp(() {
    net = _Net();
    final api = ApiClient(_Tokens(), baseUrl: 'http://api.test')..dio.httpClientAdapter = net;
    repo = WorkoutRepository(api, OfflineStore('u1', storage: MemoryOfflineStorage()));
  });

  test('senza rete le schede arrivano dall\'ultima copia', () async {
    expect((await repo.mine()).single.name, 'Gambe');
    net.online = false;
    expect((await repo.mine()).single.name, 'Gambe');
    expect((await repo.byId('w1')).name, 'Gambe');
  });

  test('una sessione finita offline resta sul telefono e parte quando torna la rete', () async {
    net.online = false;
    final end = DateTime.now();
    final saved = await repo.logSession(workoutId: 'w1', startedAt: end.subtract(const Duration(minutes: 45)), completedAt: end);
    expect(saved.queued, isTrue);
    expect(await repo.flushPending(), 0); // ancora offline: resta in coda

    net.online = true;
    expect(await repo.flushPending(), 1);
    expect(net.posted.single['workoutId'], 'w1');
    expect(await repo.flushPending(), 0); // non la manda due volte
  });

  test('online la sessione va subito al server', () async {
    final end = DateTime.now();
    final saved = await repo.logSession(workoutId: 'w1', startedAt: end.subtract(const Duration(minutes: 30)), completedAt: end);
    expect(saved, (id: 'h1', queued: false));
  });
}
