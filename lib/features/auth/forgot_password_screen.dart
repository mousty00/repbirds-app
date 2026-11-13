import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/ui.dart';
import '../../data/auth_repository.dart';
import 'auth_widgets.dart';

/// Reset password in due passi: email → codice + nuova password.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sendCode() {
    if (!_emailForm.currentState!.validate()) return;
    _run(() async {
      await ref.read(authRepositoryProvider).sendResetOtp(_email.text.trim());
      if (!mounted) return;
      setState(() => _codeSent = true);
      showMessage(context, tr('Se l\'email esiste, riceverai un codice a breve.'));
    });
  }

  void _reset() {
    if (!_resetForm.currentState!.validate()) return;
    _run(() async {
      await ref.read(authRepositoryProvider).resetPassword(
            email: _email.text.trim(),
            otp: _otp.text.trim(),
            newPassword: _password.text,
          );
      if (!mounted) return;
      showMessage(context, tr('Password aggiornata. Accedi con la nuova password.'));
      context.pushReplacement('/auth/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: _codeSent ? tr('Nuova\npassword') : tr('Password\ndimenticata?'),
      subtitle: _codeSent
          ? tr('Inserisci il codice ricevuto via email e scegli una nuova password.')
          : tr('Ti mandiamo un codice per reimpostarla.'),
      children: [
        Form(
          key: _emailForm,
          child: LabeledField(
            label: tr('Email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            validator: validEmail,
            readOnly: _codeSent,
          ),
        ),
        if (_codeSent)
          Form(
            key: _resetForm,
            child: Column(
              children: [
                LabeledField(
                  label: tr('Codice'),
                  controller: _otp,
                  keyboardType: TextInputType.number,
                  validator: requiredField,
                ),
                PasswordField(controller: _password, label: tr('Nuova password'), validator: validPassword),
              ],
            ),
          ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: _codeSent ? tr('Reimposta password') : tr('Invia codice'),
          loading: _loading,
          onPressed: _codeSent ? _reset : _sendCode,
        ),
        if (_codeSent)
          Center(
            child: TextButton(
              onPressed: _loading ? null : () => setState(() => _codeSent = false),
              child: Text(tr('Cambia email')),
            ),
          ),
      ],
    );
  }
}
