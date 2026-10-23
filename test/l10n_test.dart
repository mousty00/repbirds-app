import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/l10n/en.dart';
import 'package:repbirds_app/core/l10n/es.dart';
import 'package:repbirds_app/core/l10n/fr.dart';
import 'package:repbirds_app/core/l10n/l10n.dart';

/// Tutti i testi passati a tr() nel codice, come stringhe.
Set<String> sourceKeys() {
  final re = RegExp(r"(?<![\w.])tr\(\s*'((?:[^'\\]|\\.)*)'");
  String unescape(String s) =>
      s.replaceAllMapped(RegExp(r'\\(.)'), (m) => switch (m[1]) { 'n' => '\n', final c! => c });
  return {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart') && !f.path.contains('/l10n/'))
        for (final m in re.allMatches(f.readAsStringSync())) unescape(m[1]!),
  };
}

Set<String> placeholders(String s) => {for (final m in RegExp(r'\{(\w+)\}').allMatches(s)) m[1]!};

void main() {
  final keys = sourceKeys();

  test('il codice usa dei testi tradotti', () => expect(keys.length, greaterThan(100)));

  for (final (name, map) in [('en', en), ('fr', fr), ('es', es)]) {
    test('$name: ogni testo è tradotto, con gli stessi segnaposto', () {
      expect(keys.where((k) => (map[k] ?? '').isEmpty).toList(), isEmpty, reason: 'testi senza traduzione');
      for (final k in keys) {
        expect(placeholders(map[k]!), placeholders(k), reason: k);
      }
    });
  }

  test('tr() riempie i segnaposto e torna all\'inglese se manca la lingua', () {
    addTearDown(() => L10n.lang = 'it');
    expect(tr('{n} min', {'n': 5}), '5 min');
    L10n.lang = 'de';
    final k = keys.firstWhere((k) => en[k] != null && en[k] != k);
    expect(tr(k), en[k]);
  });

  test('lingua del dispositivo non supportata: inglese', () {
    expect(L10n.resolve(const Locale('de'), const []), const Locale('en'));
    expect(L10n.resolve(const Locale('fr', 'CA'), const []), const Locale('fr'));
  });
}
