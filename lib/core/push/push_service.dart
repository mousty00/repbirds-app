import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chat_repository.dart';
import '../../data/notification_repository.dart';
import '../../data/providers.dart';
import '../../features/auth/session.dart';
import '../../models/notification.dart';
import '../config/env.dart';
import '../l10n/l10n.dart';
import '../router/app_router.dart';

/// Per mostrare le push arrivate con l'app aperta (il sistema le mostra solo in background).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Push native, senza plugin: su iOS il token APNs (l'API scrive direttamente ad
/// Apple, niente Firebase), su Android il token FCM (`MainActivity.kt`, attivo solo
/// se c'è `android/app/google-services.json`).
///
/// Dopo il login chiede il permesso e registra il token su `POST /devices`; al
/// logout lo cancella. Con l'app aperta una push ricarica le notifiche e mostra un
/// avviso; il tap su una push apre la schermata giusta. In modalità mock, sul web o
/// senza configurazione non fa nulla.
class PushService {
  PushService(this._ref);

  static const _channel = MethodChannel('repbirds/push');

  final Ref _ref;
  String? _token;

  static bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  static String get _platform => defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';

  bool get _active => _supported && !Env.useMock;

  /// Da chiamare una volta all'avvio: riceve gli eventi dal codice nativo.
  void init() {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      switch (call.method) {
        case 'onToken':
          if (args is String) await _register(args);
        case 'onMessage':
          if (args is Map) _onForeground(args);
        case 'onOpened':
          if (args is Map) _open(args);
      }
    });
  }

  /// Dopo il login (e a ogni avvio con sessione valida).
  Future<void> onLogin() async {
    if (!_active) return;
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission') ?? false;
      if (!granted) return;
      final token = await _channel.invokeMethod<String>('getToken');
      if (token != null) await _register(token);
      final initial = await _channel.invokeMethod<Map<dynamic, dynamic>>('getInitialMessage');
      if (initial != null) _open(initial);
    } catch (e) {
      debugPrint('Registrazione push non riuscita: $e');
    }
  }

  /// Prima del logout, finché la sessione è ancora valida.
  Future<void> onLogout() async {
    final token = _token;
    _token = null;
    if (!_active || token == null) return;
    try {
      await _ref.read(notificationRepositoryProvider).unregisterDevice(token);
    } catch (_) {
      // Il backend scarta comunque i token che APNs/FCM rifiutano.
    }
  }

  Future<void> _register(String token) async {
    if (_ref.read(sessionProvider).value == null) return;
    _token = token;
    await _ref.read(notificationRepositoryProvider).registerDevice(token, _platform);
  }

  /// `{title, body, data: {type, referenceId, notificationId}}` dal codice nativo.
  void _onForeground(Map<dynamic, dynamic> message) {
    refreshNotifications(_ref.invalidate);
    refreshChats(_ref.invalidate, _data(message)['conversationId']);
    final text = [message['title'], message['body']].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    if (text.isEmpty) return;
    final route = _routeOf(message);
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        action: route == null
            ? null
            : SnackBarAction(label: tr('Apri'), onPressed: () => _ref.read(routerProvider).push(route)),
      ));
  }

  void _open(Map<dynamic, dynamic> message) {
    refreshNotifications(_ref.invalidate);
    refreshChats(_ref.invalidate, _data(message)['conversationId']);
    final id = _data(message)['notificationId'];
    if (id != null) {
      _ref.read(notificationRepositoryProvider).markRead(id).catchError((_) {});
    }
    final route = _routeOf(message);
    if (route != null) _ref.read(routerProvider).push(route);
  }

  static Map<String, String> _data(Map<dynamic, dynamic> message) {
    final data = message['data'];
    if (data is! Map) return const {};
    return {for (final e in data.entries) '${e.key}': '${e.value}'};
  }

  static String? _routeOf(Map<dynamic, dynamic> message) {
    final data = _data(message);
    if (data['type'] == 'CHAT_MESSAGE' && data['conversationId'] != null) return '/chats/${data['conversationId']}';
    return AppNotification.routeFor(NotificationKind.parse(data['type']), data['referenceId']);
  }
}

final pushServiceProvider = Provider<PushService>(PushService.new);
