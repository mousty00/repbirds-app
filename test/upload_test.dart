import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/network/api_client.dart';
import 'package:repbirds_app/core/network/api_exception.dart';
import 'package:repbirds_app/core/storage/token_storage.dart';

/// Token in memoria: niente keychain nei test.
class _Tokens extends TokenStorage {
  String? access = 'old';

  @override
  Future<String?> get accessToken async => access;

  @override
  Future<String?> get refreshToken async => 'refresh';
}

/// Risponde con [handle] e conta le richieste; legge sempre tutto il corpo, come la rete.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);

  final Future<ResponseBody> Function(RequestOptions options, int call) handle;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (requestStream != null) await requestStream.drain<void>();
    return handle(options, ++calls);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

FormData _photo() => FormData()..files.add(MapEntry('imageFile', MultipartFile.fromBytes([1, 2, 3], filename: 'body.jpg')));

void main() {
  test('un upload rifiutato col token scaduto si ripete col token nuovo, senza "FormData already finalized"', () async {
    final tokens = _Tokens();
    final api = ApiClient(tokens, baseUrl: 'http://api.test');
    final adapter = _Adapter((options, call) async {
      if (call == 1) {
        // un'altra richiesta ha già rinnovato il token mentre questa era in volo
        tokens.access = 'new';
        return _json(401, {'message': 'expired'});
      }
      expect(options.headers['Authorization'], 'Bearer new');
      return _json(201, {'result': {'id': 'p1'}});
    });
    api.dio.httpClientAdapter = adapter;

    final res = await api.post<Map<String, dynamic>>('/body-photos', data: _photo());

    expect(res['result'], {'id': 'p1'});
    expect(adapter.calls, 2);
  });

  test('una foto troppo grande dice perché', () async {
    final api = ApiClient(_Tokens(), baseUrl: 'http://api.test');
    api.dio.httpClientAdapter = _Adapter((_, _) async => _json(413, {'message': 'The file is too large: at most 10MB'}));

    await expectLater(
      api.post<dynamic>('/body-photos', data: _photo()),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 413)),
    );
  });

  test('un upload che non finisce in tempo viene annullato con un errore, non resta appeso', () async {
    final api = ApiClient(_Tokens(), baseUrl: 'http://api.test');
    api.dio.httpClientAdapter = _Adapter((options, _) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.sendTimeout,
        ));

    await expectLater(
      api.post<dynamic>('/body-photos', data: _photo()),
      throwsA(isA<ApiException>().having((e) => e.unreachable, 'unreachable', true)),
    );
  });
}
