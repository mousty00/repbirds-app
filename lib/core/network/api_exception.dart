import 'package:dio/dio.dart';

import '../l10n/l10n.dart';

/// Errore leggibile ricavato dall'`ErrorResponse` del backend
/// (`{timestamp, status, error, message, details}`).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.details = const {}, this.unreachable = false});

  final String message;
  final int? statusCode;
  final Map<String, String> details;

  bool get isUnauthorized => statusCode == 401;

  /// Nessuna risposta: server spento, URL sbagliato o rete assente.
  final bool unreachable;
  bool get isEmailNotVerified =>
      statusCode == 403 && message.toLowerCase().contains('not verified');

  /// Un caricamento che non è finito in tempo (rete lenta o server che non risponde).
  factory ApiException.uploadTimeout() => ApiException(
        tr('Il caricamento ci sta mettendo troppo. Controlla la connessione e riprova.'),
        unreachable: true,
      );

  factory ApiException.fromDio(Object error) {
    if (error is ApiException) return error;
    if (error is! DioException) {
      return ApiException(tr('Qualcosa è andato storto. Riprova.'));
    }
    final response = error.response;
    if (response == null) {
      return ApiException(
        tr('Impossibile raggiungere il server. Controlla la connessione.'),
        unreachable: true,
      );
    }
    final data = response.data;
    var message = tr('Errore {code}', {'code': response.statusCode ?? ''}).trim();
    final details = <String, String>{};
    if (data is Map) {
      final m = data['message'];
      if (m is String && m.isNotEmpty) message = m;
      final d = data['details'];
      if (d is Map) {
        d.forEach((k, v) => details['$k'] = '$v');
      }
    }
    if (details.isNotEmpty) {
      message = details.values.join('\n');
    }
    final status = response.statusCode ?? 0;
    if (status == 413) {
      message = tr('Il file è troppo grande.');
    } else if (status == 429) {
      // rate limit sulle rotte /auth (20 richieste al minuto per IP)
      message = tr('Troppi tentativi. Aspetta un minuto e riprova.');
    } else if (status >= 500 && details.isEmpty) {
      message = tr('Il server ha avuto un problema. Riprova tra poco.');
    }
    return ApiException(message, statusCode: response.statusCode, details: details);
  }

  @override
  String toString() => message;
}
