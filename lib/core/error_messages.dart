// error_messages.dart — vertaalt technische excepties naar een begrijpelijke
// Nederlandse melding voor de gebruiker. Nooit een rauwe exception-tekst
// (zoals "PostgrestException(message: ..., code: ...)") rechtstreeks tonen —
// die wordt hier gemapt, met de technische details naar de devconsole via
// debugPrint voor als je zelf nog wilt debuggen.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const genericErrorFallback =
    'Er ging iets mis. Controleer je internetverbinding en probeer het opnieuw.';

/// Geeft een begrijpelijke Nederlandse melding voor [error] — gebruik dit
/// overal waar een gevangen exception aan de gebruiker getoond moet worden,
/// in plaats van de exception zelf of `error.toString()`.
String friendlyErrorMessage(
  Object error, {
  String fallback = genericErrorFallback,
}) {
  debugPrint('friendlyErrorMessage: $error');
  if (error is AuthException) return _friendlyAuthMessage(error);
  return fallback;
}

String _friendlyAuthMessage(AuthException error) {
  final message = error.message.toLowerCase();
  if (message.contains('invalid login credentials')) {
    return 'E-mailadres of wachtwoord klopt niet.';
  }
  if (message.contains('email not confirmed')) {
    return 'Bevestig eerst je e-mailadres via de link die je hebt gekregen.';
  }
  if (message.contains('user already registered')) {
    return 'Er bestaat al een account met dit e-mailadres.';
  }
  if (message.contains('password') && message.contains('least')) {
    return 'Kies een wachtwoord van minstens 6 tekens.';
  }
  if (message.contains('email') && message.contains('valid')) {
    return 'Vul een geldig e-mailadres in.';
  }
  if (error.message.trim().isEmpty) {
    return 'Aanmelden is niet gelukt. Probeer het opnieuw.';
  }
  // Onbekend geval: Supabase's eigen boodschap is meestal al een gewone zin
  // (bv. "Auth session missing!"), dus die is bruikbaarder dan een
  // generieke tekst — maar nooit de class-naam/toString() eromheen.
  return error.message;
}
