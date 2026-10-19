import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env.dart';
import '../core/network/api_client.dart';
import '../models/json.dart';
import '../models/notification.dart';
import '../models/page.dart';

/// Endpoint `/notifications` e `/devices` (token per le push).
class NotificationRepository {
  NotificationRepository(this._api);

  final ApiClient _api;

  Future<PageResult<AppNotification>> all({int page = 0}) async {
    final res = await _api.get<Json>('/notifications', query: {'page': page, 'size': Env.pageSize});
    return PageResult.fromJson(res, AppNotification.fromJson);
  }

  Future<int> unreadCount() async =>
      parseInt((await _api.get<Json>('/notifications/unread-count'))['count']);

  Future<void> markRead(String id) => _api.post<dynamic>('/notifications/$id/read');

  Future<void> markAllRead() => _api.post<dynamic>('/notifications/read-all');

  /// Toglie la notifica dalla lista (per sempre).
  Future<void> delete(String id) => _api.delete<dynamic>('/notifications/$id');

  /// Svuota la lista.
  Future<void> deleteAll() => _api.delete<dynamic>('/notifications');

  /// [platform]: `ANDROID` o `IOS`.
  Future<void> registerDevice(String token, String platform) =>
      _api.post<dynamic>('/devices', data: {'token': token, 'platform': platform});

  Future<void> unregisterDevice(String token) =>
      _api.delete<dynamic>('/devices', query: {'token': token});
}

final notificationRepositoryProvider =
    Provider<NotificationRepository>((ref) => NotificationRepository(ref.watch(apiClientProvider)));
