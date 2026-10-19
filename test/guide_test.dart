import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gymbro_app/features/help/help_screen.dart';
import 'package:gymbro_app/features/onboarding/guide_screen.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    GuideNotifier.seen = false;
  });

  // La guida ha animazioni che si ripetono: niente pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(ProviderContainer, GoRouter)> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/help', builder: (_, _) => const HelpScreen()),
        GoRoute(path: '/guide', builder: (_, _) => const GuideScreen()),
      ],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
    return (container, router);
  }

  testWidgets('la guida si sfoglia fino in fondo e poi non si riapre da sola', (tester) async {
    final (container, router) = await open(tester);
    router.push('/guide');
    await settle(tester);
    expect(find.text('Benvenuto su RepBirds'), findsOneWidget);
    expect(container.read(guideProvider), isFalse);

    for (final title in ['Oggi', 'Allenati', 'Insieme', 'Crea', 'Profilo']) {
      await tester.tap(find.text('Avanti'));
      await settle(tester);
      expect(find.widgetWithText(Column, title), findsWidgets, reason: title);
    }
    expect(find.text('Avanti'), findsNothing);

    await tester.tap(find.text('Iniziamo'));
    await settle(tester);
    expect(container.read(guideProvider), isTrue);
    expect(GuideNotifier.seen, isTrue);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Salta chiude la guida e la segna come vista', (tester) async {
    final (container, router) = await open(tester);
    router.push('/guide');
    await settle(tester);

    await tester.tap(find.text('Salta'));
    await settle(tester);
    expect(container.read(guideProvider), isTrue);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('da Aiuto si apre una risposta e si rivede la guida', (tester) async {
    final (_, router) = await open(tester);
    router.push('/help');
    await settle(tester);

    expect(find.text('Domande frequenti'), findsOneWidget);
    await tester.tap(find.text('Come creo una scheda?'));
    await settle(tester);
    expect(find.textContaining('Tocca + al centro della barra'), findsOneWidget);

    await tester.tap(find.text('Rivedi la guida'));
    await settle(tester);
    expect(find.text('Benvenuto su RepBirds'), findsOneWidget);
  });
}
