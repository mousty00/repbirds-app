/// Link pubblici da condividere fuori dall'app (WhatsApp, Telegram, …).
///
/// Puntano al sito: se l'app è installata il sistema la apre direttamente sulla
/// schermata giusta (App Links su Android, Universal Links su iOS, vedi
/// DEPLOY.md), altrimenti si apre la pagina web. Il dominio si cambia a build
/// time:
///
///   flutter run --dart-define=WEB_BASE_URL=https://staging.repbirds.com
class ShareLinks {
  const ShareLinks._();

  static const String webBaseUrl = String.fromEnvironment('WEB_BASE_URL', defaultValue: 'https://repbirds.com');

  /// `/w/<id>`: apre la scheda.
  static String workout(String id) => '$webBaseUrl/w/$id';

  /// `/r/<id>`: apre il percorso di corsa (pubblico: lo vedono gli amici dell'autore).
  static String route(String id) => '$webBaseUrl/r/$id';

  /// `/p/<id>`: apre il post.
  static String post(String id) => '$webBaseUrl/p/$id';

  /// `/u/<username>`: apre il profilo.
  static String profile(String username) => '$webBaseUrl/u/${Uri.encodeComponent(username)}';

  /// Pagine legali sul sito (non sono App/Universal Links: si aprono nel browser).
  static String get privacy => '$webBaseUrl/privacy';
  static String get terms => '$webBaseUrl/terms';

  /// Casella del supporto (vedi STORE_PRIVACY.md).
  static const supportEmail = 'support@repbirds.com';

  /// Email al supporto, già con l'oggetto.
  static String support(String subject) => Uri(scheme: 'mailto', path: supportEmail, queryParameters: {'subject': subject}).toString();
}
