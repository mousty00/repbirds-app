import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../mock/mock_backend.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Client HTTP verso repbirds-api.
///
/// - aggiunge `Authorization: Bearer <token>` a ogni richiesta;
/// - su 401 prova una volta `POST /auth/refresh` con il refresh token
///   (che il backend ruota) e ripete la richiesta;
/// - se il refresh fallisce emette su [sessionExpired] così l'app torna al login.
class ApiClient {
  ApiClient(this._tokens, {String? baseUrl})
      : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? Env.apiBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Accept': 'application/json'},
          ),
        ) {
    _refreshDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
    dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: _onRequest,
        onError: _onError,
      ),
    );
    // Modalità mock: con Env.useMock le richieste non escono dal dispositivo.
    dio.interceptors.add(MockBackend());
  }

  final TokenStorage _tokens;
  final Dio dio;
  late final Dio _refreshDio;

  final _sessionExpired = StreamController<void>.broadcast();
  Stream<void> get sessionExpired => _sessionExpired.stream;

  static const _retriedKey = 'repbirds.retried';

  static bool _isAuthPath(String path) =>
      path.startsWith('/auth/') && !path.startsWith('/auth/profile');

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isAuthPath(options.path)) {
      final token = await _tokens.accessToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final unauthorized = err.response?.statusCode == 401;
    if (!unauthorized || _isAuthPath(options.path) || options.extra[_retriedKey] == true) {
      return handler.next(err);
    }

    final refresh = await _tokens.refreshToken;
    if (refresh == null) {
      _sessionExpired.add(null);
      return handler.next(err);
    }

    // Se un'altra richiesta in coda ha già rinnovato il token, riusalo.
    final current = await _tokens.accessToken;
    final sent = options.headers['Authorization'];
    if (current != null && sent != 'Bearer $current') {
      await _retry(options, current, handler, err);
      return;
    }

    try {
      final res = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refresh},
      );
      final access = res.data?['token'] as String?;
      final newRefresh = res.data?['refreshToken'] as String?;
      if (access == null || newRefresh == null) throw StateError('no token');
      await _tokens.save(access: access, refresh: newRefresh);
      await _retry(options, access, handler, err);
      return;
    } on DioException catch (e) {
      // Senza risposta (rete assente, timeout) il refresh token è ancora valido:
      // non buttare via la sessione, la prossima richiesta riproverà.
      if (e.response == null) return handler.next(err);
      await _tokens.clear();
      _sessionExpired.add(null);
      return handler.next(err);
    } catch (_) {
      await _tokens.clear();
      _sessionExpired.add(null);
      return handler.next(err);
    }
  }

  Future<void> _retry(
    RequestOptions options,
    String token,
    ErrorInterceptorHandler handler,
    DioException original,
  ) async {
    options.headers['Authorization'] = 'Bearer $token';
    options.extra[_retriedKey] = true;
    try {
      final response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    } catch (_) {
      handler.next(original);
    }
  }

  // Helper tipizzati: convertono ogni errore in ApiException.

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get<T>(path, queryParameters: query));

  Future<T> post<T>(String path, {Object? data, Map<String, dynamic>? query}) =>
      _wrap(() => dio.post<T>(path, data: data, queryParameters: query));

  Future<T> put<T>(String path, {Object? data, Map<String, dynamic>? query}) =>
      _wrap(() => dio.put<T>(path, data: data, queryParameters: query));

  Future<T> patch<T>(String path, {Object? data, Map<String, dynamic>? query}) =>
      _wrap(() => dio.patch<T>(path, data: data, queryParameters: query));

  Future<T> delete<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.delete<T>(path, queryParameters: query));

  Future<T> _wrap<T>(Future<Response<T>> Function() call) async {
    try {
      final res = await call();
      return res.data as T;
    } catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  void dispose() => _sessionExpired.close();
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(ref.watch(tokenStorageProvider));
  ref.onDispose(client.dispose);
  return client;
});
