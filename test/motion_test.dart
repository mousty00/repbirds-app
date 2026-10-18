import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymbro_app/core/widgets/motion.dart';

double _opacity(WidgetTester tester) {
  final o = find.ancestor(of: find.text('ciao'), matching: find.byType(Opacity));
  return o.evaluate().isEmpty ? 1 : tester.widget<Opacity>(o.first).opacity;
}

void main() {
  Widget app(Widget child, {bool reduced = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(body: child),
        ),
      );

  testWidgets('FadeInUp parte trasparente e finisce visibile', (tester) async {
    await tester.pumpWidget(app(const FadeInUp(index: 2, child: Text('ciao'))));
    expect(_opacity(tester), 0);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets('con le animazioni ridotte FadeInUp mostra subito il contenuto', (tester) async {
    await tester.pumpWidget(app(const FadeInUp(index: 2, child: Text('ciao')), reduced: true));
    expect(_opacity(tester), 1);
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('Pressable rimpicciolisce mentre è premuto e lascia passare il tocco', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(Center(
      child: Pressable(child: TextButton(onPressed: () => taps++, child: const Text('ciao'))),
    )));
    final gesture = await tester.startGesture(tester.getCenter(find.text('ciao')));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, lessThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(taps, 1);
  });
}
