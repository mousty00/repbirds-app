import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/auth_repository.dart';
import 'auth_widgets.dart';

/// Verifica email con l'OTP ricevuto dopo la registrazione.
class VerifyOtpScreen extends ConsumerStatefulWidget {
  const VerifyOtpScreen({super.key, required this.username, this.email});

  final String username;
  final String? email;

  @override
  ConsumerState<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends ConsumerState<VerifyOtpScreen> {
  late final _username = TextEditingController(text: widget.username);
  late final _email = TextEditingController(text: widget.email ?? '');
  final _otp = TextEditingController();
  bool _loading = false;
  bool _sending = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_username.text.trim().isEmpty || _otp.text.trim().isEmpty) {
      showMessage(context, tr('Inserisci username e codice'), error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).verifyOtp(username: _username.text.trim(), otp: _otp.text.trim());
      if (!mounted) return;
      showMessage(context, tr('Email verificata! Ora puoi accedere.'));
      context.pushReplacement('/auth/login');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    final err = validEmail(_email.text);
    if (err != null) {
      showMessage(context, tr('Inserisci l\'email per ricevere un nuovo codice'), error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(authRepositoryProvider).sendVerifyOtp(_email.text.trim());
      if (mounted) showMessage(context, tr('Nuovo codice inviato'));
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: tr('Controlla\nla tua email'),
      subtitle: tr('Inserisci il codice a 6 cifre che ti abbiamo inviato per attivare l\'account.'),
      children: [
        if (widget.username.isEmpty) LabeledField(label: tr('Username'), controller: _username, inputFormatters: usernameFormatters),
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(tr('Codice'), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
        ),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 14),
          decoration: const InputDecoration(counterText: '', hintText: '••••••'),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 24),
        PrimaryButton(label: tr('Verifica'), loading: _loading, onPressed: _verify),
        const SizedBox(height: 28),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Non hai ricevuto il codice?'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(hintText: tr('La tua email')),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _sending ? null : _resend,
                child: Text(_sending ? tr('Invio…') : tr('Invia un nuovo codice')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
