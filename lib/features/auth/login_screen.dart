import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import 'auth_widgets.dart';
import 'session.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  /// Il server non ha risposto all'ultimo tentativo.
  bool _unreachable = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(sessionProvider.notifier).login(_username.text, _password.text);
      // il router porta in home
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.unreachable) {
        setState(() => _unreachable = true);
        showMessage(context, tr('Server non raggiungibile ({url})', {'url': Env.apiBaseUrl}), error: true);
      } else if (e.isEmailNotVerified) {
        showMessage(context, tr('Verifica prima la tua email con il codice che ti abbiamo inviato.'));
        context.push('/auth/verify?username=${Uri.encodeComponent(_username.text.trim())}');
      } else {
        showMessage(context, e.statusCode == 401 ? tr('Username o password non corretti') : e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Passa ai dati finti senza riavviare l'app (solo build di debug).
  void _useDemo() {
    setState(() {
      Env.useMock = true;
      _unreachable = false;
    });
    if (_username.text.trim().isEmpty) _username.text = 'mousty';
    if (_password.text.isEmpty) _password.text = 'password';
    _submit();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: tr('Bentornato'),
      subtitle: tr('Accedi per riprendere i tuoi allenamenti.'),
      children: [
        if (Env.useMock)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: SoftCard(
              color: AppColors.lilacSoft,
              child: Text(
                tr('Modalità demo: qualunque username e password funzionano. Usa "nonverificato" per provare la verifica email, la password "sbagliata" per l\'errore.'),
                style: TextStyle(color: AppColors.inkSoft, height: 1.4),
              ),
            ),
          ),
        if (_unreachable && kDebugMode && !Env.useMock)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: SoftCard(
              color: AppColors.lilacSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Non riesco a contattare {url}. Vuoi provare l\'app con i dati demo?', {'url': Env.apiBaseUrl}),
                    style: TextStyle(color: AppColors.inkSoft, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  PillActionButton(icon: Icons.science_rounded, label: tr('Usa dati demo'), onPressed: _useDemo),
                ],
              ),
            ),
          ),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                LabeledField(
                  label: tr('Username'),
                  controller: _username,
                  hint: tr('il_tuo_username'),
                  validator: requiredField,
                  autofillHints: const [AutofillHints.username],
                  inputFormatters: usernameFormatters,
                ),
                PasswordField(controller: _password, validator: requiredField, onSubmitted: (_) => _submit()),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push('/auth/forgot'),
            child: Text(tr('Password dimenticata?')),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: tr('Accedi'), loading: _loading, onPressed: _submit),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: () => context.pushReplacement('/auth/signup'),
            child: Text.rich(
              TextSpan(
                text: tr('Non hai un account? '),
                style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w500),
                children: [TextSpan(text: tr('Registrati'), style: const TextStyle(color: AppColors.blue))],
              ),
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => context.pushReplacement('/auth/signup/gym'),
            child: Text(tr('Hai una palestra? Registrala'), style: TextStyle(color: AppColors.inkSoft)),
          ),
        ),
      ],
    );
  }
}
