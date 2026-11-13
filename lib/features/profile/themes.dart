import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_mode.dart';
import '../../core/widgets/ui.dart';

/// Scelta del tema: dispositivo, chiaro, scuro o uno dei tuoi; da qui si
/// creano e modificano i temi personalizzati.
void showThemePicker(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final choice = ref.watch(themeProvider);
        final notifier = ref.read(themeProvider.notifier);
        void edit([CustomTheme? theme]) {
          Navigator.pop(ctx);
          Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => ThemeEditorScreen(initial: theme)));
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: RadioGroup<String>(
              groupValue: choice.custom?.id ?? choice.mode.name,
              onChanged: (v) {
                if (v == null) return;
                final mode = ThemeMode.values.asNameMap()[v];
                mode != null ? notifier.setMode(mode) : notifier.apply(v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RadioListTile<String>(value: ThemeMode.system.name, title: Text(tr('Tema del dispositivo'))),
                  RadioListTile<String>(value: ThemeMode.light.name, title: Text(tr('Chiaro'))),
                  RadioListTile<String>(value: ThemeMode.dark.name, title: Text(tr('Scuro'))),
                  if (choice.themes.isNotEmpty) const Divider(indent: 16, endIndent: 16),
                  for (final t in choice.themes)
                    RadioListTile<String>(
                      value: t.id,
                      title: Text(t.name),
                      secondary: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Dot(color: t.bg),
                          const SizedBox(width: 4),
                          _Dot(color: t.accent),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: tr('Modifica'),
                            onPressed: () => edit(t),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: OutlinedButton.icon(
                      onPressed: edit,
                      icon: const Icon(Icons.palette_outlined),
                      label: Text(tr('Crea un tema')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 22, this.selected = false});

  final Color color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? AppColors.ink : AppColors.stroke, width: selected ? 3 : 1),
        ),
      );
}

const _accents = [
  Color(0xFF6366F1), Color(0xFF4C7CF5), Color(0xFF0EA5E9), Color(0xFF14B8A6), Color(0xFF2FB475), Color(0xFFF2B33D),
  Color(0xFFF97316), Color(0xFFE5484D), Color(0xFFEC4899), Color(0xFF8E7CF8), Color(0xFF64748B),
];
const _lightBgs = [
  Color(0xFFF3F5FA), Color(0xFFFAFAF9), Color(0xFFFFF7ED), Color(0xFFFEFCE8), Color(0xFFF0FDF4), Color(0xFFEFF6FF),
  Color(0xFFF5F3FF), Color(0xFFFDF2F8),
];
const _darkBgs = [
  Color(0xFF0D0F1A), Color(0xFF000000), Color(0xFF111827), Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF1A1025),
  Color(0xFF0B1F17), Color(0xFF1C1917),
];

/// Crea o modifica un tema: nome, base chiara o scura, accento e sfondo,
/// con un'anteprima. Salvando si applica subito.
class ThemeEditorScreen extends ConsumerStatefulWidget {
  const ThemeEditorScreen({super.key, this.initial});

  final CustomTheme? initial;

  @override
  ConsumerState<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends ConsumerState<ThemeEditorScreen> {
  late final _name = TextEditingController(text: widget.initial?.name ?? tr('Il mio tema'));
  late bool _dark = widget.initial?.dark ?? AppColors.isDark;
  late Color _accent = widget.initial?.accent ?? _accents.first;
  late Color _bg = widget.initial?.bg ?? (_dark ? _darkBgs : _lightBgs).first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, tr('Dai un nome al tema'), error: true);
      return;
    }
    await ref.read(themeProvider.notifier).saveTheme(CustomTheme(
          id: widget.initial?.id ?? '${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          dark: _dark,
          accent: _accent,
          bg: _bg,
        ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, title: tr('Eliminare il tema?'), ok: tr('Elimina'), destructive: true)) return;
    await ref.read(themeProvider.notifier).delete(widget.initial!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.custom(dark: _dark, accent: _accent, bg: _bg);
    final bgs = _dark ? _darkBgs : _lightBgs;
    Widget swatches(List<Color> colors, Color selected, ValueChanged<Color> onPick) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in colors)
              GestureDetector(onTap: () => onPick(c), child: _Dot(color: c, size: 40, selected: c == selected)),
          ],
        );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              title: widget.initial == null ? tr('Nuovo tema') : tr('Modifica tema'),
              actions: [
                if (widget.initial != null)
                  CircleIconButton(icon: Icons.delete_outline_rounded, size: 44, tooltip: tr('Elimina'), onTap: _delete),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  // anteprima con i colori scelti
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(28), border: Border.all(color: p.stroke)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(22)),
                          child: Text(tr('Oggi'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22)),
                          child: Text(_name.text.isEmpty ? tr('Il mio tema') : _name.text,
                              style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _name,
                    maxLength: 30,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: tr('Nome del tema')),
                  ),
                  const SizedBox(height: 8),
                  SegmentedPill(
                    options: [tr('Chiaro'), tr('Scuro')],
                    index: _dark ? 1 : 0,
                    onChanged: (i) => setState(() {
                      _dark = i == 1;
                      _bg = (_dark ? _darkBgs : _lightBgs).first;
                    }),
                  ),
                  const SizedBox(height: 22),
                  SectionHeader(tr('Colore principale')),
                  swatches(_accents, _accent, (c) => setState(() => _accent = c)),
                  const SizedBox(height: 22),
                  SectionHeader(tr('Sfondo')),
                  swatches(bgs, _bg, (c) => setState(() => _bg = c)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: PillActionButton(label: tr('Salva e applica'), icon: Icons.check_rounded, onPressed: _save),
            ),
          ],
        ),
      ),
    );
  }
}
