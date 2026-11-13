import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/session.dart';
import 'app_theme.dart';

/// Un tema creato dall'utente: base chiara o scura, accento e sfondo.
class CustomTheme {
  CustomTheme({required this.id, required this.name, required this.dark, required this.accent, required this.bg});

  final String id;
  final String name;
  final bool dark;
  final Color accent;
  final Color bg;

  /// Una sola istanza per tema: AppThemeSync ridisegna tutto quando cambia.
  late final AppPalette palette = AppPalette.custom(dark: dark, accent: accent, bg: bg);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'dark': dark, 'accent': accent.toARGB32(), 'bg': bg.toARGB32()};

  factory CustomTheme.fromJson(Map<String, dynamic> j) => CustomTheme(
        id: '${j['id']}',
        name: '${j['name']}',
        dark: j['dark'] == true,
        accent: Color((j['accent'] as num).toInt()),
        bg: Color((j['bg'] as num).toInt()),
      );
}

/// Tema scelto (dispositivo, chiaro, scuro o uno personalizzato) e i temi
/// personalizzati dell'utente.
class ThemeChoice {
  const ThemeChoice({this.mode = ThemeMode.system, this.customId, this.themes = const []});

  final ThemeMode mode;

  /// Id del tema personalizzato attivo; vince su [mode].
  final String? customId;
  final List<CustomTheme> themes;

  CustomTheme? get custom => themes.where((t) => t.id == customId).firstOrNull;

  ThemeMode get themeMode => switch (custom) {
        final c? => c.dark ? ThemeMode.dark : ThemeMode.light,
        null => mode,
      };
}

/// Salvato sul telefono. I temi personalizzati sono di ciascun utente:
/// chi entra con un altro account sullo stesso telefono non li vede.
class ThemeNotifier extends Notifier<ThemeChoice> {
  static const _modeKey = 'repbirds.theme';
  static const _storage = FlutterSecureStorage();

  /// Letto in main() prima di avviare l'app.
  static ThemeChoice saved = const ThemeChoice();

  static String _themesKey(String username) => 'repbirds.themes.$username';

  /// Scelta e temi dell'ultimo utente, per partire già col tema giusto.
  static Future<void> load() async {
    try {
      final raw = await _storage.read(key: _modeKey);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final user = j['user'] as String?;
      saved = ThemeChoice(
        mode: ThemeMode.values.asNameMap()[j['mode']] ?? ThemeMode.system,
        customId: j['custom'] as String?,
        themes: user == null ? const [] : await _readThemes(user),
      );
    } catch (_) {}
  }

  static Future<List<CustomTheme>> _readThemes(String username) async {
    final raw = await _storage.read(key: _themesKey(username));
    if (raw == null) return const [];
    return [for (final t in jsonDecode(raw) as List) CustomTheme.fromJson(t as Map<String, dynamic>)];
  }

  String? get _user => ref.read(sessionProvider).value?.username;

  @override
  ThemeChoice build() {
    // Cambia utente: si ricaricano i suoi temi.
    ref.listen(sessionProvider.select((s) => s.value?.username), (previous, next) async {
      if (previous == next) return;
      final themes = next == null ? const <CustomTheme>[] : await _readThemes(next).catchError((_) => <CustomTheme>[]);
      final keep = themes.any((t) => t.id == state.customId);
      state = ThemeChoice(mode: state.mode, customId: keep ? state.customId : null, themes: themes);
    });
    return saved;
  }

  Future<void> _save(ThemeChoice choice) async {
    state = saved = choice;
    try {
      final user = _user;
      await _storage.write(
        key: _modeKey,
        value: jsonEncode({'mode': choice.mode.name, 'custom': choice.customId, 'user': user}),
      );
      if (user != null) {
        await _storage.write(key: _themesKey(user), value: jsonEncode([for (final t in choice.themes) t.toJson()]));
      }
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode mode) => _save(ThemeChoice(mode: mode, themes: state.themes));

  Future<void> apply(String id) => _save(ThemeChoice(mode: state.mode, customId: id, themes: state.themes));

  /// Crea o aggiorna un tema e lo applica.
  Future<void> saveTheme(CustomTheme theme) => _save(ThemeChoice(
        mode: state.mode,
        customId: theme.id,
        themes: state.themes.any((t) => t.id == theme.id)
            ? [for (final t in state.themes) t.id == theme.id ? theme : t]
            : [...state.themes, theme],
      ));

  Future<void> delete(String id) => _save(ThemeChoice(
        mode: state.mode,
        customId: state.customId == id ? null : state.customId,
        themes: [for (final t in state.themes) if (t.id != id) t],
      ));
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeChoice>(ThemeNotifier.new);
