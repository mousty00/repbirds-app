import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/gym.dart';

/// Il codice della tessera: `RBG1.{cardId}.{finestra}.{firma}`, cambia ogni
/// [MembershipCard.periodSeconds]. Stessa formula di `GymCardService` di repbirds-api
/// e del servizio NFC Android (`GymCardApduService.kt`): la firma è HMAC-SHA256 di
/// "{cardId}.{finestra}" con il segreto della tessera, in base64url senza padding, primi 16 caratteri.
/// Si calcola sul telefono, quindi la tessera funziona anche senza rete.
abstract final class CardCode {
  static const prefix = 'RBG1';

  static int window(MembershipCard card, DateTime now) => now.millisecondsSinceEpoch ~/ 1000 ~/ card.periodSeconds;

  static String at(MembershipCard card, DateTime now) {
    final w = window(card, now);
    final key = base64Url.decode(base64Url.normalize(card.secret));
    final digest = Hmac(sha256, key).convert(utf8.encode('${card.cardId}.$w')).bytes;
    final sig = base64Url.encode(digest).replaceAll('=', '').substring(0, 16);
    return '$prefix.${card.cardId}.$w.$sig';
  }

  /// Quanto manca al prossimo cambio di codice.
  static Duration untilNext(MembershipCard card, DateTime now) {
    final periodMs = card.periodSeconds * 1000;
    return Duration(milliseconds: periodMs - now.millisecondsSinceEpoch % periodMs);
  }

  /// Sembra un codice di tessera (prima di mandarlo al server).
  static bool looksValid(String code) => code.startsWith('$prefix.') && code.split('.').length == 4;
}
