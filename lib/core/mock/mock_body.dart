part of 'mock_backend.dart';

/// Foto del fisico in modalità mock, con le stesse forme JSON di `/body-photos`.
extension _MockBody on MockBackend {
  void _seedBody(Map<String, dynamic> giulia) {
    Map<String, dynamic> photo(Map<String, dynamic> owner, int daysAgo, int img, bool isPublic, {int hours = 2, bool story = false}) {
      final at = _now.subtract(Duration(days: daysAgo, hours: hours));
      return {
        'id': _id('bp'),
        'owner': owner['username'],
        'imageUrl': 'asset:assets/mock/post$img.jpg',
        'isPublic': isPublic || story,
        'takenAt': MockBackend._iso(at),
        'workoutHistoryId': null,
        'workoutName': story ? null : 'Push day',
        'isStory': story,
        'storyUntil': story ? MockBackend._iso(at.add(_storyDuration)) : null,
      };
    }
    // stesso mese di oggi quando possibile, così il confronto si vede subito
    final spread = (_now.day - 1).clamp(0, 20);
    _bodyPhotos.addAll([
      photo(_me, spread, 1, false),
      photo(_me, spread ~/ 2, 2, true),
      photo(_me, 0, 3, false),
      photo(giulia, 3, 4, true),
      // storie di oggi: Giulia e Marco
      photo(giulia, 0, 2, true, hours: 1, story: true),
      photo(giulia, 0, 4, true, hours: 0, story: true),
      photo(_userBy('marco_lifts'), 0, 3, true, hours: 5, story: true),
    ]);
  }

  Future<Object?> _body(bool Function(String, String) match, String last, Map<String, dynamic> q, RequestOptions o,
      Map<String, dynamic> body) async {
    Map<String, dynamic> view(Map<String, dynamic> p) => {...p}..remove('owner');
    Map<String, dynamic> mine(String id) => _bodyPhotos.firstWhere((p) => p['id'] == id && p['owner'] == _meName,
        orElse: () => throw _MockError(404, 'Foto non trovata'));

    if (match('GET', '/body-photos/stories')) {
      final since = DateTime.now().subtract(_storyDuration);
      final live = _bodyPhotos.where((p) =>
          p['isStory'] == true &&
          p['isPublic'] == true &&
          DateTime.parse('${p['takenAt']}').isAfter(since) &&
          (p['owner'] == _meName || _isFriend('${p['owner']}')));
      final byUser = <String, List<Map<String, dynamic>>>{};
      for (final p in live) {
        byUser.putIfAbsent('${p['owner']}', () => []).add(p);
      }
      for (final list in byUser.values) {
        list.sort((a, b) => '${a['takenAt']}'.compareTo('${b['takenAt']}'));
      }
      final users = byUser.keys.toList()
        ..sort((a, b) => a == _meName
            ? -1
            : b == _meName
                ? 1
                : '${byUser[b]!.last['takenAt']}'.compareTo('${byUser[a]!.last['takenAt']}'));
      return [
        for (final u in users) {'user': _simple(_userBy(u)), 'photos': byUser[u]!.map(view).toList()},
      ];
    }
    if (match('GET', '/body-photos/user/:u')) {
      final owner = Uri.decodeComponent(last);
      final from = DateTime.parse('${q['from']}');
      final to = DateTime.parse('${q['to']}');
      return _bodyPhotos.where((p) {
        final at = DateTime.parse('${p['takenAt']}');
        return p['owner'] == owner && (owner == _meName || p['isPublic'] == true) && !at.isBefore(from) && at.isBefore(to);
      }).map(view).toList();
    }
    if (match('POST', '/body-photos')) {
      final bytes = await _fileFrom(o.data, 'imageFile');
      if (bytes == null) throw _MockError(400, 'File is empty');
      final key = _id('img');
      MockBackend.uploads[key] = bytes;
      final historyId = q['workoutHistoryId']?.toString();
      final history = _history.where((h) => h['id'] == historyId).firstOrNull;
      final workout = history == null ? null : _workouts.where((w) => w['id'] == history['workoutId']).firstOrNull;
      final story = q['asStory'] == true || q['asStory'] == 'true';
      final now = DateTime.now();
      final p = {
        'id': _id('bp'),
        'owner': _meName,
        'imageUrl': '${MockBackend.uploadScheme}$key',
        'isPublic': story || q['isPublic'] == true || q['isPublic'] == 'true',
        'takenAt': MockBackend._iso(now),
        'workoutHistoryId': history?['id'],
        'workoutName': workout?['name'],
        'isStory': story,
        'storyUntil': story ? MockBackend._iso(now.add(_storyDuration)) : null,
      };
      _bodyPhotos.add(p);
      return {'message': 'Photo saved', 'result': view(p)};
    }
    if (match('PATCH', '/body-photos/:id/visibility')) {
      final p = mine(_idBeforeLast(o))..['isPublic'] = body['isPublic'] == true;
      if (p['isPublic'] != true) {
        p
          ..['isStory'] = false
          ..['storyUntil'] = null;
      }
      return view(p);
    }
    if (match('DELETE', '/body-photos/:id')) {
      _bodyPhotos.remove(mine(last));
      return _ok('Photo deleted');
    }
    return _unhandled;
  }

  static const _storyDuration = Duration(hours: 24);

  String _idBeforeLast(RequestOptions o) {
    final seg = Uri.parse(o.path).pathSegments.where((s) => s.isNotEmpty).toList();
    return seg[seg.length - 2];
  }
}
