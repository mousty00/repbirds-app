import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:repbirds_app/core/config/env.dart';
import 'package:repbirds_app/core/network/api_client.dart';
import 'package:repbirds_app/features/auth/session.dart';
import 'package:repbirds_app/features/gym/gym_courses_screen.dart';
import 'package:repbirds_app/features/gym/gym_members_screen.dart';
import 'package:repbirds_app/features/gym/gym_overview_screen.dart';
import 'package:repbirds_app/features/gym/gym_plans_screen.dart';
import 'package:repbirds_app/features/gym/gym_signup_screen.dart';
import 'package:repbirds_app/features/gym/gym_workouts_screen.dart';
import 'package:repbirds_app/features/membership/membership_screen.dart';
import 'package:repbirds_app/models/user.dart';

/// Le schermate della palestra e della tessera si aprono sui dati del mock senza errori.
void main() {
  setUpAll(() => initializeDateFormatting());
  setUp(() {
    Env.useMock = true;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => Env.useMock = false);

  Future<void> open(WidgetTester tester, Widget screen, {required String login, required String expected}) async {
    final container = ProviderContainer(
      overrides: [currentUserProvider.overrideWithValue(User(id: 'x', username: login, email: '$login@repbirds.app'))],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(apiClientProvider).post<dynamic>('/auth/login', data: {'username': login, 'password': 'x'}));
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: screen)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump();
    // le schede e i corsi sotto la tessera partono dopo il primo frame
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.textContaining(expected), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('dashboard: panoramica', (t) => open(t, const GymOverviewScreen(), login: 'palestra', expected: 'Fit Club Milano'));
  testWidgets('dashboard: iscritti', (t) => open(t, const GymMembersScreen(), login: 'palestra', expected: 'giulia.fit'));
  testWidgets('dashboard: abbonamenti', (t) => open(t, const GymPlansScreen(), login: 'palestra', expected: 'Annuale'));
  testWidgets('dashboard: schede', (t) => open(t, const GymWorkoutsScreen(), login: 'palestra', expected: 'Full body principianti'));
  testWidgets('dashboard: corsi', (t) => open(t, const GymCoursesScreen(), login: 'palestra', expected: 'Spinning'));
  testWidgets('registrazione palestra', (t) => open(t, const GymSignupScreen(), login: 'mousty', expected: 'Nome della palestra'));
  testWidgets('iscritto: tessera', (t) => open(t, const MembershipScreen(), login: 'mousty', expected: 'Fit Club Milano'));
}
