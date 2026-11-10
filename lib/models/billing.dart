import 'gym.dart';
import 'json.dart';

/// Un piano RepBirds per palestre: FREE, STARTER, PRO, BUSINESS.
class BillingTier {
  const BillingTier({required this.tier, this.priceCents = 0, this.memberLimit});

  final String tier;
  final int priceCents;

  /// null = soci illimitati.
  final int? memberLimit;

  factory BillingTier.fromJson(Json j) => BillingTier(
        tier: j['tier'] as String? ?? 'FREE',
        priceCents: parseInt(j['priceCents']),
        memberLimit: j['memberLimit'] == null ? null : parseInt(j['memberLimit']),
      );
}

/// Il piano RepBirds della palestra (`GymBillingDTO`).
class GymBilling {
  const GymBilling({
    this.tier = 'FREE',
    this.status = 'ACTIVE',
    this.memberLimit,
    this.activeMembers = 0,
    this.currentPeriodEnd,
    this.canManageSubscription = false,
    this.tiers = const [],
    this.paymentsConnected = false,
    this.onlinePayments = false,
    this.feePercent = 0,
  });

  final String tier;
  final String status;
  final int? memberLimit;
  final int activeMembers;
  final DateTime? currentPeriodEnd;
  final bool canManageSubscription;
  final List<BillingTier> tiers;

  /// Account Stripe creato (magari ancora da completare).
  final bool paymentsConnected;

  /// I soci possono pagare l'abbonamento nell'app.
  final bool onlinePayments;
  final double feePercent;

  bool get pastDue => status == 'PAST_DUE';

  factory GymBilling.fromJson(Json j) => GymBilling(
        tier: j['tier'] as String? ?? 'FREE',
        status: j['status'] as String? ?? 'ACTIVE',
        memberLimit: j['memberLimit'] == null ? null : parseInt(j['memberLimit']),
        activeMembers: parseInt(j['activeMembers']),
        currentPeriodEnd: parseInstant(j['currentPeriodEnd']),
        canManageSubscription: j['canManageSubscription'] == true,
        tiers: parseList(j['tiers'], BillingTier.fromJson),
        paymentsConnected: j['paymentsConnected'] == true,
        onlinePayments: j['onlinePayments'] == true,
        feePercent: (j['feePercent'] as num?)?.toDouble() ?? 0,
      );
}

/// Un pagamento di un socio (`GymPaymentDTO`). [netCents]: quanto arriva alla palestra.
class GymPayment {
  const GymPayment({
    required this.id,
    required this.username,
    this.planName,
    this.amountCents = 0,
    this.feeCents = 0,
    this.netCents = 0,
    this.status = 'PENDING',
    this.createdAt,
    this.paidAt,
  });

  final String id;
  final String username;
  final String? planName;
  final int amountCents;
  final int feeCents;
  final int netCents;
  final String status;
  final DateTime? createdAt;
  final DateTime? paidAt;

  factory GymPayment.fromJson(Json j) => GymPayment(
        id: '${j['id']}',
        username: j['username'] as String? ?? '',
        planName: j['planName'] as String?,
        amountCents: parseInt(j['amountCents']),
        feeCents: parseInt(j['feeCents']),
        netCents: parseInt(j['netCents']),
        status: j['status'] as String? ?? 'PENDING',
        createdAt: parseInstant(j['createdAt']),
        paidAt: parseInstant(j['paidAt']),
      );
}

/// Una palestra come la trova chiunque nell'app (`PublicGymDTO`).
class PublicGym {
  const PublicGym({
    required this.id,
    required this.name,
    this.description,
    this.address,
    this.city,
    this.phone,
    this.plans = const [],
    this.payOnline = false,
  });

  final String id;
  final String name;
  final String? description;
  final String? address;
  final String? city;
  final String? phone;
  final List<GymPlan> plans;
  final bool payOnline;

  String get place => [address, city].whereType<String>().where((s) => s.isNotEmpty).join(', ');

  factory PublicGym.fromJson(Json j) => PublicGym(
        id: '${j['id']}',
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        address: j['address'] as String?,
        city: j['city'] as String?,
        phone: j['phone'] as String?,
        plans: parseList(j['plans'], GymPlan.fromJson),
        payOnline: j['payOnline'] == true,
      );
}
