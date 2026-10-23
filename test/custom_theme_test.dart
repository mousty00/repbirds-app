import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/theme/theme_mode.dart';

void main() {
  test('un tema personalizzato si salva, si rilegge e vince sulla scelta chiaro/scuro', () {
    final t = CustomTheme(id: '1', name: 'Notte', dark: true, accent: const Color(0xFFF97316), bg: const Color(0xFF000000));
    final back = CustomTheme.fromJson(t.toJson());
    expect((back.name, back.dark, back.accent, back.bg), ('Notte', true, t.accent, t.bg));
    expect(back.palette.accent, t.accent);
    expect(back.palette.brightness, Brightness.dark);

    final choice = ThemeChoice(mode: ThemeMode.light, customId: '1', themes: [back]);
    expect(choice.themeMode, ThemeMode.dark);
    expect(ThemeChoice(mode: ThemeMode.light, customId: 'altro', themes: [back]).themeMode, ThemeMode.light);
  });
}
