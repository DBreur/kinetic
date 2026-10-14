import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;

  /// Uitleg na registreren (geen fout): bv. "check je mail".
  String? _info;

  /// E-mailadres dat nog bevestigd moet worden — dan tonen we "opnieuw
  /// sturen".
  String? _awaitingConfirm;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    setState(() => _info = null);
    if (_register) {
      final outcome = await widget.controller.register(email, _password.text);
      if (!mounted) return;
      setState(() {
        switch (outcome) {
          case RegisterOutcome.confirmEmail:
            _register = false;
            _awaitingConfirm = email;
            _info =
                'Je account is aangemaakt. We hebben een bevestigingsmail '
                'gestuurd naar $email — klik op de link in die mail (kijk '
                'ook in je spam) en log daarna hier in.';
          case RegisterOutcome.alreadyExists:
            _register = false;
            _info =
                'Er bestaat al een account met $email. Log in, of gebruik '
                '"Wachtwoord vergeten".';
          case RegisterOutcome.signedIn || RegisterOutcome.failed:
            break;
        }
      });
    } else {
      await widget.controller.signIn(email, _password.text);
      if (!mounted) return;
      // Nog niet bevestigd? Dan meteen de knop om de mail opnieuw te sturen.
      final error = widget.controller.authError ?? '';
      if (error.startsWith('Bevestig eerst')) {
        setState(() => _awaitingConfirm = email);
      }
    }
  }

  Future<void> _resend() async {
    final email = _awaitingConfirm;
    if (email == null) return;
    final ok = await widget.controller.resendConfirmation(email);
    if (!mounted || !ok) return;
    setState(
      () => _info =
          'Nieuwe bevestigingsmail verstuurd naar $email. Klik op de link en '
          'log daarna in.',
    );
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul eerst je e-mailadres in.')),
      );
      return;
    }
    await widget.controller.resetPassword(_email.text.trim());
    if (!mounted || widget.controller.authError != null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reset-link verstuurd als dit account bestaat.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final error = widget.controller.authError;
        return Scaffold(
          backgroundColor: AppColor.bg,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: KLogo(size: 56),
                ),
                const SizedBox(height: 28),
                Text(
                  'KINETIC',
                  style: AppText.display.copyWith(fontSize: 40, letterSpacing: 2),
                ),
                const SizedBox(height: 10),
                Text(
                  _register
                      ? 'Maak je account aan. Daarna verschijnt onboarding precies één keer.'
                      : 'Log in om je glucose, instellingen en trainingen te laden.',
                  style: AppText.body.copyWith(
                    color: AppColor.inkMuted,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 30),
                _Field(
                  controller: _email,
                  label: 'E-mail',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                _Field(
                  controller: _password,
                  label: 'Wachtwoord',
                  obscureText: true,
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    error,
                    style: AppText.caption.copyWith(color: AppColor.redBright),
                  ),
                ],
                if (_info != null && error == null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColor.greenWash,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.mark_email_unread_outlined,
                          size: 18,
                          color: AppColor.ice,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_info!, style: AppText.body),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: widget.controller.busy ? null : _submit,
                  child: widget.controller.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_register ? 'Account maken' : 'Inloggen'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: widget.controller.busy
                      ? null
                      : () => setState(() {
                          _register = !_register;
                          _info = null;
                        }),
                  child: Text(
                    _register
                        ? 'Ik heb al een account'
                        : 'Nieuw account aanmaken',
                  ),
                ),
                if (_awaitingConfirm != null && !_register)
                  TextButton(
                    onPressed: widget.controller.busy ? null : _resend,
                    child: const Text('Bevestigingsmail opnieuw sturen'),
                  ),
                TextButton(
                  onPressed: widget.controller.busy ? null : _reset,
                  child: const Text('Wachtwoord vergeten'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: AppText.body.copyWith(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColor.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColor.line),
        ),
      ),
    );
  }
}
