import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../data/auth_repository.dart';
import '../auth/auth_widgets.dart';
import '../auth/session.dart';

/// Modifica profilo: username, nome, cognome, data di nascita. L'email si
/// cambia a parte, con un codice mandato al nuovo indirizzo.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _me = ref.read(currentUserProvider);
  late final _username = TextEditingController(text: _me.username);
  late final _firstName = TextEditingController(text: _me.firstName ?? '');
  late final _lastName = TextEditingController(text: _me.lastName ?? '');
  late final _birth = TextEditingController(text: formatDate(_me.birthDate));
  late DateTime? _birthDate = _me.birthDate;
  String? _usernameTaken;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_username, _firstName, _lastName, _birth]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final last = DateTime(now.year - 14, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate != null && _birthDate!.isBefore(last) ? _birthDate! : last,
      firstDate: DateTime(1920),
      // età minima 14 anni, come alla registrazione (la controlla anche il backend)
      lastDate: last,
      helpText: tr('Data di nascita'),
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birth.text = formatDate(picked);
      });
    }
  }

  Future<void> _save() async {
    setState(() => _usernameTaken = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final user = await ref.read(authRepositoryProvider).updateProfile(
            username: _username.text.trim(),
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            birthDate: _birthDate!,
          );
      ref.read(sessionProvider.notifier).setUser(user);
      if (!mounted) return;
      showMessage(context, tr('Profilo aggiornato'));
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        // errore sotto il campo, non in un messaggio che sparisce
        setState(() => _usernameTaken = tr('Username già in uso, scegline un altro'));
        _form.currentState!.validate();
      } else {
        showMessage(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(currentUserProvider).email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Modifica profilo')),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LabeledField(
                        label: tr('Username'),
                        controller: _username,
                        autofillHints: const [AutofillHints.username],
                        inputFormatters: usernameFormatters,
                        validator: (v) {
                          final u = v?.trim() ?? '';
                          if (u.isEmpty) return tr('Scegli uno username');
                          if (u.length < 3 || u.length > 50) return tr('Da 3 a 50 caratteri');
                          if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(u)) {
                            return tr('Solo lettere, numeri, punto, trattino e underscore');
                          }
                          return _usernameTaken;
                        },
                      ),
                      Row(
                        children: [
                          Expanded(child: LabeledField(label: tr('Nome'), controller: _firstName)),
                          const SizedBox(width: 12),
                          Expanded(child: LabeledField(label: tr('Cognome'), controller: _lastName)),
                        ],
                      ),
                      LabeledField(
                        label: tr('Data di nascita'),
                        controller: _birth,
                        hint: tr('Seleziona'),
                        readOnly: true,
                        onTap: _pickBirthDate,
                        suffix: const Icon(Icons.calendar_today_rounded, size: 18),
                        validator: (_) => _birthDate == null ? tr('Inserisci la data di nascita') : null,
                      ),
                      const SizedBox(height: 8),
                      Text(tr('Email'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SoftCard(
                        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(email, overflow: TextOverflow.ellipsis)),
                            TextButton(onPressed: () => _showChangeEmail(context), child: Text(tr('Cambia'))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      PrimaryButton(label: tr('Salva'), loading: _saving, onPressed: _save),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showChangeEmail(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => const _ChangeEmailSheet(),
  );
}

/// Due passi: nuova email → codice ricevuto lì. Fino alla conferma resta la vecchia.
class _ChangeEmailSheet extends ConsumerStatefulWidget {
  const _ChangeEmailSheet();

  @override
  ConsumerState<_ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends ConsumerState<_ChangeEmailSheet> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(ApiException e) {
    final m = e.message.toLowerCase();
    if (e.statusCode == 409) return tr('Questa email è già usata da un altro account');
    if (m.contains('already your email')) return tr('È già la tua email');
    if (m.contains('expired')) return tr('Il codice è scaduto: richiedine un altro');
    if (m.contains('invalid otp')) return tr('Codice non valido');
    return e.message;
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      await ref.read(authRepositoryProvider).requestEmailChange(_email.text.trim());
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _confirm() async {
    if (_otp.text.trim().length != 6) {
      setState(() => _error = tr('Il codice ha 6 cifre'));
      return;
    }
    await _run(() async {
      final user = await ref.read(authRepositoryProvider).confirmEmailChange(_otp.text.trim());
      ref.read(sessionProvider.notifier).setUser(user);
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(context, tr('Email aggiornata'));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('Cambia email'), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  _codeSent
                      ? tr('Abbiamo mandato un codice a {email}. Inseriscilo per confermare: fino ad allora resta la tua email attuale.', {'email': _email.text.trim()})
                      : tr('Ti mandiamo un codice al nuovo indirizzo per verificarlo.'),
                  style: TextStyle(color: AppColors.inkSoft),
                ),
                const SizedBox(height: 16),
                if (!_codeSent)
                  LabeledField(
                    label: tr('Nuova email'),
                    controller: _email,
                    hint: tr('nome@email.com'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: validEmail,
                    onSubmitted: (_) => _send(),
                  )
                else
                  LabeledField(
                    label: tr('Codice'),
                    controller: _otp,
                    hint: '••••••',
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    onSubmitted: (_) => _confirm(),
                  ),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                ],
                PrimaryButton(
                  label: _codeSent ? tr('Conferma') : tr('Invia codice'),
                  loading: _loading,
                  onPressed: _codeSent ? _confirm : _send,
                ),
                if (_codeSent)
                  TextButton(
                    onPressed: _loading ? null : () => setState(() => _codeSent = false),
                    child: Text(tr('Usa un\'altra email')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
