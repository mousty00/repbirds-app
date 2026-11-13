import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../data/premium_repository.dart';
import '../../data/providers.dart';
import '../l10n/l10n.dart';
import '../network/api_exception.dart';

/// Lo stato di un acquisto in corso, per il paywall.
class PurchaseUi {
  const PurchaseUi({this.busy = false, this.error, this.done = false});

  final bool busy;
  final String? error;

  /// Premium appena attivato (o ripristinato).
  final bool done;
}

/// Acquisti in-app di Premium con StoreKit e Google Play Billing.
///
/// L'acquisto porta l'id dell'utente (appAccountToken su iOS, obfuscatedAccountId su
/// Android): il server lo controlla chiedendo ad Apple o Google, così una ricevuta non
/// si può spostare su un altro account. Solo dopo la verifica la transazione si chiude.
class PremiumPurchases extends Notifier<PurchaseUi> {
  StreamSubscription<List<PurchaseDetails>>? _sub;

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  @override
  PurchaseUi build() {
    ref.onDispose(() => _sub?.cancel());
    return const PurchaseUi();
  }

  /// Da chiamare dopo il login: completa anche gli acquisti rimasti a metà.
  void start() {
    if (!supported || _sub != null) return;
    _sub = InAppPurchase.instance.purchaseStream.listen(_handle, onError: (Object e) {
      state = PurchaseUi(error: '$e');
    });
  }

  Future<List<ProductDetails>> products(List<String> ids) async {
    if (!supported || !await InAppPurchase.instance.isAvailable()) return const [];
    final res = await InAppPurchase.instance.queryProductDetails(ids.toSet());
    final list = [...res.productDetails]..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    return list;
  }

  Future<void> buy(ProductDetails product) async {
    final userId = ref.read(userKeyProvider);
    if (userId == null) return;
    start();
    state = const PurchaseUi(busy: true);
    try {
      final ok = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product, applicationUserName: userId),
      );
      if (!ok) state = const PurchaseUi();
    } catch (e) {
      state = PurchaseUi(error: '$e');
    }
  }

  Future<void> restore() async {
    if (!supported) return;
    start();
    state = const PurchaseUi(busy: true);
    try {
      await InAppPurchase.instance.restorePurchases(applicationUserName: ref.read(userKeyProvider));
      // se non c'è niente da ripristinare lo stream non dice nulla
      await Future<void>.delayed(const Duration(seconds: 3));
      if (state.busy) state = const PurchaseUi();
      ref.invalidate(premiumProvider);
    } catch (e) {
      state = PurchaseUi(error: '$e');
    }
  }

  Future<void> _handle(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          state = const PurchaseUi(busy: true);
        case PurchaseStatus.canceled:
          state = const PurchaseUi();
          if (p.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(p);
        case PurchaseStatus.error:
          state = PurchaseUi(error: p.error?.message ?? tr('Acquisto non riuscito'));
          if (p.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(p);
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          await _verify(p);
      }
    }
  }

  Future<void> _verify(PurchaseDetails p) async {
    final repo = ref.read(premiumRepositoryProvider);
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await repo.verifyApple(p.purchaseID ?? '');
      } else {
        await repo.verifyGoogle(p.verificationData.serverVerificationData);
      }
      if (p.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(p);
      ref.invalidate(premiumProvider);
      state = const PurchaseUi(done: true);
    } on ApiException catch (e) {
      // Rifiutata (di un altro account, prodotto sconosciuto): si chiude. Server o rete
      // giù: resta aperta, lo store la ripresenta e si riprova.
      final rejected = (e.statusCode ?? 500) < 500 && !e.unreachable;
      if (rejected && p.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(p);
      state = PurchaseUi(error: e.message);
    }
  }
}

final premiumPurchasesProvider = NotifierProvider<PremiumPurchases, PurchaseUi>(PremiumPurchases.new);
