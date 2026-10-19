import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env.dart';
import '../core/network/api_client.dart';
import '../models/json.dart';
import 'providers.dart';

/// Un evento Server-Sent Events: nome (`event:`) e dati (`data:`).
typedef SseEvent = ({String event, String data});

/// Trasforma i byte di `text/event-stream` in eventi. I commenti (`: ping`)
/// tengono viva la connessione e vengono scartati.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  var event = 'message';
  final data = <String>[];
  await for (final line in bytes.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield (event: event, data: data.join('\n'));
      event = 'message';
      data.clear();
    } else if (line.startsWith(':')) {
      continue;
    } else {
      final i = line.indexOf(':');
      final field = i < 0 ? line : line.substring(0, i);
      var value = i < 0 ? '' : line.substring(i + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      if (field == 'event') event = value;
      if (field == 'data') data.add(value);
    }
  }
}

/// Notifiche in tempo reale da `GET /notifications/stream`, finché l'app è aperta
/// e c'è una sessione: il contatore sulla campanella segue il server e una nuova
/// notifica ricarica la lista. Quando la connessione cade riprova con attese
/// crescenti (fino a un minuto). Le push restano per quando l'app è chiusa.
class NotificationStream {
  NotificationStream(this._ref);

  final Ref _ref;
  CancelToken? _cancel;
  Timer? _retry;
  var _attempt = 0;
  var _running = false;

  /// Senza eventi né ping (il server ne manda uno ogni 25 s) la connessione è morta.
  static const _idle = Duration(seconds: 70);

  bool get _active => !Env.useMock;

  /// Dopo il login e quando l'app torna in primo piano.
  void start() {
    if (!_active || _running) return;
    _running = true;
    _attempt = 0;
    _connect();
  }

  /// Al logout e quando l'app va in background.
  void stop() {
    _running = false;
    _retry?.cancel();
    _retry = null;
    _cancel?.cancel();
    _cancel = null;
  }

  Future<void> _connect() async {
    final cancel = _cancel = CancelToken();
    try {
      final res = await _ref.read(apiClientProvider).dio.get<ResponseBody>(
            '/notifications/stream',
            cancelToken: cancel,
            options: Options(
              responseType: ResponseType.stream,
              receiveTimeout: _idle,
              headers: {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'},
            ),
          );
      await for (final e in parseSse(res.data!.stream)) {
        _attempt = 0;
        _onEvent(e);
      }
    } catch (e) {
      if (!cancel.isCancelled) debugPrint('Stream notifiche interrotto: $e');
    }
    if (!_running || cancel.isCancelled) return;
    // il server chiude dopo 30 minuti, o è caduta la rete: si riconnette
    final wait = Duration(seconds: [1 << _attempt, 60].reduce((a, b) => a < b ? a : b));
    _attempt = (_attempt + 1).clamp(0, 6);
    _retry = Timer(wait, _connect);
  }

  void _onEvent(SseEvent e) {
    final Json json;
    try {
      json = Map<String, dynamic>.from(jsonDecode(e.data) as Map);
    } catch (_) {
      return;
    }
    final unread = _ref.read(unreadActivityProvider.notifier);
    switch (e.event) {
      case 'unread-count':
        unread.set(parseInt(json['count']));
      case 'notification':
        unread.set(parseInt(json['unreadCount']));
        // la nuova notifica, e la richiesta o l'invito a cui punta
        _ref.invalidate(activityProvider);
        _ref.invalidate(friendRequestsProvider);
        _ref.invalidate(groupInvitesProvider);
    }
  }
}

final notificationStreamProvider = Provider<NotificationStream>((ref) {
  final stream = NotificationStream(ref);
  ref.onDispose(stream.stop);
  return stream;
});
