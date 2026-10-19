import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:gymbro_app/core/mock/mock_backend.dart';
import 'package:gymbro_app/data/body_photo_repository.dart';
import 'package:gymbro_app/features/body/body_calendar.dart';
import 'package:gymbro_app/models/body_photo.dart';
import 'package:gymbro_app/models/notification.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  group('mese da confrontare', () {
    test('nella prima settimana è il mese appena finito, poi quello corrente', () {
      expect(comparisonMonth(DateTime(2026, 11, 2)), DateTime(2026, 10));
      expect(comparisonMonth(DateTime(2026, 1, 3)), DateTime(2025, 12));
      expect(comparisonMonth(DateTime(2026, 10, 31, 18)), DateTime(2026, 10));
    });

    test('chiave del mese come nel dettaglio della notifica', () {
      expect(monthKey(DateTime(2026, 3, 15)), '2026-03');
      expect(parseMonthKey('2026-03'), DateTime(2026, 3));
      expect(parseMonthKey('marzo'), isNull);
    });

    test('la notifica di fine mese apre il confronto di quel mese', () {
      final n = AppNotification.fromJson({'id': 'n1', 'type': 'BODY_PHOTO_MONTHLY', 'detail': '2026-10'});
      expect(n.kind, NotificationKind.bodyPhotoMonthly);
      expect(n.route, '/body-photos/compare?month=2026-10');
      expect(AppNotification.routeFor(NotificationKind.bodyPhotoMonthly, null), '/body-photos/compare');
    });
  });

  group('backend mock', () {
    late Dio dio;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://mock/api'))
        ..interceptors.add(MockBackend(latency: Duration.zero, enabled: () => true));
    });

    Future<List<BodyPhoto>> month(String username) async {
      final now = DateTime.now();
      final res = await dio.get<dynamic>('/body-photos/user/$username', queryParameters: {
        'from': DateTime(now.year, now.month).toUtc().toIso8601String(),
        'to': DateTime(now.year, now.month + 1).toUtc().toIso8601String(),
      });
      return (res.data as List).map((e) => BodyPhoto.fromJson(e as Map<String, dynamic>)).toList();
    }

    test('le foto private le vede solo il proprietario; caricate private di default', () async {
      final form = FormData()..files.add(MapEntry('imageFile', MultipartFile.fromBytes([1, 2, 3], filename: 'me.jpg')));
      final res = await dio.post<dynamic>('/body-photos', data: form, queryParameters: {'isPublic': false});
      final created = BodyPhoto.fromJson((res.data as Map)['result'] as Map<String, dynamic>);
      expect(created.isPublic, isFalse);
      expect((await month('mousty')).map((p) => p.id), contains(created.id));

      final giulia = await month('giulia.fit');
      expect(giulia, isNotEmpty);
      expect(giulia.every((p) => p.isPublic), isTrue);

      final updated = await dio.patch<dynamic>('/body-photos/${created.id}/visibility', data: {'isPublic': true});
      expect(BodyPhoto.fromJson(updated.data as Map<String, dynamic>).isPublic, isTrue);
      await dio.delete<dynamic>('/body-photos/${created.id}');
      expect((await month('mousty')).map((p) => p.id), isNot(contains(created.id)));
    });
  });

  testWidgets('calendario: le foto stanno sul loro giorno e con due foto si può confrontare', (tester) async {
    final now = DateTime.now();
    final photos = [
      BodyPhoto(id: 'a', takenAt: DateTime(now.year, now.month, 1, 9)),
      BodyPhoto(id: 'b', takenAt: DateTime(now.year, now.month, 1, 19)),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [bodyPhotosProvider.overrideWith((ref, k) async => k.username == 'mousty' ? photos : <BodyPhoto>[])],
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BodyCalendar(username: 'mousty', mine: true)))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Confronta'), findsOneWidget);
    // due foto lo stesso giorno: una sola cella, con il contatore
    final badge = find.byWidgetPredicate((w) => w is Text && w.data == '2' && w.style?.fontSize == 10);
    expect(badge, findsOneWidget);
    expect(find.text('Nessuna foto questo mese. Alla fine di un allenamento puoi aggiungerne una.'), findsNothing);
  });
}
