import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/l10n.dart';

/// Colori fissi del tema chiaro. Servono anche dove il colore non deve
/// seguire il tema del dispositivo (le card da condividere come immagine).
abstract final class LightColors {
  static const ink = Color(0xFF111322);
  static const inkSoft = Color(0xFF5B6075);
  static const muted = Color(0xFF9A9FB2);
  static const bg = Color(0xFFF3F5FA);
  static const card = Colors.white;
  static const stroke = Color(0xFFE9ECF3);
  static const onInk = Colors.white;

  static const blue = AppColors.blue;
  static const blueSoft = Color(0xFFE3EBFE);
  static const lilac = AppColors.lilac;
  static const lilacSoft = Color(0xFFEDE8FE);
  static const pink = AppColors.pink;
  static const pinkSoft = Color(0xFFFCE4F6);
  static const mint = AppColors.mint;
  static const mintSoft = Color(0xFFDFF5EA);
  static const amber = AppColors.amber;
  static const danger = AppColors.danger;

  static const skyTop = Color(0xFFD6E2FB);

  static const brandGradient = AppColors.brandGradient;
}

/// I colori che cambiano tra tema chiaro e scuro.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.bg,
    required this.card,
    required this.stroke,
    required this.onInk,
    required this.blueSoft,
    required this.lilacSoft,
    required this.pinkSoft,
    required this.mintSoft,
    this.accent = const Color(0xFF6366F1),
  });

  /// Tema personalizzato: parte dal chiaro o dallo scuro e cambia accento e
  /// sfondo; card e bordi si ricavano dallo sfondo.
  factory AppPalette.custom({required bool dark, required Color accent, required Color bg}) {
    final base = dark ? AppPalette.dark : AppPalette.light;
    return AppPalette(
      brightness: base.brightness,
      ink: base.ink,
      inkSoft: base.inkSoft,
      muted: base.muted,
      bg: bg,
      card: Color.lerp(bg, Colors.white, dark ? 0.07 : 0.8)!,
      stroke: Color.lerp(bg, base.ink, 0.08)!,
      onInk: base.onInk,
      blueSoft: base.blueSoft,
      lilacSoft: base.lilacSoft,
      pinkSoft: base.pinkSoft,
      mintSoft: base.mintSoft,
      accent: accent,
    );
  }

  final Brightness brightness;
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color bg;
  final Color card;
  final Color stroke;
  final Color onInk;
  final Color blueSoft;
  final Color lilacSoft;
  final Color pinkSoft;
  final Color mintSoft;

  /// Colore principale (pulsanti in evidenza, card di oggi).
  final Color accent;

  static const light = AppPalette(
    brightness: Brightness.light,
    ink: LightColors.ink,
    inkSoft: LightColors.inkSoft,
    muted: LightColors.muted,
    bg: LightColors.bg,
    card: LightColors.card,
    stroke: LightColors.stroke,
    onInk: LightColors.onInk,
    blueSoft: LightColors.blueSoft,
    lilacSoft: LightColors.lilacSoft,
    pinkSoft: LightColors.pinkSoft,
    mintSoft: LightColors.mintSoft,
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    ink: Color(0xFFEEF0F8),
    inkSoft: Color(0xFFA9AEC4),
    muted: Color(0xFF7A7F98),
    bg: Color(0xFF0D0F1A),
    card: Color(0xFF181B2B),
    stroke: Color(0xFF272B3F),
    onInk: Color(0xFF111322),
    blueSoft: Color(0xFF1D2A4E),
    lilacSoft: Color(0xFF29234D),
    pinkSoft: Color(0xFF3B2039),
    mintSoft: Color(0xFF16352B),
  );

  static AppPalette of(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}

/// Palette dell'app: chiara e pulita a tinte unite, o
/// scura con gli stessi accenti. Segue il tema del dispositivo: i colori
/// neutri (testo, sfondi, card, bordi) cambiano col tema attivo, gli accenti
/// restano uguali.
abstract final class AppColors {
  static AppPalette _palette = AppPalette.light;

  /// Imposta la palette attiva. Lo chiama solo [AppThemeSync].
  static void use(AppPalette palette) => _palette = palette;

  static bool get isDark => _palette.brightness == Brightness.dark;

  /// Testo principale; anche sfondo dei pulsanti "pieni" (scuri nel tema
  /// chiaro, chiari nel tema scuro).
  static Color get ink => _palette.ink;
  static Color get inkSoft => _palette.inkSoft;
  static Color get muted => _palette.muted;
  static Color get bg => _palette.bg;
  static Color get card => _palette.card;
  static Color get stroke => _palette.stroke;

  /// Testo e icone sopra [ink].
  static Color get onInk => _palette.onInk;

  /// Card in evidenza (allenamento di oggi, timer della sessione): scura in
  /// entrambi i temi, col testo bianco sopra.
  static Color get inkCard => isDark ? const Color(0xFF252A41) : _palette.ink;

  /// Colore principale: quello del logo, o l'accento del tema personalizzato.
  static Color get brand => _palette.accent;

  static const blue = Color(0xFF4C7CF5);
  static Color get blueSoft => _palette.blueSoft;
  static const lilac = Color(0xFF8E7CF8);
  static Color get lilacSoft => _palette.lilacSoft;
  static const pink = Color(0xFFF39BDF);
  static Color get pinkSoft => _palette.pinkSoft;
  static const mint = Color(0xFF2FB475);
  static Color get mintSoft => _palette.mintSoft;
  static const amber = Color(0xFFF2B33D);
  static const danger = Color(0xFFE5484D);

  static const brandGradient = LinearGradient(
    colors: [blue, lilac],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Tiene [AppColors] e [L10n.lang] allineati a tema e lingua attivi e,
/// quando cambiano (chiaro/scuro, o la lingua) con l'app aperta,
/// ridisegna tutte le schermate senza perdere navigazione e stato.
class AppThemeSync extends StatefulWidget {
  const AppThemeSync({super.key, required this.child, this.custom});

  final Widget child;

  /// Tema personalizzato attivo, se c'è.
  final AppPalette? custom;

  @override
  State<AppThemeSync> createState() => _AppThemeSyncState();
}

class _AppThemeSyncState extends State<AppThemeSync> {
  AppPalette? _palette;
  String? _lang;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final lang = Localizations.localeOf(context).languageCode;
    final custom = widget.custom;
    final palette = custom != null && custom.brightness == brightness ? custom : AppPalette.of(brightness);
    AppColors.use(palette);
    L10n.lang = lang;
    if ((_palette != null && _palette != palette) || (_lang != null && _lang != lang)) {
      // Molti widget leggono AppColors e tr() in costruttori const o senza
      // dipendere da Theme/Localizations: dopo il cambio vanno ricostruiti tutti.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        void rebuild(Element el) {
          el.markNeedsBuild();
          el.visitChildren(rebuild);
        }

        (context as Element).visitChildren(rebuild);
      });
    }
    _palette = palette;
    _lang = lang;
    final dark = brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: widget.child,
    );
  }
}

class AppRadius {
  const AppRadius._();
  static const sm = 14.0;
  static const md = 20.0;
  static const lg = 28.0;
}

class AppShadows {
  const AppShadows._();

  static const soft = [
    BoxShadow(color: Color(0x0F1B2559), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const float = [
    BoxShadow(color: Color(0x1F1B2559), blurRadius: 32, offset: Offset(0, 12)),
  ];
}

/// Tema Material per una palette (chiara o scura).
ThemeData buildAppTheme([AppPalette p = AppPalette.light]) {
  final dark = p.brightness == Brightness.dark;
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      brightness: p.brightness,
      primary: AppColors.blue,
      secondary: AppColors.lilac,
      surface: p.card,
      onSurface: p.ink,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    cardColor: p.card,
    // Gesto indietro di sistema: swipe dal bordo su iOS, back predittivo
    // (anteprima della schermata sotto) su Android.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
    bodyColor: p.ink,
    displayColor: p.ink,
  );

  return base.copyWith(
    textTheme: text.copyWith(
      displayLarge: text.displayLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -1.6, height: 1.05),
      displayMedium: text.displayMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -1.4, height: 1.05),
      displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -1.0, height: 1.1),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.8),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.6),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      bodyMedium: text.bodyMedium?.copyWith(color: p.inkSoft, height: 1.45),
      bodySmall: text.bodySmall?.copyWith(color: p.muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: p.ink,
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      hintStyle: TextStyle(color: p.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: p.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: p.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.blue, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.onInk,
        minimumSize: const Size.fromHeight(58),
        shape: const StadiumBorder(),
        textStyle: text.titleMedium,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        backgroundColor: p.card,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: p.stroke),
        shape: const StadiumBorder(),
        textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.blue,
        textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.card,
      selectedColor: p.ink,
      side: BorderSide(color: p.stroke),
      shape: const StadiumBorder(),
      labelStyle: text.labelLarge?.copyWith(color: p.ink),
      secondaryLabelStyle: text.labelLarge?.copyWith(color: p.onInk),
      checkmarkColor: p.onInk,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: p.onInk),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.muted,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.stroke, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(color: p.card, surfaceTintColor: Colors.transparent),
    iconTheme: IconThemeData(color: p.ink),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.blue),
  );
}
