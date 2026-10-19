part of 'mock_backend.dart';

/// Foto del fisico in modalità mock, con le stesse forme JSON di `/body-photos`.
extension _MockBody on MockBackend {
  void _seedBody(Map<String, dynamic> giulia) {
    Map<String, dynamic> photo(Map<String, dynamic> owner, int daysAgo, int img, bool isPublic) => {
          'id': _id('bp'),
          'owner': owner['username'],
          'imageUrl': 'asset:assets/mock/post$img.jpg',
          'isPublic': isPublic,
          'takenAt': MockBackend._iso(_now.subtract(Duration(days: daysAgo, hours: 2))),
          'workoutHistoryId': null,
          'workoutName': 'Push day',
        };
    // stesso mese di oggi quando possibile, così il confronto si vede subito
    final spread = (_now.day - 1).clamp(0, 20);
    _bodyPhotos.addAll([
      photo(_me, spread, 1, false),
      photo(_me, spread ~/ 2, 2, true),
      photo(_me, 0, 3, false),
      photo(giulia, 3, 4, true),
    ]);
  }

  Future<Object?> _body(bool Function(String, String) match, String last, Map<String, dynamic> q, RequestOptions o,
      Map<String, dynamic> body) async {
    Map<String, dynamic> view(Map<String, dynamic> p) => {...p}..remove('owner');
    Map<String, dynamic> mine(String id) => _bodyPhotos.firstWhere((p) => p['id'] == id && p['owner'] == _meName,
        orElse: () => throw _MockError(404, 'Foto non trovata'));

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
      final p = {
        'id': _id('bp'),
        'owner': _meName,
        'imageUrl': '${MockBackend.uploadScheme}$key',
        'isPublic': q['isPublic'] == true || q['isPublic'] == 'true',
        'takenAt': MockBackend._iso(DateTime.now()),
        'workoutHistoryId': history?['id'],
        'workoutName': workout?['name'],
      };
      _bodyPhotos.add(p);
      return {'message': 'Photo saved', 'result': view(p)};
    }
    if (match('PATCH', '/body-photos/:id/visibility')) {
      final p = mine(_idBeforeLast(o))..['isPublic'] = body['isPublic'] == true;
      return view(p);
    }
    if (match('DELETE', '/body-photos/:id')) {
      _bodyPhotos.remove(mine(last));
      return _ok('Photo deleted');
    }
    return _unhandled;
  }

  String _idBeforeLast(RequestOptions o) {
    final seg = Uri.parse(o.path).pathSegments.where((s) => s.isNotEmpty).toList();
    return seg[seg.length - 2];
  }
}
