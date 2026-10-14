// glucose_provider_test.dart — resolveGlucoseProvider mag nooit een
// onopgevangen fout laten ontsnappen als secure storage faalt (bv. een
// keystore-probleem) — anders breekt het ophalen van glucosewaarden (en in
// de instellingen het opslaan) overal stil, zonder foutmelding aan de
// gebruiker. Zie glucose_provider.dart's dexcomShare-tak.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/services/glucose_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'geeft null terug (i.p.v. te gooien) als secure storage faalt bij het lezen van het Dexcom-wachtwoord',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'keystore_error',
              message: 'nagebootst keystore-probleem',
            );
          });

      final profile = AppProfile.defaults('u1').copyWith(
        glucoseSource: GlucoseSource.dexcomShare,
        dexcomUsername: 'test',
      );

      final provider = await resolveGlucoseProvider(profile);

      expect(provider, isNull);
    },
  );

  test('geeft null terug als er nog geen Dexcom-gebruikersnaam is ingevuld', () async {
    final profile = AppProfile.defaults(
      'u1',
    ).copyWith(glucoseSource: GlucoseSource.dexcomShare);

    final provider = await resolveGlucoseProvider(profile);

    expect(provider, isNull);
  });

  test('geeft null terug bij vingerprik, ongeacht overige instellingen', () async {
    final profile = AppProfile.defaults(
      'u1',
    ).copyWith(glucoseSource: GlucoseSource.finger);

    final provider = await resolveGlucoseProvider(profile);

    expect(provider, isNull);
  });
}
