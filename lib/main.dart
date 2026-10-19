import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/l10n/l10n.dart';
import 'core/push/push_service.dart';
import 'core/router/app_router.dart';
import 'core/sound/sounds.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';
import 'features/auth/session.dart';
import 'features/onboarding/guide_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await LanguageNotifier.load();
  await SoundNotifier.load();
  await ThemeNotifier.load();
  await GuideNotifier.load();

  final container = ProviderContainer();
  final push = container.read(pushServiceProvider);
  push.init();
  // Registra il dispositivo per le push a ogni login (e all'avvio con sessione valida).
  container.listen(sessionProvider, (previous, next) {
    final user = next.value;
    if (user != null && previous?.value?.id != user.id) push.onLogin();
  }, fireImmediately: true);

  runApp(UncontrolledProviderScope(container: container, child: const RepBirdsApp()));
}

class RepBirdsApp extends ConsumerWidget {
  const RepBirdsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final custom = theme.custom?.palette;
    return MaterialApp.router(
      title: 'RepBirds',
      debugShowCheckedModeBanner: false,
      // Di base segue il tema del dispositivo; si cambia dal profilo.
      // Un tema personalizzato sostituisce il chiaro o lo scuro, secondo la sua base.
      themeMode: theme.themeMode,
      theme: buildAppTheme(custom != null && !theme.custom!.dark ? custom : AppPalette.light),
      darkTheme: buildAppTheme(custom != null && theme.custom!.dark ? custom : AppPalette.dark),
      builder: (context, child) => AppThemeSync(custom: custom, child: child!),
      routerConfig: ref.watch(routerProvider),
      scaffoldMessengerKey: scaffoldMessengerKey,
      // Di base la lingua del dispositivo (inglese se non supportata); si cambia dal profilo.
      locale: switch (ref.watch(languageProvider)) {
        final lang? => Locale(lang),
        null => null,
      },
      supportedLocales: L10n.locales,
      localeResolutionCallback: L10n.resolve,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
