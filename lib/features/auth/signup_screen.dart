import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../data/auth_repository.dart';
import '../share/share_links.dart';
import 'auth_widgets.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _birth = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  DateTime? _birthDate;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_username, _firstName, _lastName, _email, _birth, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1920),
      // età minima 14 anni (consenso digitale in Italia), la controlla anche il backend
      lastDate: DateTime(now.year - 14, now.month, now.day),
      helpText: tr('Data di nascita'),
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birth.text = formatDate(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).signup(
            username: _username.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            birthDate: _birthDate!,
          );
      if (!mounted) return;
      showMessage(context, tr('Account creato! Ti abbiamo inviato un codice via email.'));
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
      title: tr('Crea il tuo\naccount'),
      subtitle: tr('Pochi dati e sei pronto per il primo allenamento.'),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                LabeledField(
                  label: tr('Username'),
                  controller: _username,
                  hint: tr('es. mario_lifts'),
                  autofillHints: const [AutofillHints.newUsername],
                  inputFormatters: usernameFormatters,
                  validator: (v) {
                    final u = v?.trim() ?? '';
                    if (u.isEmpty) return tr('Scegli uno username');
                    if (u.length < 3 || u.length > 50) return tr('Da 3 a 50 caratteri');
                    // stessa regola del backend: finisce in URL e chiavi di storage
                    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(u)) {
                      return tr('Solo lettere, numeri, punto, trattino e underscore');
                    }
                    return null;
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: LabeledField(
                        label: tr('Nome'),
                        controller: _firstName,
                        validator: requiredField,
                        autofillHints: const [AutofillHints.givenName],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LabeledField(
                        label: tr('Cognome'),
                        controller: _lastName,
                        validator: requiredField,
                        autofillHints: const [AutofillHints.familyName],
                      ),
                    ),
                  ],
                ),
                LabeledField(
                  label: tr('Email'),
                  controller: _email,
                  hint: tr('nome@email.com'),
                  keyboardType: TextInputType.emailAddress,
                  validator: validEmail,
                  autofillHints: const [AutofillHints.email],
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
                PasswordField(
                  controller: _password,
                  validator: validPassword,
                  textInputAction: TextInputAction.next,
                ),
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
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            text: tr('Creando un account accetti i '),
            children: [
              _link(tr('Termini di servizio'), ShareLinks.terms),
              TextSpan(text: tr(' e la ')),
              _link(tr('Privacy policy'), ShareLinks.privacy),
              TextSpan(text: tr('. Niente contenuti offensivi: chi li pubblica viene rimosso.')),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        PrimaryButton(label: tr('Crea account'), loading: _loading, onPressed: _submit),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => context.pushReplacement('/auth/signup/gym'),
            icon: const Icon(Icons.storefront_rounded, size: 18),
            label: Text(tr('Hai una palestra? Registrala qui')),
          ),
        ),
      ],
    );
  }
}

TextSpan _link(String text, String url) => TextSpan(
      text: text,
      style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600),
      recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url)),
    );
