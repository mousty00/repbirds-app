part of 'mock_backend.dart';

/// Risposta di [_running] per le rotte che non sono della corsa.
const _unhandled = Object();

/// Corsa in modalità mock: percorsi, corse di gruppo e corse registrate, con le
/// stesse forme JSON di `/routes`, `/run-events` e `/runs` di repbirds-api.
extension _MockRunning on MockBackend {
  void _seedRunning(Map<String, dynamic> giulia, Map<String, dynamic> marco, Map<String, dynamic> sara) {
    // Milano: giro del Parco Sempione, Navigli, e un lungo dell'Idroscalo di Giulia
    const sempione = [
      [45.4728, 9.1765], [45.4755, 9.1720], [45.4740, 9.1675], [45.4705, 9.1700], [45.4690, 9.1750], [45.4728, 9.1765],
    ];
    const navigli = [
      [45.4520, 9.1770], [45.4535, 9.1720], [45.4550, 9.1660], [45.4560, 9.1600], [45.4545, 9.1590], [45.4520, 9.1770],
    ];
    const idroscalo = [
      [45.4640, 9.2830], [45.4740, 9.2860], [45.4790, 9.2930], [45.4700, 9.2950], [45.4600, 9.2900], [45.4640, 9.2830],
    ];
    final r1 = _newRoute(_me, 'Giro del Sempione', sempione, isPublic: true, climb: 6, description: 'Sterrato battuto, fontanella vicino all\'Arco.');
    final r2 = _newRoute(_me, 'Navigli al tramonto', navigli, climb: 2);
    final r3 = _newRoute(giulia, 'Lungo dell\'Idroscalo', idroscalo, isPublic: true, climb: 4);
    _runRoutes.addAll([r1, r2, r3]);

    Map<String, dynamic> participant(Map<String, dynamic> u, String status) =>
        {'id': _id('rp'), 'user': _simple(u), 'status': status, 'createdAt': MockBackend._iso(_now)};
    _runEvents.addAll([
      _newEvent(r1, _me, 'Corsetta del sabato', _now.add(const Duration(days: 4, hours: 2)), 'Arco della Pace',
          [participant(giulia, 'accepted'), participant(marco, 'invited')]),
      _newEvent(r3, giulia, 'Lungo della domenica', _now.add(const Duration(days: 5)), 'Ingresso Idroscalo Est',
          [participant(_me, 'invited'), participant(sara, 'accepted')]),
    ]);

    final start = _now.subtract(const Duration(days: 2, hours: 3));
    _runs.add(_newRun(_me, r1, null, start, 1650, sempione));
    _notifications.insert(
      0,
      {
        'id': _id('n'),
        'type': 'RUN_INVITE',
        'actor': _simple(giulia),
        'referenceId': _runEvents[1]['id'],
        'detail': 'Lungo della domenica',
        'read': false,
        'createdAt': MockBackend._iso(_now.subtract(const Duration(hours: 1))),
      },
    );
  }

  Map<String, dynamic> _newRoute(Map<String, dynamic> owner, String name, List<List<double>> points,
      {bool isPublic = false, int? climb, String? description, Map<String, dynamic>? author, String? sourceId}) {
    final line = [for (final p in points) LatLng(p[0], p[1])];
    return {
      'id': _id('r'),
      'name': name,
      'description': description,
      'isPublic': isPublic,
      'owner': _simple(owner),
      'originalAuthor': author == null ? null : _simple(author),
      'sourceRouteId': sourceId,
      'waypoints': points,
      'points': points,
      'distanceM': lengthOf(line).round(),
      'elevationGainM': climb,
      'createdAt': MockBackend._iso(DateTime.now()),
      'updatedAt': MockBackend._iso(DateTime.now()),
    };
  }

  Map<String, dynamic> _newEvent(Map<String, dynamic> route, Map<String, dynamic> creator, String title, DateTime when,
      String? meeting, List<Map<String, dynamic>> participants) {
    final start = (route['points'] as List).first as List;
    return {
      'id': _id('re'),
      'title': title,
      'startsAt': MockBackend._iso(when),
      'meetingPoint': meeting,
      'meetingLat': start[0],
      'meetingLng': start[1],
      'notes': null,
      'createdBy': _simple(creator),
      'routeId': route['id'],
      'participants': participants,
      'createdAt': MockBackend._iso(DateTime.now()),
    };
  }

  Map<String, dynamic> _newRun(Map<String, dynamic> user, Map<String, dynamic>? route, Map<String, dynamic>? event,
      DateTime startedAt, int durationS, List<List<double?>> track) {
    final line = [for (final p in track) LatLng(p[0]!, p[1]!)];
    final distance = lengthOf(line).round();
    return {
      'id': _id('run'),
      'user': _simple(user),
      'routeId': route?['id'],
      'routeName': route?['name'],
      'eventId': event?['id'],
      'eventTitle': event?['title'],
      'startedAt': MockBackend._iso(startedAt),
      'completedAt': MockBackend._iso(startedAt.add(Duration(seconds: durationS))),
      'distanceM': distance,
      'durationS': durationS,
      'paceSPerKm': distance >= 100 ? (durationS * 1000 / distance).round() : null,
      'elevationGainM': null,
      'track': track,
      'notes': null,
    };
  }

  // ---------------------------------------------------------------- viste

  String _ownerOf(Map<String, dynamic> r) => (r['owner'] as Map)['username'] as String;

  bool _canSeeRoute(Map<String, dynamic> r) =>
      _ownerOf(r) == _meName ||
      (r['isPublic'] == true && _isFriend(_ownerOf(r))) ||
      _runEvents.any((e) => e['routeId'] == r['id'] && _eventStatus(e) != null);

  String? _eventStatus(Map<String, dynamic> e) {
    if ((e['createdBy'] as Map)['username'] == _meName) return 'owner';
    for (final p in e['participants'] as List) {
      if ((p['user'] as Map)['username'] == _meName) return p['status'] as String;
    }
    return null;
  }

  Map<String, dynamic> _routeById(String id) {
    final r = _runRoutes.firstWhere((r) => r['id'] == id, orElse: () => throw _MockError(404, 'Percorso non trovato'));
    if (!_canSeeRoute(r)) throw _MockError(404, 'Percorso non trovato');
    return r;
  }

  Map<String, dynamic> _eventById(String id) {
    final e = _runEvents.firstWhere((e) => e['id'] == id, orElse: () => throw _MockError(404, 'Corsa non trovata'));
    if (_eventStatus(e) == null) throw _MockError(404, 'Corsa non trovata');
    return e;
  }

  Map<String, dynamic> _eventView(Map<String, dynamic> e) => {
        ...e,
        'route': _runRoutes.firstWhere((r) => r['id'] == e['routeId']),
        'myStatus': _eventStatus(e),
      };

  void _requireOwner(Map<String, dynamic> owner, String message) {
    if (owner['username'] != _meName) throw _MockError(403, message);
  }

  // ---------------------------------------------------------------- rotte

  Object? _running(bool Function(String, String) match, String last, List<String> seg, Map<String, dynamic> body) {
    // Percorsi
    if (match('GET', '/routes')) return _page(_runRoutes.where((r) => _ownerOf(r) == _meName).toList().reversed.toList());
    if (match('GET', '/routes/friends')) {
      return _page(_runRoutes.where((r) => _ownerOf(r) != _meName && r['isPublic'] == true && _isFriend(_ownerOf(r))).toList());
    }
    if (match('POST', '/routes/plan')) {
      final points = List<List<double>>.from((body['waypoints'] as List).map((p) => List<double>.from(p as List)));
      if (points.length < 2) throw _MockError(400, 'Servono almeno due punti');
      return {
        'points': points,
        'distanceM': lengthOf([for (final p in points) LatLng(p[0], p[1])]).round(),
        'elevationGainM': null,
        'snapped': false,
      };
    }
    if (match('POST', '/routes/create') || match('PUT', '/routes/update/:id')) {
      final points = List<List<double>>.from(((body['points'] ?? body['waypoints']) as List).map((p) => List<double>.from(p as List)));
      final route = _newRoute(_me, '${body['name']}', points,
          isPublic: body['isPublic'] == true, description: body['description'] as String?);
      route['waypoints'] = body['waypoints'];
      if (seg.first == 'routes' && seg.length == 3) {
        final existing = _routeById(last);
        _requireOwner(existing['owner'] as Map<String, dynamic>, 'Non è un tuo percorso');
        existing.addAll({...route, 'id': existing['id'], 'createdAt': existing['createdAt'], 'originalAuthor': existing['originalAuthor']});
        return {'message': 'Route updated', 'result': existing};
      }
      _runRoutes.add(route);
      return {'message': 'Route created', 'result': route};
    }
    if (match('DELETE', '/routes/delete/:id')) {
      final r = _routeById(last);
      _requireOwner(r['owner'] as Map<String, dynamic>, 'Non è un tuo percorso');
      _runRoutes.remove(r);
      _runEvents.removeWhere((e) => e['routeId'] == last);
      return _ok('Route deleted');
    }
    if (match('POST', '/routes/:id/save')) {
      final r = _routeById(seg[1]);
      if (_ownerOf(r) == _meName) throw _MockError(400, 'Questo percorso è già tuo');
      if (r['isPublic'] != true) throw _MockError(403, 'Si possono salvare solo i percorsi pubblici');
      if (_runRoutes.any((c) => c['sourceRouteId'] == r['id'] && _ownerOf(c) == _meName)) {
        throw _MockError(409, 'Hai già salvato questo percorso');
      }
      final copy = {
        ...r,
        'id': _id('r'),
        'owner': _simple(_me),
        'isPublic': false,
        'sourceRouteId': r['id'],
        'originalAuthor': r['originalAuthor'] ?? r['owner'],
      };
      _runRoutes.add(copy);
      return {'message': 'Route saved', 'result': copy};
    }
    if (match('GET', '/routes/:id/gpx')) return _gpx('${_routeById(seg[1])['name']}', _routeById(seg[1])['points'] as List);
    if (match('GET', '/routes/:id')) return _routeById(last);

    // Corse di gruppo
    if (match('GET', '/run-events')) {
      return _page(_runEvents.where((e) => _eventStatus(e) != null).map(_eventView).toList());
    }
    if (match('POST', '/run-events/create')) {
      final route = _routeById('${body['routeId']}');
      _requireOwner(route['owner'] as Map<String, dynamic>, 'Puoi organizzare una corsa solo su un tuo percorso');
      final e = _newEvent(route, _me, '${body['title']}', DateTime.parse('${body['startsAt']}'), body['meetingPoint'] as String?, [
        for (final u in {...?(body['invitedUsernames'] as List?)?.map((u) => '$u')})
          if (u != _meName) {'id': _id('rp'), 'user': _simple(_userBy(u)), 'status': 'invited', 'createdAt': MockBackend._iso(DateTime.now())},
      ]);
      e['notes'] = body['notes'];
      _runEvents.add(e);
      return {'message': 'Run event created', 'result': _eventView(e)};
    }
    if (match('POST', '/run-events/:id/invite')) {
      final e = _eventById(seg[1]);
      _requireOwner(e['createdBy'] as Map<String, dynamic>, 'Solo chi organizza può invitare');
      final u = _userBy('${body['username']}');
      final participants = e['participants'] as List;
      if (u['username'] == _meName || participants.any((p) => (p['user'] as Map)['username'] == u['username'])) {
        throw _MockError(409, '@${u['username']} è già invitato');
      }
      participants.add({'id': _id('rp'), 'user': _simple(u), 'status': 'invited', 'createdAt': MockBackend._iso(DateTime.now())});
      return {'message': 'Invited', 'result': _eventView(e)};
    }
    if (match('POST', '/run-events/:id/accept') || match('POST', '/run-events/:id/reject')) {
      final e = _eventById(seg[1]);
      final participants = e['participants'] as List;
      final mine = participants.firstWhere((p) => (p['user'] as Map)['username'] == _meName && p['status'] == 'invited',
          orElse: () => throw _MockError(404, 'Invito non trovato'));
      last == 'accept' ? mine['status'] = 'accepted' : participants.remove(mine);
      return _ok(last == 'accept' ? 'Invitation accepted' : 'Invitation rejected');
    }
    if (match('DELETE', '/run-events/participants/:id')) {
      for (final e in _runEvents) {
        (e['participants'] as List).removeWhere((p) => p['id'] == last);
      }
      return _ok('Participant removed');
    }
    if (match('DELETE', '/run-events/delete/:id')) {
      final e = _eventById(last);
      _requireOwner(e['createdBy'] as Map<String, dynamic>, 'Solo chi organizza può annullare la corsa');
      _runEvents.remove(e);
      return _ok('Run event deleted');
    }
    if (match('GET', '/run-events/:id/runs')) {
      _eventById(seg[1]);
      return _runs.where((r) => r['eventId'] == seg[1]).toList()
        ..sort((a, b) => (a['durationS'] as int).compareTo(b['durationS'] as int));
    }
    if (match('GET', '/run-events/:id')) return _eventView(_eventById(last));

    // Corse registrate
    if (match('GET', '/runs')) {
      return _page(_runs.where((r) => (r['user'] as Map)['username'] == _meName).toList()
        ..sort((a, b) => '${b['startedAt']}'.compareTo('${a['startedAt']}')));
    }
    if (match('POST', '/runs/create')) {
      final event = body['eventId'] == null ? null : _eventById('${body['eventId']}');
      if (event != null && _eventStatus(event) == 'invited') throw _MockError(403, 'Accetta prima l\'invito');
      final routeId = body['routeId'] ?? event?['routeId'];
      final route = routeId == null ? null : _routeById('$routeId');
      final track = List<List<double?>>.from((body['track'] as List).map((p) => [for (final c in p as List) (c as num?)?.toDouble()]));
      final run = _newRun(_me, route, event, DateTime.parse('${body['startedAt']}'), body['durationS'] as int, track);
      _runs.add(run);
      return {'message': 'Run saved', 'result': run};
    }
    if (match('DELETE', '/runs/delete/:id')) {
      _runs.removeWhere((r) => r['id'] == last && (r['user'] as Map)['username'] == _meName);
      return _ok('Run deleted');
    }
    if (match('GET', '/runs/:id/gpx')) {
      final run = _runs.firstWhere((r) => r['id'] == seg[1], orElse: () => throw _MockError(404, 'Corsa non trovata'));
      return _gpx('${run['routeName'] ?? 'Corsa RepBirds'}', run['track'] as List);
    }
    if (match('GET', '/runs/:id')) {
      return _runs.firstWhere((r) => r['id'] == last, orElse: () => throw _MockError(404, 'Corsa non trovata'));
    }
    return _unhandled;
  }

  String _gpx(String name, List<dynamic> points) => [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<gpx version="1.1" creator="RepBirds" xmlns="http://www.topografix.com/GPX/1/1">',
        '  <trk><name>$name</name><trkseg>',
        for (final p in points) '    <trkpt lat="${(p as List)[0]}" lon="${p[1]}"></trkpt>',
        '  </trkseg></trk>',
        '</gpx>',
      ].join('\n');
}
