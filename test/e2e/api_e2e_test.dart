// Test end to end dei repository dell'app contro un gymbro-api vero.
//
// Non gira con `flutter test` normale: serve un backend avviato e il file dove
// il server SMTP di sviluppo salva le email (per leggere gli OTP).
//
//   flutter test test/e2e/api_e2e_test.dart \
//     --dart-define=E2E_API=http://localhost:8080/api \
//     --dart-define=E2E_MAILS=/percorso/mails.log
//
// Crea utenti nuovi a ogni giro (anna…, bruno…, carla…) e cancella quasi
// tutto quello che crea. Per il backend locale vedi il README.
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:dio/dio.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymbro_app/core/network/api_client.dart';
import 'package:gymbro_app/core/network/api_exception.dart';
import 'package:gymbro_app/core/storage/token_storage.dart';
import 'package:gymbro_app/data/auth_repository.dart';
import 'package:gymbro_app/data/social_repository.dart';
import 'package:gymbro_app/data/user_repository.dart';
import 'package:gymbro_app/data/workout_repository.dart';
import 'package:gymbro_app/models/group.dart';
import 'package:gymbro_app/models/json.dart';
import 'package:gymbro_app/models/user.dart';
import 'package:gymbro_app/models/workout.dart';

const api = String.fromEnvironment('E2E_API');
const mails = String.fromEnvironment('E2E_MAILS');

/// Token in memoria al posto del keychain.
class MemoryTokens extends TokenStorage {
  String? access;
  String? refresh;

  @override
  Future<String?> get accessToken async => access;

  @override
  Future<String?> get refreshToken async => refresh;

  @override
  Future<void> save({required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> clear() async => access = refresh = null;
}

/// Un utente con il suo client e i repository dell'app.
class Actor {
  Actor(this.username) : tokens = MemoryTokens() {
    client = ApiClient(tokens, baseUrl: api);
    // Le rotte /auth hanno un rate limit (20 al minuto per IP): aspetta e riprova.
    client.dio.interceptors.add(InterceptorsWrapper(onError: (e, handler) async {
      if (e.response?.statusCode != 429) return handler.next(e);
      final wait = int.tryParse(e.response?.headers.value('retry-after') ?? '') ?? 60;
      await Future<void>.delayed(Duration(seconds: wait + 1));
      try {
        handler.resolve(await client.dio.fetch<dynamic>(e.requestOptions));
      } on DioException catch (err) {
        handler.next(err);
      }
    }));
    auth = AuthRepository(client, tokens);
    users = UserRepository(client);
    posts = PostRepository(client);
    friends = FriendshipRepository(client);
    workouts = WorkoutRepository(client);
    groups = GroupRepository(client);
  }

  final String username;
  final MemoryTokens tokens;
  late final ApiClient client;
  late final AuthRepository auth;
  late final UserRepository users;
  late final PostRepository posts;
  late final FriendshipRepository friends;
  late final WorkoutRepository workouts;
  late final GroupRepository groups;
  late User me;

  String get email => '$username@e2e.test';
}

/// Ultimo OTP a 6 cifre arrivato a [email].
Future<String> otpFor(String email) async {
  for (var i = 0; i < 20; i++) {
    final text = File(mails).existsSync() ? File(mails).readAsStringSync() : '';
    final blocks = text.split('--- TO ').where((b) => b.contains(email)).toList();
    if (blocks.isNotEmpty) {
      final m = RegExp(r'OTP: (\d{6})').firstMatch(blocks.last);
      if (m != null) return m.group(1)!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw StateError('Nessun OTP per $email');
}

void main() {
  if (api.isEmpty || mails.isEmpty) {
    test('e2e saltato: manca E2E_API o E2E_MAILS', () {}, skip: true);
    return;
  }

  final run = DateTime.now().millisecondsSinceEpoch % 1000000;
  final a = Actor('anna$run');
  final b = Actor('bruno$run');
  final c = Actor('carla$run');
  const password = 'Password123!';
  late Exercise squat;
  late Exercise bench;
  late Workout workout;
  late WorkoutGroup wg;
  late String postId;

  final png = File('web/icons/Icon-192.png').readAsBytesSync();

  group('auth', () {
    for (final actor in [a, b, c]) {
      test('registrazione, login bloccato, verifica OTP, login: ${actor.username}', () async {
        await actor.auth.signup(
          username: actor.username,
          email: actor.email,
          password: password,
          firstName: actor.username[0].toUpperCase() + actor.username.substring(1, 4),
          lastName: 'Test',
          birthDate: DateTime(1998, 5, 12),
        );
        await expectLater(
          actor.auth.login(actor.username, password),
          throwsA(isA<ApiException>().having((e) => e.isEmailNotVerified, 'isEmailNotVerified', isTrue)),
        );
        await actor.auth.verifyOtp(username: actor.username, otp: await otpFor(actor.email));
        actor.me = await actor.auth.login(actor.username, password);
        expect(actor.me.username, actor.username);
        expect(actor.me.isAccountVerified, isTrue);
      });
    }

    test('password errata', () async {
      await expectLater(
        Actor(a.username).auth.login(a.username, 'sbagliata'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
    });

    test('profilo e refresh del token scaduto', () async {
      expect((await a.auth.profile()).username, a.username);
      final oldRefresh = a.tokens.refresh;
      a.tokens.access = 'token-non-valido';
      expect((await a.auth.profile()).username, a.username);
      expect(a.tokens.refresh, isNot(oldRefresh), reason: 'il backend ruota il refresh token');
    });

    test('reinvio OTP di verifica', () async {
      await a.auth.sendVerifyOtp(a.email);
    });
  });

  group('utenti', () {
    test('cerca, profilo per username e per id', () async {
      final found = await a.users.search('brun');
      expect(found.map((u) => u.username), contains(b.username));
      final byName = await a.users.byUsername(b.username);
      expect(byName.id, b.me.id);
      expect((await a.users.byId(b.me.id)).username, b.username);
    });

    test('foto profilo', () async {
      await a.users.updateProfileImage(png, 'avatar.png');
      final me = await a.auth.profile();
      expect(me.image, isNotNull);
    });
  });

  group('esercizi e schede', () {
    test('crea esercizi: nei miei subito, negli altri solo dopo averli salvati', () async {
      squat = await a.workouts.createExercise(name: 'Squat $run', muscleGroup: 'Gambe');
      bench = await a.workouts.createExercise(name: 'Panca $run', muscleGroup: 'Petto', description: 'Bilanciere');
      expect((await a.workouts.exercises()).map((e) => e.id), containsAll([squat.id, bench.id]));
      expect((await b.workouts.exercises()).map((e) => e.id), isNot(contains(squat.id)));

      await b.workouts.saveExercise(squat.id);
      expect((await b.workouts.exercises()).map((e) => e.id), contains(squat.id));
      await b.workouts.unsaveExercise(squat.id);
      expect((await b.workouts.exercises()).map((e) => e.id), isNot(contains(squat.id)));
    });

    test('crea scheda, aggiunge, modifica e rimuove esercizi', () async {
      workout = await a.workouts.create(WorkoutInput(
        name: 'Push $run',
        description: 'Scheda e2e',
        isPublic: true,
        dayOfWeek: const [1, 4],
        startTime: const TimeOfDayValue(18, 30),
      ));
      await a.workouts.addExercise(WorkoutExerciseInput(
          workoutId: workout.id, exerciseId: bench.id, sets: 4, reps: 8, weight: 70, restSeconds: 120, position: 1));
      await a.workouts.addExercise(WorkoutExerciseInput(
          workoutId: workout.id, exerciseId: squat.id, sets: 5, reps: 5, restSeconds: 150, position: 2));
      var w = await a.workouts.byId(workout.id);
      expect(w.exercises.map((e) => e.exerciseName), ['Panca $run', 'Squat $run']);
      expect(w.startTime?.label, '18:30');
      expect(w.dayOfWeek, [1, 4]);

      final first = w.exercises.first;
      await a.workouts.updateExercise(WorkoutExerciseInput(
          id: first.id, workoutId: workout.id, exerciseId: bench.id, sets: 5, reps: 6, weight: 75, restSeconds: 120, position: 1));
      await a.workouts.removeExercise(w.exercises.last.id);
      w = await a.workouts.byId(workout.id);
      expect(w.exercises.single.sets, 5);
      expect(w.exercises.single.weight, 75);

      await a.workouts.update(WorkoutInput(
        id: workout.id,
        name: 'Push day $run',
        isPublic: true,
        dayOfWeek: const [2],
        startTime: const TimeOfDayValue(7, 0),
      ));
      workout = await a.workouts.byId(workout.id);
      expect(workout.name, 'Push day $run');
      expect(workout.startTime?.label, '07:00');
    });

    test('le mie schede e quelle pubbliche', () async {
      expect((await a.workouts.mine()).map((w) => w.id), contains(workout.id));
      final explore = await b.workouts.explore();
      expect(explore.results.map((w) => w.id), contains(workout.id));
    });

    test('sessione salvata nello storico', () async {
      final end = DateTime.now();
      await a.workouts.logSession(
        workoutId: workout.id,
        startedAt: end.subtract(const Duration(minutes: 50)),
        completedAt: end,
        notes: 'e2e',
      );
      final history = await a.workouts.history();
      expect(history.first.workoutId, workout.id);
      expect(history.first.duration?.inMinutes, 50);
    });
  });

  group('amici', () {
    test('richiesta, accettazione e rifiuto', () async {
      await a.friends.add(b.username);
      final pending = await b.friends.pendingRequests();
      final req = pending.singleWhere((f) => f.other(b.username).username == a.username);
      await b.friends.accept(req.id);
      expect((await a.friends.all()).map((f) => f.other(a.username).username), contains(b.username));
      expect((await b.friends.all()).map((f) => f.other(b.username).username), contains(a.username));

      await c.friends.add(a.username);
      final fromC = (await a.friends.pendingRequests()).singleWhere((f) => f.other(a.username).username == c.username);
      await a.friends.reject(fromC.id);
      expect(await a.friends.pendingRequests(), isEmpty);
      expect((await a.friends.all()).map((f) => f.other(a.username).username), isNot(contains(c.username)));
    });
  });

  group('post', () {
    test('nuovo post con foto, feed e profilo', () async {
      final post = await a.posts.create(userId: a.me.id, content: 'Primo post $run', imageBytes: png, imageName: 'foto.png');
      postId = post.id;
      expect(post.image, startsWith('http'));
      expect((await b.posts.all()).results.map((p) => p.id), contains(postId));
      expect((await b.posts.friendsPosts()).map((p) => p.id), contains(postId));
      expect((await c.posts.byUser(a.username)).map((p) => p.id), contains(postId));
    });

    test('like, unlike, commento, modifica ed eliminazione', () async {
      final like = await b.posts.like(postId: postId, userId: b.me.id);
      var p = await a.posts.byId(postId);
      expect(p.numLikes, 1);
      expect(p.likeBy(b.username)?.id, like.id);
      await b.posts.unlike(like.id);
      expect((await a.posts.byId(postId)).numLikes, 0);

      final comment = await b.posts.comment(postId: postId, content: 'Grande!');
      p = await a.posts.byId(postId);
      expect(p.comments.single.content, 'Grande!');
      expect(p.comments.single.username, b.username);
      await b.posts.deleteComment(comment.id);
      expect((await a.posts.byId(postId)).comments, isEmpty);

      await a.posts.update(id: postId, content: 'Modificato $run');
      expect((await a.posts.byId(postId)).content, 'Modificato $run');
    });
  });

  group('gruppi', () {
    test('crea gruppo, invita, accetta, sessione di gruppo', () async {
      wg = await a.groups.create(name: 'Allenamento $run');
      expect(wg.workoutId, isNull);

      await a.groups.invite(groupId: wg.id, username: b.username);
      await a.groups.invite(groupId: wg.id, username: c.username);
      final invite = (await b.groups.myMemberships()).singleWhere((m) => m.groupId == wg.id);
      expect(invite.status, GroupMemberStatus.invited);
      expect(invite.groupName, 'Allenamento $run');
      expect(invite.groupCreatedBy, a.username);
      await b.groups.acceptInvite(invite.id);
      final cInvite = (await c.groups.myMemberships()).singleWhere((m) => m.groupId == wg.id);
      await c.groups.rejectInvite(cInvite.id);

      expect((await b.groups.all()).map((g) => g.id), contains(wg.id));
      final full = await b.groups.byId(wg.id);
      final bMember = full.members.singleWhere((m) => m.user.username == b.username);
      expect(bMember.status, GroupMemberStatus.accepted);

      // sessione del gruppo: b risponde, a avvia, tutti leggono lo stesso inizio
      final session = await a.groups.createSession(
        groupId: wg.id,
        workoutId: workout.id,
        scheduledFor: DateTime.now().add(const Duration(days: 2)),
      );
      expect((await b.groups.answer(session.id, going: true)).myStatus, Attendance.going);
      expect((await b.groups.upcomingSessions()).map((s) => s.id), contains(session.id));
      final started = await a.groups.start(session.id);
      expect((await b.groups.session(session.id)).startedAt, started.startedAt);

      final end = DateTime.now();
      await b.workouts.logSession(
        workoutId: workout.id,
        groupId: wg.id,
        startedAt: end.subtract(const Duration(minutes: 40)),
        completedAt: end,
      );
      final gh = await a.workouts.groupHistory(wg.id);
      expect(gh.single.groupId, wg.id);

      await a.groups.removeMember(bMember.id);
      expect((await a.groups.byId(wg.id)).members.where((m) => m.user.username == b.username), isEmpty);
    });
  });

  group('pulizia e account', () {
    test('elimina post, storico, gruppo, scheda ed esercizio', () async {
      await a.posts.delete(postId);
      final h = (await a.workouts.history()).first;
      await a.workouts.deleteHistory(h.id);
      await a.groups.delete(wg.id);
      await a.workouts.delete(workout.id);
      await a.workouts.deleteExercise(squat.id);
      await a.workouts.deleteExercise(bench.id);
      expect((await a.workouts.mine()).map((w) => w.id), isNot(contains(workout.id)));
    });

    test('password dimenticata', () async {
      await c.auth.sendResetOtp(c.email);
      await c.auth.resetPassword(email: c.email, otp: await otpFor(c.email), newPassword: 'NuovaPass456!');
      final fresh = Actor(c.username);
      expect((await fresh.auth.login(c.username, 'NuovaPass456!')).username, c.username);
    });

    test('logout ed eliminazione account', () async {
      await b.auth.logout();
      expect(await b.auth.hasSession(), isFalse);
      await c.users.deleteMe();
      await expectLater(
        Actor(c.username).auth.login(c.username, 'NuovaPass456!'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
