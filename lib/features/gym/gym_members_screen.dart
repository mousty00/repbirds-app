import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../models/gym.dart';
import '../auth/auth_widgets.dart';
import 'gym_widgets.dart';

/// Iscritti: chi la palestra ha abilitato su un abbonamento. Da qui si abilita una
/// persona (per username), si rinnova, si sospende, si fa entrare a mano o si toglie.
class GymMembersScreen extends ConsumerStatefulWidget {
  const GymMembersScreen({super.key});

  @override
  ConsumerState<GymMembersScreen> createState() => _GymMembersScreenState();
}

class _GymMembersScreenState extends ConsumerState<GymMembersScreen> {
  String _query = '';
  int _filter = 0; // 0 tutti, 1 attivi, 2 non attivi

  void _refresh() {
    ref.invalidate(gymMembersProvider);
    ref.invalidate(gymProvider);
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(gymMembersProvider);
    return GymPage(
      title: tr('Iscritti'),
      onRefresh: () async {
        _refresh();
        await ref.read(gymMembersProvider.future).catchError((_) => <GymMember>[]);
      },
      fab: FloatingActionButton.extended(
        heroTag: 'gym-add-member',
        onPressed: () => showAddMember(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(tr('Abilita iscritto')),
      ),
      children: [
        TextField(
          decoration: InputDecoration(hintText: tr('Cerca per nome o username'), prefixIcon: const Icon(Icons.search_rounded)),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),
        SegmentedPill(
          options: [tr('Tutti'), tr('Attivi'), tr('Non attivi')],
          index: _filter,
          onChanged: (i) => setState(() => _filter = i),
        ),
        const SizedBox(height: 16),
        AsyncView<List<GymMember>>(
          value: members,
          onRetry: _refresh,
          data: (list) {
            final shown = list.where((m) {
              if (_filter == 1 && !m.active) return false;
              if (_filter == 2 && m.active) return false;
              return _query.isEmpty ||
                  m.user.username.toLowerCase().contains(_query) ||
                  m.displayName.toLowerCase().contains(_query);
            }).toList();
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.badge_rounded,
                title: tr('Nessun iscritto'),
                message: tr('Abilita chi si è iscritto: basta il suo username di RepBirds e l\'abbonamento.'),
                action: tr('Abilita iscritto'),
                onAction: () => showAddMember(context, ref),
              );
            }
            if (shown.isEmpty) return EmptyState(icon: Icons.search_off_rounded, title: tr('Nessun risultato'));
            return Column(children: [for (final m in shown) _MemberRow(member: m)]);
          },
        ),
      ],
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.member});

  final GymMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = member;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        radius: AppRadius.md,
        onTap: () => showGymSheet<void>(
          context,
          title: m.displayName,
          builder: (_) => _MemberSheet(member: m),
        ),
        child: Row(
          children: [
            UserAvatar(username: m.user.username, imageUrl: m.user.image, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${m.user.username} · ${m.planName ?? tr('Abbonamento')} · ${tr('fino al {date}', {'date': formatDate(m.endsOn)})}',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            memberStatusTag(m),
          ],
        ),
      ),
    );
  }
}

/// Abilita una persona (o la rinnova, se c'è già) su un abbonamento.
Future<void> showAddMember(BuildContext context, WidgetRef ref, {String? username}) => showGymSheet<void>(
  context,
  title: tr('Abilita iscritto'),
  builder: (_) => _EnableForm(username: username),
);

class _EnableForm extends ConsumerStatefulWidget {
  const _EnableForm({this.username, this.member});

  final String? username;

  /// Rinnovo di un iscritto: username fisso, abbonamento nuovo.
  final GymMember? member;

  @override
  ConsumerState<_EnableForm> createState() => _EnableFormState();
}

class _EnableFormState extends ConsumerState<_EnableForm> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.member?.user.username ?? widget.username);
  final _start = TextEditingController();
  String? _planId;
  DateTime? _startsOn;
  bool _saving = false;

  @override
  void dispose() {
    _username.dispose();
    _start.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsOn ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() {
        _startsOn = picked;
        _start.text = formatDate(picked);
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(gymRepositoryProvider);
      if (widget.member != null) {
        await repo.updateMember(widget.member!.id, planId: _planId, startsOn: _startsOn, status: MembershipStatus.active);
      } else {
        await repo.addMember(username: _username.text.trim(), planId: _planId!, startsOn: _startsOn);
      }
      ref.invalidate(gymMembersProvider);
      ref.invalidate(gymProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, tr('Fatto: la tessera è nell\'app di @{username}', {'username': _username.text.trim()}));
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(gymPlansProvider);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: tr('Username RepBirds'),
            controller: _username,
            hint: tr('es. mario_lifts'),
            readOnly: widget.member != null,
            inputFormatters: usernameFormatters,
            validator: requiredField,
          ),
          AsyncView<List<GymPlan>>(
            value: plans,
            onRetry: () => ref.invalidate(gymPlansProvider),
            data: (list) {
              final onSale = list.where((p) => p.active).toList();
              if (onSale.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    tr('Crea prima un abbonamento nella sezione Abbonamenti.'),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DropdownButtonFormField<String>(
                  initialValue: _planId,
                  decoration: InputDecoration(labelText: tr('Abbonamento')),
                  items: [
                    for (final p in onSale)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          '${p.name} · ${formatPlanDuration(p.durationDays)} · ${formatPrice(p.priceCents)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _planId = v),
                  validator: (v) => v == null ? tr('Scegli un abbonamento') : null,
                ),
              );
            },
          ),
          LabeledField(
            label: tr('Inizio'),
            controller: _start,
            hint: tr('Oggi'),
            readOnly: true,
            onTap: _pickStart,
            suffix: const Icon(Icons.calendar_today_rounded, size: 18),
          ),
          PrimaryButton(label: widget.member != null ? tr('Rinnova') : tr('Abilita'), loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}

/// Dettaglio di un iscritto con le azioni.
class _MemberSheet extends ConsumerStatefulWidget {
  const _MemberSheet({required this.member});

  final GymMember member;

  @override
  ConsumerState<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends ConsumerState<_MemberSheet> {
  bool _busy = false;

  GymMember get m => widget.member;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(gymMembersProvider);
      ref.invalidate(gymProvider);
      ref.invalidate(gymCheckInsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      if (done != null) showMessage(context, done);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _letIn() async {
    setState(() => _busy = true);
    try {
      final c = await ref.read(gymRepositoryProvider).manualCheckIn(m.id);
      ref.invalidate(gymCheckInsProvider);
      ref.invalidate(gymProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, c.accepted ? tr('Ingresso registrato') : refusalText(c), error: !c.accepted);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(gymRepositoryProvider);
    final suspended = m.status == MembershipStatus.suspended;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          child: Column(
            children: [
              _Info(tr('Username'), '@${m.user.username}'),
              _Info(tr('Abbonamento'), m.planName ?? '—'),
              _Info(tr('Dal'), formatDate(m.startsOn)),
              _Info(tr('Al'), formatDate(m.endsOn)),
              _Info(tr('Ultimo ingresso'), m.lastCheckInAt == null ? '—' : formatDayTime(m.lastCheckInAt)),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(alignment: Alignment.centerRight, child: memberStatusTag(m)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_busy)
          const Center(
            child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
          ),
        FilledButton.icon(
          onPressed: _busy ? null : _letIn,
          icon: const Icon(Icons.login_rounded),
          label: Text(tr('Fai entrare a mano')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () {
                  Navigator.pop(context);
                  showGymSheet<void>(
                    context,
                    title: tr('Rinnova abbonamento'),
                    builder: (_) => _EnableForm(member: m),
                  );
                },
          icon: const Icon(Icons.autorenew_rounded),
          label: Text(tr('Rinnova o cambia abbonamento')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _run(
                  () => repo.updateMember(m.id, status: suspended ? MembershipStatus.active : MembershipStatus.suspended),
                  done: suspended ? tr('Abbonamento riattivato') : tr('Abbonamento sospeso: la tessera non apre più'),
                ),
          icon: Icon(suspended ? Icons.play_arrow_rounded : Icons.pause_rounded),
          label: Text(suspended ? tr('Riattiva') : tr('Sospendi')),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final ok = await confirm(
                    context,
                    title: tr('Togliere {name}?', {'name': m.displayName}),
                    message: tr('La tessera smette di funzionare ed esce dai corsi della palestra.'),
                    ok: tr('Togli'),
                    destructive: true,
                  );
                  if (ok) await _run(() => repo.removeMember(m.id), done: tr('Iscritto tolto'));
                },
          icon: const Icon(Icons.person_remove_rounded, color: AppColors.danger),
          label: Text(tr('Togli dalla palestra'), style: const TextStyle(color: AppColors.danger)),
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(label, style: TextStyle(color: AppColors.muted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
