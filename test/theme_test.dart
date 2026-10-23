import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repbirds_app/core/theme/app_theme.dart';

/// Widget const che legge AppColors senza dipendere dal Theme: è il caso che
/// AppThemeSync deve ridisegnare quando cambia il tema del dispositivo.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) => ColoredBox(color: AppColors.bg, child: const SizedBox.expand());
}

Color _probeColor(WidgetTester tester) =>
    tester.widget<ColoredBox>(find.descendant(of: find.byType(_Probe), matching: find.byType(ColoredBox))).color;

void main() {
  Widget app() => MaterialApp(
        themeMode: ThemeMode.system,
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        builder: (context, child) => AppThemeSync(child: child!),
        home: const _Probe(),
      );

  tearDown(() => AppColors.use(AppPalette.light));

  testWidgets("all'avvio segue il tema scuro del dispositivo", (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(app());

    expect(AppColors.isDark, isTrue);
    expect(_probeColor(tester), AppPalette.dark.bg);
  });

  testWidgets("all'avvio segue il tema chiaro del dispositivo", (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(app());

    expect(AppColors.isDark, isFalse);
    expect(_probeColor(tester), AppPalette.light.bg);
  });

  testWidgets("cambia tema con l'app aperta, anche nei widget const", (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(app());
    expect(_probeColor(tester), AppPalette.light.bg);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(_probeColor(tester), AppPalette.dark.bg);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(_probeColor(tester), AppPalette.light.bg);
  });
}
