import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/models/notification.dart';
import 'package:repbirds_app/core/network/api_exception.dart';
import 'package:repbirds_app/models/group.dart';
import 'package:repbirds_app/models/json.dart';
import 'package:repbirds_app/models/page.dart';
import 'package:repbirds_app/models/social.dart';
import 'package:repbirds_app/models/workout.dart';

void main() {
  test('Connection del backend → PageResult', () {
    final page = PageResult.fromJson({
      'results': [
        {'id': 'e1', 'name': 'Squat', 'muscleGroup': 'Gambe', 'isPublic': true, 'createdBy': {'username': 'mousty'}},
      ],
      'pageInfo': {'hasNext': true, 'hasPrevious': false, 'numberOfElements': 1, 'totalPages': 3, 'currentPage': 0},
      'totalCount': 41,
    }, Exercise.fromJson);
    expect(page.results.single.name, 'Squat');
    expect(page.results.single.createdBy, 'mousty');
    expect(page.hasNext, isTrue);
    expect(page.totalCount, 41);
  });

  test('WorkoutDTO: esercizi ordinati, giorni e orario', () {
    final w = Workout.fromJson({
      'id': 'w1',
      'name': 'Push',
      'isPublic': false,
      'dayOfWeek': [4, 1],
      'startTime': '18:30:00',
      'user': {'id': 'u1', 'username': 'mousty'},
      'workoutExercises': [
        {'id': 'b', 'workoutId': 'w1', 'exerciseId': 'e2', 'sets': 3, 'reps': 10, 'weight': 40.0, 'restSeconds': 90, 'position': 2},
        {'id': 'a', 'workoutId': 'w1', 'exerciseId': 'e1', 'sets': 4, 'reps': 8, 'weight': 70, 'restSeconds': 120, 'position': 1},
      ],
    });
    expect(w.exercises.map((e) => e.id), ['a', 'b']);
    expect(w.startTime!.label, '18:30');
    expect(weekdaysLabel(w.dayOfWeek), 'Lun · Gio');
    expect(w.exercises.first.summary, '4 × 8 · 70 kg');
    expect(WorkoutInput(name: 'x', startTime: w.startTime).toJson()['startTime'], '18:30:00');
  });

  test('Post: like dell\'utente e amicizia', () {
    final p = Post.fromJson({
      'id': 'p1',
      'user': {'id': 'u2', 'username': 'giulia'},
      'content': 'ciao',
      'createdAt': '2026-10-12T08:00:00Z',
      'likes': [
        {'id': 'l1', 'username': 'mousty', 'createdAt': '2026-10-12T09:00:00Z'},
      ],
      'numLikes': 1,
      'numComments': 0,
    });
    expect(p.likeBy('mousty')?.id, 'l1');
    expect(p.likeBy('altro'), isNull);
    expect(p.createdAt!.toUtc().hour, 8);

    final f = Friendship.fromJson({
      'id': 'f1',
      'user': {'id': '1', 'username': 'mousty'},
      'friend': {'id': '2', 'username': 'giulia'},
      'status': 'accepted',
    });
    expect(f.other('mousty').username, 'giulia');
    expect(f.status, FriendshipStatus.accepted);
  });

  test('WorkoutGroup e inviti', () {
    final g = WorkoutGroup.fromJson({
      'id': 'g1',
      'name': 'Leg day',
      'workout': {'id': 'w1', 'name': 'Gambe'},
      'createdBy': {'id': '1', 'username': 'mousty'},
      'status': 'scheduled',
      'groupMembers': [
        {'id': 'm1', 'workoutGroupId': 'g1', 'user': {'id': '2', 'username': 'giulia'}, 'status': 'accepted'},
        {'id': 'm2', 'workoutGroupId': 'g1', 'user': {'id': '3', 'username': 'marco'}, 'status': 'invited'},
      ],
    });
    expect(g.workoutName, 'Gambe');
    expect(g.acceptedMembers.single.user.username, 'giulia');
    expect(formatLocalDate(DateTime(1998, 5, 2)), '1998-05-02');
  });

  test('errori del backend → messaggi leggibili', () {
    ApiException from(int status, Object? data) {
      final req = RequestOptions(path: '/x');
      return ApiException.fromDio(DioException(
        requestOptions: req,
        response: Response<dynamic>(requestOptions: req, statusCode: status, data: data),
      ));
    }

    expect(from(429, {'error': 'Too many requests'}).message, contains('Troppi tentativi'));
    expect(from(500, null).message, contains('server'));
    expect(from(409, {'message': 'Username already taken'}).message, 'Username already taken');
    expect(from(400, {'message': 'Validation failed', 'details': {'name': 'obbligatorio'}}).message, 'obbligatorio');
    final offline = ApiException.fromDio(DioException(requestOptions: RequestOptions(path: '/x')));
    expect(offline.unreachable, isTrue);
  });

  test('invito a un gruppo con il riepilogo del gruppo', () {
    final m = GroupMember.fromJson({
      'id': 'm1',
      'workoutGroupId': 'g1',
      'user': {'id': 'u1', 'username': 'mousty'},
      'status': 'invited',
      'groupName': 'Push con Marco',
      'groupCreatedBy': 'marco_lifts',
      'groupScheduledFor': '2026-10-15T07:00:00Z',
    });
    expect(m.groupName, 'Push con Marco');
    expect(m.groupCreatedBy, 'marco_lifts');
    expect(m.groupScheduledFor!.toUtc().hour, 7);
  });

  test('AppNotification dal JSON del backend', () {
    final n = AppNotification.fromJson({
      'id': 'n1',
      'type': 'GROUP_INVITE_ACCEPTED',
      'actor': {'id': 'u1', 'username': 'giulia'},
      'referenceId': 'g1',
      'detail': 'Morning crew',
      'read': false,
      'createdAt': '2026-10-13T08:00:00Z',
    });
    expect(n.kind, NotificationKind.groupInviteAccepted);
    expect(n.text, 'è entrato in Morning crew');
    expect(n.route, '/group/g1');
    expect(n.read, isFalse);

    expect(AppNotification.fromJson({'id': 'n2', 'type': 'NUOVO_TIPO'}).kind, NotificationKind.unknown);
    expect(AppNotification.routeFor(NotificationKind.friendAccepted, 'f1'), '/friends');
  });
}
