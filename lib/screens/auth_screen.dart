// auth_screen.dart: inloggen/registreren met Supabase Auth, in de stijl van
// het Kinetic design system (logo, vlakke kaart, één primaire knop).

import 'package:material_ui/material_ui.dart';

import '../core/auth_validation.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic_widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _showPassword = false;
  String? _localError;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final store = KineticScope.read(context);
    final error = validateCredentials(_email.text, _password.text, register: _register);
    setState(() {
      _localError = error;
      _info = null;
    });
    if (error != null) return;
    if (_register) {
      final signedIn = await store.register(_email.text, _password.text);
      if (!mounted) return;
      if (signedIn == false) {
        setState(() => _info = 'Check je mail en klik op de bevestigingslink. Log daarna hier in.');
      }
    } else {
      await store.signIn(_email.text, _password.text);
    }
  }

  Future<void> _forgot() async {
    final store = KineticScope.read(context);
    if (_email.text.trim().isEmpty) {
      setState(() => _localError = 'Vul eerst je e-mailadres in.');
      return;
    }
    final ok = await store.resetPassword(_email.text);
    if (!mounted) return;
    setState(() => _info = ok ? 'Als dit adres bestaat, staat er een resetlink in je mail.' : null);
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final error = _localError ?? store.authError;
    final media = MediaQuery.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, media.viewPadding.top + 24, 16, 24 + context.bottomInset),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: KineticLogo(size: 72)),
                  const SizedBox(height: 16),
                  Text('Kinetic', textAlign: TextAlign.center, style: context.t.headlineLg),
                  const SizedBox(height: 4),
                  Text(
                    'Combat sports • atletische telemetrie • T1D/CGM',
                    textAlign: TextAlign.center,
                    style: context.t.caption,
                  ),
                  const SizedBox(height: 28),
                  KCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Eyebrow(_register ? 'Nieuw account' : 'Welkom terug'),
                        const SizedBox(height: 4),
                        Text(_register ? 'Account aanmaken' : 'Inloggen', style: context.t.headline),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          style: context.t.body,
                          decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: !_showPassword,
                          autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                          style: context.t.body,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Wachtwoord',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _showPassword ? 'Wachtwoord verbergen' : 'Wachtwoord tonen',
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                              icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            ),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          _Notice(text: error, tone: KTone.danger, icon: Icons.error_outline),
                        ],
                        if (_info != null) ...[
                          const SizedBox(height: 12),
                          _Notice(text: _info!, tone: KTone.primary, icon: Icons.mark_email_read_outlined),
                        ],
                        const SizedBox(height: 20),
                        BigButton(
                          label: store.busy ? 'Even geduld…' : (_register ? 'Account aanmaken' : 'Inloggen'),
                          icon: _register ? Icons.person_add_alt : Icons.login,
                          onPressed: store.busy ? null : _submit,
                        ),
                        if (!_register) ...[
                          const SizedBox(height: 4),
                          TextButton(onPressed: _forgot, child: const Text('Wachtwoord vergeten')),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_register ? 'Al een account?' : 'Nog geen account?', style: context.t.caption),
                      TextButton(
                        onPressed: () => setState(() {
                          _register = !_register;
                          _localError = null;
                          _info = null;
                        }),
                        child: Text(_register ? 'Inloggen' : 'Nieuw account aanmaken'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Je data staat in je eigen Supabase-account, beveiligd met Row Level Security.',
                    textAlign: TextAlign.center,
                    style: context.t.caption.copyWith(color: k.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone, required this.icon});
  final String text;
  final KTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(context.k, tone);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(KRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: context.t.body.copyWith(color: fg))),
        ],
      ),
    );
  }
}
