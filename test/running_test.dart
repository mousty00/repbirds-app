import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/features/running/geo.dart';
import 'package:repbirds_app/features/running/run_recorder.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('geo', () {
    test('formati di distanza, passo e tempo', () {
      expect(formatDistance(850), '850 m');
      expect(formatDistance(5234), '5,23 km');
      expect(formatPace(330), "5'30\"");
      expect(formatPace(null), '–');
      expect(formatSeconds(65), '01:05');
      expect(formatSeconds(3725), '1:02:05');
    });

    test('distanza dalla linea del percorso', () {
      const line = [LatLng(45.0, 9.0), LatLng(45.0, 9.01)];
      expect(distanceToLine(const LatLng(45.0, 9.005), line), lessThan(1));
      // 0,0005° di latitudine ≈ 55 m a nord della linea
      expect(distanceToLine(const LatLng(45.0005, 9.005), line), closeTo(55.6, 1));
      // oltre la fine: distanza dall'ultimo punto
      expect(distanceToLine(const LatLng(45.0, 9.011), line), closeTo(78.7, 1.5));
    });
  });

  group('RunRecorder', () {
    final t0 = DateTime(2026, 10, 13, 7);
    // ~11 m verso est ogni 4 s: circa 6'00"/km
    Fix at(int i, {double accuracy = 5, double lat = 45.0}) =>
        Fix(LatLng(lat, 9.0 + i * 0.00014), time: t0.add(Duration(seconds: i * 4)), accuracy: accuracy);

    test('somma la distanza e calcola il passo', () {
      final r = RunRecorder()..start(t0);
      for (var i = 0; i <= 50; i++) {
        r.add(at(i));
      }
      expect(r.distance, closeTo(550, 10));
      expect(r.track, hasLength(51));
      expect(r.track.last[3], 200);
      final end = t0.add(const Duration(seconds: 200));
      expect(r.averagePace(end), closeTo(363, 10));
      expect(r.currentPace(), closeTo(363, 10));
    });

    test('scarta posizioni imprecise, salti del GPS e rumore da fermi', () {
      final r = RunRecorder()..start(t0);
      r.add(at(0));
      expect(r.add(at(1, accuracy: 80)), isFalse);
      // 1 km in 4 secondi: impossibile di corsa
      expect(r.add(Fix(const LatLng(45.009, 9.0), time: t0.add(const Duration(seconds: 4)))), isFalse);
      // 1 m: rumore
      expect(r.add(Fix(const LatLng(45.00001, 9.0), time: t0.add(const Duration(seconds: 5)))), isFalse);
      expect(r.distance, 0);
    });

    test('le pause non contano né nel tempo né nella distanza', () {
      final r = RunRecorder()..start(t0);
      r.add(at(0));
      r.add(at(10));
      r.pause(t0.add(const Duration(seconds: 40)));
      expect(r.add(at(20)), isFalse);
      r.resume(t0.add(const Duration(seconds: 100)));
      r.add(at(30)); // riparte da qui, il tratto 10 → 30 fatto in pausa non conta
      r.add(at(40));
      expect(r.movingTime(t0.add(const Duration(seconds: 160))).inSeconds, 100);
      expect(r.distance, closeTo(2 * 110, 5));
    });

    test('fuori percorso dopo tre posizioni lontane dalla linea', () {
      final r = RunRecorder(route: const [LatLng(45.0, 9.0), LatLng(45.0, 9.02)])..start(t0);
      r.add(at(0));
      r.add(at(1));
      expect(r.isOffRoute, isFalse);
      for (var i = 2; i < 5; i++) {
        r.add(at(i, lat: 45.001)); // ~111 m a nord
      }
      expect(r.isOffRoute, isTrue);
      expect(r.distanceFromRoute, closeTo(111, 2));
      r.add(at(5));
      expect(r.isOffRoute, isFalse);
    });
  });
}
