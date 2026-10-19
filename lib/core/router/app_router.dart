import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/session.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/verify_otp_screen.dart';
import '../../features/feed/create_post_screen.dart';
import '../../features/feed/post_detail_screen.dart';
import '../../features/friends/friends_screen.dart';
import '../../features/friends/notifications_screen.dart';
import '../../features/friends/user_profile_screen.dart';
import '../../features/groups/group_detail_screen.dart';
import '../../features/groups/group_form_screen.dart';
import '../../features/groups/group_session_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/welcome_screen.dart';
import '../../features/profile/history_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/running/route_detail_screen.dart';
import '../../features/running/route_editor_screen.dart';
import '../../features/running/run_detail_screen.dart';
import '../../features/running/run_event_detail_screen.dart';
import '../../features/running/run_tracker_screen.dart';
import '../../features/running/running_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/profile/edit_profile_screen.dart';
import '../../features/together/search_screen.dart';
import '../../features/together/together_screen.dart';
import '../../features/workouts/workouts_screen.dart';
import '../../features/workouts/workout_detail_screen.dart';
import '../../features/workouts/workout_form_screen.dart';
import '../../features/workouts/workout_session_screen.dart';
import '../../models/workout.dart';
import '../widgets/ui.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Dove andare dopo splash o login, se l'app è stata aperta da un link.
String? _pendingLocation;

/// Pagine raggiungibili dai link condivisi (vedi ShareLinks).
bool _isSharedLink(String loc) => [
      '/w/', '/workout/', '/u/', '/r/', '/running/route/', '/p/', '/posts/' //
    ].any(loc.startsWith);

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(splashDoneProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      final onPublic = loc == '/welcome' || loc.startsWith('/auth');

      // Un link aperto da fuori (scheda, profilo) prima che la sessione sia
      // pronta o prima del login: ci si torna appena si entra.
      // Lo splash animato resta finché non finisce, anche con la sessione pronta.
      if (!session.hasValue || !ref.read(splashDoneProvider)) {
        if (_isSharedLink(loc)) _pendingLocation = state.uri.toString();
        return loc == '/splash' ? null : '/splash';
      }

      final user = session.value;
      if (user == null) {
        if (_isSharedLink(loc)) _pendingLocation = state.uri.toString();
        return onPublic ? null : '/welcome';
      }
      if (onPublic || loc == '/splash') {
        final next = _pendingLocation;
        _pendingLocation = null;
        return next ?? '/home';
      }
      return null;
    },
    // ContentWidth: su un pieghevole aperto o un tablet la pagina resta una colonna al centro.
    // Le mappe della corsa e le tab con TwoPane (Allenati, Insieme) usano tutto lo schermo.
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const ContentWidth(child: WelcomeScreen())),
      GoRoute(path: '/auth/login', builder: (_, _) => const ContentWidth(child: LoginScreen())),
      GoRoute(path: '/auth/signup', builder: (_, _) => const ContentWidth(child: SignupScreen())),
      GoRoute(
        path: '/auth/verify',
        builder: (_, s) => ContentWidth(
          child: VerifyOtpScreen(
            username: s.uri.queryParameters['username'] ?? '',
            email: s.uri.queryParameters['email'],
          ),
        ),
      ),
      GoRoute(path: '/auth/forgot', builder: (_, _) => const ContentWidth(child: ForgotPasswordScreen())),

      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const ContentWidth(child: HomeScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: '/workouts', builder: (_, _) => const BackToHome(child: WorkoutsScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: '/together', builder: (_, _) => const BackToHome(child: TogetherScreen()))]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ContentWidth(child: BackToHome(child: ProfileScreen()))),
          ]),
        ],
      ),

      // Vecchi indirizzi delle tab (notifiche, link): ora è tutto in Insieme.
      GoRoute(path: '/groups', redirect: (_, _) => '/together'),
      GoRoute(path: '/feed', redirect: (_, _) => '/together'),

      // Schermate a tutto schermo sopra le tab.
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/search',
        builder: (_, _) => const ContentWidth(child: SearchScreen()),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/workouts/explore',
        builder: (_, _) => const WorkoutsScreen(explore: true),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/posts/new',
        builder: (_, s) => ContentWidth(child: CreatePostScreen(draft: s.extra as PostDraft?)),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/posts/:id',
        builder: (_, s) => ContentWidth(child: PostDetailScreen(postId: s.pathParameters['id']!)),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/workout/new',
        builder: (_, _) => const ContentWidth(child: WorkoutFormScreen()),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/workout/:id',
        builder: (_, s) => ContentWidth(child: WorkoutDetailScreen(workoutId: s.pathParameters['id']!)),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/workout/:id/edit',
        builder: (_, s) => ContentWidth(child: WorkoutEditScreen(workoutId: s.pathParameters['id']!, initial: s.extra as Workout?)),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/workout/:id/session',
        builder: (_, s) => ContentWidth(
          child: WorkoutSessionScreen(
            workoutId: s.pathParameters['id']!,
            groupId: s.uri.queryParameters['group'],
            // sessione di gruppo avviata dall'organizzatore: tutti contano dallo stesso istante
            startedAt: DateTime.tryParse(s.uri.queryParameters['start'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/profile/edit',
        builder: (_, _) => const ContentWidth(child: EditProfileScreen()),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/history',
        builder: (_, _) => const ContentWidth(child: HistoryScreen()),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/group/new',
        builder: (_, s) => ContentWidth(child: GroupFormScreen(workoutId: s.uri.queryParameters['workout'])),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/group/:id',
        builder: (_, s) => ContentWidth(child: GroupDetailScreen(groupId: s.pathParameters['id']!)),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/group/:id/session/new',
        builder: (_, s) => ContentWidth(
          child: GroupFormScreen(
            groupId: s.pathParameters['id'],
            workoutId: s.uri.queryParameters['workout'],
            routeId: s.uri.queryParameters['route'],
          ),
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/group-session/:id',
        builder: (_, s) => ContentWidth(child: GroupSessionScreen(sessionId: s.pathParameters['id']!)),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/running',
        builder: (_, s) => RunningScreen(initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/running/route/new',
        builder: (_, _) => const RouteEditorScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/running/route/:id',
        builder: (_, s) => RouteDetailScreen(routeId: s.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/running/route/:id/edit',
        builder: (_, s) => RouteEditorScreen(routeId: s.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/running/event/:id',
        builder: (_, s) => RunEventDetailScreen(eventId: s.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/running/run',
        builder: (_, s) => RunTrackerScreen(
          routeId: s.uri.queryParameters['route'],
          eventId: s.uri.queryParameters['event'],
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/running/runs/:id',
        builder: (_, s) => RunDetailScreen(runId: s.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/friends',
        builder: (_, _) => const ContentWidth(child: FriendsScreen()),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/notifications',
        builder: (_, _) => const ContentWidth(child: NotificationsScreen()),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/u/:username',
        builder: (_, s) => ContentWidth(child: UserProfileScreen(username: s.pathParameters['username']!)),
      ),
      // Link condivisi fuori dall'app (https://repbirds.com/w/<id>, vedi ShareLinks).
      GoRoute(path: '/w/:id', redirect: (_, s) => '/workout/${s.pathParameters['id']}'),
      GoRoute(path: '/r/:id', redirect: (_, s) => '/running/route/${s.pathParameters['id']}'),
      GoRoute(path: '/p/:id', redirect: (_, s) => '/posts/${s.pathParameters['id']}'),
    ],
  );
});
