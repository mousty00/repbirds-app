import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../features/auth/session.dart';
import '../models/group.dart';
import '../models/notification.dart';
import '../models/running.dart';
import '../models/social.dart';
import '../models/user.dart';
import '../models/workout.dart';
import 'notification_repository.dart';
import 'running_repository.dart';
import 'social_repository.dart';
import 'user_repository.dart';
import 'workout_repository.dart';

// Provider di lettura condivisi tra le schermate. Dopo una modifica si fa
// `ref.invalidate(...)` sul provider interessato.

/// Id dell'utente loggato: i provider non autoDispose lo osservano così
/// vengono ricaricati quando cambia account.
final userKeyProvider = Provider<String?>((ref) => ref.watch(sessionProvider).value?.id);

// Allenamenti

final myWorkoutsProvider = FutureProvider<List<Workout>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(workoutRepositoryProvider).mine();
});

final exploreWorkoutsProvider = FutureProvider<List<Workout>>((ref) async {
  ref.watch(userKeyProvider);
  return (await ref.watch(workoutRepositoryProvider).explore()).results;
});

final workoutProvider = FutureProvider.autoDispose.family<Workout, String>(
  (ref, id) => ref.watch(workoutRepositoryProvider).byId(id),
);

final exercisesProvider = FutureProvider<List<Exercise>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(workoutRepositoryProvider).exercises();
});

final historyProvider = FutureProvider<List<WorkoutHistory>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(workoutRepositoryProvider).history();
});

// Gruppi

final groupsProvider = FutureProvider<List<WorkoutGroup>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(groupRepositoryProvider).all();
});

final groupProvider = FutureProvider.autoDispose.family<WorkoutGroup, String>(
  (ref, id) => ref.watch(groupRepositoryProvider).byId(id),
);

final groupSessionsProvider = FutureProvider.autoDispose.family<List<GroupSession>, String>(
  (ref, groupId) => ref.watch(groupRepositoryProvider).sessions(groupId),
);

final upcomingSessionsProvider = FutureProvider<List<GroupSession>>(
  (ref) => ref.watch(groupRepositoryProvider).upcomingSessions(),
);

final groupHistoryProvider = FutureProvider.autoDispose.family<List<WorkoutHistory>, String>(
  (ref, id) => ref.watch(workoutRepositoryProvider).groupHistory(id),
);

/// Inviti ai gruppi ancora da accettare.
final groupInvitesProvider = FutureProvider<List<GroupMember>>((ref) async {
  ref.watch(userKeyProvider);
  final all = await ref.watch(groupRepositoryProvider).myMemberships();
  return all.where((m) => m.status == GroupMemberStatus.invited).toList();
});

// Corsa

final myRoutesProvider = FutureProvider<List<RunRoute>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(runningRepositoryProvider).myRoutes();
});

/// Percorsi pubblici degli amici.
final friendsRoutesProvider = FutureProvider<List<RunRoute>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(runningRepositoryProvider).friendsRoutes();
});

final runRouteProvider = FutureProvider.autoDispose.family<RunRoute, String>(
  (ref, id) => ref.watch(runningRepositoryProvider).route(id),
);

final runEventsProvider = FutureProvider<List<RunEvent>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(runningRepositoryProvider).events();
});

final runEventProvider = FutureProvider.autoDispose.family<RunEvent, String>(
  (ref, id) => ref.watch(runningRepositoryProvider).event(id),
);

final eventRunsProvider = FutureProvider.autoDispose.family<List<RunActivity>, String>(
  (ref, id) => ref.watch(runningRepositoryProvider).eventRuns(id),
);

final myRunsProvider = FutureProvider<List<RunActivity>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(runningRepositoryProvider).myRuns();
});

final runProvider = FutureProvider.autoDispose.family<RunActivity, String>(
  (ref, id) => ref.watch(runningRepositoryProvider).run(id),
);

// Social

final friendsProvider = FutureProvider<List<Friendship>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(friendshipRepositoryProvider).all();
});

final friendRequestsProvider = FutureProvider<List<Friendship>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(friendshipRepositoryProvider).pendingRequests();
});

/// Richieste inviate da me, ancora in attesa: il pulsante "Aggiungi" le usa
/// per mostrare "Inviata" anche dopo aver cambiato schermata.
final sentFriendRequestsProvider = FutureProvider<List<Friendship>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(friendshipRepositoryProvider).sentRequests();
});

final friendsPostsProvider = FutureProvider<List<Post>>((ref) {
  ref.watch(userKeyProvider);
  return ref.watch(postRepositoryProvider).friendsPosts();
});

final explorePostsProvider = FutureProvider<List<Post>>((ref) async {
  ref.watch(userKeyProvider);
  return (await ref.watch(postRepositoryProvider).all()).results;
});

final postProvider = FutureProvider.autoDispose.family<Post, String>(
  (ref, id) => ref.watch(postRepositoryProvider).byId(id),
);

final userPostsProvider = FutureProvider.autoDispose.family<List<Post>, String>(
  (ref, username) => ref.watch(postRepositoryProvider).byUser(username),
);

final userProfileProvider = FutureProvider.autoDispose.family<User, String>(
  (ref, username) => ref.watch(userRepositoryProvider).byUsername(username),
);

final userOverviewProvider = FutureProvider.autoDispose.family<UserOverview, String>(
  (ref, username) => ref.watch(userRepositoryProvider).overview(username),
);

// Notifiche

/// Attività recenti (like, commenti, richieste, inviti), più recenti prima.
final activityProvider = FutureProvider<List<AppNotification>>((ref) async {
  ref.watch(userKeyProvider);
  return (await ref.watch(notificationRepositoryProvider).all()).results;
});

/// Notifiche non ancora lette; 0 se il backend non risponde. Lo stream in tempo
/// reale (`NotificationStream`) lo aggiorna con [UnreadActivity.set].
class UnreadActivity extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    ref.watch(userKeyProvider);
    try {
      return await ref.watch(notificationRepositoryProvider).unreadCount();
    } catch (_) {
      return 0;
    }
  }

  void set(int count) => state = AsyncData(count);
}

final unreadActivityProvider = AsyncNotifierProvider<UnreadActivity, int>(UnreadActivity.new);

/// Numero sulla campanella: le notifiche non lette (richieste e inviti compresi,
/// arrivano anche loro come notifica).
final notificationCountProvider = Provider<int>((ref) => ref.watch(unreadActivityProvider).value ?? 0);

/// Ricarica tutto quello che una nuova notifica può cambiare (es. all'arrivo di
/// una push). Riceve `ref.invalidate` così va bene sia con `Ref` sia con `WidgetRef`.
void refreshNotifications(void Function(ProviderOrFamily provider) invalidate) {
  invalidate(activityProvider);
  invalidate(unreadActivityProvider);
  invalidate(friendRequestsProvider);
  invalidate(groupInvitesProvider);
}

/// Invalida i feed dei post (dopo like, commenti, nuovi post).
void refreshPosts(WidgetRef ref) {
  ref.invalidate(friendsPostsProvider);
  ref.invalidate(explorePostsProvider);
}

/// Dopo un like: ricarica tutte le liste in cui compare il post, così ogni
/// schermata mostra lo stesso stato (e un secondo tap toglie davvero il like).
void refreshPost(WidgetRef ref, Post post) {
  refreshPosts(ref);
  ref.invalidate(postProvider(post.id));
  ref.invalidate(userPostsProvider(post.user.username));
}
