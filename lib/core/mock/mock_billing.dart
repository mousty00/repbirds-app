part of 'mock_backend.dart';

/// Pagamenti in modalità mock (`/gym/billing`, `/gyms` di repbirds-api). Le pagine di
/// Stripe non esistono qui: gli indirizzi puntano al sito di RepBirds.
extension _MockBilling on MockBackend {
  static const _demoUrl = 'https://repbirds.com/pagamento?esito=demo';

  Object? _billingRoutes(bool Function(String, String) match, List<String> seg, Map<String, dynamic> q) {
    Map<String, dynamic> publicGym() => {
          ..._gym,
          'plans': _gymPlans.where((p) => p['active'] != false).toList(),
          'payOnline': true,
        };

    if (match('GET', '/gyms')) {
      final query = '${q['q'] ?? ''}'.toLowerCase();
      final g = publicGym();
      final hit = query.isEmpty || '${g['name']} ${g['city']}'.toLowerCase().contains(query);
      return [if (hit) g];
    }
    if (match('GET', '/gyms/:id')) {
      if (seg[1] != _gym['id']) throw _MockError(404, 'Palestra non trovata');
      return publicGym();
    }
    if (match('POST', '/gyms/:id/plans/:plan/checkout')) return {'url': _demoUrl};

    final gymSide = match('GET', '/gym/billing') ||
        match('POST', '/gym/billing/checkout') ||
        match('POST', '/gym/billing/portal') ||
        match('POST', '/gym/billing/connect') ||
        match('GET', '/gym/payments');
    if (!gymSide) return _unhandled;
    if (!_asGymAccount) throw _MockError(403, 'Access Denied');
    if (match('GET', '/gym/billing')) {
      return {
        'tier': 'FREE',
        'status': 'ACTIVE',
        'memberLimit': 15,
        'activeMembers': _gymMembers.where((m) => m['status'] == 'ACTIVE').length,
        'currentPeriodEnd': null,
        'canManageSubscription': false,
        'tiers': [
          {'tier': 'FREE', 'priceCents': 0, 'memberLimit': 15},
          {'tier': 'STARTER', 'priceCents': 4900, 'memberLimit': 100},
          {'tier': 'PRO', 'priceCents': 9900, 'memberLimit': 300},
          {'tier': 'BUSINESS', 'priceCents': 19900, 'memberLimit': null},
        ],
        'paymentsConnected': true,
        'onlinePayments': true,
        'feePercent': 2.0,
      };
    }
    if (match('GET', '/gym/payments')) {
      return [
        {
          'id': 'pay1',
          'username': 'giulia.fit',
          'planName': 'Annuale',
          'amountCents': 39000,
          'feeCents': 780,
          'netCents': 38220,
          'status': 'PAID',
          'createdAt': MockBackend._iso(_now.subtract(const Duration(days: 3))),
          'paidAt': MockBackend._iso(_now.subtract(const Duration(days: 3))),
        },
      ];
    }
    return {'url': _demoUrl};
  }
}
