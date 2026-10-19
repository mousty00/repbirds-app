import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../features/running/geo.dart';
import '../config/env.dart';

part 'mock_running.dart';

/// Backend finto in memoria, attivo quando `Env.useMock` è vero
/// (`flutter run -t lib/main_mock.dart` o `--dart-define=USE_MOCK=true`).
///
/// È un interceptor di dio: risponde alle stesse rotte di gymbro-api con le
/// stesse forme JSON, così repository, modelli e schermate restano identici.
/// I dati vivono in memoria: le modifiche (post, like, schede, gruppi…)
/// valgono finché l'app resta aperta.
///
/// Comportamenti utili per provare la UX:
/// - qualunque username e password fanno il login come `mousty`;
/// - lo username `nonverificato` simula l'email non verificata (403);
/// - la password `sbagliata` simula credenziali errate (401);
/// - il codice OTP `000000` è sempre rifiutato, gli altri sono accettati.
class MockBackend extends Interceptor {
  MockBackend({this.latency = const Duration(milliseconds: 350), bool Function()? enabled})
      : enabled = enabled ?? (() => Env.useMock) {
    _seed();
  }

  final Duration latency;

  /// Se falso le richieste passano al server vero.
  final bool Function() enabled;

  /// Immagini caricate dall'app in modalità mock, lette da `AppImage`.
  static final Map<String, Uint8List> uploads = {};

  static const uploadScheme = 'mock-upload:';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!enabled()) return handler.next(options);
    await Future<void>.delayed(latency);
    try {
      final data = await _route(options);
      handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 200, data: data));
    } on _MockError catch (e) {
      _reject(options, handler, e.status, e.message);
    } catch (e) {
      // Un bug del mock non deve lasciare la richiesta appesa.
      _reject(options, handler, 500, 'Mock: $e');
    }
  }

  void _reject(RequestOptions options, RequestInterceptorHandler handler, int status, String message) {
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: status,
          data: {'status': status, 'message': message, 'timestamp': _iso(DateTime.now())},
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- dati

  final _now = DateTime.now();
  var _seq = 100;
  String _id(String prefix) => '$prefix${_seq++}';

  late Map<String, dynamic> _me;
  String? _pendingEmail;
  final _users = <Map<String, dynamic>>[];
  final _exercises = <Map<String, dynamic>>[];
  final _workouts = <Map<String, dynamic>>[];
  final _history = <Map<String, dynamic>>[];
  final _groups = <Map<String, dynamic>>[];
  final _sessions = <Map<String, dynamic>>[];
  final _posts = <Map<String, dynamic>>[];
  final _friendships = <Map<String, dynamic>>[];
  final _notifications = <Map<String, dynamic>>[];
  final _runRoutes = <Map<String, dynamic>>[];
  final _runEvents = <Map<String, dynamic>>[];
  final _runs = <Map<String, dynamic>>[];
  final devices = <String>{};

  static String _iso(DateTime d) => d.toUtc().toIso8601String();

  Map<String, dynamic> _user(String id, String username, String first, String last, int ageDays) => {
        'id': id,
        'username': username,
        'email': '$username@repbirds.app',
        'firstName': first,
        'lastName': last,
        'birthDate': '1998-05-12',
        'image': null,
        'roleName': 'USER',
        'isAccountVerified': true,
        'createdAt': _iso(_now.subtract(Duration(days: ageDays))),
      };

  Map<String, dynamic> _simple(Map<String, dynamic> u) =>
      {'id': u['id'], 'username': u['username'], 'image': u['image'], 'isAccountVerified': u['isAccountVerified']};

  Set<String> _friendsOf(String username) => {
        for (final f in _friendships)
          if (f['status'] == 'accepted' && (f['user']['username'] == username || f['friend']['username'] == username))
            '${f['user']['username'] == username ? f['friend']['username'] : f['user']['username']}',
      };

  Map<String, dynamic> _overview(Map<String, dynamic> u) {
    final name = '${u['username']}';
    final close = name == _meName || _isFriend(name);
    final mine = _friendsOf(_meName);
    // ponytail: niente storico finto per gli altri, attività e ore derivate dal nome
    final days = name.length % 5 + 1;
    return {
      'trainingSeconds': close ? days * 9000 : null,
      'recentActivity': close ? [for (var i = 0; i < days; i++) _iso(_now.subtract(Duration(days: i, hours: 3)))] : null,
      'mutualFriends': [for (final f in _friendsOf(name)) if (f != _meName && mine.contains(f)) _simple(_userBy(f))],
      'workouts': [
        for (final w in _workouts)
          if (w['user']['username'] == name && w['isPublic'] == true)
            {'id': w['id'], 'name': w['name'], 'exercises': (w['workoutExercises'] as List).length},
      ],
      'exercises': [
        for (final e in _exercises)
          if (e['createdBy']['username'] == name && e['isPublic'] == true) {'id': e['id'], 'name': e['name'], 'muscleGroup': e['muscleGroup']},
      ],
      'routes': close
          ? [
              for (final r in _runRoutes)
                if (r['owner']['username'] == name && r['isPublic'] == true) {'id': r['id'], 'name': r['name'], 'distanceM': r['distanceM']},
            ]
          : null,
    };
  }

  Map<String, dynamic> _userBy(String username) =>
      _users.firstWhere((u) => u['username'] == username, orElse: () => throw _MockError(404, 'Utente non trovato'));

  void _seed() {
    _me = _user('u1', 'mousty', 'Mousty', 'D.', 140);
    final giulia = _user('u2', 'giulia.fit', 'Giulia', 'Rossi', 300);
    final marco = _user('u3', 'marco_lifts', 'Marco', 'Bianchi', 200);
    final sara = _user('u4', 'sara.runs', 'Sara', 'Verdi', 90);
    final luca = _user('u5', 'luca.cali', 'Luca', 'Neri', 40);
    _users.addAll([_me, giulia, marco, sara, luca]);

    const ex = [
      ('Panca piana', 'Petto'), ('Squat', 'Gambe'), ('Stacco da terra', 'Schiena'), ('Military press', 'Spalle'),
      ('Trazioni', 'Schiena'), ('Curl manubri', 'Bicipiti'), ('French press', 'Tricipiti'), ('Hip thrust', 'Glutei'),
      ('Affondi', 'Gambe'), ('Plank', 'Addome'), ('Crunch', 'Addome'), ('Corsa', 'Cardio'), ('Burpees', 'Full body'),
    ];
    for (var i = 0; i < ex.length; i++) {
      _exercises.add({
        'id': 'e$i',
        'name': ex[i].$1,
        'muscleGroup': ex[i].$2,
        'description': null,
        'isPublic': true,
        'createdBy': i < 3 ? _me : giulia,
      });
    }

    Map<String, dynamic> we(String wid, int pos, int exIdx, int sets, int reps, num? kg, int rest) => {
          'id': '$wid-$pos',
          'workoutId': wid,
          'exerciseId': 'e$exIdx',
          'exerciseName': ex[exIdx].$1,
          'sets': sets,
          'reps': reps,
          'weight': kg,
          'restSeconds': rest,
          'position': pos,
        };

    final today = _now.weekday;
    _workouts.addAll([
      _workout('w1', _me, 'Push day', 'Petto, spalle e tricipiti. Carichi progressivi.', true, [today, (today + 2) % 7 + 1], '18:30',
          [we('w1', 1, 0, 4, 8, 70, 120), we('w1', 2, 3, 4, 10, 40, 90), we('w1', 3, 6, 3, 12, 25, 60), we('w1', 4, 9, 3, 1, null, 45)]),
      _workout('w2', _me, 'Leg day', 'Forza e volume per le gambe.', false, [3, 6], '10:00',
          [we('w2', 1, 1, 5, 5, 100, 150), we('w2', 2, 8, 3, 10, 20, 90), we('w2', 3, 7, 4, 12, 80, 90)]),
      _workout('w3', _me, 'Pull & core', null, false, [5], null,
          [we('w3', 1, 4, 4, 8, null, 120), we('w3', 2, 2, 3, 5, 120, 180), we('w3', 3, 5, 3, 12, 14, 60)]),
      _workout('w4', giulia, 'Full body 45\'', 'Circuito veloce per chi ha poco tempo.', true, [2], null,
          [we('w4', 1, 1, 3, 12, 40, 60), we('w4', 2, 12, 3, 15, null, 45), we('w4', 3, 9, 3, 1, null, 45)]),
      _workout('w5', marco, 'Powerlifting base', '5x5 sui fondamentali.', true, [1, 3, 5], '07:00',
          [we('w5', 1, 1, 5, 5, 140, 180), we('w5', 2, 0, 5, 5, 100, 180), we('w5', 3, 2, 1, 5, 180, 240)]),
    ]);

    void hist(int daysAgo, int minutes, String wid, {String? group, String? notes}) {
      final start = _now.subtract(Duration(days: daysAgo, hours: 2));
      _history.add({
        'id': _id('h'),
        'userId': _me['id'],
        'workoutId': wid,
        'groupId': group,
        'startedAt': _iso(start),
        'completedAt': _iso(start.add(Duration(minutes: minutes))),
        'notes': notes,
      });
    }

    hist(0, 52, 'w1', notes: 'Panca 72,5 kg x 8, nuovo record!');
    hist(2, 61, 'w2');
    hist(4, 38, 'w3');
    hist(6, 70, 'w2', group: 'g1', notes: 'Con Giulia e Marco');
    hist(9, 48, 'w1');
    hist(12, 55, 'w2');
    hist(15, 44, 'w3');

    Map<String, dynamic> member(String gid, Map<String, dynamic> u, String status) => {
          'id': _id('m'),
          'workoutGroupId': gid,
          'user': _simple(u),
          'status': status,
          'createdAt': _iso(_now.subtract(const Duration(days: 1))),
        };

    _groups.addAll([
      _group('g1', 'Leg day del sabato', 'w2', _me, _now.add(const Duration(days: 5, hours: 3)),
          [member('g1', giulia, 'accepted'), member('g1', marco, 'accepted'), member('g1', sara, 'invited')]),
      _group('g2', 'Push con Marco', 'w5', marco, _now.add(const Duration(days: 2, hours: 6)), [member('g2', _me, 'accepted')]),
      _group('g3', 'Corsa al parco', 'w4', sara, _now.add(const Duration(days: 8)), [member('g3', _me, 'invited')]),
    ]);
    // ogni gruppo ha le sue sessioni: un giorno e una scheda ciascuna
    for (final g in _groups) {
      _sessions.add(_session(g, '${g['workoutId']}', DateTime.parse('${g['scheduledFor']}'), {
        'giulia.fit': 'going',
        'marco_lifts': g['id'] == 'g1' ? 'declined' : 'going',
      }));
    }
    _sessions.add(_session(_groups.first, 'w1', _now.add(const Duration(days: 1, hours: 2)), {'giulia.fit': 'going'}));

    Map<String, dynamic> post(Map<String, dynamic> u, String text, int? img, int hoursAgo, List<String> likes,
        List<(String, String)> comments) {
      final id = _id('p');
      final at = _iso(_now.subtract(Duration(hours: hoursAgo)));
      return {
        'id': id,
        'user': u,
        'content': text,
        'image': img == null ? null : 'asset:assets/mock/post$img.jpg',
        'createdAt': at,
        'updatedAt': at,
        'comments': <Map<String, dynamic>>[
          for (final c in comments)
            {'id': _id('c'), 'postId': id, 'username': c.$1, 'content': c.$2, 'createdAt': at},
        ],
        'likes': <Map<String, dynamic>>[
          for (final l in likes) {'id': _id('l'), 'username': l, 'createdAt': at},
        ],
      };
    }

    _posts.addAll([
      post(giulia, 'Primo 5x5 di squat a 80 kg completato. Le gambe tremano ma ne è valsa la pena 🔥', 1, 2,
          ['mousty', 'marco_lifts'], [('mousty', 'Grande Giulia!'), ('marco_lifts', 'Sabato tocca a noi 💪')]),
      post(marco, 'Sessione push con la crew stamattina. Chi viene sabato?', 2, 20, ['giulia.fit'], [('giulia.fit', 'Io ci sono')]),
      post(_me, 'Nuovo record in panca: 72,5 kg x 8!', 3, 30, ['giulia.fit', 'marco_lifts', 'sara.runs'], []),
      post(luca, 'Primo muscle-up pulito dopo tre mesi di prove. Non mollate!', 4, 50, ['sara.runs'], []),
      post(_me, 'Leg day completato, domani non cammino 😅', 1, 54, ['giulia.fit'], [('giulia.fit', 'Classico!')]),
      post(_me, 'Push con Marco, si chiude la settimana alla grande', 2, 100, ['marco_lifts', 'luca.cali'], []),
      post(_me, 'Riposo attivo: 5 km tranquilli al parco', null, 140, ['sara.runs'], []),
      post(_me, 'Primo mese di RepBirds: 12 sessioni 💪', 4, 300, ['giulia.fit', 'marco_lifts'], []),
    ]);

    _friendships.addAll([
      {'id': 'f1', 'user': _simple(_me), 'friend': _simple(giulia), 'status': 'accepted', 'createdAt': _iso(_now)},
      {'id': 'f2', 'user': _simple(marco), 'friend': _simple(_me), 'status': 'accepted', 'createdAt': _iso(_now)},
      {
        'id': 'f3',
        'user': _simple(sara),
        'friend': _simple(_me),
        'status': 'pending',
        'createdAt': _iso(_now.subtract(const Duration(hours: 3))),
      },
      // tra altri: servono per gli amici in comune
      {'id': 'f4', 'user': _simple(giulia), 'friend': _simple(marco), 'status': 'accepted', 'createdAt': _iso(_now)},
      {'id': 'f5', 'user': _simple(luca), 'friend': _simple(giulia), 'status': 'accepted', 'createdAt': _iso(_now)},
    ]);

    final myPost = _posts.firstWhere((p) => p['user'] == _me)['id'];
    Map<String, dynamic> notification(String type, Map<String, dynamic> actor, Object? ref, int hoursAgo,
            {String? detail, bool read = false}) =>
        {
          'id': _id('n'),
          'type': type,
          'actor': _simple(actor),
          'referenceId': ref,
          'detail': detail,
          'read': read,
          'createdAt': _iso(_now.subtract(Duration(hours: hoursAgo))),
        };
    _notifications.addAll([
      notification('FRIEND_REQUEST', sara, 'f3', 3),
      notification('WORKOUT_SHARED', giulia, 'w4', 4, detail: 'Full body 45\''),
      notification('POST_COMMENTED', giulia, myPost, 5, detail: 'Che macchina! 🔥'),
      notification('POST_LIKED', marco, myPost, 26, read: true),
      notification('FRIEND_ACCEPTED', giulia, 'f1', 48, read: true),
    ]);
    _seedRunning(giulia, marco, sara);
    // una corsa di gruppo: sessione del gruppo su un percorso
    _sessions.add(_session(_groups.first, null, _now.add(const Duration(days: 2, hours: 1)), {'giulia.fit': 'going'},
        routeId: '${_runRoutes.first['id']}', meetingPoint: 'Ingresso del parco'));
  }

  Map<String, dynamic> _workout(String id, Map<String, dynamic> owner, String name, String? description, bool isPublic,
          List<int> days, String? time, List<Map<String, dynamic>> exercises) =>
      {
        'id': id,
        'user': owner,
        'name': name,
        'description': description,
        'isPublic': isPublic,
        'dayOfWeek': days,
        'startTime': time,
        'createdAt': _iso(_now.subtract(const Duration(days: 20))),
        'workoutExercises': exercises,
        'workoutGroups': <dynamic>[],
        'workoutHistories': <dynamic>[],
      };

  Map<String, dynamic> _group(String id, String name, String workoutId, Map<String, dynamic> creator, DateTime when,
          List<Map<String, dynamic>> members) =>
      {
        'id': id,
        'name': name,
        'workoutId': workoutId,
        'createdBy': _simple(creator),
        'scheduledFor': _iso(when),
        'status': 'scheduled',
        'createdAt': _iso(_now),
        'groupMembers': members,
      };

  Map<String, dynamic> _session(Map<String, dynamic> g, String? workoutId, DateTime? when, Map<String, String> answers,
          {String? routeId, String? meetingPoint}) =>
      {
        'id': _id('s'),
        'groupId': g['id'],
        'workoutId': workoutId,
        'routeId': routeId,
        'meetingPoint': meetingPoint,
        'scheduledFor': when == null ? null : _iso(when),
        'startedAt': null,
        'answers': answers,
        // demo: le sessioni degli altri partono da sole poco dopo che dici "partecipo"
        'autoStartAt': null,
      };

  // ---------------------------------------------------------------- viste JSON

  /// Membro con il riepilogo del gruppo, come `GroupMemberDTO` del backend.
  Map<String, dynamic> _withGroup(Map<String, dynamic> m, Map<String, dynamic> g) => {
        ...m,
        'groupName': g['name'],
        'groupCreatedBy': (g['createdBy'] as Map)['username'],
        'groupScheduledFor': g['scheduledFor'],
      };

  String get _meName => _me['username'] as String;

  Map<String, dynamic> _page(List<dynamic> items) => {
        'results': items,
        'pageInfo': {
          'hasNext': false,
          'hasPrevious': false,
          'numberOfElements': items.length,
          'totalPages': 1,
          'currentPage': 0,
        },
        'totalCount': items.length,
      };

  /// Foto profilo attuale di un utente (come l'URL firmato dell'API).
  String? _imageOf(String username) =>
      _users.firstWhere((u) => u['username'] == username, orElse: () => const {})['image'] as String?;

  Map<String, dynamic> _postView(Map<String, dynamic> p) => {
        ...p,
        'user': {...p['user'] as Map, 'image': _imageOf('${(p['user'] as Map)['username']}')},
        'comments': [
          for (final c in p['comments'] as List) {...c as Map, 'userImage': _imageOf('${c['username']}')},
        ],
        'numLikes': (p['likes'] as List).length,
        'numComments': (p['comments'] as List).length,
      };

  Map<String, dynamic> _sessionView(Map<String, dynamic> s) {
    final g = _groupById('${s['groupId']}');
    final auto = s['autoStartAt'] as DateTime?;
    if (s['startedAt'] == null && auto != null && !DateTime.now().isBefore(auto)) s['startedAt'] = _iso(auto);
    final w = s['workoutId'] == null
        ? null
        : _workouts.firstWhere((w) => w['id'] == s['workoutId'], orElse: () => {'id': s['workoutId'], 'name': 'Scheda'});
    final r = s['routeId'] == null ? null : _runRoutes.firstWhere((r) => r['id'] == s['routeId']);
    final organizer = g['createdBy'] as Map<String, dynamic>;
    final members = [
      organizer,
      for (final m in g['groupMembers'] as List)
        if (m['status'] == 'accepted') m['user'] as Map<String, dynamic>,
    ];
    final answers = s['answers'] as Map<String, String>;
    String status(String u) => u == organizer['username'] ? 'going' : answers[u] ?? 'pending';
    return {
      'id': s['id'],
      'groupId': g['id'],
      'groupName': g['name'],
      'organizer': organizer,
      'workout': w == null ? null : {'id': w['id'], 'name': w['name']},
      'route': r == null ? null : {'id': r['id'], 'name': r['name'], 'distanceM': r['distanceM']},
      'meetingPoint': s['meetingPoint'],
      'scheduledFor': s['scheduledFor'],
      'startedAt': s['startedAt'],
      'myStatus': status(_meName),
      'attendees': [
        for (final u in members)
          {
            'user': u,
            'status': status('${u['username']}'),
            'connected': u['username'] == _meName || answers[u['username']] == 'going',
            'organizer': u['username'] == organizer['username'],
          },
      ],
    };
  }

  Map<String, dynamic> _sessionById(String id) =>
      _sessions.firstWhere((s) => s['id'] == id, orElse: () => throw _MockError(404, 'Sessione non trovata'));

  Map<String, dynamic> _groupView(Map<String, dynamic> g) {
    if (g['workoutId'] == null) return g;
    final w = _workouts.firstWhere((w) => w['id'] == g['workoutId'], orElse: () => {'id': g['workoutId'], 'name': 'Scheda'});
    return {
      ...g,
      'workout': {
        'id': w['id'],
        'name': w['name'],
        'user': w['user'] == null ? null : _simple(w['user'] as Map<String, dynamic>),
        'isPublic': w['isPublic'],
        'dayOfWeek': w['dayOfWeek'],
      },
    };
  }

  bool _isFriend(String username) => _friendships.any((f) =>
      f['status'] == 'accepted' &&
      {(f['user'] as Map)['username'], (f['friend'] as Map)['username']}.containsAll([_meName, username]));

  bool _canSeeGroup(Map<String, dynamic> g) =>
      (g['createdBy'] as Map)['username'] == _meName ||
      (g['groupMembers'] as List).any((m) => (m['user'] as Map)['username'] == _meName && m['status'] == 'accepted');

  Map<String, dynamic> _ok(String message) => {'message': message, 'timestamp': _iso(DateTime.now())};

  // ---------------------------------------------------------------- rotte

  Future<dynamic> _route(RequestOptions o) async {
    final method = o.method.toUpperCase();
    final path = Uri.parse(o.path).path;
    final q = o.queryParameters;
    final body = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    final last = seg.isEmpty ? '' : seg.last;

    bool match(String m, String pattern) {
      if (m != method) return false;
      final p = pattern.split('/').where((s) => s.isNotEmpty).toList();
      if (p.length != seg.length) return false;
      for (var i = 0; i < p.length; i++) {
        if (!p[i].startsWith(':') && p[i] != seg[i]) return false;
      }
      return true;
    }

    // Auth
    if (match('POST', '/auth/login')) {
      final username = '${body['username']}'.trim();
      if (body['password'] == 'sbagliata') throw _MockError(401, 'Bad credentials');
      if (username == 'nonverificato') {
        throw _MockError(403, 'Email not verified: check your inbox for the verification code');
      }
      return {'message': 'login successful', 'result': _me, 'token': 'mock-token', 'refreshToken': 'mock-refresh'};
    }
    if (match('POST', '/auth/signup')) return _ok('Signup successful!');
    if (match('POST', '/auth/verify-otp')) {
      if (body['otp'] == '000000') throw _MockError(400, 'Invalid OTP');
      return _ok('Email verified');
    }
    if (match('POST', '/auth/send-otp') || match('POST', '/auth/send-reset-otp')) return _ok('OTP sent');
    if (match('POST', '/auth/reset-password')) {
      if (body['otp'] == '000000') throw _MockError(400, 'Invalid OTP');
      return _ok('Password reset');
    }
    if (match('GET', '/auth/profile')) return _me;
    if (match('POST', '/auth/refresh')) {
      return {'message': 'ok', 'token': 'mock-token', 'refreshToken': 'mock-refresh'};
    }
    if (match('POST', '/auth/logout')) return _ok('Logged out');

    // Utenti
    if (match('GET', '/users/search')) {
      final s = '${q['username'] ?? ''}'.toLowerCase();
      return _users.where((u) => '${u['username']}'.toLowerCase().contains(s)).map(_simple).toList();
    }
    if (match('GET', '/users/username/:u/overview')) return _overview(_userBy(Uri.decodeComponent(seg[2])));
    if (match('GET', '/users/username/:u')) return _userBy(Uri.decodeComponent(last));
    if (match('GET', '/users/:id')) {
      return _users.firstWhere((u) => u['id'] == last, orElse: () => throw _MockError(404, 'Utente non trovato'));
    }
    if (match('PUT', '/users/update-profile-image')) {
      final bytes = await _fileFrom(o.data, 'imageFile');
      if (bytes != null) {
        final key = _id('img');
        uploads[key] = bytes;
        _me['image'] = '$uploadScheme$key';
      }
      return _ok('Image updated');
    }
    if (match('DELETE', '/users/me')) return _ok('Account deleted');
    if (match('PUT', '/users/me')) {
      final username = '${body['username']}';
      if (username != _me['username'] && _users.any((u) => u['username'] == username)) {
        throw _MockError(409, "Username '$username' already exists");
      }
      _me
        ..['username'] = username
        ..['firstName'] = body['firstName']
        ..['lastName'] = body['lastName']
        ..['birthDate'] = body['birthDate'];
      return {'message': 'Profile updated', 'result': _me, 'token': 'mock-token', 'refreshToken': 'mock-refresh'};
    }
    if (match('POST', '/users/me/email')) {
      final email = '${body['email']}';
      if (_users.any((u) => u['email'] == email)) throw _MockError(409, "Email '$email' already exists");
      _pendingEmail = email;
      return _ok('A code has been sent to the new email');
    }
    if (match('POST', '/users/me/email/verify')) {
      if (_pendingEmail == null) throw _MockError(400, 'OTP expired');
      if (body['otp'] == '000000') throw _MockError(400, 'Invalid OTP');
      _me['email'] = _pendingEmail;
      _pendingEmail = null;
      return _me;
    }

    // Post
    if (match('GET', '/posts')) {
      final sorted = [..._posts]..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
      return _page(sorted.map(_postView).toList());
    }
    if (match('GET', '/posts/user')) {
      return _posts.where((p) => (p['user'] as Map)['username'] == q['username']).map(_postView).toList();
    }
    if (match('GET', '/friendship/posts')) {
      return _posts.where((p) => _isFriend('${(p['user'] as Map)['username']}')).map(_postView).toList();
    }
    if (match('POST', '/posts/create')) {
      final form = o.data as FormData;
      final req = form.files.firstWhere((f) => f.key == 'request', orElse: () => throw _MockError(400, 'Richiesta non valida'));
      final json = jsonDecode(utf8.decode(await _read(req.value))) as Map<String, dynamic>;
      final bytes = await _fileFrom(form, 'imageFile');
      String? image;
      if (bytes != null) {
        final key = _id('img');
        uploads[key] = bytes;
        image = '$uploadScheme$key';
      }
      final at = _iso(DateTime.now());
      final post = {
        'id': _id('p'),
        'user': _me,
        'content': json['content'],
        'image': image,
        'createdAt': at,
        'updatedAt': at,
        'comments': <dynamic>[],
        'likes': <dynamic>[],
      };
      _posts.insert(0, post);
      return {'message': 'Post created', 'result': _postView(post)};
    }
    if (match('PUT', '/posts/update')) {
      _postById('${body['id']}')['content'] = body['content'];
      return _ok('Post updated');
    }
    if (match('DELETE', '/posts/delete/:id')) {
      _posts.remove(_postById(last));
      return _ok('Post deleted');
    }
    if (match('GET', '/posts/:id')) return _postView(_postById(last));

    // Like e commenti
    if (match('POST', '/likes/create')) {
      final post = _postById('${body['postId']}');
      if ((post['likes'] as List).any((l) => l['username'] == _meName)) {
        throw _MockError(409, 'User has already liked this post');
      }
      final like = {'id': _id('l'), 'username': _meName, 'createdAt': _iso(DateTime.now())};
      (post['likes'] as List).add(like);
      return {'id': like['id'], 'postId': post['id'], 'user': _me, 'createdAt': like['createdAt']};
    }
    if (match('DELETE', '/likes/delete/:id')) {
      final found = _posts.any((p) => (p['likes'] as List).any((l) => l['id'] == last));
      if (!found) throw _MockError(404, 'Like not found: $last');
      for (final p in _posts) {
        (p['likes'] as List).removeWhere((l) => l['id'] == last);
      }
      return _ok('Like removed');
    }
    if (match('POST', '/comments/create')) {
      final post = _postById('${body['postId']}');
      final c = {
        'id': _id('c'),
        'postId': post['id'],
        'username': _meName,
        'content': body['content'],
        'createdAt': _iso(DateTime.now()),
      };
      (post['comments'] as List).add(c);
      return {'message': 'Comment created', 'result': {...c, 'user': _me}};
    }
    if (match('DELETE', '/comments/:id')) {
      for (final p in _posts) {
        (p['comments'] as List).removeWhere((c) => c['id'] == last);
      }
      return _ok('Comment deleted');
    }

    // Amicizie
    if (match('GET', '/friendship')) {
      return _page(_friendships
          .where((f) =>
              f['status'] == 'accepted' &&
              ((f['user'] as Map)['username'] == _meName || (f['friend'] as Map)['username'] == _meName))
          .toList());
    }
    if (match('GET', '/friendship/requests')) {
      return _friendships
          .where((f) => f['status'] == 'pending' && (f['friend'] as Map)['username'] == _meName)
          .toList();
    }
    if (match('GET', '/friendship/sent')) {
      return _friendships
          .where((f) => f['status'] == 'pending' && (f['user'] as Map)['username'] == _meName)
          .toList();
    }
    if (match('DELETE', '/friendship/cancel/:id')) {
      final f = _friendshipById(last);
      if ((f['user'] as Map)['username'] != _meName) throw _MockError(403, 'Non puoi annullare questa richiesta');
      if (f['status'] != 'pending') throw _MockError(404, 'Richiesta non trovata');
      _friendships.remove(f);
      return _ok('Friend request cancelled!');
    }
    if (match('POST', '/friendship/create')) {
      final other = _userBy('${q['friendUsername']}');
      if (other['username'] == _meName) throw _MockError(400, 'Non puoi aggiungere te stesso');
      final exists = _friendships.any((f) =>
          {(f['user'] as Map)['username'], (f['friend'] as Map)['username']}.containsAll([_meName, other['username']]));
      if (exists) throw _MockError(409, 'Siete già amici o c\'è già una richiesta');
      _friendships.add({
        'id': _id('f'),
        'user': _simple(_me),
        'friend': _simple(other),
        'status': 'pending',
        'createdAt': _iso(DateTime.now()),
      });
      return _ok('Friend request sent!');
    }
    if (match('GET', '/friendship/accept/:id')) {
      _friendshipById(last)['status'] = 'accepted';
      return _ok('Friend request accepted!');
    }
    if (match('GET', '/friendship/reject/:id')) {
      _friendships.remove(_friendshipById(last));
      return _ok('Friend request rejected!');
    }
    if (match('GET', '/friendship/block/:id')) {
      _friendshipById(last)['status'] = 'blocked';
      return _ok('User blocked!');
    }

    // Schede
    if (match('GET', '/workouts/profile')) {
      return _workouts.where((w) => (w['user'] as Map)['username'] == _meName).toList();
    }
    if (match('GET', '/workouts')) {
      return _page(_workouts.where((w) => w['isPublic'] == true || (w['user'] as Map)['username'] == _meName).toList());
    }
    if (match('POST', '/workouts/create')) {
      final w = _workout(_id('w'), _me, '${body['name']}', body['description'] as String?, body['isPublic'] == true,
          List<int>.from(body['dayOfWeek'] as List? ?? const []), body['startTime'] as String?, []);
      w['createdAt'] = _iso(DateTime.now());
      _workouts.add(w);
      return {'message': 'Workout created', 'result': w};
    }
    if (match('PUT', '/workouts/update')) {
      final w = _workoutById('${body['id']}');
      w
        ..['name'] = body['name']
        ..['description'] = body['description']
        ..['isPublic'] = body['isPublic']
        ..['dayOfWeek'] = body['dayOfWeek'] ?? const []
        ..['startTime'] = body['startTime'];
      return _ok('Workout updated');
    }
    if (match('DELETE', '/workouts/delete/:id')) {
      _workouts.remove(_workoutById(last));
      return _ok('Workout deleted');
    }
    if (match('GET', '/workouts/:id')) return _workoutById(last);
    if (match('POST', '/workouts/:id/share')) {
      final w = _workoutById(seg[1]);
      if ((w['user'] as Map)['username'] != _meName && w['isPublic'] != true) {
        throw _MockError(403, 'Only the owner can share a private workout');
      }
      final recipients = <String>{};
      for (final u in List<String>.from(body['usernames'] as List? ?? const [])) {
        if (!_isFriend(u)) throw _MockError(403, 'You can only share with your friends: $u');
        recipients.add(u);
      }
      for (final id in List<String>.from(body['groupIds'] as List? ?? const [])) {
        final g = _groupById(id);
        if (!_canSeeGroup(g)) throw _MockError(404, 'Gruppo non trovato');
        recipients.add((g['createdBy'] as Map)['username'] as String);
        for (final m in g['groupMembers'] as List) {
          if (m['status'] == 'accepted') recipients.add((m['user'] as Map)['username'] as String);
        }
      }
      recipients.remove(_meName);
      if (recipients.isEmpty) throw _MockError(400, 'Choose at least one friend or group to share with');
      return {'recipients': recipients.length};
    }

    // Esercizi della scheda
    if (match('POST', '/workout-exercises/create') || match('PUT', '/workout-exercises/update')) {
      final w = _workoutById('${body['workoutId']}');
      final ex = _exercises.firstWhere((e) => e['id'] == body['exerciseId'], orElse: () => throw _MockError(404, 'Esercizio non trovato'));
      final list = w['workoutExercises'] as List;
      final item = {...body, 'id': body['id'] ?? _id('we'), 'exerciseName': ex['name']};
      final i = list.indexWhere((e) => e['id'] == item['id']);
      i >= 0 ? list[i] = item : list.add(item);
      return {'message': 'ok', 'result': item};
    }
    if (match('DELETE', '/workout-exercises/delete/:id')) {
      for (final w in _workouts) {
        (w['workoutExercises'] as List).removeWhere((e) => e['id'] == last);
      }
      return _ok('Exercise removed');
    }

    // Libreria esercizi
    if (match('GET', '/exercises')) {
      final visible = _exercises.where((e) => e['isPublic'] == true || (e['createdBy'] as Map)['username'] == _meName).toList()
        ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      return _page(visible);
    }
    if (match('POST', '/exercises/create')) {
      final e = {...body, 'id': _id('e'), 'createdBy': _me};
      _exercises.add(e);
      return {'message': 'Exercise created', 'result': e};
    }
    if (match('DELETE', '/exercises/delete/:id')) {
      _exercises.removeWhere((e) => e['id'] == last);
      return _ok('Exercise deleted');
    }

    // Storico
    if (match('GET', '/workout-history/user') || match('GET', '/workout-history')) {
      final sorted = [..._history]..sort((a, b) => '${b['startedAt']}'.compareTo('${a['startedAt']}'));
      return _page(sorted);
    }
    if (match('GET', '/workout-history/group/:id')) {
      return _page(_history.where((h) => h['groupId'] == last).toList());
    }
    if (match('POST', '/workout-history')) {
      final h = {...body, 'id': _id('h'), 'userId': _me['id']};
      _history.add(h);
      return {'message': 'Workout logged', 'result': h};
    }
    if (match('DELETE', '/workout-history/delete/:id')) {
      _history.removeWhere((h) => h['id'] == last);
      return _ok('History deleted');
    }

    // Gruppi
    if (match('GET', '/workout_groups')) return _page(_groups.where(_canSeeGroup).map(_groupView).toList());
    if (match('POST', '/workout_groups/create')) {
      final g = _group(_id('g'), '${body['name']}', '', _me, DateTime.now(), [])
        ..['workoutId'] = null
        ..['scheduledFor'] = null;
      _groups.add(g);
      return {'message': 'Group created', 'result': _groupView(g)};
    }
    if (match('DELETE', '/workout_groups/delete/:id')) {
      _groups.removeWhere((g) => g['id'] == last);
      return _ok('Group deleted');
    }
    if (match('GET', '/workout_groups/:id')) return _groupView(_groupById(last));

    // Sessioni dei gruppi
    if (match('GET', '/group-sessions/upcoming')) {
      return [
        for (final s in _sessions)
          if (_canSeeGroup(_groupById('${s['groupId']}')) && s['startedAt'] == null) _sessionView(s),
      ]..sort((a, b) => '${a['scheduledFor']}'.compareTo('${b['scheduledFor']}'));
    }
    if (match('GET', '/group-sessions/group/:id')) {
      return [for (final s in _sessions) if (s['groupId'] == last) _sessionView(s)];
    }
    if (match('POST', '/group-sessions')) {
      if ((body['workoutId'] == null) == (body['routeId'] == null)) {
        throw _MockError(400, 'A session is either a workout or a run: set workoutId or routeId');
      }
      final s = _session(_groupById('${body['groupId']}'), body['workoutId'] as String?, DateTime.tryParse('${body['scheduledFor']}'), {},
          routeId: body['routeId'] as String?, meetingPoint: body['meetingPoint'] as String?);
      _sessions.add(s);
      return _sessionView(s);
    }
    if (match('POST', '/group-sessions/:id/attendance')) {
      final s = _sessionById(seg[1]);
      final going = body['going'] == true;
      (s['answers'] as Map<String, String>)[_meName] = going ? 'going' : 'declined';
      final organizer = (_groupById('${s['groupId']}')['createdBy'] as Map)['username'];
      if (going && organizer != _meName && s['startedAt'] == null) s['autoStartAt'] = DateTime.now().add(const Duration(seconds: 8));
      return _sessionView(s);
    }
    if (match('POST', '/group-sessions/:id/start')) {
      final s = _sessionById(seg[1]);
      s['startedAt'] ??= _iso(DateTime.now());
      return _sessionView(s);
    }
    if (match('DELETE', '/group-sessions/:id')) {
      _sessions.removeWhere((s) => s['id'] == last);
      return _ok('Session deleted');
    }
    if (match('GET', '/group-sessions/:id')) return _sessionView(_sessionById(last));

    // Membri dei gruppi
    if (match('GET', '/group_members')) {
      return _page([
        for (final g in _groups)
          for (final m in g['groupMembers'] as List)
            if ((m['user'] as Map)['username'] == _meName) _withGroup(m as Map<String, dynamic>, g),
      ]);
    }
    if (match('POST', '/group_members/create')) {
      final g = _groupById('${body['groupId']}');
      final u = _userBy('${body['invitedUsername']}');
      final members = g['groupMembers'] as List;
      if (members.any((m) => (m['user'] as Map)['username'] == u['username'])) {
        throw _MockError(409, '@${u['username']} è già nel gruppo');
      }
      final m = {
        'id': _id('m'),
        'workoutGroupId': g['id'],
        'user': _simple(u),
        'status': 'invited',
        'createdAt': _iso(DateTime.now()),
      };
      members.add(m);
      return {'message': 'Invited', 'result': _withGroup(m, g)};
    }
    if (match('POST', '/group_members/accept-invitation/:id')) {
      _memberById(last)['status'] = 'accepted';
      return _ok('Invitation accepted');
    }
    if (match('POST', '/group_members/reject-invitation/:id') || match('DELETE', '/group_members/delete/:id')) {
      for (final g in _groups) {
        (g['groupMembers'] as List).removeWhere((m) => m['id'] == last);
      }
      return _ok('Removed');
    }

    // Notifiche
    if (match('GET', '/notifications')) return _page(_notifications);
    if (match('GET', '/notifications/unread-count')) {
      return {'count': _notifications.where((n) => n['read'] != true).length};
    }
    if (match('POST', '/notifications/read-all')) {
      for (final n in _notifications) {
        n['read'] = true;
      }
      return _ok('Notifications marked as read');
    }
    if (match('POST', '/notifications/:id/read')) {
      final id = seg[1];
      _notifications.firstWhere((n) => n['id'] == id, orElse: () => throw _MockError(404, 'Notifica non trovata'))['read'] = true;
      return _ok('Notification marked as read');
    }
    if (match('DELETE', '/notifications/:id')) {
      final id = seg[1];
      if (!_notifications.any((n) => n['id'] == id)) throw _MockError(404, 'Notifica non trovata');
      _notifications.removeWhere((n) => n['id'] == id);
      return _ok('Notification deleted');
    }
    if (match('DELETE', '/notifications')) {
      _notifications.clear();
      return _ok('Notifications deleted');
    }
    if (match('POST', '/devices')) {
      devices.add('${body['token']}');
      return _ok('Device registered');
    }
    if (match('DELETE', '/devices')) {
      devices.remove('${q['token']}');
      return _ok('Device unregistered');
    }

    // Corsa
    final running = _running(match, last, seg, body);
    if (!identical(running, _unhandled)) return running;

    throw _MockError(404, 'Mock: rotta non gestita $method $path');
  }

  Map<String, dynamic> _postById(String id) =>
      _posts.firstWhere((p) => p['id'] == id, orElse: () => throw _MockError(404, 'Post non trovato'));

  Map<String, dynamic> _workoutById(String id) =>
      _workouts.firstWhere((w) => w['id'] == id, orElse: () => throw _MockError(404, 'Scheda non trovata'));

  Map<String, dynamic> _groupById(String id) =>
      _groups.firstWhere((g) => g['id'] == id, orElse: () => throw _MockError(404, 'Gruppo non trovato'));

  Map<String, dynamic> _friendshipById(String id) =>
      _friendships.firstWhere((f) => f['id'] == id, orElse: () => throw _MockError(404, 'Amicizia non trovata'));

  Map<String, dynamic> _memberById(String id) {
    for (final g in _groups) {
      for (final m in g['groupMembers'] as List) {
        if (m['id'] == id) return m as Map<String, dynamic>;
      }
    }
    throw _MockError(404, 'Invito non trovato');
  }

  Future<Uint8List?> _fileFrom(Object? data, String field) async {
    if (data is! FormData) return null;
    for (final f in data.files) {
      if (f.key == field) return _read(f.value);
    }
    return null;
  }

  Future<Uint8List> _read(MultipartFile file) async {
    final chunks = await file.finalize().toList();
    return Uint8List.fromList(chunks.expand((c) => c).toList());
  }
}

class _MockError implements Exception {
  _MockError(this.status, this.message);

  final int status;
  final String message;
}
