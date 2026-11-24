// glucose_provider.dart: gedeelde interface voor alles dat een
// GlucoseSnapshot kan leveren (Dexcom Share, Nightscout), zodat schermen
// niet hoeven te weten welke bron erachter zit.

import '../models/glucose.dart';
import '../models/kinetic_profile.dart';
import 'dexcom_credentials.dart';
import 'dexcom_share_service.dart';
import 'nightscout_service.dart';

abstract class GlucoseProvider {
  Future<GlucoseSnapshot> fetch({int count = 20});
}

/// De juiste, al geconfigureerde provider voor dit profiel, of `null` bij
/// vingerprik of als de bron nog niet volledig is ingesteld (geen
/// gebruikersnaam of nog geen Dexcom-wachtwoord op dit toestel).
Future<GlucoseProvider?> resolveGlucoseProvider(KineticProfile profile) async {
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
        // Secure storage kan falen (keystore-probleem): dan geen provider.
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
