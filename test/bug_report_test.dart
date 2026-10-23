import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repbirds_app/core/config/env.dart';
import 'package:repbirds_app/features/support/bug_report_screen.dart';

void main() {
  setUp(() {
    Env.useMock = true;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => Env.useMock = false);

  Widget app() => ProviderScope(
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/report', routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('profilo')),
              routes: [GoRoute(path: 'report', builder: (_, _) => const BugReportScreen())],
            ),
          ]),
        ),
      );

  testWidgets('descrizione troppo corta: errore, nessun invio', (tester) async {
    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField), 'rotto');
    await tester.tap(find.text('Invia segnalazione'));
    await tester.pump();
    expect(find.text('Descrivi il problema in almeno 10 caratteri'), findsOneWidget);
    expect(find.byType(BugReportScreen), findsOneWidget);
  });

  testWidgets('segnalazione inviata: conferma e torna indietro', (tester) async {
    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField), 'Il timer si blocca alla terza serie');
    await tester.runAsync(() async {
      await tester.tap(find.text('Invia segnalazione'));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Grazie! Abbiamo ricevuto la segnalazione'), findsOneWidget);
    expect(find.text('profilo'), findsOneWidget);
  });
}
