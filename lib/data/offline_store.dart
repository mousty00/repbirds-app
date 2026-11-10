import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Quello che serve per allenarsi senza rete: le mie schede (l'ultima copia arrivata dal
/// server) e le sessioni finite offline, da mandare appena la rete torna. Tutto per
/// utente, sul telefono.
class OfflineStore {
  OfflineStore(this._userId, {OfflineStorage? storage}) : _storage = storage ?? SecureOfflineStorage();

  final String _userId;
  final OfflineStorage _storage;

  String get _workoutsKey => 'repbirds.offline.workouts.$_userId';
  String get _pendingKey => 'repbirds.offline.sessions.$_userId';

  Future<void> saveWorkouts(List<dynamic> raw) => _storage.write(_workoutsKey, jsonEncode(raw));

  Future<List<dynamic>?> workouts() async {
    final s = await _storage.read(_workoutsKey);
    if (s == null) return null;
    try {
      final v = jsonDecode(s);
      return v is List ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Le sessioni da mandare, nell'ordine in cui sono finite.
  Future<List<Map<String, dynamic>>> pendingSessions() async {
    final s = await _storage.read(_pendingKey);
    if (s == null) return [];
    try {
      return [for (final m in (jsonDecode(s) as List).whereType<Map>()) Map<String, dynamic>.from(m)];
    } catch (_) {
      return [];
    }
  }

  Future<void> addPendingSession(Map<String, dynamic> body) async =>
      _storage.write(_pendingKey, jsonEncode([...await pendingSessions(), body]));

  Future<void> setPendingSessions(List<Map<String, dynamic>> list) => _storage.write(_pendingKey, jsonEncode(list));
}

abstract class OfflineStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureOfflineStorage implements OfflineStorage {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('Copia offline non letta: $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('Copia offline non salvata: $e');
    }
  }
}

class MemoryOfflineStorage implements OfflineStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
