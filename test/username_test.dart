import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/widgets/ui.dart';

void main() {
  test('username: maiuscole e spazi spariscono mentre scrivi', () {
    var v = TextEditingValue.empty;
    for (final f in usernameFormatters) {
      v = f.formatEditUpdate(v, const TextEditingValue(text: 'Mario Lifts', selection: TextSelection.collapsed(offset: 11)));
    }
    expect(v.text, 'mariolifts');
    expect(v.selection.end, 10);
  });
}
