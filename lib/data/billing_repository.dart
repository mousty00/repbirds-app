import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../models/billing.dart';
import '../models/json.dart';
import 'providers.dart';

/// Pagamenti con Stripe: il piano RepBirds della palestra e gli abbonamenti dei soci.
/// Le pagine di pagamento sono di Stripe e si aprono nel browser.
class BillingRepository {
  BillingRepository(this._api);

  final ApiClient _api;

  // Lato palestra

  Future<GymBilling> billing() async => GymBilling.fromJson(await _api.get<Json>('/gym/billing'));

  Future<String> checkout(String tier) async =>
      '${(await _api.post<Json>('/gym/billing/checkout', data: {'tier': tier}))['url']}';

  Future<String> portal() async => '${(await _api.post<Json>('/gym/billing/portal'))['url']}';

  Future<String> connect() async => '${(await _api.post<Json>('/gym/billing/connect'))['url']}';

  Future<List<GymPayment>> payments() async => parseList(await _api.get<List<dynamic>>('/gym/payments'), GymPayment.fromJson);

  // Lato socio

  Future<List<PublicGym>> search(String query) async =>
      parseList(await _api.get<List<dynamic>>('/gyms', query: {if (query.isNotEmpty) 'q': query}), PublicGym.fromJson);

  Future<PublicGym> gym(String id) async => PublicGym.fromJson(await _api.get<Json>('/gyms/$id'));

  Future<String> payPlan(String gymId, String planId) async =>
      '${(await _api.post<Json>('/gyms/$gymId/plans/$planId/checkout'))['url']}';
}

final billingRepositoryProvider = Provider<BillingRepository>((ref) => BillingRepository(ref.watch(apiClientProvider)));

final gymBillingProvider = FutureProvider.autoDispose<GymBilling>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(billingRepositoryProvider).billing();
});

final gymPaymentsProvider = FutureProvider.autoDispose<List<GymPayment>>((ref) => ref.watch(billingRepositoryProvider).payments());

final gymSearchProvider = FutureProvider.autoDispose.family<List<PublicGym>, String>(
  (ref, q) => ref.watch(billingRepositoryProvider).search(q),
);

final publicGymProvider = FutureProvider.autoDispose.family<PublicGym, String>(
  (ref, id) => ref.watch(billingRepositoryProvider).gym(id),
);
