import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health/health.dart';

/// Allenamenti e corse finiti vanno in Apple Salute (iPhone) o Health Connect
/// (Android), se l'utente lo attiva dal profilo. Solo scrittura: l'app non legge
/// dati di salute.
class HealthSync extends Notifier<bool> {
  static const _key = 'repbirds.health';
  static const _storage = FlutterSecureStorage();
  static final _health = Health();
  static const _types = [HealthDataType.WORKOUT];
  static const _access = [HealthDataAccess.WRITE];

  /// Letto in main() prima di avviare l'app.
  static bool on = false;

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  static Future<void> load() async {
    try {
      on = await _storage.read(key: _key) == 'on';
    } catch (_) {}
  }

  @override
  bool build() => on;

  /// Attivandolo chiede il permesso; torna false se non c'è (o Health Connect manca).
  Future<bool> set(bool value) async {
    var granted = value;
    if (value) {
      try {
        await _health.configure();
        if (defaultTargetPlatform == TargetPlatform.android &&
            await _health.getHealthConnectSdkStatus() != HealthConnectSdkStatus.sdkAvailable) {
          await _health.installHealthConnect();
          granted = false;
        } else {
          granted = await _health.requestAuthorization(_types, permissions: _access);
        }
      } catch (e) {
        debugPrint('Salute non collegata: $e');
        granted = false;
      }
    }
    state = on = granted;
    try {
      await _storage.write(key: _key, value: granted ? 'on' : 'off');
    } catch (_) {}
    return granted;
  }

  /// Scrive un allenamento finito; non fa niente se l'utente non l'ha attivato.
  static Future<void> writeWorkout({
    required String title,
    required DateTime start,
    required DateTime end,
    bool running = false,
  }) async {
    if (!on || !supported || !end.isAfter(start)) return;
    try {
      await _health.configure();
      await _health.writeWorkoutData(
        activityType: running
            ? HealthWorkoutActivityType.RUNNING
            : (defaultTargetPlatform == TargetPlatform.iOS
                ? HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING
                : HealthWorkoutActivityType.STRENGTH_TRAINING),
        start: start,
        end: end,
        title: title,
        recordingMethod: RecordingMethod.manual,
      );
    } catch (e) {
      debugPrint('Allenamento non scritto in Salute: $e');
    }
  }
}

final healthSyncProvider = NotifierProvider<HealthSync, bool>(HealthSync.new);
