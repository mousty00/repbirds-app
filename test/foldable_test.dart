import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymbro_app/core/widgets/ui.dart';

void main() {
  // Galaxy Z Fold aperto a libro: piega verticale al centro, senza spessore.
  const bookFold = DisplayFeature(
    bounds: Rect.fromLTWH(345, 0, 0, 840),
    type: DisplayFeatureType.fold,
    state: DisplayFeatureState.postureFlat,
  );
  // Aperto a metà e appoggiato in orizzontale: piega a metà altezza.
  const tabletop = DisplayFeature(
    bounds: Rect.fromLTWH(0, 400, 840, 0),
    type: DisplayFeatureType.fold,
    state: DisplayFeatureState.postureHalfOpened,
  );

  Future<void> pump(WidgetTester tester, Size size, List<DisplayFeature> features, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(displayFeatures: features),
            child: Scaffold(body: child),
          ),
        ),
      ),
    ));
  }

  const pane = TwoPane(start: SizedBox.expand(child: Text('lista')), end: Text('dettaglio'));

  testWidgets('telefono: solo la lista, larga al massimo una colonna', (tester) async {
    await pump(tester, const Size(400, 800), const [], pane);
    expect(find.text('dettaglio'), findsNothing);

    await pump(tester, const Size(700, 800), const [], pane);
    expect(find.text('dettaglio'), findsNothing, reason: '700dp senza piega: ancora una colonna');
    expect(tester.getSize(find.byType(SizedBox).first).width, ContentWidth.maxWidth);
  });

  testWidgets('pieghevole aperto a libro: lista e dettaglio divisi sulla piega', (tester) async {
    await pump(tester, const Size(690, 840), const [bookFold], pane);
    expect(find.text('dettaglio'), findsOneWidget);
    expect(tester.getTopLeft(find.text('dettaglio')).dx, 345);
  });

  testWidgets('finestra larga senza piega: due pannelli', (tester) async {
    await pump(tester, const Size(1000, 800), const [], pane);
    expect(find.text('dettaglio'), findsOneWidget);
  });

  testWidgets('modalità tavolino riconosciuta solo a metà apertura e con piega orizzontale', (tester) async {
    Rect? fold;
    final probe = Builder(builder: (context) {
      fold = tabletopFold(context);
      return const SizedBox();
    });
    await pump(tester, const Size(840, 800), const [tabletop], probe);
    expect(fold, tabletop.bounds);

    await pump(tester, const Size(690, 840), const [bookFold], probe);
    expect(fold, isNull, reason: 'aperto a libro non è tavolino');
  });

  testWidgets('in un pannello niente indietro, e chiudere svuota il pannello', (tester) async {
    var closed = false;
    await pump(
      tester,
      const Size(400, 800),
      const [],
      PaneScope(
        onClose: () => closed = true,
        child: Builder(
          builder: (context) => Column(children: [
            const TopBar(title: 'Post'),
            TextButton(onPressed: () => closePage(context), child: const Text('elimina')),
          ]),
        ),
      ),
    );
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    await tester.tap(find.text('elimina'));
    expect(closed, isTrue);
  });
}
