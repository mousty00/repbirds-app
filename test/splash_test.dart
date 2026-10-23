import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/widgets/rep_bird.dart';
import 'package:repbirds_app/features/auth/session.dart';
import 'package:repbirds_app/features/onboarding/splash_screen.dart';
import 'package:repbirds_app/models/user.dart';

class _NoSession extends SessionController {
  @override
  Future<User?> build() async => null;
}

void main() {
  testWidgets("lo splash mostra il logo e segnala la fine dell'animazione", (tester) async {
    final container = ProviderContainer(overrides: [sessionProvider.overrideWith(_NoSession.new)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SplashScreen()),
    ));

    expect(find.byType(RepBird), findsOneWidget);
    expect(container.read(splashDoneProvider), isFalse);

    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump();
    expect(container.read(splashDoneProvider), isTrue);
    expect(find.text('RepBirds'), findsOneWidget);
  });
}
