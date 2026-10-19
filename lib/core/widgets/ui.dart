import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/session.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'app_image.dart';

/// Card bianca arrotondata con ombra morbida.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.onTap,
    this.radius = AppRadius.lg,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  /// Di default [AppColors.card].
  final Color? color;
  final VoidCallback? onTap;
  final double radius;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final color = this.color ?? AppColors.card;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: shape,
        border: border && color == AppColors.card
            ? Border.all(color: AppColors.stroke.withValues(alpha: 0.7))
            : null,
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Pulsante circolare bianco (campanella, +, indietro…).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.dark = false,
    this.size = 48,
    this.badge = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool dark;
  final double size;
  final bool badge;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: dark ? AppColors.ink : AppColors.card,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: size * 0.44, color: dark ? AppColors.onInk : AppColors.ink),
              if (badge)
                Positioned(
                  top: size * 0.24,
                  right: size * 0.26,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.card, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: AppShadows.soft),
      child: tooltip == null ? button : Tooltip(message: tooltip!, child: button),
    );
  }
}

/// Pulsante a pillola bianco con cerchio scuro a destra ("Inizia  »").
class PillActionButton extends StatelessWidget {
  const PillActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.keyboard_double_arrow_right_rounded,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        boxShadow: AppShadows.float,
      ),
      child: Material(
        color: AppColors.card,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 7, 7, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: Theme.of(context).textTheme.titleMedium),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                  child: loading
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onInk),
                        )
                      : Icon(icon, color: AppColors.onInk),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pulsante primario scuro a tutta larghezza con stato di caricamento.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
      onPressed: loading ? null : onPressed,
      child: loading
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.onInk),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 10)],
                Text(label),
              ],
            ),
    );
  }
}

/// Avatar con foto o iniziali su colore pieno. Per l'utente loggato usa sempre
/// la sua foto profilo attuale, anche dove il dato arriva senza immagine o con
/// quella vecchia (i suoi post, i commenti, gli avatar di gruppo).
class UserAvatar extends ConsumerWidget {
  const UserAvatar({super.key, required this.username, this.imageUrl, this.size = 44, this.ring = false});

  final String username;
  final String? imageUrl;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionProvider.select((s) => s.value));
    final imageUrl = me != null && me.username == username && AppImage.supports(me.image) ? me.image : this.imageUrl;
    final initials = username.isEmpty ? '?' : username.characters.first.toUpperCase();
    final hasImage = AppImage.supports(imageUrl);
    final color = _palette[username.hashCode.abs() % _palette.length];
    final initialsView = ColoredBox(color: color, child: Center(child: _Initials(initials, size)));
    // La foto riempie tutto il cerchio (cover + ritaglio tondo), anche dentro l'anello.
    return Container(
      width: size,
      height: size,
      padding: ring ? const EdgeInsets.all(3) : EdgeInsets.zero,
      decoration: ring ? const BoxDecoration(shape: BoxShape.circle, color: AppColors.blue) : null,
      child: Container(
        padding: ring ? const EdgeInsets.all(2.5) : EdgeInsets.zero,
        decoration: ring ? BoxDecoration(shape: BoxShape.circle, color: AppColors.card) : null,
        child: ClipOval(
          child: SizedBox.expand(
            child: hasImage
                ? AppImage(imageUrl!, width: double.infinity, height: double.infinity, fallback: initialsView)
                : initialsView,
          ),
        ),
      ),
    );
  }

  static const _palette = [
    Color(0xFFBFD3FF),
    Color(0xFFFFD1EE),
    Color(0xFFC6F0E0),
    Color(0xFFFFE2B8),
  ];
}

class _Initials extends StatelessWidget {
  const _Initials(this.text, this.size);

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: LightColors.ink),
      );
}

/// Titolo di sezione con azione opzionale ("Vedi tutti").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!, style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

/// Piccolo badge colorato (icona su fondo tenue).
class IconChip extends StatelessWidget {
  const IconChip({super.key, required this.icon, this.color = AppColors.blue, this.background, this.size = 40});

  final IconData icon;
  final Color color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.36),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Etichetta a pillola.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color = AppColors.blue, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Stato vuoto: un'icona che dice cosa manca (post, schede, amici…), titolo,
/// messaggio e azione opzionali.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});

  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: AppColors.blueSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: AppColors.blue),
          ),
          const SizedBox(height: 16),
          Text(title, style: t.titleLarge, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, style: t.bodyMedium, textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              child: OutlinedButton(onPressed: onAction, child: Text(action!)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Barre verticali arrotondate (stile "Sleep Level"), una evidenziata.
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    this.highlight,
    this.color,
    this.highlightColor,
    this.height = 64,
    this.labels,
  });

  final List<double> values;
  final int? highlight;
  /// Di default [AppColors.card].
  final Color? color;

  /// Di default [AppColors.ink].
  final Color? highlightColor;
  final double height;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 10 + (max == 0 ? 0 : (values[i] / max) * (height - 10)),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: i == highlight ? (highlightColor ?? AppColors.ink) : (color ?? AppColors.card),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                if (labels != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    labels![i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == highlight ? FontWeight.w700 : FontWeight.w500,
                      color: i == highlight ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Barra di ricerca a pillola con pulsante circolare.
class SearchPill extends StatelessWidget {
  const SearchPill({super.key, this.controller, this.hint, this.onChanged, this.onSubmitted, this.inputFormatters, this.autofocus = false});

  final TextEditingController? controller;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(40),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              inputFormatters: inputFormatters,
              autofocus: autofocus,
              autocorrect: inputFormatters == null,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hint ?? tr('Cerca…'),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
            child: Icon(Icons.search_rounded, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

/// Barra superiore per le schermate interne: indietro + titolo + azioni.
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, this.actions = const [], this.showBack = true, this.titleWidget});

  final String title;
  final List<Widget> actions;
  final bool showBack;

  /// Al posto del titolo, es. il selettore di sezione dentro una tab (niente indietro).
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          if (showBack && titleWidget == null && !PaneScope.inPane(context)) ...[
            CircleIconButton(
              icon: Icons.arrow_back_rounded,
              size: 44,
              // Aperta da deep link senza storia: torna alla home.
              onTap: () => context.canPop() ? Navigator.of(context).maybePop() : context.go('/home'),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: titleWidget ??
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                  overflow: TextOverflow.ellipsis,
                ),
          ),
          for (final a in actions) ...[const SizedBox(width: 10), a],
        ],
      ),
    );
  }
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: error ? const TextStyle(color: Colors.white) : null),
        backgroundColor: error ? AppColors.danger : AppColors.ink,
      ),
    );
}

Future<bool> confirm(BuildContext context, {required String title, String? message, String? ok, bool destructive = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Annulla'), style: TextStyle(color: AppColors.inkSoft)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok ?? tr('Conferma'), style: TextStyle(color: destructive ? AppColors.danger : AppColors.blue)),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Campi username: sempre minuscolo e senza spazi, mentre scrivi (anche con il
/// blocco maiuscole o l'autocompletamento).
const usernameFormatters = <TextInputFormatter>[_LowerCaseFormatter()];

class _LowerCaseFormatter extends TextInputFormatter {
  const _LowerCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.toLowerCase().replaceAll(RegExp(r'\s'), '');
    if (text == newValue.text) return newValue;
    final cut = newValue.text.length - text.length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: (newValue.selection.end - cut).clamp(0, text.length)),
    );
  }
}

/// Selettore a pillola (es. Amici · Richieste).
class SegmentedPill extends StatelessWidget {
  const SegmentedPill({super.key, required this.options, required this.index, required this.onChanged});

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(40),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: i == index ? AppColors.onInk : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Schermi larghi e pieghevoli (Galaxy Z Fold/Flip, Pixel Fold, tablet) ---

/// Su uno schermo largo il contenuto resta una colonna leggibile al centro,
/// invece di stirarsi da bordo a bordo.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  static const maxWidth = 640.0;

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxWidth), child: child),
        ),
      );
}

/// La piega orizzontale di un pieghevole aperto a metà e appoggiato (modalità
/// tavolino / Flex Mode), in coordinate dello schermo. Null se il telefono non è
/// in quella posizione, e sempre su iOS, che non la comunica alle app.
Rect? tabletopFold(BuildContext context) {
  for (final f in MediaQuery.displayFeaturesOf(context)) {
    if (f.state == DisplayFeatureState.postureHalfOpened && f.bounds.width > f.bounds.height) return f.bounds;
  }
  return null;
}

/// Lista e dettaglio affiancati quando lo schermo lo permette: un pieghevole
/// aperto a libro (si divide sulla piega, niente sotto la cerniera) o una
/// finestra da almeno 840dp. Altrimenti solo [start], come su un telefono.
class TwoPane extends StatelessWidget {
  const TwoPane({super.key, required this.start, required this.end});

  final Widget start;
  final Widget end;

  static Rect? _verticalFold(BuildContext context) {
    for (final f in MediaQuery.displayFeaturesOf(context)) {
      if (f.type != DisplayFeatureType.cutout && f.bounds.height > f.bounds.width) return f.bounds;
    }
    return null;
  }

  /// Se vero, aprire un elemento della lista lo mostra in [end] invece di aprire una pagina.
  static bool active(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 840 || (width >= 600 && _verticalFold(context) != null);
  }

  @override
  Widget build(BuildContext context) {
    if (!active(context)) return ContentWidth(child: start);
    final fold = _verticalFold(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ponytail: si assume che il pannello parta dal bordo sinistro dello schermo (è il corpo di una tab)
        SizedBox(width: fold?.left ?? MediaQuery.sizeOf(context).width * 0.4, child: start),
        SizedBox(width: fold?.width ?? 0),
        Expanded(child: end),
      ],
    );
  }
}

/// Una pagina mostrata come pannello di [TwoPane] invece che a tutto schermo:
/// niente "indietro", e chiuderla (es. dopo averla eliminata) svuota il pannello.
class PaneScope extends InheritedWidget {
  const PaneScope({super.key, required this.onClose, required super.child});

  final VoidCallback onClose;

  static bool inPane(BuildContext context) => context.getInheritedWidgetOfExactType<PaneScope>() != null;

  @override
  bool updateShouldNotify(PaneScope oldWidget) => false;
}

/// Chiude la pagina corrente: un pop se c'è dove tornare, o svuota il pannello di [TwoPane].
void closePage(BuildContext context) {
  final pane = context.getInheritedWidgetOfExactType<PaneScope>();
  if (pane != null) {
    pane.onClose();
  } else if (context.canPop()) {
    context.pop();
  }
}
