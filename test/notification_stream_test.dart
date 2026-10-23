import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/widgets/ui.dart';
import 'package:repbirds_app/data/notification_stream.dart';

void main() {
  test('SSE: eventi con nome e dati, commenti scartati, anche se spezzati a metà', () async {
    const raw = ': ping\n\n'
        'event:unread-count\ndata:{"count":3}\n\n'
        'event: notification\ndata: {"notification":{"id":"n1"},\ndata: "unreadCount":4}\n\n'
        'data:senza nome\n\n';
    final bytes = utf8.encode(raw);
    // a pezzi, come arrivano dalla rete
    final chunks = Stream.fromIterable([bytes.sublist(0, 20), bytes.sublist(20, 50), bytes.sublist(50)]);

    final events = await parseSse(chunks).toList();

    expect(events, [
      (event: 'unread-count', data: '{"count":3}'),
      (event: 'notification', data: '{"notification":{"id":"n1"},\n"unreadCount":4}'),
      (event: 'message', data: 'senza nome'),
    ]);
  });

  testWidgets('la campanella mostra quante notifiche non sono lette', (tester) async {
    Future<void> pump(int badge) => tester.pumpWidget(MaterialApp(
          home: Center(child: CircleIconButton(icon: Icons.notifications_none_rounded, badge: badge)),
        ));

    await pump(0);
    expect(find.byType(CountBadge), findsNothing);

    await pump(3);
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    await pump(120);
    await tester.pumpAndSettle();
    expect(find.text('99+'), findsOneWidget);
  });
}
