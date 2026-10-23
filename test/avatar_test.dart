import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/widgets/ui.dart';

void main() {
  Future<Size> imageSize(WidgetTester tester, {required bool ring}) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Center(
          child: UserAvatar(username: 'mousty', imageUrl: 'asset:assets/mock/post1.jpg', size: 100, ring: ring),
        ),
      ),
    ));
    return tester.getSize(find.byType(Image));
  }

  testWidgets('la foto profilo riempie tutto il cerchio', (tester) async {
    expect(await imageSize(tester, ring: false), const Size(100, 100));
    // con l'anello: 100 - 2 * (3 + 2.5)
    expect(await imageSize(tester, ring: true), const Size(89, 89));
    expect(find.byType(ClipOval), findsOneWidget);
  });
}
