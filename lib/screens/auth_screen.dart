// auth_screen.dart: inloggen/registreren met Supabase Auth.

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
    final error = _localError ?? store.authError;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: KColor.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(KRadius.lg),
                      border: Border.all(color: KColor.teal),
                    ),
                    child: const Icon(Icons.bolt, color: KColor.teal, size: 36),
                  ),
                  const SizedBox(height: 20),
                  Text('Kinetic', style: KText.display.copyWith(fontSize: 34)),
                  const SizedBox(height: 6),
                  Text('Combat sports • atletische telemetrie • T1D/CGM', style: KText.caption),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    style: KText.body,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    style: KText.body,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'Wachtwoord'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error, style: KText.caption.copyWith(color: KColor.danger)),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!, style: KText.caption.copyWith(color: KColor.tealLight)),
                  ],
                  const SizedBox(height: 20),
                  BigButton(
                    label: store.busy ? 'Even geduld…' : (_register ? 'Account aanmaken' : 'Inloggen'),
                    onPressed: store.busy ? null : _submit,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _register = !_register;
                      _localError = null;
                      _info = null;
                    }),
                    child: Text(_register ? 'Ik heb al een account' : 'Nieuw account aanmaken'),
                  ),
                  if (!_register) TextButton(onPressed: _forgot, child: const Text('Wachtwoord vergeten')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
