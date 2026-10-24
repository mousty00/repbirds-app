import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../models/gym.dart';
import '../auth/auth_widgets.dart';
import '../auth/session.dart';
import 'gym_widgets.dart';

/// Panoramica: i numeri di oggi, il pulsante per l'ingresso e gli ultimi accessi.
class GymOverviewScreen extends ConsumerWidget {
  const GymOverviewScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(gymProvider);
    ref.invalidate(gymCheckInsProvider);
    await ref.read(gymProvider.future).catchError((_) => const Gym(id: '', username: '', name: ''));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(gymProvider);
    final checkIns = ref.watch(gymCheckInsProvider);
    return GymPage(
      title: gym.value?.name ?? tr('La tua palestra'),
      subtitle: tr('Dashboard palestra'),
      onRefresh: () => _refresh(ref),
      actions: [
        CircleIconButton(
          icon: Icons.settings_outlined,
          tooltip: tr('Profilo palestra'),
          onTap: gym.value == null ? null : () => _editProfile(context, ref, gym.value!),
        ),
      ],
      children: [
        _EntranceCard(onTap: () => context.push('/gym/entrance')),
        const SizedBox(height: 16),
        AsyncView<Gym>(
          value: gym,
          onRetry: () => ref.invalidate(gymProvider),
          data: (g) {
            final s = g.stats ?? const GymStats();
            return GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 3 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                StatTile(
                  icon: Icons.badge_rounded,
                  color: AppColors.blue,
                  value: '${s.activeMembers}',
                  label: tr('Iscritti attivi su {total}', {'total': s.totalMembers}),
                  onTap: () => context.go('/gym/members'),
                ),
                StatTile(
                  icon: Icons.login_rounded,
                  color: AppColors.mint,
                  value: '${s.checkInsToday}',
                  label: tr('Ingressi oggi'),
                ),
                StatTile(
                  icon: Icons.card_membership_rounded,
                  color: AppColors.lilac,
                  value: '${s.activePlans}',
                  label: tr('Abbonamenti in vendita'),
                  onTap: () => context.go('/gym/plans'),
                ),
                StatTile(
                  icon: Icons.event_rounded,
                  color: AppColors.pink,
                  value: '${s.courses}',
                  label: tr('Corsi'),
                  onTap: () => context.go('/gym/courses'),
                ),
                StatTile(
                  icon: Icons.fitness_center_rounded,
                  color: AppColors.amber,
                  value: '${s.workouts}',
                  label: tr('Schede per gli iscritti'),
                  onTap: () => context.go('/gym/workouts'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        SectionHeader(tr('Ultimi ingressi'), action: tr('Aggiorna'), onAction: () => ref.invalidate(gymCheckInsProvider)),
        AsyncView<List<CheckIn>>(
          value: checkIns,
          onRetry: () => ref.invalidate(gymCheckInsProvider),
          data: (list) => list.isEmpty
              ? EmptyState(
                  icon: Icons.contactless_rounded,
                  title: tr('Ancora nessun ingresso'),
                  message: tr('Apri l\'ingresso e fai avvicinare il telefono o il QR della tessera.'),
                )
              : Column(children: [for (final c in list.take(20)) CheckInRow(checkIn: c)]),
        ),
      ],
    );
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref, Gym gym) async {
    await showGymSheet<void>(
      context,
      title: tr('Profilo palestra'),
      builder: (ctx) => _ProfileForm(gym: gym),
    );
  }
}

class _EntranceCard extends StatelessWidget {
  const _EntranceCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              const Icon(Icons.contactless_rounded, color: Colors.white, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Apri l\'ingresso'), style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(tr('Leggi le tessere con NFC o con la fotocamera'), style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.gym});

  final Gym gym;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.gym.name);
  late final _description = TextEditingController(text: widget.gym.description);
  late final _address = TextEditingController(text: widget.gym.address);
  late final _city = TextEditingController(text: widget.gym.city);
  late final _phone = TextEditingController(text: widget.gym.phone);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _address, _city, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(gymRepositoryProvider)
          .updateMe(
            name: _name.text.trim(),
            description: _text(_description),
            address: _text(_address),
            city: _text(_city),
            phone: _text(_phone),
          );
      ref.invalidate(gymProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    if (!await confirm(context, title: tr('Vuoi uscire?'), ok: tr('Esci dall\'account'))) return;
    if (mounted) Navigator.pop(context);
    await ref.read(sessionProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(label: tr('Nome della palestra'), controller: _name, validator: requiredField),
          LabeledField(
            label: tr('Descrizione'),
            controller: _description,
            maxLines: 3,
            hint: tr('Orari, servizi, cosa vi distingue'),
          ),
          LabeledField(label: tr('Indirizzo'), controller: _address),
          Row(
            children: [
              Expanded(
                child: LabeledField(label: tr('Città'), controller: _city),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(label: tr('Telefono'), controller: _phone, keyboardType: TextInputType.phone),
              ),
            ],
          ),
          PrimaryButton(label: tr('Salva'), loading: _saving, onPressed: _save),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
            label: Text(tr('Esci dall\'account'), style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
