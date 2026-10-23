import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:repbirds_app/core/config/env.dart';
import 'package:repbirds_app/features/auth/session.dart';
import 'package:repbirds_app/features/profile/edit_profile_screen.dart';
import 'package:repbirds_app/models/user.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  setUp(() {
    Env.useMock = true;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => Env.useMock = false);

  testWidgets('username già preso: errore sotto il campo', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(User(id: 'u1', username: 'mousty', email: 'mousty@repbirds.app', birthDate: DateTime(1998, 5, 12))),
      ],
      child: const MaterialApp(home: EditProfileScreen()),
    ));
    await tester.enterText(find.byType(TextFormField).first, 'marco_lifts');
    await tester.runAsync(() async {
      await tester.tap(find.text('Salva'));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    expect(find.text('Username già in uso, scegline un altro'), findsOneWidget);
  });
}
