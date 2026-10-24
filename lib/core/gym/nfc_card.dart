import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/gym.dart';

/// NFC della tessera, solo Android (canale `repbirds/gym_nfc`, vedi MainActivity.kt):
///
/// - tessera: [setCard] passa cardId e segreto al servizio HCE (`GymCardApduService`),
///   che risponde al lettore della palestra con il codice del momento. Funziona a schermo
///   acceso anche con l'app chiusa, senza rete.
/// - lettore (dashboard palestra): [startReading] mette il telefono in modalità lettura e
///   [codes] emette i codici delle tessere avvicinate.
///
/// Su iOS le app non possono emulare una carta NFC senza un permesso speciale di Apple
/// (HCE solo nello Spazio economico europeo, con contratto e entitlement): lì la tessera
/// è il QR, e l'iPhone della reception legge il QR con la fotocamera.
abstract final class NfcCard {
  static const _channel = MethodChannel('repbirds/gym_nfc');
  static final _codes = StreamController<String>.broadcast();
  static bool _listening = false;

  static bool get platformSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// NFC presente e acceso. Sempre false fuori da Android.
  static Future<bool> available() async {
    if (!platformSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// La tessera che il telefono presenta al lettore (una sola: l'ultima aperta).
  static Future<void> setCard(MembershipCard card) async {
    if (!platformSupported) return;
    final json = jsonEncode(card.toJson());
    if (json == _current) return;
    _current = json;
    try {
      await _channel.invokeMethod<void>('setCard', {'card': json});
    } catch (_) {}
  }

  static String? _current;

  /// Dopo il logout o quando l'abbonamento non è più attivo.
  static Future<void> clearCard() async {
    if (!platformSupported) return;
    _current = null;
    try {
      await _channel.invokeMethod<void>('clearCard');
    } catch (_) {}
  }

  static Stream<String> get codes {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onCode' && call.arguments is String) _codes.add(call.arguments as String);
      });
    }
    return _codes.stream;
  }

  static Future<bool> startReading() async {
    if (!platformSupported) return false;
    codes; // registra il gestore prima che arrivi il primo codice
    try {
      return await _channel.invokeMethod<bool>('startReading') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopReading() async {
    if (!platformSupported) return;
    try {
      await _channel.invokeMethod<void>('stopReading');
    } catch (_) {}
  }
}
