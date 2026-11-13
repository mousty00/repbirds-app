import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// Cifratura end-to-end della chat (vedi la sezione Chat del README di repbirds-api).
///
/// Ogni dispositivo ha una coppia di chiavi X25519: la privata resta nel portachiavi
/// del telefono, la pubblica va al server. Un messaggio si cifra una volta con una
/// chiave casuale K (AES-256-GCM, l'id della conversazione come dato associato) e K
/// si "avvolge" per ogni dispositivo dei membri con una chiave derivata da
/// X25519(mia privata, sua pubblica) → HKDF-SHA256. Il server vede solo testo cifrato.
class ChatCrypto {
  ChatCrypto(this._keyPair, this.publicKey);

  final SimpleKeyPair _keyPair;

  /// La mia chiave pubblica, base64 (32 byte).
  final String publicKey;

  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const _info = 'repbirds-chat-v1';

  /// Una coppia nuova; [seed] (32 byte) va salvato per ricrearla con [fromSeed].
  static Future<(ChatCrypto, List<int> seed)> generate() async {
    final pair = await _x25519.newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    return (await fromSeed(seed), seed);
  }

  static Future<ChatCrypto> fromSeed(List<int> seed) async {
    final pair = await _x25519.newKeyPairFromSeed(seed);
    final public = await pair.extractPublicKey();
    return ChatCrypto(pair, base64.encode(public.bytes));
  }

  /// Cifra [text] per i dispositivi in [devices] (id → chiave pubblica base64),
  /// i miei compresi. Torna il corpo di `POST /chat/conversations/{id}/messages`.
  Future<Map<String, dynamic>> encrypt({
    required String conversationId,
    required String myDeviceId,
    required String text,
    required Map<String, String> devices,
  }) async {
    final key = await _aes.newSecretKey();
    final keyBytes = await key.extractBytes();
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode({'v': 1, 'text': text})),
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(conversationId),
    );
    final keys = <Map<String, String>>[];
    for (final MapEntry(key: deviceId, value: publicKey) in devices.entries) {
      final kek = await _kek(conversationId, myDeviceId, deviceId, publicKey);
      final wrapNonce = _aes.newNonce();
      final wrapped = await _aes.encrypt(keyBytes, secretKey: kek, nonce: wrapNonce);
      keys.add({'deviceId': deviceId, 'wrappedKey': base64.encode([...wrapNonce, ...wrapped.cipherText, ...wrapped.mac.bytes])});
    }
    return {
      'deviceId': myDeviceId,
      'ciphertext': base64.encode([...box.cipherText, ...box.mac.bytes]),
      'nonce': base64.encode(nonce),
      'keys': keys,
    };
  }

  /// Il testo di un messaggio ricevuto su questo dispositivo ([myDeviceId]), o null
  /// se non si può leggere qui (mandato prima che il dispositivo esistesse, o alterato).
  Future<String?> decrypt({
    required String conversationId,
    required String myDeviceId,
    required String senderDeviceId,
    required String senderPublicKey,
    required String ciphertext,
    required String nonce,
    required String wrappedKey,
  }) async {
    try {
      final kek = await _kek(conversationId, senderDeviceId, myDeviceId, senderPublicKey);
      final wrapped = base64.decode(wrappedKey);
      final keyBytes = await _aes.decrypt(_box(wrapped.sublist(12), wrapped.sublist(0, 12)), secretKey: kek);
      final clear = await _aes.decrypt(
        _box(base64.decode(ciphertext), base64.decode(nonce)),
        secretKey: SecretKey(keyBytes),
        aad: utf8.encode(conversationId),
      );
      final json = jsonDecode(utf8.decode(clear));
      return json is Map ? json['text'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  static SecretBox _box(List<int> cipherAndTag, List<int> nonce) => SecretBox(
        cipherAndTag.sublist(0, cipherAndTag.length - 16),
        nonce: nonce,
        mac: Mac(cipherAndTag.sublist(cipherAndTag.length - 16)),
      );

  /// La chiave che avvolge K tra il dispositivo [from] e il dispositivo [to]: la
  /// stessa da entrambi i lati, perché X25519 dà lo stesso segreto ai due.
  Future<SecretKey> _kek(String conversationId, String from, String to, String otherPublicKey) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: SimplePublicKey(base64.decode(otherPublicKey), type: KeyPairType.x25519),
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(conversationId),
      info: utf8.encode('$_info:$from:$to'),
    );
  }

  /// Codice di sicurezza di una conversazione: uguale su tutti i telefoni dei membri
  /// finché nessuno cambia chiave. Confrontandolo di persona si esclude che il server
  /// abbia infilato una chiave sua. 6 gruppi da 5 cifre.
  static String securityCode(Iterable<String> publicKeys) {
    final sorted = publicKeys.toList()..sort();
    final digest = hash.sha256.convert(utf8.encode(sorted.join('|'))).bytes;
    final groups = <String>[];
    for (var i = 0; i < 6; i++) {
      final chunk = ByteData.sublistView(Uint8List.fromList(digest), i * 4, i * 4 + 4).getUint32(0);
      groups.add((chunk % 100000).toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }
}
