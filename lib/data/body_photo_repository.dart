import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../models/body_photo.dart';
import '../models/json.dart';

/// Foto del fisico (`/body-photos`).
class BodyPhotoRepository {
  BodyPhotoRepository(this._api);

  final ApiClient _api;

  /// Le foto di un mese del calendario di [username]: tutte per il
  /// proprietario, solo le pubbliche per gli altri. Dalla più vecchia.
  Future<List<BodyPhoto>> month(String username, DateTime month) async {
    final from = monthOf(month);
    final to = DateTime(from.year, from.month + 1);
    final res = await _api.get<List<dynamic>>('/body-photos/user/${Uri.encodeComponent(username)}', query: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    });
    return parseList(res, BodyPhoto.fromJson)..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  }

  Future<BodyPhoto> upload({
    required List<int> imageBytes,
    required String imageName,
    required bool isPublic,
    bool asStory = false,
    String? workoutHistoryId,
  }) async {
    final form = FormData()..files.add(MapEntry('imageFile', MultipartFile.fromBytes(imageBytes, filename: imageName)));
    final res = await _api.post<Json>('/body-photos', data: form, query: {
      'isPublic': isPublic,
      if (asStory) 'asStory': true,
      'workoutHistoryId': ?workoutHistoryId,
    });
    return BodyPhoto.fromJson(Map<String, dynamic>.from(res['result'] as Map));
  }

  /// Le storie delle ultime 24 ore, mie e dei miei amici: prima le mie, poi le più recenti.
  Future<List<BodyStories>> stories() async =>
      parseList(await _api.get<List<dynamic>>('/body-photos/stories'), BodyStories.fromJson);

  Future<BodyPhoto> setVisibility(String id, bool isPublic) async =>
      BodyPhoto.fromJson(await _api.patch<Json>('/body-photos/$id/visibility', data: {'isPublic': isPublic}));

  /// Sostituisce l'immagine di una mia foto con quella modificata; la storia resta com'era (e scade quando doveva).
  Future<BodyPhoto> replaceImage(String id, List<int> imageBytes) async {
    final form = FormData()..files.add(MapEntry('imageFile', MultipartFile.fromBytes(imageBytes, filename: 'body.jpg')));
    return BodyPhoto.fromJson(await _api.put<Json>('/body-photos/$id/image', data: form));
  }

  Future<void> delete(String id) => _api.delete<dynamic>('/body-photos/$id');
}

final bodyPhotoRepositoryProvider =
    Provider<BodyPhotoRepository>((ref) => BodyPhotoRepository(ref.watch(apiClientProvider)));

/// La barra delle storie: io e i miei amici.
final bodyStoriesProvider = FutureProvider.autoDispose<List<BodyStories>>(
  (ref) => ref.watch(bodyPhotoRepositoryProvider).stories(),
);

/// Un mese del calendario di un utente.
final bodyPhotosProvider = FutureProvider.autoDispose.family<List<BodyPhoto>, ({String username, DateTime month})>(
  (ref, k) => ref.watch(bodyPhotoRepositoryProvider).month(k.username, k.month),
);
