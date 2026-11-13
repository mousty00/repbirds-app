import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/backgrounds.dart';
import '../../core/widgets/ui.dart';

/// Layout comune delle schermate di autenticazione.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: CircleIconButton(
                  icon: Icons.arrow_back_rounded,
                  size: 44,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(height: 28),
              Text(title, style: t.displaySmall),
              const SizedBox(height: 10),
              Text(subtitle, style: t.bodyLarge?.copyWith(color: AppColors.inkSoft)),
              const SizedBox(height: 28),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Campo di testo con etichetta sopra.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.suffix,
    this.readOnly = false,
    this.onTap,
    this.maxLines = 1,
    this.autofillHints,
    this.onSubmitted,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final Widget? suffix;
  final bool readOnly;
  final VoidCallback? onTap;
  final int maxLines;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  /// Es. [usernameFormatters]; con questi niente correttore né suggerimenti.
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
          ),
          TextFormField(
            controller: controller,
            validator: validator,
            obscureText: obscure,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            readOnly: readOnly,
            onTap: onTap,
            maxLines: maxLines,
            autofillHints: autofillHints,
            onFieldSubmitted: onSubmitted,
            inputFormatters: inputFormatters,
            autocorrect: inputFormatters == null,
            enableSuggestions: inputFormatters == null,
            decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
          ),
        ],
      ),
    );
  }
}

/// Campo password con occhio per mostrare/nascondere.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label,
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: widget.label ?? tr('Password'),
      controller: widget.controller,
      obscure: _hidden,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      autofillHints: const [AutofillHints.password],
      suffix: IconButton(
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.muted),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    );
  }
}

String? requiredField(String? v) => (v == null || v.trim().isEmpty) ? tr('Campo obbligatorio') : null;

String? validEmail(String? v) {
  if (v == null || v.trim().isEmpty) return tr('Inserisci la tua email');
  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
  return ok ? null : tr('Email non valida');
}

String? validPassword(String? v) {
  if (v == null || v.isEmpty) return tr('Inserisci una password');
  if (v.length < 8) return tr('Almeno 8 caratteri');
  // bcrypt usa solo i primi 72 byte: il backend rifiuta password più lunghe
  if (utf8.encode(v).length > 72) return tr('Massimo 72 caratteri');
  return null;
}
