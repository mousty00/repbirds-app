part of 'mock_backend.dart';

/// Chat in modalità mock, con le forme JSON di `/chat` di repbirds-api. La cifratura
/// la fa l'app come col server vero: qui si salvano solo testo cifrato e chiavi.
extension _MockChat on MockBackend {
  void _seedChat() {
    final gymChat = {
      'id': 'chat-gym1',
      'type': 'GYM',
      'name': _gym['name'],
      'gymId': _gym['id'],
      'members': [_me],
      'mutedBy': <String>{},
      'readAt': <String, DateTime>{},
    };
    _chats.add(gymChat);
    _chatMessages.add({
      'id': _id('cm'),
      'conversationId': gymChat['id'],
      'sender': _gymUser,
      'body': 'Da lunedì la sala pesi apre alle 6:30. Buon allenamento!',
      'createdAt': _now.subtract(const Duration(hours: 5)),
    });
  }

  Map<String, dynamic> _chatById(String id) => _chats.firstWhere(
        (c) => c['id'] == id && (c['members'] as List).any((u) => u['username'] == _meName),
        orElse: () => throw _MockError(404, 'Chat non trovata'),
      );

  Map<String, dynamic> _chatView(Map<String, dynamic> c) {
    final msgs = _chatMessages.where((m) => m['conversationId'] == c['id']).toList();
    final readAt = (c['readAt'] as Map<String, DateTime>)[_meName];
    final members = (c['members'] as List).cast<Map<String, dynamic>>();
    final gym = c['type'] == 'GYM';
    return {
      'id': c['id'],
      'type': c['type'],
      'name': c['type'] == 'DIRECT'
          ? members.firstWhere((u) => u['username'] != _meName, orElse: () => _me)['username']
          : c['name'],
      'encrypted': !gym,
      'gymId': c['gymId'],
      'members': [
        for (final u in members)
          {'user': _simple(u), 'role': u['username'] == (c['admin'] ?? '') ? 'ADMIN' : 'MEMBER'},
      ],
      'lastMessageAt': msgs.isEmpty ? null : MockBackend._iso(msgs.last['createdAt'] as DateTime),
      'unreadCount': msgs
          .where((m) => (m['sender'] as Map)['username'] != _meName)
          .where((m) => readAt == null || (m['createdAt'] as DateTime).isAfter(readAt))
          .length,
      'muted': (c['mutedBy'] as Set<String>).contains(_meName),
      'admin': c['admin'] == _meName,
      'canWrite': !gym,
    };
  }

  Map<String, dynamic> _newChat(String type, String? name, List<Map<String, dynamic>> members) {
    final c = {
      'id': _id('chat'),
      'type': type,
      'name': name,
      'members': members,
      'admin': type == 'GROUP' ? _meName : null,
      'mutedBy': <String>{},
      'readAt': <String, DateTime>{},
    };
    _chats.add(c);
    return c;
  }

  Object? _chatRoutes(bool Function(String, String) match, List<String> seg, Map<String, dynamic> q, Map<String, dynamic> body) {
    // Canale della palestra, lato palestra
    if (match('GET', '/gym/channel') || match('POST', '/gym/channel')) {
      if (!_asGymAccount) throw _MockError(403, 'Access Denied');
      final c = _chats.firstWhere((c) => c['type'] == 'GYM');
      if (match('POST', '/gym/channel')) {
        final text = '${body['body'] ?? ''}'.trim();
        if (text.isEmpty) throw _MockError(400, 'Scrivi qualcosa');
        _chatMessages.add({'id': _id('cm'), 'conversationId': c['id'], 'sender': _gymUser, 'body': text, 'createdAt': DateTime.now()});
      }
      return [
        for (final m in _chatMessages.reversed.where((m) => m['conversationId'] == c['id'])) _messageView(m, null),
      ];
    }

    if (seg.isEmpty || seg.first != 'chat') return _unhandled;

    if (match('POST', '/chat/devices')) {
      final key = '${body['publicKey']}';
      final existing = _chatDevices.where((d) => d['publicKey'] == key && d['username'] == _meName);
      if (existing.isNotEmpty) return existing.first;
      final d = {'id': _id('dev'), 'userId': _me['id'], 'username': _meName, 'publicKey': key, 'name': body['name'], 'createdAt': MockBackend._iso(DateTime.now())};
      _chatDevices.add(d);
      return d;
    }
    if (match('GET', '/chat/devices')) return _chatDevices.where((d) => d['username'] == _meName).toList();
    if (match('GET', '/chat/conversations')) {
      final mine = _chats.where((c) => (c['members'] as List).any((u) => u['username'] == _meName)).map(_chatView).toList()
        ..sort((a, b) => '${b['lastMessageAt'] ?? ''}'.compareTo('${a['lastMessageAt'] ?? ''}'));
      return mine;
    }
    if (match('GET', '/chat/unread-count')) {
      return {
        'count': _chats
            .where((c) => (c['members'] as List).any((u) => u['username'] == _meName))
            .fold<int>(0, (n, c) => n + (_chatView(c)['unreadCount'] as int)),
      };
    }
    if (match('POST', '/chat/conversations/direct')) {
      final other = '${body['username']}';
      if (!_isFriend(other)) throw _MockError(403, 'Puoi scrivere solo agli amici');
      final existing = _chats.where((c) =>
          c['type'] == 'DIRECT' && (c['members'] as List).map((u) => u['username']).toSet().containsAll([_meName, other]));
      return _chatView(existing.isNotEmpty ? existing.first : _newChat('DIRECT', null, [_me, _userBy(other)]));
    }
    if (match('POST', '/chat/conversations/group')) {
      final names = [for (final u in (body['usernames'] as List? ?? const [])) '$u'];
      if (names.any((n) => !_isFriend(n))) throw _MockError(403, 'Puoi aggiungere solo amici');
      return _chatView(_newChat('GROUP', '${body['name']}', [_me, for (final n in names) _userBy(n)]));
    }
    if (match('GET', '/chat/conversations/:id')) return _chatView(_chatById(seg[2]));
    if (match('PUT', '/chat/conversations/:id')) {
      final c = _chatById(seg[2]);
      c['name'] = body['name'];
      return _chatView(c);
    }
    if (match('POST', '/chat/conversations/:id/members')) {
      final c = _chatById(seg[2]);
      (c['members'] as List).add(_userBy('${body['username']}'));
      return _chatView(c);
    }
    if (match('DELETE', '/chat/conversations/:id/members/:user')) {
      final c = _chatById(seg[2]);
      (c['members'] as List).removeWhere((u) => u['id'] == seg[4]);
      return _ok('Removed');
    }
    if (match('PUT', '/chat/conversations/:id/mute')) {
      final c = _chatById(seg[2]);
      final muted = c['mutedBy'] as Set<String>;
      body['muted'] == true ? muted.add(_meName) : muted.remove(_meName);
      return _chatView(c);
    }
    if (match('POST', '/chat/conversations/:id/read')) {
      (_chatById(seg[2])['readAt'] as Map<String, DateTime>)[_meName] = DateTime.now();
      return _ok('Read');
    }
    if (match('GET', '/chat/conversations/:id/devices')) {
      final c = _chatById(seg[2]);
      final names = (c['members'] as List).map((u) => u['username']).toSet();
      return _chatDevices.where((d) => names.contains(d['username'])).toList();
    }
    if (match('GET', '/chat/conversations/:id/messages')) {
      final c = _chatById(seg[2]);
      final before = q['before'] == null ? null : DateTime.parse('${q['before']}');
      return [
        for (final m in _chatMessages.reversed)
          if (m['conversationId'] == c['id'] && (before == null || (m['createdAt'] as DateTime).isBefore(before)))
            _messageView(m, q['deviceId'] as String?),
      ];
    }
    if (match('POST', '/chat/conversations/:id/messages')) {
      final c = _chatById(seg[2]);
      if (c['type'] == 'GYM') throw _MockError(403, 'Solo la palestra può scrivere qui');
      final m = {
        'id': _id('cm'),
        'conversationId': c['id'],
        'sender': _me,
        'senderDeviceId': body['deviceId'],
        'ciphertext': body['ciphertext'],
        'nonce': body['nonce'],
        'keys': {for (final k in (body['keys'] as List? ?? const [])) '${k['deviceId']}': '${k['wrappedKey']}'},
        'createdAt': DateTime.now(),
      };
      _chatMessages.add(m);
      return _messageView(m, '${body['deviceId']}');
    }
    return _unhandled;
  }

  Map<String, dynamic> _messageView(Map<String, dynamic> m, String? deviceId) {
    final senderDevice = _chatDevices.where((d) => d['id'] == m['senderDeviceId']);
    return {
      'id': m['id'],
      'conversationId': m['conversationId'],
      'sender': _simple(m['sender'] as Map<String, dynamic>),
      'senderDeviceId': m['senderDeviceId'],
      'senderPublicKey': senderDevice.isEmpty ? null : senderDevice.first['publicKey'],
      'ciphertext': m['ciphertext'],
      'nonce': m['nonce'],
      'wrappedKey': deviceId == null ? null : (m['keys'] as Map?)?[deviceId],
      'body': m['body'],
      'createdAt': MockBackend._iso(m['createdAt'] as DateTime),
    };
  }
}
