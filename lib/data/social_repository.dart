import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env.dart';
import '../core/network/api_client.dart';
import '../models/json.dart';
import '../models/page.dart';
import '../models/social.dart';

/// Post, like, commenti (`/posts`, `/likes`, `/comments`).
class PostRepository {
  PostRepository(this._api);

  final ApiClient _api;

  Future<PageResult<Post>> all({int page = 0}) async {
    final res = await _api.get<Json>('/posts', query: {
      'page': page,
      'size': Env.pageSize,
      'sort': 'createdAt,desc',
    });
    return PageResult.fromJson(res, Post.fromJson);
  }

  Future<List<Post>> friendsPosts() async {
    final res = await _api.get<List<dynamic>>('/friendship/posts');
    return parseList(res, Post.fromJson)..sort(_newestFirst);
  }

  Future<List<Post>> byUser(String username) async {
    final res = await _api.get<List<dynamic>>('/posts/user', query: {'username': username});
    return parseList(res, Post.fromJson)..sort(_newestFirst);
  }

  Future<Post> byId(String id) async => Post.fromJson(await _api.get<Json>('/posts/$id'));

  /// `POST /posts/create` è multipart: parte JSON `request` + parte `imageFile`
  /// (obbligatoria lato backend).
  Future<Post> create({
    required String userId,
    required String content,
    required List<int> imageBytes,
    required String imageName,
  }) async {
    final form = FormData();
    form.files
      ..add(MapEntry(
        'request',
        MultipartFile.fromString(
          jsonEncode({'userId': userId, 'content': content}),
          contentType: DioMediaType('application', 'json'),
        ),
      ))
      ..add(MapEntry('imageFile', MultipartFile.fromBytes(imageBytes, filename: imageName)));
    final res = await _api.post<Json>('/posts/create', data: form);
    return Post.fromJson(Map<String, dynamic>.from(res['result'] as Map));
  }

  Future<void> update({required String id, required String content}) =>
      _api.put<dynamic>('/posts/update', data: {'id': id, 'content': content});

  Future<void> delete(String id) => _api.delete<dynamic>('/posts/delete/$id');

  Future<SimpleLike> like({required String postId, required String userId}) async {
    final res = await _api.post<Json>('/likes/create', data: {'postId': postId, 'userId': userId});
    return SimpleLike.fromLikeJson(res);
  }

  Future<void> unlike(String likeId) => _api.delete<dynamic>('/likes/delete/$likeId');

  Future<SimpleComment> comment({required String postId, required String content}) async {
    final res =
        await _api.post<Json>('/comments/create', data: {'postId': postId, 'content': content});
    return SimpleComment.fromCommentJson(Map<String, dynamic>.from(res['result'] as Map));
  }

  Future<void> deleteComment(String id) => _api.delete<dynamic>('/comments/$id');

  static int _newestFirst(Post a, Post b) =>
      (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
}

/// Amicizie (`/friendship/**`).
class FriendshipRepository {
  FriendshipRepository(this._api);

  final ApiClient _api;

  Future<List<Friendship>> all() async {
    final res = await _api.get<Json>('/friendship', query: {'page': 0, 'size': 100});
    return PageResult.fromJson(res, Friendship.fromJson).results;
  }

  Future<List<Friendship>> pendingRequests() async =>
      parseList(await _api.get<List<dynamic>>('/friendship/requests'), Friendship.fromJson);

  /// Richieste inviate da me e non ancora accettate.
  Future<List<Friendship>> sentRequests() async =>
      parseList(await _api.get<List<dynamic>>('/friendship/sent'), Friendship.fromJson);

  Future<void> add(String friendUsername) =>
      _api.post<dynamic>('/friendship/create', query: {'friendUsername': friendUsername});

  /// Ritira una richiesta inviata ancora in attesa.
  Future<void> cancel(String id) => _api.delete<dynamic>('/friendship/cancel/$id');

  Future<void> accept(String id) => _api.get<dynamic>('/friendship/accept/$id');

  Future<void> reject(String id) => _api.get<dynamic>('/friendship/reject/$id');

  Future<void> block(String id) => _api.get<dynamic>('/friendship/block/$id');

  /// Blocca chiunque, amico o no: post, commenti e notifiche spariscono in entrambe le direzioni.
  Future<void> blockUser(String username) =>
      _api.post<dynamic>('/friendship/block-user', query: {'username': username});
}

final postRepositoryProvider =
    Provider<PostRepository>((ref) => PostRepository(ref.watch(apiClientProvider)));

final friendshipRepositoryProvider =
    Provider<FriendshipRepository>((ref) => FriendshipRepository(ref.watch(apiClientProvider)));
