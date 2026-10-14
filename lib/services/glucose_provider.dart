// glucose_provider.dart — gedeelde interface voor alles dat een
// GlucoseSnapshot kan leveren (Nightscout, Dexcom Share), zodat
// sessiecontrollers en schermen niet hoeven te weten welke bron erachter zit.

import '../models/app_profile.dart';
import '../models/glucose.dart';
import 'dexcom_credentials.dart';
import 'dexcom_share_service.dart';
import 'nightscout_service.dart';

abstract class GlucoseProvider {
  Future<GlucoseSnapshot> fetch({int count = 20});
}

/// Bouwt de juiste, al-geconfigureerde provider voor het huidige profiel —
/// `null` bij vingerprik, of als de gekozen bron nog niet (volledig)
/// ingesteld is (geen URL/gebruikersnaam, of nog geen Dexcom-wachtwoord
/// opgeslagen).
Future<GlucoseProvider?> resolveGlucoseProvider(AppProfile profile) async {
  switch (profile.glucoseSource) {
    case GlucoseSource.finger:
      return null;
    case GlucoseSource.nightscout:
      if (profile.nightscoutUrl.trim().isEmpty) return null;
      return NightscoutService(
        baseUrl: profile.nightscoutUrl,
        token: profile.nightscoutToken,
      );
    case GlucoseSource.dexcomShare:
      if (profile.dexcomUsername.trim().isEmpty) return null;
      String? password;
      try {
        password = await DexcomCredentials.read();
      } catch (_) {
        // Secure storage kan falen (bv. een keystore-probleem) — dan is er
        // gewoon geen bruikbare provider, in plaats van dat elke aanroeper
        // hier zelf op moet vangen.
        return null;
      }
      if (password == null || password.isEmpty) return null;
      return DexcomShareService(
        username: profile.dexcomUsername,
        password: password,
        server: profile.dexcomServer,
      );
  }
}
