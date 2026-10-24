import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../auth/auth_widgets.dart';

/// Registrazione di una palestra: credenziali e dati della palestra. Poi stesso
/// codice via email e stesso login delle persone, ma si entra nella dashboard.
class GymSignupScreen extends ConsumerStatefulWidget {
  const GymSignupScreen({super.key});

  @override
  ConsumerState<GymSignupScreen> createState() => _GymSignupScreenState();
}

class _GymSignupScreenState extends ConsumerState<GymSignupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_name, _username, _email, _address, _city, _phone, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(gymRepositoryProvider).signup(
            username: _username.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            name: _name.text.trim(),
            address: _text(_address),
            city: _text(_city),
            phone: _text(_phone),
          );
      if (!mounted) return;
      showMessage(context, tr('Palestra registrata! Ti abbiamo inviato un codice via email.'));
      context.pushReplacement(
        '/auth/verify?username=${Uri.encodeComponent(_username.text.trim())}'
        '&email=${Uri.encodeComponent(_email.text.trim())}',
      );
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: tr('Registra la tua\npalestra'),
      subtitle: tr('Gestisci abbonamenti, iscritti, schede e corsi. I tuoi iscritti entrano con la tessera nell\'app.'),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                LabeledField(
                  label: tr('Nome della palestra'),
                  controller: _name,
                  hint: tr('es. Fit Club Milano'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return tr('Campo obbligatorio');
                    if (v.trim().length > 100) return tr('Massimo 100 caratteri');
                    return null;
                  },
                ),
                LabeledField(
                  label: tr('Username'),
                  controller: _username,
                  hint: tr('es. fitclub_milano'),
                  autofillHints: const [AutofillHints.newUsername],
                  inputFormatters: usernameFormatters,
                  validator: (v) {
                    final u = v?.trim() ?? '';
                    if (u.length < 3 || u.length > 50) return tr('Da 3 a 50 caratteri');
                    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(u)) {
                      return tr('Solo lettere, numeri, punto, trattino e underscore');
                    }
                    return null;
                  },
                ),
                LabeledField(
                  label: tr('Email'),
                  controller: _email,
                  hint: tr('info@palestra.it'),
                  keyboardType: TextInputType.emailAddress,
                  validator: validEmail,
                  autofillHints: const [AutofillHints.email],
                ),
                LabeledField(label: tr('Indirizzo'), controller: _address, autofillHints: const [AutofillHints.streetAddressLine1]),
                Row(
                  children: [
                    Expanded(child: LabeledField(label: tr('Città'), controller: _city, autofillHints: const [AutofillHints.addressCity])),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LabeledField(
                        label: tr('Telefono'),
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                      ),
                    ),
                  ],
                ),
                PasswordField(controller: _password, validator: validPassword, textInputAction: TextInputAction.next),
                PasswordField(
                  controller: _confirm,
                  label: tr('Conferma password'),
                  validator: (v) => v != _password.text ? tr('Le password non coincidono') : null,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton(label: tr('Registra la palestra'), loading: _loading, onPressed: _submit),
      ],
    );
  }
}
