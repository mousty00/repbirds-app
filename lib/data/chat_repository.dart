import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/chat/chat_crypto.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../features/auth/session.dart';
import '../models/chat.dart';
import '../models/json.dart';
import '../models/user.dart';
import 'providers.dart';

/// Dove stanno la chiave privata della chat e l'id del dispositivo: il portachiavi
/// del telefono (Keychain / Keystore). Nei test una mappa in memoria.
abstract class ChatKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureChatKeyStore implements ChatKeyStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

class MemoryChatKeyStore implements ChatKeyStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// Endpoint `/chat` e `/gym/channel`. Cifra e decifra sul telefono: al server arriva
/// solo testo cifrato (tranne il canale della palestra, che è un avviso a tutti).
class ChatRepository {
  ChatRepository(this._api, this._store, this._userId);

  final ApiClient _api;
  final ChatKeyStore _store;
  final String _userId;

  ChatCrypto? _crypto;
  String? _deviceId;
  Future<void>? _ready;

  /// Testi già decifrati, per non rifare i conti a ogni ricarica.
  final _plain = <String, String?>{};

  String get _seedKey => 'repbirds.chat.seed.$_userId';
  String get _deviceKey => 'repbirds.chat.device.$_userId';

  /// Chiave del dispositivo (creata la prima volta) registrata sul server.
  Future<void> ensureDevice() => _ready ??= _setUp().catchError((Object e) {
        _ready = null;
        throw e;
      });

  Future<void> _setUp() async {
    final seed = await _store.read(_seedKey);
    if (seed != null) {
      _crypto = await ChatCrypto.fromSeed(base64.decode(seed));
    } else {
      final (crypto, newSeed) = await ChatCrypto.generate();
      await _store.write(_seedKey, base64.encode(newSeed));
      _crypto = crypto;
    }
    // registrare la stessa chiave di nuovo la rinfresca soltanto: ogni avvio va bene
    final res = await _api.post<Json>('/chat/devices', data: {'publicKey': _crypto!.publicKey, 'name': _deviceName()});
    _deviceId = '${res['id']}';
    await _store.write(_deviceKey, _deviceId!);
  }

  static String _deviceName() {
    if (kIsWeb) return 'Web';
    try {
      return Platform.isIOS ? 'iPhone' : Platform.isAndroid ? 'Android' : Platform.operatingSystem;
    } catch (_) {
      return 'App';
    }
  }

  // Conversazioni

  Future<List<Conversation>> conversations() async =>
      parseList(await _api.get<List<dynamic>>('/chat/conversations'), Conversation.fromJson);

  Future<Conversation> conversation(String id) async => Conversation.fromJson(await _api.get<Json>('/chat/conversations/$id'));

  Future<int> unreadCount() async => parseInt((await _api.get<Json>('/chat/unread-count'))['count']);

  Future<Conversation> openDirect(String username) async =>
      Conversation.fromJson(await _api.post<Json>('/chat/conversations/direct', data: {'username': username}));

  Future<Conversation> createGroup(String name, List<String> usernames) async => Conversation.fromJson(
      await _api.post<Json>('/chat/conversations/group', data: {'name': name, 'usernames': usernames}));

  Future<Conversation> rename(String id, String name) async =>
      Conversation.fromJson(await _api.put<Json>('/chat/conversations/$id', data: {'name': name}));

  Future<Conversation> addMember(String id, String username) async =>
      Conversation.fromJson(await _api.post<Json>('/chat/conversations/$id/members', data: {'username': username}));

  /// Toglie qualcuno dal gruppo; con il mio id esco io.
  Future<void> removeMember(String id, String userId) => _api.delete<dynamic>('/chat/conversations/$id/members/$userId');

  Future<Conversation> mute(String id, bool muted) async =>
      Conversation.fromJson(await _api.put<Json>('/chat/conversations/$id/mute', data: {'muted': muted}));

  Future<void> markRead(String id) => _api.post<dynamic>('/chat/conversations/$id/read');

  Future<List<ChatDevice>> devices(String id) async =>
      parseList(await _api.get<List<dynamic>>('/chat/conversations/$id/devices'), ChatDevice.fromJson);

  /// Codice di sicurezza da confrontare di persona (vedi [ChatCrypto.securityCode]).
  Future<String> securityCode(String id) async => ChatCrypto.securityCode((await devices(id)).map((d) => d.publicKey));

  // Messaggi

  /// I più recenti per primi, più vecchi di [before].
  Future<List<ChatMessage>> messages(Conversation c, {DateTime? before}) async {
    if (c.encrypted) await ensureDevice();
    final raw = await _api.get<List<dynamic>>('/chat/conversations/${c.id}/messages', query: {
      if (c.encrypted) 'deviceId': _deviceId,
      if (before != null) 'before': before.toUtc().toIso8601String(),
      'limit': 50,
    });
    final out = <ChatMessage>[];
    for (final j in raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m))) {
      out.add(ChatMessage(
        id: '${j['id']}',
        conversationId: c.id,
        sender: SimpleUser.fromJson(Map<String, dynamic>.from(j['sender'] as Map)),
        text: c.encrypted ? await _decrypt(c.id, j) : j['body'] as String?,
        createdAt: parseInstant(j['createdAt']),
      ));
    }
    return out;
  }

  Future<String?> _decrypt(String conversationId, Json j) async {
    final id = '${j['id']}';
    if (_plain.containsKey(id)) return _plain[id];
    final wrapped = j['wrappedKey'] as String?;
    final senderDevice = j['senderDeviceId'] as String?;
    final senderKey = j['senderPublicKey'] as String?;
    final cipher = j['ciphertext'] as String?;
    final nonce = j['nonce'] as String?;
    String? text;
    if (wrapped != null && senderDevice != null && senderKey != null && cipher != null && nonce != null) {
      text = await _crypto!.decrypt(
        conversationId: conversationId,
        myDeviceId: _deviceId!,
        senderDeviceId: senderDevice,
        senderPublicKey: senderKey,
        ciphertext: cipher,
        nonce: nonce,
        wrappedKey: wrapped,
      );
    }
    return _plain[id] = text;
  }

  /// Cifra per i dispositivi di tutti i membri e manda. Se nel frattempo qualcuno ha
  /// aggiunto o tolto un dispositivo (409) li richiede e ritenta una volta.
  Future<void> send(Conversation c, String text) async {
    if (!c.encrypted) {
      await _api.post<Json>('/gym/channel', data: {'body': text});
      return;
    }
    await ensureDevice();
    for (var attempt = 0;; attempt++) {
      final devices = {for (final d in await this.devices(c.id)) d.id: d.publicKey};
      final body = await _crypto!.encrypt(conversationId: c.id, myDeviceId: _deviceId!, text: text, devices: devices);
      try {
        final res = await _api.post<Json>('/chat/conversations/${c.id}/messages', data: body);
        _plain['${res['id']}'] = text;
        return;
      } on ApiException catch (e) {
        if (e.statusCode != 409 || attempt > 0) rethrow;
      }
    }
  }

  // Canale della palestra (lato palestra)

  Future<List<ChatMessage>> gymChannel() async {
    final raw = await _api.get<List<dynamic>>('/gym/channel');
    return [
      for (final j in raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)))
        ChatMessage(
          id: '${j['id']}',
          conversationId: '${j['conversationId']}',
          sender: SimpleUser.fromJson(Map<String, dynamic>.from(j['sender'] as Map)),
          text: j['body'] as String?,
          createdAt: parseInstant(j['createdAt']),
        ),
    ];
  }

  Future<void> announce(String text) => _api.post<dynamic>('/gym/channel', data: {'body': text});
}

final chatKeyStoreProvider = Provider<ChatKeyStore>((ref) => SecureChatKeyStore());

final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository(
      ref.watch(apiClientProvider),
      ref.watch(chatKeyStoreProvider),
      ref.watch(sessionProvider).value?.id ?? 'anon',
    ));

final conversationsProvider = FutureProvider<List<Conversation>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(chatRepositoryProvider).conversations();
});

final conversationProvider = FutureProvider.autoDispose.family<Conversation, String>(
  (ref, id) => ref.watch(chatRepositoryProvider).conversation(id),
);

final chatMessagesProvider = FutureProvider.autoDispose.family<List<ChatMessage>, String>((ref, id) async {
  final c = await ref.watch(conversationProvider(id).future);
  return ref.watch(chatRepositoryProvider).messages(c);
});

/// Messaggi non letti in tutte le chat, per il bollino. 0 se il server non risponde.
final chatUnreadProvider = FutureProvider<int>((ref) async {
  ref.watch(userKeyProvider);
  try {
    return await ref.watch(chatRepositoryProvider).unreadCount();
  } catch (_) {
    return 0;
  }
});

final gymChannelProvider = FutureProvider.autoDispose<List<ChatMessage>>(
  (ref) => ref.watch(chatRepositoryProvider).gymChannel(),
);

/// Dopo un messaggio nuovo (stream, push) o letto.
void refreshChats(void Function(ProviderOrFamily provider) invalidate, [String? conversationId]) {
  invalidate(conversationsProvider);
  invalidate(chatUnreadProvider);
  if (conversationId != null) invalidate(chatMessagesProvider(conversationId));
}
