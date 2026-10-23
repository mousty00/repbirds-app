import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/network/api_exception.dart';
import 'package:repbirds_app/data/providers.dart';
import 'package:repbirds_app/data/social_repository.dart';
import 'package:repbirds_app/features/auth/session.dart';
import 'package:repbirds_app/features/feed/post_card.dart';
import 'package:repbirds_app/features/friends/friends_screen.dart';
import 'package:repbirds_app/models/social.dart';
import 'package:repbirds_app/models/user.dart';

const _me = User(id: 'u1', username: 'mousty');
const _meSimple = SimpleUser(id: 'u1', username: 'mousty');
const _giulia = SimpleUser(id: 'u2', username: 'giulia.fit');

/// Server finto: tiene le richieste inviate e i like come il backend vero
/// (duplicati → 409, già tolti → 404).
class _FakeFriendships implements FriendshipRepository {
  final sent = <Friendship>[];
  int adds = 0;
  int cancels = 0;

  @override
  Future<List<Friendship>> sentRequests() async => List.of(sent);

  @override
  Future<void> add(String friendUsername) async {
    adds++;
    if (sent.any((f) => f.friend.username == friendUsername)) {
      throw ApiException('Users are already friends or a request is pending', statusCode: 409);
    }
    sent.add(Friendship(id: 'f$adds', user: _meSimple, friend: _giulia, status: FriendshipStatus.pending));
  }

  @override
  Future<void> cancel(String id) async {
    cancels++;
    final before = sent.length;
    sent.removeWhere((f) => f.id == id);
    if (sent.length == before) throw ApiException('Friend request not found', statusCode: 404);
  }

  @override
  Future<List<Friendship>> all() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosts implements PostRepository {
  _FakePosts(this.post);

  Post post;

  @override
  Future<SimpleLike> like({required String postId, required String userId}) async {
    if (post.likeBy('mousty') != null) throw ApiException('User has already liked this post', statusCode: 409);
    const like = SimpleLike(id: 'l-new', username: 'mousty');
    post = post.copyWith(likes: [...post.likes, like], numLikes: post.numLikes + 1);
    return like;
  }

  @override
  Future<void> unlike(String likeId) async {
    if (!post.likes.any((l) => l.id == likeId)) throw ApiException('Like not found', statusCode: 404);
    post = post.copyWith(likes: post.likes.where((l) => l.id != likeId).toList(), numLikes: post.numLikes - 1);
  }

  @override
  Future<Post> byId(String id) async => post;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child, List overrides) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_me),
        userKeyProvider.overrideWithValue('u1'),
        ...overrides.cast(),
      ],
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

Post _post({List<SimpleLike> likes = const []}) => Post(
      id: 'p1',
      user: const User(id: 'u2', username: 'giulia.fit'),
      content: 'Squat',
      likes: likes,
      numLikes: likes.length,
    );

void main() {
  group('AddFriendButton', () {
    testWidgets('una richiesta già inviata si vede subito e un tap la ritira', (tester) async {
      final repo = _FakeFriendships()
        ..sent.add(const Friendship(id: 'f0', user: _meSimple, friend: _giulia, status: FriendshipStatus.pending));
      await tester.pumpWidget(_app(const AddFriendButton(username: 'giulia.fit'), [
        friendshipRepositoryProvider.overrideWithValue(repo),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Inviata'), findsOneWidget);

      await tester.tap(find.text('Inviata'));
      await tester.pumpAndSettle();

      expect(repo.cancels, 1);
      expect(repo.adds, 0);
      expect(repo.sent, isEmpty);
      expect(find.text('Aggiungi'), findsOneWidget);
    });

    testWidgets('invia, poi un secondo tap annulla invece di reinviare', (tester) async {
      final repo = _FakeFriendships();
      await tester.pumpWidget(_app(const AddFriendButton(username: 'giulia.fit', large: true), [
        friendshipRepositoryProvider.overrideWithValue(repo),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aggiungi agli amici'));
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(1));
      expect(find.text('Richiesta inviata · Annulla'), findsOneWidget);

      await tester.tap(find.text('Richiesta inviata · Annulla'));
      await tester.pumpAndSettle();
      expect(repo.adds, 1);
      expect(repo.cancels, 1);
      expect(repo.sent, isEmpty);
      expect(find.text('Aggiungi agli amici'), findsOneWidget);
    });
  });

  group('PostCard like', () {
    testWidgets('un like già messo: il tap lo toglie', (tester) async {
      final repo = _FakePosts(_post(likes: const [SimpleLike(id: 'l1', username: 'mousty')]));
      await tester.pumpWidget(_app(PostCard(post: repo.post, openOnTap: false), [
        postRepositoryProvider.overrideWithValue(repo),
      ]));

      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pumpAndSettle();

      expect(repo.post.likes, isEmpty);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('copia vecchia del post (like già messo altrove): niente errore, si mostra lo stato vero',
        (tester) async {
      final repo = _FakePosts(_post(likes: const [SimpleLike(id: 'l1', username: 'mousty')]));
      // la card ha il post di prima del like
      await tester.pumpWidget(_app(PostCard(post: _post(), openOnTap: false), [
        postRepositoryProvider.overrideWithValue(repo),
      ]));

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // e ora il tap lo toglie davvero
      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pumpAndSettle();
      expect(repo.post.likes, isEmpty);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });
  });
}
