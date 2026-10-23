import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repbirds_app/features/shell/app_shell.dart';

void main() {
  GoRouter router() => GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => Scaffold(body: shell),
            branches: [
              StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const Text('home'))]),
              StatefulShellBranch(routes: [
                GoRoute(path: '/profile', builder: (_, _) => const BackToHome(child: Text('profile'))),
              ]),
            ],
          ),
        ],
      );

  testWidgets('indietro da una tab torna alla Home invece di chiudere l\'app', (tester) async {
    final r = router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    r.go('/profile');
    await tester.pumpAndSettle();
    expect(find.text('profile'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(r.state.matchedLocation, '/home');
  });
}
