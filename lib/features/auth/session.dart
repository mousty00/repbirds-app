import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gym/nfc_card.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/push/push_service.dart';
import '../../data/auth_repository.dart';
import '../../models/user.dart';

/// Utente loggato (null = nessuna sessione). Guida i redirect del router.
class SessionController extends AsyncNotifier<User?> {
  StreamSubscription<void>? _expiredSub;

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<User?> build() async {
    _expiredSub ??= ref.read(apiClientProvider).sessionExpired.listen((_) {
      state = const AsyncData(null);
    });
    ref.onDispose(() => _expiredSub?.cancel());

    if (!await _repo.hasSession()) return null;
    try {
      return await _repo.profile();
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _repo.clearSession();
        return null;
      }
      rethrow;
    }
  }

  Future<void> login(String username, String password) async {
    final user = await _repo.login(username.trim(), password);
    state = AsyncData(user);
  }

  /// Dopo una modifica del profilo, con l'utente restituito dal server.
  void setUser(User user) => state = AsyncData(user);

  Future<void> reloadProfile() async {
    final user = await _repo.profile();
    state = AsyncData(user);
  }

  Future<void> logout() async {
    // prima del logout: serve ancora la sessione per cancellare il token push
    await ref.read(pushServiceProvider).onLogout();
    // la tessera NFC non deve restare sul telefono di chi esce
    await NfcCard.clearCard();
    await _repo.logout();
    state = const AsyncData(null);
  }

  /// Dopo l'eliminazione dell'account.
  Future<void> forget() async {
    await NfcCard.clearCard();
    await _repo.clearSession();
    state = const AsyncData(null);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, User?>(SessionController.new);

User? _lastUser;

/// Utente corrente, da usare solo nelle schermate protette (dopo il login).
/// Durante il logout restituisce l'ultimo utente noto finché il router non
/// porta via dalle schermate protette.
final currentUserProvider = Provider<User>((ref) {
  final user = ref.watch(sessionProvider).value ?? _lastUser;
  if (user == null) throw StateError('Nessun utente loggato');
  return _lastUser = user;
});
