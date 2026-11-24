// auth_validation.dart — controle van e-mail/wachtwoord vóórdat er iets naar
// Supabase gaat. Pure functie, zodat hij los te testen is.

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// Foutmelding (Nederlands) of null als alles klopt. Bij inloggen alleen
/// vormcontrole; bij registreren ook wachtwoordsterkte.
String? validateCredentials(
  String email,
  String password, {
  required bool register,
}) {
  final e = email.trim();
  if (e.isEmpty) return 'Vul je e-mailadres in.';
  if (!_emailPattern.hasMatch(e)) return 'Dit e-mailadres klopt niet.';
  if (password.isEmpty) return 'Vul je wachtwoord in.';
  if (!register) return null;
  if (password.length < 8) {
    return 'Kies een wachtwoord van minstens 8 tekens.';
  }
  if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
      !RegExp(r'[0-9]').hasMatch(password)) {
    return 'Gebruik letters én cijfers in je wachtwoord.';
  }
  return null;
}
