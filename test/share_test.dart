import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/mock/mock_backend.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:repbirds_app/features/share/share_actions.dart';
import 'package:repbirds_app/features/share/share_cards.dart';
import 'package:repbirds_app/features/share/share_links.dart';
import 'package:repbirds_app/models/notification.dart';
import 'package:repbirds_app/models/running.dart';
import 'package:repbirds_app/models/social.dart';
import 'package:repbirds_app/models/user.dart';
import 'package:repbirds_app/models/workout.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  group('link condivisi', () {
    test('scheda e profilo puntano al sito', () {
      expect(ShareLinks.workout('abc'), 'https://repbirds.com/w/abc');
      expect(ShareLinks.profile('giulia.fit'), 'https://repbirds.com/u/giulia.fit');
      expect(ShareLinks.route('r1'), 'https://repbirds.com/r/r1');
      expect(ShareLinks.post('p1'), 'https://repbirds.com/p/p1');
    });

    test('la notifica di una scheda ricevuta apre la scheda', () {
      final n = AppNotification.fromJson({
        'id': 'n1',
        'type': 'WORKOUT_SHARED',
        'actor': {'id': 'u2', 'username': 'giulia.fit'},
        'referenceId': 'w4',
        'detail': 'Full body',
      });
      expect(n.kind, NotificationKind.workoutShared);
      expect(n.route, '/workout/w4');
      expect(n.text, contains('Full body'));
    });
  });

  group('invio di una scheda (mock)', () {
    late Dio dio;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://mock/api'))
        ..interceptors.add(MockBackend(latency: Duration.zero, enabled: () => true));
    });

    Future<int?> share(String id, Map<String, dynamic> body) async {
      final res = await dio.post<dynamic>('/workouts/$id/share', data: body);
      return (res.data as Map)['recipients'] as int?;
    }

    Matcher status(int code) => throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', code));

    test('ad amici e gruppi, non a sconosciuti', () async {
      expect(
        await share('w2', {
          'usernames': ['giulia.fit', 'mousty'],
        }),
        1,
      );
      expect(
        await share('w2', {
          'groupIds': ['g2'],
        }),
        greaterThanOrEqualTo(1),
      );
      await expectLater(
        share('w2', {
          'usernames': ['luca.cali'],
        }),
        status(403),
      );
      await expectLater(share('w2', {'usernames': <String>[]}), status(400));
    });
  });

  group('card da condividere', () {
    final workout = Workout(
      id: 'w1',
      name: 'Una scheda dal nome davvero molto lungo per vedere se va a capo bene',
      user: const SimpleUser(id: 'u1', username: 'mousty'),
      exercises: [
        for (var i = 1; i <= 8; i++)
          WorkoutExercise(
            id: 'we$i',
            workoutId: 'w1',
            exerciseId: 'e$i',
            exerciseName: 'Esercizio numero $i con nome lungo',
            sets: 4,
            reps: 8,
            weight: 62.5,
            restSeconds: 90,
            position: i,
          ),
      ],
    );

    Future<void> pump(WidgetTester tester, Widget card) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: Center(child: card)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byWidget(card)), shareCardSize);
    }

    testWidgets('scheda: mostra i primi esercizi e quanti altri', (tester) async {
      await pump(tester, WorkoutShareCard(workout: workout));
      expect(find.text('+ altri 3'), findsOneWidget);
      expect(find.text('repbirds.com/w/w1'), findsOneWidget);
    });

    testWidgets('sessione completata', (tester) async {
      final session = WorkoutHistory(
        id: 'h1',
        workoutId: 'w1',
        groupId: 'g1',
        startedAt: DateTime(2026, 10, 14, 18),
        completedAt: DateTime(2026, 10, 14, 19, 5),
        notes: 'Nuovo record sulla panca, e anche un po\' di fatica in più del solito sulle trazioni',
      );
      await pump(tester, SessionShareCard(session: session, workout: workout, username: 'mousty'));
      expect(find.text('1 h 5 min'), findsOneWidget);
    });

    testWidgets('profilo', (tester) async {
      const user = User(id: 'u1', username: 'mousty', firstName: 'Mousty');
      await pump(tester, const ProfileShareCard(user: user, sessions: 42, trained: Duration(hours: 31), friends: 7));
      expect(find.text('@mousty'), findsOneWidget);
      expect(find.text('repbirds.com/u/mousty'), findsOneWidget);
    });

    const track = [LatLng(45.4642, 9.19), LatLng(45.468, 9.185), LatLng(45.4705, 9.1795), LatLng(45.466, 9.175)];

    testWidgets('percorso', (tester) async {
      const route = RunRoute(
        id: 'r1',
        name: 'Giro dei Navigli',
        owner: SimpleUser(id: 'u1', username: 'mousty'),
        waypoints: track,
        points: track,
        distanceM: 5230,
        elevationGainM: 12,
        isPublic: true,
      );
      await pump(tester, const RouteShareCard(route: route));
      expect(find.text('5,23 km'), findsOneWidget);
    });

    testWidgets('corsa', (tester) async {
      final run = RunActivity(
        id: 'a1',
        user: const SimpleUser(id: 'u1', username: 'mousty'),
        distanceM: 10020,
        durationS: 3005,
        paceSPerKm: 300,
        track: track,
        startedAt: DateTime(2026, 10, 14, 7),
      );
      await pump(tester, RunShareCard(run: run));
      expect(find.text("5'00\""), findsOneWidget);
    });

    testWidgets('post', (tester) async {
      const post = Post(
        id: 'p1',
        user: User(id: 'u2', username: 'giulia.fit'),
        content: 'Gambe distrutte',
      );
      await pump(tester, const PostShareCard(post: post));
      expect(find.text('repbirds.com/p/p1'), findsOneWidget);
    });
  });

  group('cose private', () {
    Future<void> open(WidgetTester tester, Future<void> Function(BuildContext) share) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(onPressed: () => share(ctx), child: const Text('apri')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
    }

    testWidgets('scheda privata: solo invio dentro l\'app', (tester) async {
      const w = Workout(
        id: 'w2',
        name: 'Leg day',
        user: SimpleUser(id: 'u1', username: 'mousty'),
      );
      await open(tester, (ctx) => shareWorkout(ctx, w, mine: true));
      expect(find.textContaining('La scheda è privata'), findsOneWidget);
      expect(find.text('Invia ad amici o gruppi'), findsOneWidget);
      expect(find.text('Invia link (WhatsApp, Telegram…)'), findsNothing);
      expect(find.text('Copia link'), findsNothing);
    });

    testWidgets('scheda pubblica: anche fuori dall\'app', (tester) async {
      const w = Workout(
        id: 'w1',
        name: 'Push day',
        isPublic: true,
        user: SimpleUser(id: 'u1', username: 'mousty'),
      );
      await open(tester, (ctx) => shareWorkout(ctx, w, mine: true));
      expect(find.text('Invia link (WhatsApp, Telegram…)'), findsOneWidget);
      expect(find.text('Condividi immagine (Instagram…)'), findsOneWidget);
      expect(find.text('Copia link'), findsOneWidget);
    });

    testWidgets('percorso privato: solo GPX', (tester) async {
      const route = RunRoute(
        id: 'r2',
        name: 'Segreto',
        owner: SimpleUser(id: 'u1', username: 'mousty'),
        waypoints: [],
        points: [],
        distanceM: 1000,
      );
      await open(tester, (ctx) => shareRoute(ctx, route, loadGpx: () async => ''));
      expect(find.textContaining('Il percorso è privato'), findsOneWidget);
      expect(find.text('Esporta GPX (Strava, Garmin…)'), findsOneWidget);
      expect(find.text('Copia link'), findsNothing);
    });
  });
}
