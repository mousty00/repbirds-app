import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/gym/card_code.dart';
import 'package:repbirds_app/core/mock/mock_backend.dart';
import 'package:repbirds_app/models/gym.dart';
import 'package:repbirds_app/models/user.dart';

void main() {
  group('codice della tessera', () {
    // stesso vettore di GymCardServiceTest in repbirds-api: le due parti devono combaciare
    const card = MembershipCard(
      cardId: '7b7f6f4e-2c1a-4d3b-9e8f-0a1b2c3d4e5f',
      secret: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
    );
    final at = DateTime.utc(2026, 10, 24, 10);

    test('uguale a quello del server', () {
      expect(CardCode.at(card, at), 'RBG1.7b7f6f4e-2c1a-4d3b-9e8f-0a1b2c3d4e5f.59761200.hzkFdMZPXmT6wtcQ');
    });

    test('cambia ogni 30 secondi', () {
      expect(CardCode.at(card, at.add(const Duration(seconds: 29))), CardCode.at(card, at));
      expect(CardCode.at(card, at.add(const Duration(seconds: 30))), isNot(CardCode.at(card, at)));
      expect(CardCode.untilNext(card, at.add(const Duration(seconds: 10))), const Duration(seconds: 20));
    });

    test('riconosce la forma del codice', () {
      expect(CardCode.looksValid(CardCode.at(card, at)), isTrue);
      expect(CardCode.looksValid('https://example.com'), isFalse);
    });
  });

  group('palestre nel mock', () {
    late Dio dio;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://mock/api'))..interceptors.add(MockBackend(latency: Duration.zero, enabled: () => true));
    });

    Future<dynamic> get(String path) async => (await dio.get<dynamic>(path)).data;
    Future<dynamic> post(String path, [Object? data]) async => (await dio.post<dynamic>(path, data: data)).data;
    Future<void> login(String username) => post('/auth/login', {'username': username, 'password': 'x'});

    test('il login palestra è un account palestra, gli altri no', () async {
      final res = await post('/auth/login', {'username': 'palestra', 'password': 'x'});
      expect(User.fromJson(res['result'] as Map<String, dynamic>).roleName, 'Gym');
      expect(Gym.fromJson(await get('/gym/me') as Map<String, dynamic>).stats?.activeMembers, greaterThan(0));

      await login('mousty');
      await expectLater(
        get('/gym/me'),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 403)),
      );
    });

    test('la tessera dell\'iscritto apre, un codice falso no', () async {
      await login('mousty');
      final memberships = [for (final m in await get('/memberships') as List) Membership.fromJson(m as Map<String, dynamic>)];
      final card = memberships.single.card!;
      final code = CardCode.at(card, DateTime.now());

      await login('palestra');
      final ok = CheckIn.fromJson(await post('/gym/check-ins', {'code': code, 'method': 'NFC'}) as Map<String, dynamic>);
      expect(ok.accepted, isTrue);
      expect(ok.member?.username, 'mousty');

      final forged = CheckIn.fromJson(
        await post('/gym/check-ins', {'code': '${code.substring(0, code.length - 2)}xx', 'method': 'QR'}) as Map<String, dynamic>,
      );
      expect(forged.refusal, CheckInRefusal.invalidCode);
    });

    test('schede e corsi della palestra solo per gli iscritti', () async {
      await login('palestra');
      final created = await post('/gym/workouts', {'name': 'Solo iscritti', 'dayOfWeek': [2]});
      expect(created['gymId'], isNotNull);
      expect(created['isPublic'], isFalse);

      await login('mousty');
      final gymId = (await get('/memberships') as List).single['gym']['id'] as String;
      final workouts = await get('/memberships/$gymId/workouts') as List;
      expect(workouts.map((w) => w['name']), contains('Solo iscritti'));
      final public = (await get('/workouts') as Map)['results'] as List;
      expect(public.map((w) => w['name']), isNot(contains('Solo iscritti')));

      final course = GymCourse.fromJson((await get('/memberships/$gymId/courses') as List).first as Map<String, dynamic>);
      final joined = GymCourse.fromJson(await post('/memberships/$gymId/courses/${course.id}/enroll') as Map<String, dynamic>);
      expect(joined.enrolled, isTrue);
    });
  });
}
