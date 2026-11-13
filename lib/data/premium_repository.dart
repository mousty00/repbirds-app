import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../models/json.dart';
import '../models/premium.dart';
import '../models/workout.dart';
import 'providers.dart';

/// RepBirds Premium: stato, verifica degli acquisti, statistiche avanzate, export e programmi.
class PremiumRepository {
  PremiumRepository(this._api);

  final ApiClient _api;

  Future<PremiumStatus> status() async => PremiumStatus.fromJson(await _api.get<Json>('/premium'));

  /// Acquisto App Store: l'id della transazione StoreKit.
  Future<PremiumStatus> verifyApple(String transactionId) async =>
      PremiumStatus.fromJson(await _api.post<Json>('/premium/apple', data: {'transactionId': transactionId}));

  /// Acquisto Google Play: il purchase token.
  Future<PremiumStatus> verifyGoogle(String purchaseToken) async =>
      PremiumStatus.fromJson(await _api.post<Json>('/premium/google', data: {'purchaseToken': purchaseToken}));

  Future<AdvancedStats> stats({int weeks = 12}) async =>
      AdvancedStats.fromJson(await _api.get<Json>('/premium/stats', query: {'weeks': weeks}));

  /// Tutti gli allenamenti completati, in CSV.
  Future<String> exportCsv() => _api.get<String>('/premium/export');

  Future<List<Program>> programs() async => parseList(await _api.get<List<dynamic>>('/programs'), Program.fromJson);

  Future<List<Workout>> startProgram(String slug) async =>
      parseList(await _api.post<List<dynamic>>('/programs/$slug/start'), Workout.fromJson);
}

final premiumRepositoryProvider = Provider<PremiumRepository>((ref) => PremiumRepository(ref.watch(apiClientProvider)));

final premiumProvider = FutureProvider<PremiumStatus>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(premiumRepositoryProvider).status();
});

/// true solo quando si sa che l'account ha Premium (in caricamento o errore: false).
final isPremiumProvider = Provider<bool>((ref) => ref.watch(premiumProvider).value?.premium ?? false);

final programsProvider = FutureProvider.autoDispose<List<Program>>((ref) {
  ref.watch(premiumProvider);
  return ref.watch(premiumRepositoryProvider).programs();
});

final advancedStatsProvider = FutureProvider.autoDispose.family<AdvancedStats, int>(
  (ref, weeks) => ref.watch(premiumRepositoryProvider).stats(weeks: weeks),
);
