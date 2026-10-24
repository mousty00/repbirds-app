import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../models/gym.dart';
import '../auth/auth_widgets.dart';
import 'gym_widgets.dart';

/// Abbonamenti che la palestra vende: nome, durata, prezzo, in vendita o no.
class GymPlansScreen extends ConsumerWidget {
  const GymPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(gymPlansProvider);
    void edit([GymPlan? plan]) => showGymSheet<void>(
      context,
      title: plan == null ? tr('Nuovo abbonamento') : tr('Modifica abbonamento'),
      builder: (_) => _PlanForm(plan: plan),
    );
    return GymPage(
      title: tr('Abbonamenti'),
      onRefresh: () async {
        ref.invalidate(gymPlansProvider);
        await ref.read(gymPlansProvider.future).catchError((_) => <GymPlan>[]);
      },
      fab: FloatingActionButton.extended(
        heroTag: 'gym-add-plan',
        onPressed: edit,
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Nuovo abbonamento')),
      ),
      children: [
        AsyncView<List<GymPlan>>(
          value: plans,
          onRetry: () => ref.invalidate(gymPlansProvider),
          data: (list) => list.isEmpty
              ? EmptyState(
                  icon: Icons.card_membership_rounded,
                  title: tr('Nessun abbonamento'),
                  message: tr('Crea gli abbonamenti che vendi (mensile, trimestrale, annuale…) per abilitarli sugli iscritti.'),
                  action: tr('Crea abbonamento'),
                  onAction: edit,
                )
              : Column(
                  children: [
                    for (final p in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SoftCard(
                          onTap: () => edit(p),
                          padding: const EdgeInsets.all(16),
                          radius: AppRadius.md,
                          child: Row(
                            children: [
                              IconChip(icon: Icons.card_membership_rounded, color: p.active ? AppColors.lilac : AppColors.muted),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(
                                      '${formatPlanDuration(p.durationDays)} · ${formatPrice(p.priceCents)}',
                                      style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                                    ),
                                    if (p.description?.isNotEmpty == true)
                                      Text(p.description!, style: TextStyle(color: AppColors.muted, fontSize: 12), maxLines: 2),
                                  ],
                                ),
                              ),
                              if (!p.active) Tag(tr('Non in vendita'), color: AppColors.muted),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PlanForm extends ConsumerStatefulWidget {
  const _PlanForm({this.plan});

  final GymPlan? plan;

  @override
  ConsumerState<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends ConsumerState<_PlanForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.plan?.name);
  late final _description = TextEditingController(text: widget.plan?.description);
  late final _days = TextEditingController(text: '${widget.plan?.durationDays ?? 30}');
  late final _price = TextEditingController(
    text: widget.plan?.priceCents == null ? '' : (widget.plan!.priceCents! / 100).toStringAsFixed(2).replaceAll('.', ','),
  );
  late bool _active = widget.plan?.active ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _days, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _cents {
    final v = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    return v == null ? null : (v * 100).round();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(gymRepositoryProvider);
    final description = _description.text.trim().isEmpty ? null : _description.text.trim();
    try {
      if (widget.plan == null) {
        await repo.createPlan(
          name: _name.text.trim(),
          description: description,
          priceCents: _cents,
          durationDays: int.parse(_days.text),
          active: _active,
        );
      } else {
        await repo.updatePlan(
          widget.plan!.id,
          name: _name.text.trim(),
          description: description,
          priceCents: _cents,
          durationDays: int.parse(_days.text),
          active: _active,
        );
      }
      ref.invalidate(gymPlansProvider);
      ref.invalidate(gymProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: tr('Eliminare l\'abbonamento?'),
      message: tr('Chi ce l\'ha lo tiene fino alla scadenza.'),
      ok: tr('Elimina'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(gymRepositoryProvider).deletePlan(widget.plan!.id);
      ref.invalidate(gymPlansProvider);
      ref.invalidate(gymProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(label: tr('Nome'), controller: _name, hint: tr('es. Mensile open'), validator: requiredField),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: tr('Durata (giorni)'),
                  controller: _days,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1 || n > 3660) return tr('Da 1 a 3660');
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  label: tr('Prezzo (€)'),
                  controller: _price,
                  hint: tr('es. 49,00'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => v != null && v.trim().isNotEmpty && _cents == null ? tr('Prezzo non valido') : null,
                ),
              ),
            ],
          ),
          LabeledField(label: tr('Descrizione'), controller: _description, maxLines: 2, hint: tr('Cosa comprende')),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: Text(tr('In vendita'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr('Solo gli abbonamenti in vendita si possono abilitare sui nuovi iscritti')),
          ),
          const SizedBox(height: 8),
          PrimaryButton(label: tr('Salva'), loading: _saving, onPressed: _save),
          if (widget.plan != null)
            TextButton(
              onPressed: _delete,
              child: Text(tr('Elimina abbonamento'), style: const TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}
