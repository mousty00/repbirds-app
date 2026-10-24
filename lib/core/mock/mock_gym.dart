part of 'mock_backend.dart';

/// Palestre in modalità mock, con le forme JSON di `/gym` e `/memberships` di
/// repbirds-api. Il login `palestra` entra come la palestra "Fit Club Milano";
/// qualunque altro login è `mousty`, iscritto a quella palestra con la tessera attiva.
extension _MockGym on MockBackend {
  static const _gymUsername = 'palestra';

  void _seedGym(Map<String, dynamic> giulia, Map<String, dynamic> marco, Map<String, dynamic> sara) {
    _gymUser = {..._user('ug', _gymUsername, '', '', 400), 'firstName': null, 'lastName': null, 'birthDate': null, 'roleName': 'Gym'};
    _gym = {
      'id': 'gym1',
      'username': _gymUsername,
      'name': 'Fit Club Milano',
      'description': 'Sala pesi, corsi e functional. Aperti 7-23.',
      'address': 'Via Tortona 12',
      'city': 'Milano',
      'phone': '02 1234567',
      'image': null,
    };
    final monthly = {'id': 'gp1', 'name': 'Mensile', 'description': 'Sala pesi e corsi', 'priceCents': 4500, 'durationDays': 30, 'active': true};
    final yearly = {'id': 'gp2', 'name': 'Annuale', 'description': 'Tutto incluso', 'priceCents': 39000, 'durationDays': 365, 'active': true};
    _gymPlans.addAll([monthly, yearly]);

    final today = _day(_now);
    Map<String, dynamic> member(Map<String, dynamic> u, Map<String, dynamic> plan, int startedDaysAgo, {String status = 'ACTIVE'}) {
      final starts = today.subtract(Duration(days: startedDaysAgo));
      return {
        'id': _id('gm'),
        'user': u,
        'planId': plan['id'],
        'startsOn': starts,
        'endsOn': starts.add(Duration(days: plan['durationDays'] as int)),
        'status': status,
        // stesso formato di GymCardService.newSecret: 32 byte in base64url
        'cardId': '7b7f6f4e-2c1a-4d3b-9e8f-${(_seq++).toString().padLeft(12, '0')}',
        'secret': base64Url.encode(List.generate(32, (i) => (i * 7 + _seq) % 256)).replaceAll('=', ''),
      };
    }

    _gymMembers.addAll([
      member(_me, monthly, 10),
      member(giulia, yearly, 100),
      member(marco, monthly, 40), // scaduto da 10 giorni
      member(sara, monthly, 5, status: 'SUSPENDED'),
    ]);

    final w = _workout('wg1', _gymUser, 'Full body principianti', 'La scheda d\'ingresso: 3 volte a settimana.', false, [1, 3, 5], null, []);
    w['gymId'] = _gym['id'];
    w['gymName'] = _gym['name'];
    _workouts.add(w);

    final weekday = _now.weekday;
    _gymCourses.addAll([
      _newCourse('Spinning', 'Chiara', 'Sala 2', [weekday, (weekday + 1) % 7 + 1], '19:00', 45, 12, [_me, giulia]),
      _newCourse('Yoga', 'Paolo', 'Sala 1', [2, 4], '08:30', 60, 15, [giulia]),
      _newCourse('Functional', 'Chiara', 'Box', [1, 3, 5], '18:00', 50, 10, []),
    ]);

    _gymCheckIns.addAll([
      _newCheckIn(_gymMembers[1], true, null, 'NFC', _now.subtract(const Duration(hours: 1))),
      _newCheckIn(_gymMembers[2], false, 'EXPIRED', 'QR', _now.subtract(const Duration(hours: 2))),
      _newCheckIn(_gymMembers[0], true, null, 'QR', _now.subtract(const Duration(days: 1, hours: 3))),
    ]);
  }

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get _asGymAccount => _account['username'] == _gymUsername;

  Map<String, dynamic> _newCourse(String name, String instructor, String room, List<int> days, String time, int minutes, int capacity,
          List<Map<String, dynamic>> enrolled) =>
      {
        'id': _id('gc'),
        'name': name,
        'description': null,
        'instructor': instructor,
        'room': room,
        'dayOfWeek': days,
        'startTime': time,
        'durationMinutes': minutes,
        'capacity': capacity,
        'enrolled': [for (final u in enrolled) {'id': _id('ge'), 'user': _simple(u), 'createdAt': MockBackend._iso(_now)}],
      };

  Map<String, dynamic> _newCheckIn(Map<String, dynamic>? m, bool accepted, String? reason, String method, DateTime at) => {
        'id': _id('gk'),
        'member': m,
        'accepted': accepted,
        'reason': reason,
        'method': method,
        'checkedInAt': at,
      };

  // ---------------------------------------------------------------- viste

  bool _memberActive(Map<String, dynamic> m) {
    final today = _day(DateTime.now());
    return m['status'] == 'ACTIVE' && !today.isBefore(m['startsOn'] as DateTime) && !today.isAfter(m['endsOn'] as DateTime);
  }

  String? _planName(Object? id) => _gymPlans.firstWhere((p) => p['id'] == id, orElse: () => const {})['name'] as String?;

  Map<String, dynamic> _gymView({bool stats = false}) {
    final today = _day(DateTime.now());
    return {
      ..._gym,
      if (stats)
        'stats': {
          'activeMembers': _gymMembers.where(_memberActive).length,
          'totalMembers': _gymMembers.length,
          'activePlans': _gymPlans.where((p) => p['active'] == true).length,
          'courses': _gymCourses.length,
          'workouts': _workouts.where((w) => w['gymId'] == _gym['id']).length,
          'checkInsToday': _gymCheckIns.where((c) => c['accepted'] == true && !(c['checkedInAt'] as DateTime).isBefore(today)).length,
        },
    };
  }

  Map<String, dynamic> _memberView(Map<String, dynamic> m) {
    final u = m['user'] as Map<String, dynamic>;
    final last = _gymCheckIns.where((c) => c['member'] == m && c['accepted'] == true).map((c) => c['checkedInAt'] as DateTime).fold<DateTime?>(
          null,
          (a, b) => a == null || b.isAfter(a) ? b : a,
        );
    return {
      'id': m['id'],
      'user': _simple(u),
      'firstName': u['firstName'],
      'lastName': u['lastName'],
      'planId': m['planId'],
      'planName': _planName(m['planId']),
      'startsOn': _date(m['startsOn'] as DateTime),
      'endsOn': _date(m['endsOn'] as DateTime),
      'status': m['status'],
      'active': _memberActive(m),
      'lastCheckInAt': last == null ? null : MockBackend._iso(last),
    };
  }

  Map<String, dynamic> _courseView(Map<String, dynamic> c) {
    final enrolled = c['enrolled'] as List;
    return {
      ...c,
      'gymId': _gym['id'],
      'gymName': _gym['name'],
      'enrolledCount': enrolled.length,
      'enrolled': enrolled.any((e) => (e['user'] as Map)['username'] == _meName),
    };
  }

  Map<String, dynamic> _checkInView(Map<String, dynamic> c) {
    final m = c['member'] as Map<String, dynamic>?;
    final u = m?['user'] as Map<String, dynamic>?;
    final name = [u?['firstName'], u?['lastName']].whereType<String>().join(' ');
    return {
      'id': c['id'],
      'accepted': c['accepted'],
      'reason': c['reason'],
      'member': u == null ? null : _simple(u),
      'memberName': name.isEmpty ? null : name,
      'planName': m == null ? null : _planName(m['planId']),
      'endsOn': m == null ? null : _date(m['endsOn'] as DateTime),
      'method': c['method'],
      'checkedInAt': MockBackend._iso(c['checkedInAt'] as DateTime),
    };
  }

  Map<String, dynamic>? get _myMembership =>
      _gymMembers.where((m) => (m['user'] as Map)['username'] == _meName).firstOrNull;

  Map<String, dynamic> _requireMembership(String gymId) {
    final m = _myMembership;
    if (gymId != _gym['id'] || m == null || !_memberActive(m)) throw _MockError(403, 'Serve un abbonamento attivo a questa palestra');
    return m;
  }

  Map<String, dynamic> _gymMemberById(String id) =>
      _gymMembers.firstWhere((m) => m['id'] == id, orElse: () => throw _MockError(404, 'Iscritto non trovato'));

  Map<String, dynamic> _gymCourseById(String id) =>
      _gymCourses.firstWhere((c) => c['id'] == id, orElse: () => throw _MockError(404, 'Corso non trovato'));

  Map<String, dynamic> _gymPlanById(String id) =>
      _gymPlans.firstWhere((p) => p['id'] == id, orElse: () => throw _MockError(404, 'Abbonamento non trovato'));

  /// Come GymCheckInService: firma valida entro ±4 finestre, poi stato e date dell'abbonamento.
  Map<String, dynamic> _verifyCode(String code, String method) {
    final parts = code.split('.');
    final m = parts.length == 4 ? _gymMembers.where((m) => m['cardId'] == parts[1]).firstOrNull : null;
    var valid = false;
    if (m != null) {
      final card = MembershipCard(cardId: '${m['cardId']}', secret: '${m['secret']}');
      final now = DateTime.now();
      for (var d = -4; d <= 4 && !valid; d++) {
        valid = CardCode.at(card, now.add(Duration(seconds: d * card.periodSeconds))) == code;
      }
    }
    final today = _day(DateTime.now());
    final reason = !valid
        ? 'INVALID_CODE'
        : m!['status'] == 'SUSPENDED'
            ? 'SUSPENDED'
            : today.isBefore(m['startsOn'] as DateTime)
                ? 'NOT_STARTED'
                : today.isAfter(m['endsOn'] as DateTime)
                    ? 'EXPIRED'
                    : null;
    final c = _newCheckIn(valid ? m : null, reason == null, reason, method, DateTime.now());
    _gymCheckIns.insert(0, c);
    return _checkInView(c);
  }

  // ---------------------------------------------------------------- rotte

  Object? _gymRoutes(bool Function(String, String) match, List<String> seg, Map<String, dynamic> q, Map<String, dynamic> body) {
    final last = seg.isEmpty ? '' : seg.last;
    if (match('POST', '/auth/signup/gym')) {
      if (_users.any((u) => u['username'] == '${body['username']}')) throw _MockError(409, "Username '${body['username']}' already exists");
      return _ok('Signup successful!');
    }

    // Lato iscritto
    if (match('GET', '/memberships')) {
      final m = _myMembership;
      if (m == null) return const <dynamic>[];
      final active = _memberActive(m);
      return [
        {
          'id': m['id'],
          'gym': _gymView(),
          'planName': _planName(m['planId']),
          'startsOn': _date(m['startsOn'] as DateTime),
          'endsOn': _date(m['endsOn'] as DateTime),
          'status': m['status'],
          'active': active,
          'card': active ? {'cardId': m['cardId'], 'secret': m['secret'], 'periodSeconds': 30} : null,
        },
      ];
    }
    if (match('GET', '/memberships/courses')) {
      final m = _myMembership;
      if (m == null || !_memberActive(m)) return const <dynamic>[];
      return [for (final c in _gymCourses) if (_courseView(c)['enrolled'] == true) _courseView(c)];
    }
    if (match('GET', '/memberships/:gym/workouts')) {
      _requireMembership(seg[1]);
      return _workouts.where((w) => w['gymId'] == seg[1]).toList();
    }
    if (match('GET', '/memberships/:gym/courses')) {
      _requireMembership(seg[1]);
      return _gymCourses.map(_courseView).toList();
    }
    if (match('POST', '/memberships/:gym/courses/:course/enroll')) {
      _requireMembership(seg[1]);
      final c = _gymCourseById(seg[3]);
      final enrolled = c['enrolled'] as List;
      if (!enrolled.any((e) => (e['user'] as Map)['username'] == _meName)) {
        if (enrolled.length >= (c['capacity'] as int? ?? 1 << 30)) throw _MockError(409, 'Il corso è al completo');
        enrolled.add({'id': _id('ge'), 'user': _simple(_me), 'createdAt': MockBackend._iso(DateTime.now())});
      }
      return _courseView(c);
    }
    if (match('DELETE', '/memberships/:gym/courses/:course/enroll')) {
      final c = _gymCourseById(seg[3]);
      (c['enrolled'] as List).removeWhere((e) => (e['user'] as Map)['username'] == _meName);
      return _courseView(c);
    }

    if (seg.isEmpty || seg.first != 'gym') return _unhandled;
    if (!_asGymAccount) throw _MockError(403, 'Access Denied');

    // Profilo
    if (match('GET', '/gym/me')) return _gymView(stats: true);
    if (match('PUT', '/gym/me')) {
      for (final k in ['name', 'description', 'address', 'city', 'phone']) {
        _gym[k] = body[k];
      }
      return _gymView(stats: true);
    }

    // Abbonamenti
    if (match('GET', '/gym/plans')) return _gymPlans;
    if (match('POST', '/gym/plans')) {
      final p = {...body, 'id': _id('gp')};
      _gymPlans.add(p);
      return p;
    }
    if (match('PUT', '/gym/plans/:id')) return _gymPlanById(last)..addAll(body);
    if (match('DELETE', '/gym/plans/:id')) {
      if (_gymMembers.any((m) => m['planId'] == last)) throw _MockError(409, 'Ci sono iscritti con questo abbonamento: disattivalo invece');
      _gymPlans.remove(_gymPlanById(last));
      return _ok('Plan deleted');
    }

    // Iscritti
    if (match('GET', '/gym/members')) return _gymMembers.map(_memberView).toList();
    if (match('POST', '/gym/members')) {
      final u = _userBy('${body['username']}');
      final plan = _gymPlanById('${body['planId']}');
      final starts = parseLocalDate(body['startsOn']) ?? _day(DateTime.now());
      final ends = parseLocalDate(body['endsOn']) ?? starts.add(Duration(days: plan['durationDays'] as int));
      final existing = _gymMembers.where((m) => m['user'] == u).firstOrNull;
      final m = existing ??
          {
            'id': _id('gm'),
            'user': u,
            'cardId': '7b7f6f4e-2c1a-4d3b-9e8f-${(_seq++).toString().padLeft(12, '0')}',
            'secret': base64Url.encode(List.generate(32, (i) => (i * 13 + _seq) % 256)).replaceAll('=', ''),
          };
      m
        ..['planId'] = plan['id']
        ..['startsOn'] = starts
        ..['endsOn'] = ends
        ..['status'] = 'ACTIVE';
      if (existing == null) _gymMembers.add(m);
      return _memberView(m);
    }
    if (match('PUT', '/gym/members/:id')) {
      final m = _gymMemberById(last);
      if (body['planId'] != null) m['planId'] = body['planId'];
      if (body['startsOn'] != null) m['startsOn'] = parseLocalDate(body['startsOn']);
      if (body['endsOn'] != null) m['endsOn'] = parseLocalDate(body['endsOn']);
      if (body['status'] != null) m['status'] = body['status'];
      return _memberView(m);
    }
    if (match('DELETE', '/gym/members/:id')) {
      _gymMembers.remove(_gymMemberById(last));
      return _ok('Member removed');
    }
    if (match('POST', '/gym/members/:id/check-in')) {
      final m = _gymMemberById(seg[2]);
      final active = _memberActive(m);
      final c = _newCheckIn(m, active, active ? null : (m['status'] == 'SUSPENDED' ? 'SUSPENDED' : 'EXPIRED'), 'MANUAL', DateTime.now());
      _gymCheckIns.insert(0, c);
      return _checkInView(c);
    }

    // Schede
    if (match('GET', '/gym/workouts')) return _workouts.where((w) => w['gymId'] == _gym['id']).toList().reversed.toList();
    if (match('POST', '/gym/workouts')) {
      final w = _workout(_id('w'), _gymUser, '${body['name']}', body['description'] as String?, false,
          List<int>.from(body['dayOfWeek'] as List? ?? const []), body['startTime'] as String?, []);
      w
        ..['createdAt'] = MockBackend._iso(DateTime.now())
        ..['gymId'] = _gym['id']
        ..['gymName'] = _gym['name'];
      _workouts.add(w);
      return w;
    }

    // Corsi
    if (match('GET', '/gym/courses')) return _gymCourses.map(_courseView).toList();
    if (match('POST', '/gym/courses')) {
      final c = {...body, 'id': _id('gc'), 'enrolled': <dynamic>[]};
      _gymCourses.add(c);
      return _courseView(c);
    }
    if (match('PUT', '/gym/courses/:id')) {
      final c = _gymCourseById(last);
      body.remove('id');
      c.addAll(body);
      return _courseView(c);
    }
    if (match('DELETE', '/gym/courses/:id')) {
      _gymCourses.remove(_gymCourseById(last));
      return _ok('Course deleted');
    }
    if (match('GET', '/gym/courses/:id/enrollments')) return _gymCourseById(seg[2])['enrolled'];
    if (match('POST', '/gym/courses/:id/enrollments')) {
      final c = _gymCourseById(seg[2]);
      final u = _userBy('${body['username']}');
      final m = _gymMembers.where((m) => m['user'] == u).firstOrNull;
      if (m == null || !_memberActive(m)) throw _MockError(400, '@${u['username']} non ha un abbonamento attivo');
      final enrolled = c['enrolled'] as List;
      if (enrolled.any((e) => (e['user'] as Map)['username'] == u['username'])) throw _MockError(409, 'Già iscritto');
      if (enrolled.length >= (c['capacity'] as int? ?? 1 << 30)) throw _MockError(409, 'Il corso è al completo');
      final e = {'id': _id('ge'), 'user': _simple(u), 'createdAt': MockBackend._iso(DateTime.now())};
      enrolled.add(e);
      return e;
    }
    if (match('DELETE', '/gym/courses/:id/enrollments/:user')) {
      (_gymCourseById(seg[2])['enrolled'] as List).removeWhere((e) => (e['user'] as Map)['id'] == last);
      return _ok('Enrollment removed');
    }

    // Ingressi
    if (match('POST', '/gym/check-ins')) return _verifyCode('${body['code']}', '${body['method'] ?? 'QR'}');
    if (match('GET', '/gym/check-ins')) {
      final limit = int.tryParse('${q['limit'] ?? 50}') ?? 50;
      return _gymCheckIns.take(limit).map(_checkInView).toList();
    }
    return _unhandled;
  }
}
