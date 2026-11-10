import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/chat/chat_crypto.dart';

void main() {
  test('un messaggio si legge su tutti i dispositivi a cui è destinato', () async {
    final (alice, aliceSeed) = await ChatCrypto.generate();
    final (bob, _) = await ChatCrypto.generate();
    final (eve, _) = await ChatCrypto.generate();

    final body = await alice.encrypt(
      conversationId: 'c1',
      myDeviceId: 'da',
      text: 'Ci vediamo in palestra alle 18 💪',
      devices: {'da': alice.publicKey, 'db': bob.publicKey},
    );
    final keys = {for (final k in body['keys'] as List) k['deviceId']: k['wrappedKey'] as String};
    expect(keys.keys, unorderedEquals(['da', 'db']));
    expect(body['ciphertext'], isNot(contains('palestra')));

    Future<String?> read(ChatCrypto who, String deviceId, {String conversationId = 'c1', String? wrapped}) => who.decrypt(
          conversationId: conversationId,
          myDeviceId: deviceId,
          senderDeviceId: 'da',
          senderPublicKey: alice.publicKey,
          ciphertext: body['ciphertext'] as String,
          nonce: body['nonce'] as String,
          wrappedKey: wrapped ?? keys[deviceId]!,
        );

    expect(await read(bob, 'db'), 'Ci vediamo in palestra alle 18 💪');
    // il mittente rilegge i suoi messaggi, anche dopo aver ricreato la chiave dal seme salvato
    expect(await read(await ChatCrypto.fromSeed(aliceSeed), 'da'), 'Ci vediamo in palestra alle 18 💪');
    // chi non era tra i destinatari non legge, neanche con la chiave avvolta di un altro
    expect(await read(eve, 'db'), isNull);
    // spostato in un'altra conversazione non si apre
    expect(await read(bob, 'db', conversationId: 'c2'), isNull);
  });

  test('il codice di sicurezza non dipende dall\'ordine e cambia con le chiavi', () async {
    final (a, _) = await ChatCrypto.generate();
    final (b, _) = await ChatCrypto.generate();
    final (c, _) = await ChatCrypto.generate();
    final code = ChatCrypto.securityCode([a.publicKey, b.publicKey]);
    expect(code, matches(RegExp(r'^\d{5}( \d{5}){5}$')));
    expect(ChatCrypto.securityCode([b.publicKey, a.publicKey]), code);
    expect(ChatCrypto.securityCode([a.publicKey, b.publicKey, c.publicKey]), isNot(code));
  });
}
