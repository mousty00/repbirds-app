import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../models/json.dart';
import '../models/user.dart';

/// Endpoint `/users/**`.
class UserRepository {
  UserRepository(this._api);

  final ApiClient _api;

  Future<List<SimpleUser>> search(String username) async {
    final res = await _api.get<List<dynamic>>('/users/search', query: {'username': username.trim().toLowerCase()});
    return parseList(res, SimpleUser.fromJson);
  }

  Future<User> byUsername(String username) async =>
      User.fromJson(await _api.get<Json>('/users/username/${Uri.encodeComponent(username)}'));

  Future<UserOverview> overview(String username) async =>
      UserOverview.fromJson(await _api.get<Json>('/users/username/${Uri.encodeComponent(username)}/overview'));

  Future<User> byId(String id) async => User.fromJson(await _api.get<Json>('/users/$id'));

  Future<void> updateProfileImage(List<int> bytes, String filename) async {
    final form = FormData.fromMap({
      'imageFile': MultipartFile.fromBytes(bytes, filename: filename),
    });
    await _api.put<dynamic>('/users/update-profile-image', data: form);
  }

  Future<void> deleteMe() => _api.delete<dynamic>('/users/me');

  /// `type`: POST, COMMENT o USER. Le segnalazioni arrivano via mail al moderatore.
  Future<void> report({required String type, required String targetId, String? reason}) =>
      _api.post<dynamic>('/reports', data: {'type': type, 'targetId': targetId, 'reason': reason});

  /// Problema dell'app (non di un contenuto), con fino a 5 screenshot. Arriva via mail al team.
  Future<void> reportBug({
    required String description,
    String? device,
    List<({List<int> bytes, String name})> images = const [],
  }) async {
    final form = FormData.fromMap({
      'description': description,
      'device': ?device,
    });
    for (final image in images) {
      form.files.add(MapEntry('images', MultipartFile.fromBytes(image.bytes, filename: image.name)));
    }
    await _api.post<dynamic>('/bug-reports', data: form);
  }
}

final userRepositoryProvider =
    Provider<UserRepository>((ref) => UserRepository(ref.watch(apiClientProvider)));
