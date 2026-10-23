import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:repbirds_app/features/body/photo_edit.dart';
import 'package:repbirds_app/features/body/photo_editor.dart';

/// Una foto finta [w]x[h]: rossa a sinistra, blu a destra.
Uint8List photo(int w, int h) {
  final i = img.Image(width: w, height: h);
  for (final p in i) {
    p
      ..r = p.x < w / 2 ? 255 : 0
      ..b = p.x < w / 2 ? 0 : 255;
  }
  return img.encodePng(i);
}

Future<ui.Image> decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

void main() {
  const source = Size(400, 300);

  group('modifiche', () {
    test('ruotare gira anche il ritaglio, quattro giri tornano all\'inizio', () {
      const start = PhotoEdits(crop: Rect.fromLTRB(0.1, 0.2, 0.5, 0.6));
      final once = start.rotated(source);
      expect(once.quarterTurns, 1);
      expect(once.oriented(source), const Size(300, 400));
      expect(once.crop, const Rect.fromLTRB(0.4, 0.1, 0.8, 0.5));
      var e = start;
      for (var i = 0; i < 4; i++) {
        e = e.rotated(source);
      }
      expect(e.quarterTurns, 0);
      expect(e.crop.left, closeTo(0.1, 1e-9));
      expect(e.crop.bottom, closeTo(0.6, 1e-9));
    });

    test('specchiata, la rotazione va nel verso di quello che si vede', () {
      final e = const PhotoEdits().mirrored().rotated(source);
      expect(e.flipped, isTrue);
      expect(e.quarterTurns, 3);
    });

    test('proporzioni fisse: il ritaglio più grande al centro, e restano dopo una rotazione', () {
      final square = const PhotoEdits().withAspect(CropAspect.square, source);
      expect(square.cropIn(source).size, const Size(300, 300));
      final story = const PhotoEdits().withAspect(CropAspect.story, source).rotated(source);
      final px = story.cropIn(source);
      expect(px.width / px.height, closeTo(9 / 16, 1e-9));
      expect(px.height, closeTo(400, 1e-9));
    });

    test('ridimensionare un angolo tiene fermo quello opposto e resta nella foto', () {
      const r = Rect.fromLTRB(0.2, 0.2, 0.8, 0.8);
      final grown = resizeCrop(r, 2, const Offset(1.5, 0.9));
      expect([grown.left, grown.top, grown.right, grown.bottom], [0.2, 0.2, 1, closeTo(0.9, 1e-9)]);
      expect(resizeCrop(r, 0, const Offset(0.79, 0.79)).size.width, closeTo(0.1, 1e-9), reason: 'non sotto il minimo');
      final locked = resizeCrop(r, 2, const Offset(0.9, 0.5), aspect: 0.5);
      expect(locked.width / locked.height, closeTo(0.5, 1e-9));
      expect(locked.topLeft, r.topLeft);
      expect(locked.bottom, lessThanOrEqualTo(1));
    });

    test('spostare il ritaglio non lo fa uscire', () {
      final moved = moveCrop(const Rect.fromLTRB(0.5, 0.5, 0.9, 0.9), const Offset(0.5, -0.7));
      expect(
        [moved.left, moved.top, moved.right, moved.bottom],
        [closeTo(0.6, 1e-9), 0, closeTo(1, 1e-9), closeTo(0.4, 1e-9)],
      );
    });

    test('senza filtri né regolazioni i colori non cambiano', () {
      expect(const PhotoEdits().colorMatrix, [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]);
      final mono = const PhotoEdits(filter: PhotoFilter.mono).colorMatrix;
      expect(mono.sublist(0, 3), mono.sublist(5, 8), reason: 'in bianco e nero i canali sono uguali');
    });
  });

  testWidgets('la foto si esporta ruotata e ritagliata, in JPEG', (tester) async {
    await tester.runAsync(() async {
      final image = await decode(photo(40, 30));
      final e = const PhotoEdits().rotated(const Size(40, 30)).copyWith(crop: const Rect.fromLTRB(0, 0, 1, 0.5));
      final out = img.decodeJpg(await renderEdited(image, e))!;
      expect((out.width, out.height), (30, 20));
      // girata in senso orario la metà rossa (sinistra) finisce in alto
      expect(out.getPixel(15, 5).r, greaterThan(200));
      expect(out.getPixel(15, 5).b, lessThan(60));

      final mirrored = img.decodeJpg(await renderEdited(image, const PhotoEdits().mirrored()))!;
      expect(mirrored.getPixel(5, 15).b, greaterThan(200), reason: 'specchiata il blu va a sinistra');
      image.dispose();
    });
  });

  testWidgets('editor: ruota, aggiunge un testo e restituisce la foto modificata', (tester) async {
    Uint8List? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPhotoEditor(context, photo(40, 30));
              closed = true;
            },
            child: const Text('apri'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ruota'));
    await tester.pump();
    await tester.tap(find.text('1:1'));
    await tester.pump();
    await tester.tap(find.text('Testo'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Giorno 30');
    await tester.pump();
    expect(find.text('Ripristina'), findsOneWidget);

    await tester.tap(find.text('Fatto'));
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && !closed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    final out = img.decodeJpg(result!)!;
    expect((out.width, out.height), (30, 30));
  });

  testWidgets('chiuso senza confermare non restituisce niente', (tester) async {
    Uint8List? result = Uint8List(0);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showPhotoEditor(context, photo(20, 20)),
            child: const Text('apri'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
